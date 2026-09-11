# Limits

**Generated — do not edit.** `python3 docs/limits_build.py` writes this file and
`test/limitstablecheck.sh` fails if it drifts from `src/`.

Every compile-time cap in `src/`, what it bounds, and whether its file discloses a truncation when
it fires. A cap is a **routing decision**: it decides what an agent can and cannot find. Set one
where the pathological tail is, never near the typical case — and when it fires, say so
(`*_capped="1"` with a `*_total=`), because a silent cut reads to the caller as "none exists".

| total caps | files | caps whose file discloses | caps whose file discloses NOTHING |
| --- | --- | --- | --- |
| 114 | 50 | 79 | **35** |

Plus 6 ranking and apportionment parameters, in their own table below: they are not caps, they
are not counted as caps, and 114 + 6 is the 120 constants this generator parses out of `src/`.

## INDEXING or OUTPUT — which half of the answer a cap bounds

**INDEXING** caps bound what can EVER be found. A silent one is unrecoverable by the caller: no
flag, no budget, no second call gets the answer back, and the output reads as "none exists".
**OUTPUT** caps bound what is SHOWN from what was found; a silent one is still a defect, but a
`--detail`, a page or a follow-up call can recover the answer. The two are not the same severity
and a single table that does not distinguish them invites fixing the cheap one first.

The `class` column below carries that answer where it is known. **26 of 114 caps are classified
(10 INDEXING, 16 OUTPUT); the remaining 88 render `—`, which means NOT YET CLASSIFIED — never
"neither".** Classifications live in `docs/limits_classes.tsv`, a sidecar with a known expiry:
the tag belongs on the declaration itself, and this file exists only because the round that
produced the taxonomy could not touch `src/`. `test/limitstablecheck.sh` fails if a row there
names a cap that no longer exists.

## Refuted by re-derivation — do not re-propose

A cap that shortens an answer is measured by `docs/TUNING.md`. A cap that could make an answer
WRONG needs a different instrument: recompute the value without the bound and compare. Two were
taken through it on 2026-09-10 and both came back inert, recorded here so the next reader does
not spend the afternoon again.

- **`kSliceRdMaxIter` = 64 cannot fire.** 4,528 reaching-definition fixpoints were observed and
  the maximum iteration count reached was **1**. The bound is 63 iterations above anything real.
- **The `src/ingest_metrics.h` parameter-walk depth of 12 fires 97 times and changes nothing.**
  Output is byte-identical at 12, at 64 and at 256: the frames past depth 12 carry no parameter.

The second one is the transferable lesson. "The bound trips 97 times" reads like a finding and is
not one — a fidelity cap is judged by whether re-derivation changes the ANSWER, never by whether
the bound trips. A tripping counter is a hypothesis; the re-derivation is the measurement.

## Not caps — ranking and apportionment parameters

These decide **how** something is weighted or apportioned, not **how many** of it survive, so
they are judged by a different instrument: an eval that sets the value, not a `shown=`/`total=`
pair. A value of `0.90` cannot be a row count. Each needs a `docs/EVALS.md` anchor naming the
measurement that chose it; listing them beside truncation caps invites tuning them by intuition.

The **anchor** column is read from each constant's own trailing comment. **unsourced** means the
comment cites no measurement — the value came from somewhere, but not from anything a reader can
check. All 6 read unsourced today, which is the finding, not an omission: `kSpecificMinLen` has
the widest measured blast radius of any constant in this tree (14 invocations across 9 verbs, per
`docs/TUNING.md`) and its entire stated provenance is the parenthetical `(aider's)`. Sourcing them
means editing `src/`; a cited anchor that `docs/EVALS.md` does not contain makes this generator
refuse to write, so the column cannot be satisfied by pointing at nothing.

