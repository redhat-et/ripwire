# Limits

**Generated — do not edit.** `python3 docs/limits_build.py` writes this file and
`test/limitstablecheck.sh` fails if it drifts from `src/`.

Every compile-time cap in `src/`, what it bounds, and whether its file discloses a truncation when
it fires. A cap is a **routing decision**: it decides what an agent can and cannot find. Set one
where the pathological tail is, never near the typical case — and when it fires, say so
(`*_capped="1"` with a `*_total=`), because a silent cut reads to the caller as "none exists".

| total caps | files | caps whose file discloses | caps whose file discloses NOTHING |
| --- | --- | --- | --- |
| 114 | 50 | 62 | **52** |

## Not caps — ranking and apportionment parameters

These decide **how** something is weighted or apportioned, not **how many** of it survive, so
they are judged by a different instrument: an eval that sets the value, not a `shown=`/`total=`
pair. A value of `0.90` cannot be a row count. Each needs a `docs/EVALS.md` anchor naming the
measurement that chose it; listing them beside truncation caps invites tuning them by intuition.

| constant | value | site | note |
| --- | --- | --- | --- |
| `kBudgetHeadroom` | `0.90` | `src/serialize.h:604` | — |
| `kCeilingFirstEntryTolerance` | `1.15` | `src/serialize.h:615` | — |
| `kCommonNameDefThreshold` | `5` | `src/graph.h:244` | >5 defs of the same name ⇒ common (aider's) |
| `kCoreBudgetShare` | `0.34` | `src/partition.h:84` | — |
| `kSpecificMinLen` | `8` | `src/graph.h:250` | ≥8 chars …  (aider's) |
| `kZoneDistanceThreshold` | `0.5` | `src/arch.h:742` | \|A+I-1\| past this → classify into pain/useless |

### `src/accessshape.h`

Discloses: `loops_capped`

| constant | value | line | note |
| --- | --- | --- | --- |
| `kMaxLoopsModeled` | `20000` | 164 | — |
| `kQueryBudget` | `50000` | 155 | — |

### `src/atoms.h`

Discloses: **none**

| constant | value | line | note |
| --- | --- | --- | --- |
| `kAtomsQueryBudget` | `100000` | 78 | — |

### `src/binstale.h`

Discloses: **none**

| constant | value | line | note |
| --- | --- | --- | --- |
| `kMaxTrackedFiles` | `20000` | 59 | — |

### `src/cachelint.h`

Discloses: **none**

| constant | value | line | note |
| --- | --- | --- | --- |
| `kCacheQueryBudget` | `100000` | 78 | — |

### `src/cli.h`

Discloses: `bridges_capped`, `files_capped`, `inc_capped`, `modules_capped`, `rows_capped`, `sibs_capped`, `syms_capped`, `tests_capped`, `untested_capped`

| constant | value | line | note |
| --- | --- | --- | --- |
| `kConnectRadiusMax` | `12` | 3085 | == connectcfg::kMaxRadius (static_assert at the seam in main.cpp) |
| `kIntFlagMax` | `1000000000` | 3084 | parsePosInt/parseNonNegInt's own overflow ceiling |
| `kPageValueMax` | `1000000000` | 591 | — |

### `src/commentcoherence.h`

Discloses: **none**

| constant | value | line | note |
| --- | --- | --- | --- |
| `kCommentCoherenceRowCap` | `40` | 75 | same shape as --readability's 40 |

### `src/contextratio.h`

Discloses: `defs_capped`, `files_capped`, `syms_capped`

| constant | value | line | note |
| --- | --- | --- | --- |
| `kDefsPerNameCap` | `8` | 94 | — |
| `kFileRowCap` | `40` | 89 | — |
| `kSymbolRowCap` | `40` | 88 | — |

### `src/dmm.h`

Discloses: **none**

| constant | value | line | note |
| --- | --- | --- | --- |
| `kUnitComplexityLowRiskMax` | `5` | 80 | cyclomatic complexity |
| `kUnitInterfacingLowRiskMax` | `2` | 81 | parameters |
| `kUnitSizeLowRiskMax` | `15` | 79 | lines |

### `src/editpreview.h`

Discloses: **none**

| constant | value | line | note |
| --- | --- | --- | --- |
| `kPreviewOverwriteBudgetBytes` | `4096` | 283 | — |

### `src/ensemble.h`

Discloses: `files_capped`, `findings_capped`, `syms_capped`

| constant | value | line | note |
| --- | --- | --- | --- |
| `kEnsembleFileRowCap` | `20` | 108 | — |
| `kEnsembleSymbolRowCap` | `40` | 107 | — |
| `kOrdinalWindowCap` | `40` | 112 | — |

### `src/expand.h`

Discloses: **none**

| constant | value | line | note |
| --- | --- | --- | --- |
| `kExpandMaxPer` | `8` | 36 | — |
| `kExpandMaxSeeds` | `8` | 35 | out-of-range env means OFF, never a clamp-and-guess |

### `src/filepool.h`

Discloses: **none**

| constant | value | line | note |
| --- | --- | --- | --- |
| `kPoolMaxTopK` | `32` | 29 | env values outside range mean OFF, never a clamp-and-guess |

### `src/gitmine.h`

Discloses: **none**

| constant | value | line | note |
| --- | --- | --- | --- |
| `kCoBoostMaxFilesPerCommit` | `30` | 2802 | same bulk-commit cap as the other co-change miners here |
| `kCoBoostMaxPartnerFiles` | `8` | 2805 | strongest partners only, by (deg desc, path asc) |
| `kCoBoostMaxSymbolsPerFile` | `3` | 2806 | per partner file: its top-3 symbols by (lens score desc, id asc) |

### `src/graph.h`

Discloses: `importers_capped`

| constant | value | line | note |
| --- | --- | --- | --- |
| `kMaxEdges` | `256` | 5385 | total emitted edge cap |
| `kMaxNodes` | `96` | 5384 | total emitted node cap (§3 size caps) |
| `kMaxRadius` | `12` | 5387 | — |
| `kMaxTerminals` | `16` | 5383 | >16 is the CALLER's usage error; the core CLAMPS (never VERIFYs on hostile input) |

### `src/handoff.h`

Discloses: **none**

| constant | value | line | note |
| --- | --- | --- | --- |
| `kHandoffCochangeRows` | `8` | 43 | heuristic co-change rows shown |
| `kHandoffDocRows` | `4` | 41 | heuristic doc pointers shown |
| `kHandoffNoteRows` | `8` | 42 | heuristic note rows shown |

### `src/infra/blanktext.h`

Discloses: **none**

| constant | value | line | note |
| --- | --- | --- | --- |
| `kBlankSpellingMaxCodePoints` | `8` | 215 | — |

### `src/infra/profilePmc.h`

Discloses: **none**

| constant | value | line | note |
| --- | --- | --- | --- |
| `kMaxEvents` | `8` | 62 | — |

### `src/ingest.h`

Discloses: `ellipsis_capped`, `hits_capped`

| constant | value | line | note |
| --- | --- | --- | --- |
| `kBinarySniffCap` | `4096` | 207 | NUL-byte sniff window |
| `kUnreachableMaxHits` | `5000` | 414 | — |

### `src/lanes.h`

Discloses: `blast_capped`, `tests_capped`

| constant | value | line | note |
| --- | --- | --- | --- |
| `kMaxBlastFiles` | `40` | 120 | blast-radius file rows per lane; total + capped always reported |
| `kMaxTestRows` | `40` | 121 | tests_to_run rows per lane; same "never drop without a number" |

### `src/lexical.h`

Discloses: **none**

| constant | value | line | note |
| --- | --- | --- | --- |
| `kMaxAnchorDefs` | `3` | 1787 | — |

### `src/lintrules.h`

Discloses: **none**

| constant | value | line | note |
| --- | --- | --- | --- |
| `kLintMaxPerRule` | `5000` | 819 | — |

### `src/main.cpp`

Discloses: **none**

| constant | value | line | note |
| --- | --- | --- | --- |
| `kRecentRows` | `40` | 982 | F3: ~45 B a row; the file-level answer, not the file list |

### `src/mcpedit.h`

Discloses: **none**

| constant | value | line | note |
| --- | --- | --- | --- |
| `kReceiptRegionBudgetBytes` | `2048` | 891 | — |

### `src/mcpjson.h`

Discloses: **none**

| constant | value | line | note |
| --- | --- | --- | --- |
| `kFrameEchoCaptureBytes` | `240` | 529 | > mcprefusal.h's kMcpEchoMaxBytes, so the cap still shows |

### `src/mcprefusal.h`

Discloses: **none**

| constant | value | line | note |
| --- | --- | --- | --- |
| `kMcpEchoMaxBytes` | `160` | 363 | — |

### `src/mcpverbs.h`

Discloses: `hits_capped`, `unindexed_candidates_capped`

| constant | value | line | note |
| --- | --- | --- | --- |
| `kBatchCap` | `16` | 4187 | max sub-queries processed per batch; excess is REPORTED, never silently dropped |
| `kMcpPageValueMax` | `1000000000` | 306 | == cli.h's kPageValueMax |
| `kMcpRecallTopKMax` | `1000` | 312 | — |

### `src/mention.h`

Discloses: **none**

| constant | value | line | note |
| --- | --- | --- | --- |
| `kDocMentionMaxAnchors` | `8` | 475 | consult only the current top-N anchors |
| `kDocMentionMaxDocsPerAnchor` | `2` | 476 | strongest-anchor-first, capped per anchor |
| `kDocMentionMaxDocsTotal` | `6` | 477 | global cap — bounds token cost regardless of fan-out |
| `kMentionMaxDirectSymbols` | `8` | 47 | directly-named (Scope.name / `name`) symbols, id asc |
| `kMentionMaxFiles` | `4` | 45 | strongest evidence only: files named first in the text |
| `kMentionMaxRawTokens` | `16` | 44 | extraction cap: first N candidate mention tokens, text order |
| `kMentionMaxSymbolsPerFile` | `3` | 46 | per mentioned file: its top symbols by (lens score desc, id asc) |

### `src/model.h`

Discloses: **none**

| constant | value | line | note |
| --- | --- | --- | --- |
| `kMaxWorkspaceRoots` | `16` | 937 | — |

### `src/namingconsistency.h`

Discloses: **none**

| constant | value | line | note |
| --- | --- | --- | --- |
| `kRowCap` | `40` | 67 | same shape as --hotspots/--readability's 40 |

### `src/naminglens.h`

Discloses: **none**

| constant | value | line | note |
| --- | --- | --- | --- |
| `kConfusableGroupMax` | `512` | 425 | beyond this many co-visible names the O(n²) pair scan |

### `src/nextverb.h`

Discloses: **none**

| constant | value | line | note |
| --- | --- | --- | --- |
| `kNextAttrMaxBytes` | `120` | 26 | — |

### `src/nonlocalstate.h`

Discloses: `cells_capped`, `decls_capped`

| constant | value | line | note |
| --- | --- | --- | --- |
| `kCellsPerRowCap` | `12` | 116 | — |
| `kDeclMatchBudget` | `40000` | 124 | — |
| `kMaxCells` | `2048` | 120 | — |
| `kRowCap` | `40` | 88 | — |

### `src/packtask.h`

Discloses: `ranking_capped`

| constant | value | line | note |
| --- | --- | --- | --- |
| `kPackTaskRankTopN` | `12` | 75 | ranking = the top-12 head, not the full 40 — leaves budget for the later sections |

### `src/pageview.h`

Discloses: `count_capped`, `findings_capped`, `hits_capped`, `importers_capped`, `modules_capped`

| constant | value | line | note |
| --- | --- | --- | --- |
| `kCallHierarchyRowCap` | `40` | 164 | — |
| `kCochangePartnerCap` | `30` | 170 | — |
| `kExternalSurfaceRowCap` | `100` | 186 | names, by ref count (≈ 5.2 KB on this repo) |
| `kImportReachRowCap` | `40` | 179 | — |
| `kPageDisclosureCap` | `224` | 366 | — |
| `kTreeRowCap` | `80` | 184 | files, by best symbol's rank: 80 rows ≈ 11.5 KB on this repo (100 = 14.3 KB) |
| `kUseSiteRowCap` | `100` | 165 | — |
| `kZoomTopModuleCap` | `40` | 185 | top-level modules, size desc (their children ride along: levels_shown=2) |

### `src/partition.h`

Discloses: **none**

| constant | value | line | note |
| --- | --- | --- | --- |
| `kMaxPartitions` | `16` | 81 | — |

### `src/pattern.h`

Discloses: `hits_capped`

| constant | value | line | note |
| --- | --- | --- | --- |
| `kMaxHits` | `5000` | 81 | same per-verb budget --match spends |
| `kMaxMetavars` | `32` | 79 | bindings live in a fixed-size env on the stack |
| `kMaxPatternBytes` | `4096` | 78 | a pattern is a code SHAPE, not a file |

### `src/prcontext.h`

Discloses: **none**

| constant | value | line | note |
| --- | --- | --- | --- |
| `kPrDefaultBudgetTokens` | `8000` | 452 | — |

### `src/qualitypanel.h`

Discloses: `findings_capped`

| constant | value | line | note |
| --- | --- | --- | --- |
| `kPanelRowCap` | `40` | 145 | — |

### `src/readability.h`

Discloses: **none**

| constant | value | line | note |
| --- | --- | --- | --- |
| `kReadabilityRowCap` | `40` | 61 | — |

### `src/recall.h`

Discloses: **none**

| constant | value | line | note |
| --- | --- | --- | --- |
| `kDefaultRecallMaxTokens` | `8000` | 311 | — |

### `src/redact.h`

Discloses: **none**

| constant | value | line | note |
| --- | --- | --- | --- |
| `kGenericMinRunLength` | `32` | 296 | — |

### `src/search.h`

Discloses: `hits_capped`

| constant | value | line | note |
| --- | --- | --- | --- |
| `kGrepCollectionBudget` | `4000000` | 1445 | — |
| `kGrepMatchedLineMaxBytes` | `512` | 941 | — |
| `kGrepTierFileBudget` | `128` | 2072 | hit files classified per call |
| `kMaxAffixSet` | `8` | 195 | cap on prefix/suffix set sizes |
| `kMaxExactLen` | `24` | 194 | beyond this exact-string length, give up exactness (⊤) |
| `kMaxExactSet` | `8` | 193 | beyond this many exact strings, give up exactness (⊤) |

### `src/serialize.h`

Discloses: `calls_capped`, `inc_capped`, `sibs_capped`

| constant | value | line | note |
| --- | --- | --- | --- |
| `kForAnchorBodyBudgetBytes` | `22800` | 793 | — |
| `kForAutoBodyBudgetBytes` | `6000` | 759 | — |
| `kForCapTailSigBytes` | `96` | 726 | — |
| `kForCompactSurfaceBudgetBytes` | `1000` | 969 | — |
| `kForFileTailShownCap` | `24` | 814 | — |
| `kForLensDefaultTopN` | `40` | 739 | — |
| `kForPayloadBudgetBytes` | `7500` | 725 | — |
| `kMaxExpandIncludes` | `24` | 4583 | inc= cap |
| `kMaxExpandSibs` | `100` | 4574 | sibs= cap — a BLOW-UP GUARD, set above the tail, not a trim of the |
| `kWithGraphNodeCap` | `8` | 5641 | — |

### `src/siblift.h`

Discloses: **none**

| constant | value | line | note |
| --- | --- | --- | --- |
| `kSibliftMaxSeed` | `4` | 24 | env values outside [1, kSibliftMax*] mean OFF, never a clamp-and-guess |
| `kSibliftMaxSib` | `4` | 25 | — |

### `src/situ.h`

Discloses: `tests_capped`, `untested_capped`

| constant | value | line | note |
| --- | --- | --- | --- |
| `kMaxUntestedRows` | `25` | 939 | — |
| `kSituPartnerFileRowsShown` | `4` | 351 | section [1] — decl/def partner rows |
| `kSituPartnerRowsShown` | `8` | 350 | section [3] — co-change partner rows |
| `kSituTestRowsShown` | `25` | 349 | section [2] — tests-to-run rows |

### `src/slice.h`

Discloses: **none**

| constant | value | line | note |
| --- | --- | --- | --- |
| `kSliceFlowDefaultDepth` | `8` | 2093 | the disclosed default bound (depth= always states it) |
| `kSliceFlowDepthMax` | `32` | 2097 | — |
| `kSliceFlowDepthMin` | `1` | 2096 | — |
| `kSliceRdMaxIter` | `64` | 1204 | — |

### `src/slicediff.h`

Discloses: `diff_capped`

| constant | value | line | note |
| --- | --- | --- | --- |
| `kMaxDiffRows` | `2000` | 71 | — |
| `kMaxRenameHops` | `8` | 75 | — |

### `src/taskroute.h`

Discloses: **none**

| constant | value | line | note |
| --- | --- | --- | --- |
| `kMinWeakSymbolLen` | `5` | 151 | — |

### `src/tracelocus.h`

Discloses: **none**

| constant | value | line | note |
| --- | --- | --- | --- |
| `kMeasuredDigitsPricedWidth` | `6` | 777 | — |
| `kNameCandidateCap` | `8` | 130 | — |
| `kTestHopBasenameRowCap` | `3` | 331 | — |
| `kTestHopCalleeRowCap` | `5` | 330 | — |

### `src/verbs_change.h`

Discloses: `seed_files_capped`

| constant | value | line | note |
| --- | --- | --- | --- |
| `kRunTraceRelevantLinesCap` | `40` | 696 | <lines view="relevant"> cap (first/last half split past it) |