| constant | value | site | anchor | note |
| --- | --- | --- | --- | --- |
| `kBudgetHeadroom` | `0.90` | `src/serialize.h:605` | **unsourced** | — |
| `kCeilingFirstEntryTolerance` | `1.15` | `src/serialize.h:616` | **unsourced** | — |
| `kCommonNameDefThreshold` | `5` | `src/graph.h:244` | **unsourced** | >5 defs of the same name ⇒ common (aider's) |
| `kCoreBudgetShare` | `0.34` | `src/partition.h:98` | **unsourced** | — |
| `kSpecificMinLen` | `8` | `src/graph.h:250` | **unsourced** | ≥8 chars …  (aider's) |
| `kZoneDistanceThreshold` | `0.5` | `src/arch.h:742` | **unsourced** | \|A+I-1\| past this → classify into pain/useless |

### `src/accessshape.h`

Discloses: `loops_capped`

| constant | value | line | class | note |
| --- | --- | --- | --- | --- |
| `kMaxLoopsModeled` | `20000` | 164 | — | — |
| `kQueryBudget` | `50000` | 155 | — | — |

### `src/atoms.h`

Discloses: **none**

| constant | value | line | class | note |
| --- | --- | --- | --- | --- |
| `kAtomsQueryBudget` | `100000` | 78 | — | — |

### `src/binstale.h`

Discloses: **none**

| constant | value | line | class | note |
| --- | --- | --- | --- | --- |
| `kMaxTrackedFiles` | `20000` | 59 | — | — |

### `src/cachelint.h`

Discloses: **none**

| constant | value | line | class | note |
| --- | --- | --- | --- | --- |
| `kCacheQueryBudget` | `100000` | 78 | — | — |

### `src/cli.h`

Discloses: `bridges_capped`, `files_capped`, `inc_capped`, `modules_capped`, `rows_capped`, `sibs_capped`, `syms_capped`, `tests_capped`, `unflagged_capped`, `untested_capped`

| constant | value | line | class | note |
| --- | --- | --- | --- | --- |
| `kConnectRadiusMax` | `12` | 3093 | — | == connectcfg::kMaxRadius (static_assert at the seam in main.cpp) |
| `kIntFlagMax` | `1000000000` | 3092 | — | parsePosInt/parseNonNegInt's own overflow ceiling |
| `kPageValueMax` | `1000000000` | 591 | — | — |

### `src/commentcoherence.h`

Discloses: **none**

| constant | value | line | class | note |
| --- | --- | --- | --- | --- |
| `kCommentCoherenceRowCap` | `40` | 75 | — | same shape as --readability's 40 |

### `src/contextratio.h`

Discloses: `defs_capped`, `files_capped`, `syms_capped`

| constant | value | line | class | note |
| --- | --- | --- | --- | --- |
| `kDefsPerNameCap` | `8` | 94 | — | — |
| `kFileRowCap` | `40` | 89 | — | — |
| `kSymbolRowCap` | `40` | 88 | — | — |

### `src/dmm.h`

Discloses: **none**

| constant | value | line | class | note |
| --- | --- | --- | --- | --- |
| `kUnitComplexityLowRiskMax` | `5` | 91 | OUTPUT | cyclomatic complexity |
| `kUnitInterfacingLowRiskMax` | `2` | 92 | OUTPUT | parameters |
| `kUnitSizeLowRiskMax` | `15` | 90 | OUTPUT | lines |

### `src/editpreview.h`

Discloses: **none**

| constant | value | line | class | note |
| --- | --- | --- | --- | --- |
| `kPreviewOverwriteBudgetBytes` | `4096` | 283 | — | — |

### `src/ensemble.h`

Discloses: `files_capped`, `findings_capped`, `syms_capped`

| constant | value | line | class | note |
| --- | --- | --- | --- | --- |
| `kEnsembleFileRowCap` | `20` | 108 | — | — |
| `kEnsembleSymbolRowCap` | `40` | 107 | — | — |
| `kOrdinalWindowCap` | `40` | 112 | — | — |

### `src/expand.h`

Discloses: **none**

| constant | value | line | class | note |
| --- | --- | --- | --- | --- |
| `kExpandMaxPer` | `8` | 37 | OUTPUT | — |
| `kExpandMaxSeeds` | `8` | 36 | OUTPUT | out-of-range env means OFF, never a clamp-and-guess |

### `src/filepool.h`

Discloses: **none**

| constant | value | line | class | note |
| --- | --- | --- | --- | --- |
| `kPoolMaxTopK` | `32` | 29 | — | env values outside range mean OFF, never a clamp-and-guess |

### `src/gitmine.h`

Discloses: `coboost_commits_capped`, `coboost_partners_capped`

| constant | value | line | class | note |
| --- | --- | --- | --- | --- |
| `kCoBoostMaxFilesPerCommit` | `30` | 2901 | INDEXING | same bulk-commit cap as the other co-change miners here |
| `kCoBoostMaxPartnerFiles` | `8` | 2904 | INDEXING | strongest partners only, by (deg desc, path asc) |
| `kCoBoostMaxSymbolsPerFile` | `3` | 2905 | INDEXING | per partner file: its top-3 symbols by (lens score desc, id asc) |

### `src/graph.h`

Discloses: `importers_capped`

| constant | value | line | class | note |
| --- | --- | --- | --- | --- |
| `kMaxEdges` | `256` | 5385 | — | total emitted edge cap |
| `kMaxNodes` | `96` | 5384 | — | total emitted node cap (§3 size caps) |
| `kMaxRadius` | `12` | 5387 | — | — |
| `kMaxTerminals` | `16` | 5383 | — | >16 is the CALLER's usage error; the core CLAMPS (never VERIFYs on hostile input) |

### `src/handoff.h`

Discloses: `syms_capped`

| constant | value | line | class | note |
| --- | --- | --- | --- | --- |
| `kHandoffCochangeRows` | `8` | 43 | OUTPUT | heuristic co-change rows shown |
| `kHandoffDocRows` | `4` | 41 | OUTPUT | heuristic doc pointers shown |
| `kHandoffNoteRows` | `8` | 42 | OUTPUT | heuristic note rows shown |

### `src/infra/blanktext.h`

Discloses: **none**

| constant | value | line | class | note |
| --- | --- | --- | --- | --- |
| `kBlankSpellingMaxCodePoints` | `8` | 215 | — | — |

### `src/infra/profilePmc.h`

Discloses: **none**

| constant | value | line | class | note |
| --- | --- | --- | --- | --- |
| `kMaxEvents` | `8` | 62 | — | — |

### `src/ingest.h`

Discloses: `ellipsis_capped`, `hits_capped`

| constant | value | line | class | note |
| --- | --- | --- | --- | --- |
| `kBinarySniffCap` | `4096` | 207 | — | NUL-byte sniff window |
| `kUnreachableMaxHits` | `5000` | 414 | — | — |

### `src/lanes.h`

Discloses: `blast_capped`, `tests_capped`

| constant | value | line | class | note |
| --- | --- | --- | --- | --- |
| `kMaxBlastFiles` | `40` | 120 | — | blast-radius file rows per lane; total + capped always reported |
| `kMaxTestRows` | `40` | 121 | — | tests_to_run rows per lane; same "never drop without a number" |

### `src/lexical.h`

Discloses: **none**

| constant | value | line | class | note |
| --- | --- | --- | --- | --- |
| `kMaxAnchorDefs` | `3` | 1829 | — | — |

### `src/lintrules.h`

Discloses: **none**

| constant | value | line | class | note |
| --- | --- | --- | --- | --- |
| `kLintMaxPerRule` | `5000` | 821 | — | — |

### `src/main.cpp`

Discloses: **none**

| constant | value | line | class | note |
| --- | --- | --- | --- | --- |
| `kRecentRows` | `40` | 982 | — | F3: ~45 B a row; the file-level answer, not the file list |

### `src/mcpedit.h`

Discloses: **none**

| constant | value | line | class | note |
| --- | --- | --- | --- | --- |
| `kReceiptRegionBudgetBytes` | `2048` | 891 | — | — |

### `src/mcpjson.h`

Discloses: **none**

| constant | value | line | class | note |
| --- | --- | --- | --- | --- |
| `kFrameEchoCaptureBytes` | `240` | 529 | — | > mcprefusal.h's kMcpEchoMaxBytes, so the cap still shows |

### `src/mcprefusal.h`

Discloses: **none**

| constant | value | line | class | note |
| --- | --- | --- | --- | --- |
| `kMcpEchoMaxBytes` | `160` | 363 | — | — |

### `src/mcpverbs.h`

Discloses: `coboost_commits_capped`, `hits_capped`, `unindexed_candidates_capped`

| constant | value | line | class | note |
| --- | --- | --- | --- | --- |
| `kBatchCap` | `16` | 4217 | — | max sub-queries processed per batch; excess is REPORTED, never silently dropped |
| `kMcpPageValueMax` | `1000000000` | 306 | — | == cli.h's kPageValueMax |
| `kMcpRecallTopKMax` | `1000` | 312 | — | — |

### `src/mention.h`

Discloses: `doc_mentions_capped`, `mention_files_capped`, `mention_syms_capped`, `mention_tokens_capped`

| constant | value | line | class | note |
| --- | --- | --- | --- | --- |
| `kDocMentionMaxAnchors` | `8` | 759 | INDEXING | consult only the current top-N anchors |
| `kDocMentionMaxDocsPerAnchor` | `2` | 760 | INDEXING | strongest-anchor-first, capped per anchor |
| `kDocMentionMaxDocsTotal` | `6` | 761 | INDEXING | global cap — bounds token cost regardless of fan-out |
| `kMentionMaxDirectSymbols` | `8` | 160 | INDEXING | directly-named (Scope.name / `name`) symbols, id asc |
| `kMentionMaxFiles` | `4` | 158 | INDEXING | strongest evidence only: files named first in the text |
| `kMentionMaxRawTokens` | `16` | 157 | INDEXING | extraction cap: first N candidate mention tokens, text order |
| `kMentionMaxSymbolsPerFile` | `3` | 159 | INDEXING | per mentioned file: its top symbols by (lens score desc, id asc) |

### `src/model.h`

Discloses: **none**

| constant | value | line | class | note |
| --- | --- | --- | --- | --- |
| `kMaxWorkspaceRoots` | `16` | 938 | — | — |

### `src/namingconsistency.h`

Discloses: **none**

| constant | value | line | class | note |
| --- | --- | --- | --- | --- |
| `kRowCap` | `40` | 67 | — | same shape as --hotspots/--readability's 40 |

### `src/naminglens.h`

Discloses: **none**

| constant | value | line | class | note |
| --- | --- | --- | --- | --- |
| `kConfusableGroupMax` | `512` | 425 | — | beyond this many co-visible names the O(n²) pair scan |

### `src/nextverb.h`

Discloses: **none**

| constant | value | line | class | note |
| --- | --- | --- | --- | --- |
| `kNextAttrMaxBytes` | `120` | 26 | — | — |

### `src/nonlocalstate.h`

Discloses: `cells_capped`, `decls_capped`

| constant | value | line | class | note |
| --- | --- | --- | --- | --- |
| `kCellsPerRowCap` | `12` | 116 | — | — |
| `kDeclMatchBudget` | `40000` | 124 | — | — |
| `kMaxCells` | `2048` | 120 | — | — |
| `kRowCap` | `40` | 88 | — | — |

### `src/packtask.h`

Discloses: `mention_syms_capped`, `ranking_capped`

| constant | value | line | class | note |
| --- | --- | --- | --- | --- |
| `kPackTaskRankTopN` | `12` | 89 | — | ranking = the top-12 head, not the full 40 — leaves budget for the later sections |

### `src/pageview.h`

Discloses: `count_capped`, `findings_capped`, `hits_capped`, `importers_capped`, `modules_capped`

| constant | value | line | class | note |
| --- | --- | --- | --- | --- |
| `kCallHierarchyRowCap` | `40` | 164 | — | — |
| `kCochangePartnerCap` | `30` | 170 | — | — |
| `kExternalSurfaceRowCap` | `100` | 186 | — | names, by ref count (≈ 5.2 KB on this repo) |
| `kImportReachRowCap` | `40` | 179 | — | — |
| `kPageDisclosureCap` | `224` | 366 | — | — |
| `kTreeRowCap` | `80` | 184 | — | files, by best symbol's rank: 80 rows ≈ 11.5 KB on this repo (100 = 14.3 KB) |
| `kUseSiteRowCap` | `100` | 165 | — | — |
| `kZoomTopModuleCap` | `40` | 185 | — | top-level modules, size desc (their children ride along: levels_shown=2) |

### `src/partition.h`

Discloses: **none**

| constant | value | line | class | note |
| --- | --- | --- | --- | --- |
| `kMaxPartitions` | `16` | 94 | OUTPUT | — |

### `src/pattern.h`

Discloses: `hits_capped`

| constant | value | line | class | note |
| --- | --- | --- | --- | --- |
| `kMaxHits` | `5000` | 81 | — | same per-verb budget --match spends |
| `kMaxMetavars` | `32` | 79 | — | bindings live in a fixed-size env on the stack |
| `kMaxPatternBytes` | `4096` | 78 | — | a pattern is a code SHAPE, not a file |

### `src/prcontext.h`

Discloses: **none**

| constant | value | line | class | note |
| --- | --- | --- | --- | --- |
| `kPrDefaultBudgetTokens` | `8000` | 453 | — | — |

### `src/qualitypanel.h`

Discloses: `findings_capped`

| constant | value | line | class | note |
| --- | --- | --- | --- | --- |
| `kPanelRowCap` | `40` | 145 | — | — |

### `src/readability.h`

Discloses: **none**

| constant | value | line | class | note |
| --- | --- | --- | --- | --- |
| `kReadabilityRowCap` | `40` | 61 | — | — |

### `src/recall.h`

Discloses: **none**

| constant | value | line | class | note |
| --- | --- | --- | --- | --- |
| `kDefaultRecallMaxTokens` | `8000` | 311 | — | — |

### `src/redact.h`

Discloses: **none**

| constant | value | line | class | note |
| --- | --- | --- | --- | --- |
| `kGenericMinRunLength` | `32` | 296 | — | — |

### `src/search.h`

Discloses: `hits_capped`

| constant | value | line | class | note |
| --- | --- | --- | --- | --- |
| `kGrepCollectionBudget` | `4000000` | 1445 | — | — |
| `kGrepMatchedLineMaxBytes` | `512` | 941 | — | — |
| `kGrepTierFileBudget` | `128` | 2072 | — | hit files classified per call |
| `kMaxAffixSet` | `8` | 195 | — | cap on prefix/suffix set sizes |
| `kMaxExactLen` | `24` | 194 | — | beyond this exact-string length, give up exactness (⊤) |
| `kMaxExactSet` | `8` | 193 | — | beyond this many exact strings, give up exactness (⊤) |

### `src/serialize.h`

Discloses: `calls_capped`, `inc_capped`, `sibs_capped`

| constant | value | line | class | note |
| --- | --- | --- | --- | --- |
| `kForAnchorBodyBudgetBytes` | `22800` | 794 | — | — |
| `kForAutoBodyBudgetBytes` | `6000` | 760 | — | — |
| `kForCapTailSigBytes` | `96` | 727 | — | — |
| `kForCompactSurfaceBudgetBytes` | `1000` | 970 | — | — |
| `kForFileTailShownCap` | `24` | 815 | — | — |
| `kForLensDefaultTopN` | `40` | 740 | — | — |
| `kForPayloadBudgetBytes` | `7500` | 726 | — | — |
| `kMaxExpandIncludes` | `24` | 4584 | — | inc= cap |
| `kMaxExpandSibs` | `100` | 4575 | — | sibs= cap — a BLOW-UP GUARD, set above the tail, not a trim of the |
| `kWithGraphNodeCap` | `8` | 5642 | — | — |

### `src/siblift.h`

Discloses: **none**

| constant | value | line | class | note |
| --- | --- | --- | --- | --- |
| `kSibliftMaxSeed` | `4` | 25 | OUTPUT | env values outside [1, kSibliftMax*] mean OFF, never a clamp-and-guess |
| `kSibliftMaxSib` | `4` | 26 | OUTPUT | — |

### `src/situ.h`

Discloses: `tests_capped`, `untested_capped`

| constant | value | line | class | note |
| --- | --- | --- | --- | --- |
| `kMaxUntestedRows` | `25` | 938 | — | — |
| `kSituPartnerFileRowsShown` | `4` | 351 | — | section [1] — decl/def partner rows |
| `kSituPartnerRowsShown` | `8` | 350 | — | section [3] — co-change partner rows |
| `kSituTestRowsShown` | `25` | 349 | — | section [2] — tests-to-run rows |

### `src/slice.h`

Discloses: **none**

| constant | value | line | class | note |
| --- | --- | --- | --- | --- |
| `kSliceFlowDefaultDepth` | `8` | 2094 | — | the disclosed default bound (depth= always states it) |
| `kSliceFlowDepthMax` | `32` | 2098 | — | — |
| `kSliceFlowDepthMin` | `1` | 2097 | — | — |
| `kSliceRdMaxIter` | `64` | 1205 | OUTPUT | — |

### `src/slicediff.h`

Discloses: `diff_capped`

| constant | value | line | class | note |
| --- | --- | --- | --- | --- |
| `kMaxDiffRows` | `2000` | 71 | — | — |
| `kMaxRenameHops` | `8` | 75 | — | — |

### `src/taskroute.h`

Discloses: **none**

| constant | value | line | class | note |
| --- | --- | --- | --- | --- |
| `kMinWeakSymbolLen` | `5` | 151 | — | — |

### `src/tracelocus.h`

Discloses: `name_ladder_capped`

| constant | value | line | class | note |
| --- | --- | --- | --- | --- |
| `kMeasuredDigitsPricedWidth` | `6` | 873 | OUTPUT | — |
| `kNameCandidateCap` | `8` | 141 | OUTPUT | — |
| `kTestHopBasenameRowCap` | `3` | 424 | OUTPUT | — |
| `kTestHopCalleeRowCap` | `5` | 423 | OUTPUT | — |

### `src/verbs_change.h`

Discloses: `seed_files_capped`

| constant | value | line | class | note |
| --- | --- | --- | --- | --- |
| `kRunTraceRelevantLinesCap` | `40` | 696 | — | <lines view="relevant"> cap (first/last half split past it) |

