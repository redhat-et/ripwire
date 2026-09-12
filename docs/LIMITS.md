# Limits

**Generated — do not edit.** `python3 docs/limits_build.py` writes this file and
`test/limitstablecheck.sh` fails if it drifts from `src/`.

Every compile-time cap in `src/`, what it bounds, and whether its file discloses a truncation when
it fires. A cap is a **routing decision**: it decides what an agent can and cannot find. Set one
where the pathological tail is, never near the typical case — and when it fires, say so
(`*_capped="1"` with a `*_total=`), because a silent cut reads to the caller as "none exists".

A row is pinned by what a cap IS — its file, name, value, class and note — never by the line it sits
on, so a comment rewritten or a helper deleted above a cap changes no row here and cannot stale this
document. To reach a declaration, search its file for the name (`grep -n <name> <file>`, or
`ripwire . --grep=<name>`). A file that declares the same name, value and note more than once shows
it once, marked `×N`.

| total caps | files | caps whose file discloses | caps whose file discloses NOTHING |
| --- | --- | --- | --- |
| 208 | 83 | 116 | **92** |

Plus 7 ranking and apportionment parameters, in their own table below: they are not caps, they
are not counted as caps, and 208 + 7 is the 215 constants this generator parses out of `src/`.

## INDEXING, OUTPUT or BOUNDARY — which half of the answer a cap bounds

**INDEXING** caps bound what can EVER be found. A silent one is unrecoverable by the caller: no
flag, no budget, no second call gets the answer back, and the output reads as "none exists".
**OUTPUT** caps bound what is SHOWN from what was found; a silent one is still a defect, but a
`--detail`, a page or a follow-up call can recover the answer. The two are not the same severity
and a single table that does not distinguish them invites fixing the cheap one first.

**BOUNDARY** is the third answer and it is not a cap at all — it is the one the census kept
getting wrong. `kUnitSizeLowRiskMax = 15` decides which SIDE of a rule a unit falls on ("15 lines
or fewer is low-risk"); `kMaxNameLen = 96` decides that a 97-character backticked token is a
sentence rather than an identifier; `kMaxPartitions = 16` bounds a hand-written `--partition=N`.
None of them truncates anything, so none can be judged by `shown=`/`total=` and none should carry
a disclosure — labelling them OUTPUT would ask for a `capped="1"` that could never honestly fire.
The distinction was named in review on #108 and the rows below now carry it.

The `class` column below carries that answer where it is known. **111 of 208 caps are classified
(37 INDEXING, 39 OUTPUT, 35 BOUNDARY); the remaining 97 render `—`, which means NOT YET
CLASSIFIED — never "neither".** Classifications live in `docs/limits_classes.tsv`, a sidecar with
a known expiry:
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
check. All 7 read unsourced today, which is the finding, not an omission: `kSpecificMinLen` has
the widest measured blast radius of any constant in this tree (14 invocations across 9 verbs, per
`docs/TUNING.md`) and its entire stated provenance is the parenthetical `(aider's)`. Sourcing them
means editing `src/`; a cited anchor that `docs/EVALS.md` does not contain makes this generator
refuse to write, so the column cannot be satisfied by pointing at nothing.

| constant | value | site | anchor | note |
| --- | --- | --- | --- | --- |
| `kBudgetHeadroom` | `0.90` | `src/serialize.h` | **unsourced** | — |
| `kCeilingFirstEntryTolerance` | `1.15` | `src/serialize.h` | **unsourced** | — |
| `kCommonNameDefThreshold` | `5` | `src/graph.h` | **unsourced** | >5 defs of the same name ⇒ common (aider's) |
| `kCoreBudgetShare` | `0.34` | `src/partition.h` | **unsourced** | — |
| `kExemplarCcxCeilFactor` | `4` | `src/exemplar.h` | **unsourced** | — |
| `kSpecificMinLen` | `8` | `src/graph.h` | **unsourced** | ≥8 chars …  (aider's) |
| `kZoneDistanceThreshold` | `0.5` | `src/arch.h` | **unsourced** | \|A+I-1\| past this → classify into pain/useless |

## Caps, by file

One table for each of the 83 files that declare a cap — the 208 caps counted above, and no parameter.

### `src/abicheck.h`

Discloses: **none**

| constant | value | class | note |
| --- | --- | --- | --- |
| `kMaxStructsPerRef` | `12` | OUTPUT | display cap per ref (mirrors crossref::kStrayFilesPerRef); --detail lifts it |

### `src/accessshape.h`

Discloses: `loops_capped`

| constant | value | class | note |
| --- | --- | --- | --- |
| `kMaxLoopsModeled` | `20000` | — | — |
| `kQueryBudget` | `50000` | — | — |

### `src/atoms.h`

Discloses: **none**

| constant | value | class | note |
| --- | --- | --- | --- |
| `kAtomsQueryBudget` | `100000` | — | — |

### `src/binstale.h`

Discloses: **none**

| constant | value | class | note |
| --- | --- | --- | --- |
| `kMaxTrackedFiles` | `20000` | — | — |

### `src/cachelint.h`

Discloses: **none**

| constant | value | class | note |
| --- | --- | --- | --- |
| `kCacheQueryBudget` | `100000` | — | — |

### `src/cli.h`

Discloses: `bridges_capped`, `files_capped`, `inc_capped`, `modules_capped`, `rows_capped`, `sibs_capped`, `syms_capped`, `tests_capped`, `unflagged_capped`, `untested_capped`

| constant | value | class | note |
| --- | --- | --- | --- |
| `kConnectRadiusMax` | `12` | — | == connectcfg::kMaxRadius (static_assert at the seam in main.cpp) |
| `kIntFlagMax` | `1000000000` | — | parsePosInt/parseNonNegInt's own overflow ceiling |
| `kPageValueMax` | `1000000000` | — | — |

### `src/cloneidiom.h`

Discloses: **none**

| constant | value | class | note |
| --- | --- | --- | --- |
| `kIdiomMaxCondTokens` | `8` | BOUNDARY | `( a.b < Limit::Hi )` is 7; anything longer is not a scalar threshold |
| `kIdiomMaxLabelTokens` | `6` | BOUNDARY | `case Enum::Member :` |
| `kIdiomMaxReturnTokens` | `6` | BOUNDARY | `return Enum::Member ;` is 3; a call or an expression is not a table return |

### `src/clones.h`

Discloses: **none**

| constant | value | class | note |
| --- | --- | --- | --- |
| `kType3MaxBucket` | `1024` | INDEXING | skip fingerprint buckets larger than this (stop-gram cut) |
| `kType3MaxTokensForLcs` | `4096` | INDEXING | cap the LCS DP dimension per body (cost guard) |

### `src/commentcoherence.h`

Discloses: **none**

| constant | value | class | note |
| --- | --- | --- | --- |
| `kCommentCoherenceRowCap` | `40` | — | same shape as --readability's 40 |

### `src/contextratio.h`

Discloses: `defs_capped`, `files_capped`, `syms_capped`

| constant | value | class | note |
| --- | --- | --- | --- |
| `kDefsPerNameCap` | `8` | — | — |
| `kFileRowCap` | `40` | — | — |
| `kSymbolRowCap` | `40` | — | — |

### `src/crossref.h`

Discloses: **none**

| constant | value | class | note |
| --- | --- | --- | --- |
| `kMaxGitWorkers` | `12` | — | matches the ingest pool's measured ~12-way; these are |
| `kMaxRefs` | `512` | INDEXING | refusal bound — a sweep, not a fork-network crawl |
| `kWhereisHits` | `60` | OUTPUT | — |

### `src/darkflags.h`

Discloses: `reads_capped`

| constant | value | class | note |
| --- | --- | --- | --- |
| `kMaxAliasDepth` | `8` | INDEXING | — |
| `kMaxEnvNameLen` | `128` | BOUNDARY | longest plausible environment-variable name |
| `kMaxSitesShown` | `8` | OUTPUT | <read> sites per gate; a DEFAULT, raisable by --limit=N (effectiveRowCap), lifted by --detail |

### `src/didyoumean.h`

Discloses: **none**

| constant | value | class | note |
| --- | --- | --- | --- |
| `kMaxEditDistance` | `3` | BOUNDARY | bandwidth cutoff: beyond this edit distance a "hint" is noise, not help |
| `kMaxEditDistance` | `3` | BOUNDARY | same bandwidth cutoff as didYouMean |

### `src/dmm.h`

Discloses: **none**

| constant | value | class | note |
| --- | --- | --- | --- |
| `kUnitComplexityLowRiskMax` | `5` | BOUNDARY | cyclomatic complexity |
| `kUnitInterfacingLowRiskMax` | `2` | BOUNDARY | parameters |
| `kUnitSizeLowRiskMax` | `15` | BOUNDARY | lines |

### `src/docdrift.h`

Discloses: `failed_capped`, `importers_capped`, `weak_capped`

| constant | value | class | note |
| --- | --- | --- | --- |
| `kMaxAnchorsShown` | `12` | OUTPUT | failed anchors per doc; a SECONDARY listing (pageview.h rule 6) — --detail lifts it, --limit does not |
| `kMaxClaimedLine` | `200000` | BOUNDARY | past this a "line number" is a hostile-input example, not a claim |
| `kMaxDecDigits` | `10` | BOUNDARY | overflow guard on a doc/code integer literal |
| `kMaxExtLen` | `6` | BOUNDARY | "cpp", "swift", "metal" — longer is not an extension |
| `kMaxFrontMatter` | `12` | — | — |
| `kMaxHexDigits` | `15` | BOUNDARY | …hex fits 15 nibbles in 64 bits with room to spare |
| `kMaxNameLen` | `96` | BOUNDARY | past this it is a sentence, not an identifier |
| `kMinMentionLen` | `4` | BOUNDARY | a backticked name shorter than this is prose, not code |
| `kMinValueNameLen` | `3` | BOUNDARY | …and the bar for a `= N` / `[N]` subject name |

### `src/editcheck.h`

Discloses: `unflagged_capped`

| constant | value | class | note |
| --- | --- | --- | --- |
| `kEditCheckSpellingsShown` | `6` | OUTPUT | — |

### `src/editpreview.h`

Discloses: **none**

| constant | value | class | note |
| --- | --- | --- | --- |
| `kPreviewOverwriteBudgetBytes` | `4096` | — | — |

### `src/ensemble.h`

Discloses: `files_capped`, `findings_capped`, `syms_capped`

| constant | value | class | note |
| --- | --- | --- | --- |
| `kEnsembleFileRowCap` | `20` | — | — |
| `kEnsembleSymbolRowCap` | `40` | — | — |
| `kOrdinalWindowCap` | `40` | — | — |

### `src/eval.h`

Discloses: **none**

| constant | value | class | note |
| --- | --- | --- | --- |
| `kMaxSample` | `80` | INDEXING | — |
| `kMaxScored` | `4000` | INDEXING | — |

### `src/expand.h`

Discloses: **none**

| constant | value | class | note |
| --- | --- | --- | --- |
| `kExpandMaxPer` | `8` | OUTPUT | — |
| `kExpandMaxSeeds` | `8` | OUTPUT | out-of-range env means OFF, never a clamp-and-guess |

### `src/fieldaffinity.h`

Discloses: `aggs_capped`, `as_loops_capped`, `as_query_capped`

| constant | value | class | note |
| --- | --- | --- | --- |
| `kMaxAggsModeled` | `8000` | INDEXING | refusal bound on the whole-repo modelling pass |
| `kMaxFieldsShown` | `32` | OUTPUT | per struct (touched fields only) |
| `kMaxFnsShown` | `8` | OUTPUT | per struct |
| `kMaxPairsShown` | `12` | OUTPUT | per struct |
| `kMaxScopeChars` | `120` | OUTPUT | displayed prefix of a PROFILE_SCOPE description |
| `kMaxStructsShown` | `20` | OUTPUT | whole-repo form: the ranked head, `capped="1"` past it |

### `src/filepool.h`

Discloses: **none**

| constant | value | class | note |
| --- | --- | --- | --- |
| `kPoolMaxTopK` | `32` | — | env values outside range mean OFF, never a clamp-and-guess |

### `src/flipimpact.h`

Discloses: `hosts_capped`

| constant | value | class | note |
| --- | --- | --- | --- |
| `kMaxBindings` | `32` | INDEXING | value-style constants tracked — bounds pass B's needle count |
| `kMaxChainDepth` | `8` | INDEXING | alias-chain depth cap (mirrors darkflags::kMaxAliasDepth) |
| `kMaxFamily` | `64` | INDEXING | gates one flip may light — an alias fan-out past this is a table, not a switch |
| `kMaxFlipRows` | `25` | OUTPUT | per emitted list; a DEFAULT --limit=N raises and --detail lifts |
| `kMaxNearMisses` | `5` | OUTPUT | "did you mean" suggestions on an unknown gate name; --limit=N raises it |

### `src/gitmine.h`

Discloses: `coboost_commits_capped`, `coboost_partners_capped`

| constant | value | class | note |
| --- | --- | --- | --- |
| `kCoBoostMaxFilesPerCommit` | `30` | INDEXING | same bulk-commit cap as the other co-change miners here |
| `kCoBoostMaxPartnerFiles` | `8` | INDEXING | strongest partners only, by (deg desc, path asc) |
| `kCoBoostMaxSymbolsPerFile` | `3` | INDEXING | per partner file: its top-3 symbols by (lens score desc, id asc) |

### `src/gitoracle.h`

Discloses: **none**

| constant | value | class | note |
| --- | --- | --- | --- |
| `kMaxNameLen` | `96` | BOUNDARY | past this it is a minified blob, not an identifier |
| `kMaxNamesTracked` | `2000000` | INDEXING | map bound; 44,904 on the deepest repo measured |
| `kMaxProbeCommits` | `40000` | INDEXING | walk bound — past it, misses are "unknown", never "never" |
| `kMinNameLen` | `4` | BOUNDARY | — |

### `src/graph.h`

Discloses: `importers_capped`

| constant | value | class | note |
| --- | --- | --- | --- |
| `kChaConeCap` | `4096` | INDEXING | per-walk discovery cap, unchanged from the per-call walk |
| `kMaxEdges` | `256` | — | total emitted edge cap |
| `kMaxNodes` | `96` | — | total emitted node cap (§3 size caps) |
| `kMaxRadius` | `12` | — | — |
| `kMaxTerminals` | `16` | — | >16 is the CALLER's usage error; the core CLAMPS (never VERIFYs on hostile input) |
| `kMemberSpellingsShown` | `6` | OUTPUT | — |

### `src/handoff.h`

Discloses: `syms_capped`

| constant | value | class | note |
| --- | --- | --- | --- |
| `kHandoffCochangeRows` | `8` | OUTPUT | heuristic co-change rows shown |
| `kHandoffDocRows` | `4` | OUTPUT | heuristic doc pointers shown |
| `kHandoffNoteRows` | `8` | OUTPUT | heuristic note rows shown |
| `kHandoffSymbolsPerCodeFile` | `50` | OUTPUT | — |
| `kHandoffSymbolsPerDocFile` | `12` | OUTPUT | — |

### `src/infra/blanktext.h`

Discloses: **none**

| constant | value | class | note |
| --- | --- | --- | --- |
| `kBlankSpellingMaxCodePoints` | `8` | — | — |

### `src/infra/fieldid.h`

Discloses: **none**

| constant | value | class | note |
| --- | --- | --- | --- |
| `kFieldIdCapacity` | `64` | — | — |

### `src/infra/profilePmc.h`

Discloses: **none**

| constant | value | class | note |
| --- | --- | --- | --- |
| `kMaxEvents` | `8` | — | — |

### `src/infra/sortutil.h`

Discloses: **none**

| constant | value | class | note |
| --- | --- | --- | --- |
| `kRadixThreshold` | `128` | BOUNDARY | — |
| `kRadixThreshold` ×2 | `2048` | BOUNDARY | — |

### `src/infra/strkern.h`

Discloses: **none**

| constant | value | class | note |
| --- | --- | --- | --- |
| `kMaxBlockBytes` | `32` | — | — |

### `src/ingest.h`

Discloses: `ellipsis_capped`, `hits_capped`

| constant | value | class | note |
| --- | --- | --- | --- |
| `kBinarySniffCap` | `4096` | — | NUL-byte sniff window |
| `kMaxSkipRowsPerClass` | `500` | OUTPUT | — |
| `kUnreachableMaxHits` | `5000` | — | — |

### `src/ingest_astquery.h`

Discloses: **none**

| constant | value | class | note |
| --- | --- | --- | --- |
| `kMaxEditDistance` | `3` | BOUNDARY | same bandwidth as didYouMean()'s symbol-name cutoff |

### `src/ingest_model.h`

Discloses: **none**

| constant | value | class | note |
| --- | --- | --- | --- |
| `kRadixThreshold` | `64` | BOUNDARY | — |

### `src/ingest_names.h`

Discloses: **none**

| constant | value | class | note |
| --- | --- | --- | --- |
| `kMaxQualifierHops` | `32` | INDEXING | `a::b::c::…` past 32 segments is not written C++ |

### `src/ingest_parsepool.h`

Discloses: **none**

| constant | value | class | note |
| --- | --- | --- | --- |
| `kCapPerThread` | `256` | — | — |
| `kMaxPendingParsedFiles` | `4` | — | — |

### `src/ingest_relations.h`

Discloses: **none**

| constant | value | class | note |
| --- | --- | --- | --- |
| `kMaxImportContainerDepth` | `256` | INDEXING | — |

### `src/ingest_sidecap.h`

Discloses: **none**

| constant | value | class | note |
| --- | --- | --- | --- |
| `kSideDepthStd` | `256` | INDEXING | FFI / routes / bindings — their own guard |
| `kSideDepthUses` | `512` | INDEXING | value-uses — twice the others, as it always was |

### `src/landingplan.h`

Discloses: **none**

| constant | value | class | note |
| --- | --- | --- | --- |
| `kMaxPlanScout` | `12` | OUTPUT | — |

### `src/lanes.h`

Discloses: `blast_capped`, `tests_capped`

| constant | value | class | note |
| --- | --- | --- | --- |
| `kMaxBlastFiles` | `40` | — | blast-radius file rows per lane; total + capped always reported |
| `kMaxTestRows` | `40` | — | tests_to_run rows per lane; same "never drop without a number" |

### `src/layout.h`

Discloses: **none**

| constant | value | class | note |
| --- | --- | --- | --- |
| `kMaxAssertChars` | `220` | OUTPUT | the displayed prefix of a static_assert's text |
| `kMaxDefsShown` | `24` | BOUNDARY | a name defined more often than this is a generic, not a mirror |
| `kMaxMacroDepth` | `4` | INDEXING | object-like macro expansion depth for a type name |
| `kMaxNestDepth` | `8` | INDEXING | nested-aggregate resolution depth (a cycle stops here) |

### `src/lexical.h`

Discloses: **none**

| constant | value | class | note |
| --- | --- | --- | --- |
| `kMaxAnchorDefs` | `3` | — | — |
| `kMaxIdentifierLookupWords` | `2` | — | — |
| `kMaxLen` | `64` | — | — |
| `kMaxShown` | `4` | OUTPUT | — |

### `src/lintcatalog.h`

Discloses: **none**

| constant | value | class | note |
| --- | --- | --- | --- |
| `kMaxEditDistance` | `3` | BOUNDARY | — |

### `src/lintrules.h`

Discloses: **none**

| constant | value | class | note |
| --- | --- | --- | --- |
| `kLintMaxPerRule` | `5000` | — | — |

### `src/main.cpp`

Discloses: **none**

| constant | value | class | note |
| --- | --- | --- | --- |
| `kRecentRows` | `40` | — | F3: ~45 B a row; the file-level answer, not the file list |

### `src/mcpedit.h`

Discloses: **none**

| constant | value | class | note |
| --- | --- | --- | --- |
| `kMaxEditDistance` | `3` | BOUNDARY | the read verbs' bandwidth (didyoumean.h::didYouMean) |
| `kReceiptRegionBudgetBytes` | `2048` | — | — |

### `src/mcpjson.h`

Discloses: **none**

| constant | value | class | note |
| --- | --- | --- | --- |
| `kFrameEchoCaptureBytes` | `240` | — | > mcprefusal.h's kMcpEchoMaxBytes, so the cap still shows |

### `src/mcprefusal.h`

Discloses: **none**

| constant | value | class | note |
| --- | --- | --- | --- |
| `kMaxEditDistance` | `3` | BOUNDARY | same bandwidth cutoff nearestName searches within |
| `kMaxEditDistance` | `3` | BOUNDARY | — |
| `kMcpEchoMaxBytes` | `160` | — | — |

### `src/mcpverbs.h`

Discloses: `blast_radius_capped`, `coboost_commits_capped`, `forgotten_capped`, `hits_capped`, `unindexed_candidates_capped`

| constant | value | class | note |
| --- | --- | --- | --- |
| `kBatchCap` | `16` | — | max sub-queries processed per batch; excess is REPORTED, never silently dropped |
| `kMcpPageValueMax` | `1000000000` | — | == cli.h's kPageValueMax |
| `kMcpRecallTopKMax` | `1000` | — | — |
| `kOtherDefCap` | `4` | OUTPUT | disclosure, not a listing — cap the tail |
| `kRowCap` | `100` | — | — |

### `src/mention.h`

Discloses: `doc_mentions_capped`, `mention_files_capped`, `mention_syms_capped`, `mention_tokens_capped`

| constant | value | class | note |
| --- | --- | --- | --- |
| `kDocMentionMaxAnchors` | `8` | INDEXING | consult only the current top-N anchors |
| `kDocMentionMaxDocsPerAnchor` | `2` | INDEXING | strongest-anchor-first, capped per anchor |
| `kDocMentionMaxDocsTotal` | `6` | INDEXING | global cap — bounds token cost regardless of fan-out |
| `kMentionMaxDirectSymbols` | `8` | INDEXING | directly-named (Scope.name / `name`) symbols, id asc |
| `kMentionMaxFiles` | `4` | INDEXING | strongest evidence only: files named first in the text |
| `kMentionMaxRawTokens` | `16` | INDEXING | extraction cap: first N candidate mention tokens, text order |
| `kMentionMaxSymbolsPerFile` | `3` | INDEXING | per mentioned file: its top symbols by (lens score desc, id asc) |

### `src/model.h`

Discloses: **none**

| constant | value | class | note |
| --- | --- | --- | --- |
| `kMaxWorkspaceRoots` | `16` | — | — |

### `src/namingconsistency.h`

Discloses: **none**

| constant | value | class | note |
| --- | --- | --- | --- |
| `kRowCap` | `40` | — | same shape as --hotspots/--readability's 40 |

### `src/naminglens.h`

Discloses: **none**

| constant | value | class | note |
| --- | --- | --- | --- |
| `kConfusableGroupMax` | `512` | — | beyond this many co-visible names the O(n²) pair scan |

### `src/nextverb.h`

Discloses: **none**

| constant | value | class | note |
| --- | --- | --- | --- |
| `kNextAttrMaxBytes` | `120` | — | — |

### `src/nonlocalstate.h`

Discloses: `cells_capped`, `decls_capped`

| constant | value | class | note |
| --- | --- | --- | --- |
| `kCellsPerRowCap` | `12` | — | — |
| `kDeclMatchBudget` | `40000` | — | — |
| `kMaxCells` | `2048` | — | — |
| `kRowCap` | `40` | — | — |

### `src/packtask.h`

Discloses: `mention_syms_capped`, `ranking_capped`

| constant | value | class | note |
| --- | --- | --- | --- |
| `kOverCeilingKeyBytes` | `22` | — | `,"over_ceiling":true` + the closing brace |
| `kPackTaskRankTopN` | `12` | — | ranking = the top-12 head, not the full 40 — leaves budget for the later sections |

### `src/pageview.h`

Discloses: `count_capped`, `findings_capped`, `hits_capped`, `importers_capped`, `modules_capped`

| constant | value | class | note |
| --- | --- | --- | --- |
| `kCallHierarchyRowCap` | `40` | — | — |
| `kCochangePartnerCap` | `30` | — | — |
| `kExternalSurfaceRowCap` | `100` | — | names, by ref count (≈ 5.2 KB on this repo) |
| `kImportReachRowCap` | `40` | — | — |
| `kPageDisclosureCap` | `224` | — | — |
| `kTreeRowCap` | `80` | — | files, by best symbol's rank: 80 rows ≈ 11.5 KB on this repo (100 = 14.3 KB) |
| `kUseSiteRowCap` | `100` | — | — |
| `kZoomTopModuleCap` | `40` | — | top-level modules, size desc (their children ride along: levels_shown=2) |

### `src/partition.h`

Discloses: **none**

| constant | value | class | note |
| --- | --- | --- | --- |
| `kMaxPartitions` | `16` | BOUNDARY | — |

### `src/pattern.h`

Discloses: `hits_capped`

| constant | value | class | note |
| --- | --- | --- | --- |
| `kMaxHits` | `5000` | — | same per-verb budget --match spends |
| `kMaxMetavars` | `32` | — | bindings live in a fixed-size env on the stack |
| `kMaxPatternBytes` | `4096` | — | a pattern is a code SHAPE, not a file |

### `src/prcontext.h`

Discloses: **none**

| constant | value | class | note |
| --- | --- | --- | --- |
| `kPrDefaultBudgetTokens` | `8000` | — | — |

### `src/quality.h`

Discloses: **none**

| constant | value | class | note |
| --- | --- | --- | --- |
| `kMaxCacheBlobAgeDays` | `30.0` | BOUNDARY | — |
| `kMaxCacheBlobCount` | `4096` | BOUNDARY | bound every future hygiene scan |
| `kMaxEditLockAgeDays` | `1.0` | BOUNDARY | — |
| `kRenameMaxChain` | `8` | INDEXING | a→b→c… chain depth followed from one current path (disclosed) |
| `kRenameMaxPairs` | `4000` | INDEXING | hard cap on recorded pairs (disclosed when hit) |

### `src/qualitypanel.h`

Discloses: `findings_capped`

| constant | value | class | note |
| --- | --- | --- | --- |
| `kPanelRowCap` | `40` | — | — |

### `src/readability.h`

Discloses: **none**

| constant | value | class | note |
| --- | --- | --- | --- |
| `kReadabilityRowCap` | `40` | — | — |

### `src/recall.h`

Discloses: **none**

| constant | value | class | note |
| --- | --- | --- | --- |
| `kDefaultRecallMaxTokens` | `8000` | — | — |

### `src/redact.h`

Discloses: **none**

| constant | value | class | note |
| --- | --- | --- | --- |
| `kGenericMinRunLength` | `32` | — | — |

### `src/renamemine.h`

Discloses: **none**

| constant | value | class | note |
| --- | --- | --- | --- |
| `kMaxCandidates` | `200000` | INDEXING | vote-map bound; 560 on the deepest history measured |
| `kMaxHunkSide` | `24` | INDEXING | per-side cap on the O(n²) line pairing; over-wide hunks are dropped + counted |
| `kMaxIdentLen` | `96` | BOUNDARY | past this it is a minified blob, not an identifier |
| `kMaxIdentsPerLine` | `256` | INDEXING | a line with more tokens than this is not hand-written code |
| `kMaxLineLen` | `2000` | BOUNDARY | a line this long is generated/vendored, not a rename site |
| `kMinIdentLen` | `2` | BOUNDARY | — |

### `src/resolve.h`

Discloses: **none**

| constant | value | class | note |
| --- | --- | --- | --- |
| `kFieldWalkCap` | `16` | INDEXING | total visited names — bounds depth and width together |

### `src/search.h`

Discloses: `hits_capped`

| constant | value | class | note |
| --- | --- | --- | --- |
| `kGrepCollectionBudget` | `4000000` | — | — |
| `kGrepMatchedLineMaxBytes` | `512` | — | — |
| `kGrepTierFileBudget` | `128` | — | hit files classified per call |
| `kMaxAffixSet` | `8` | — | cap on prefix/suffix set sizes |
| `kMaxExactLen` | `24` | — | beyond this exact-string length, give up exactness (⊤) |
| `kMaxExactSet` | `8` | — | beyond this many exact strings, give up exactness (⊤) |

### `src/selectorrefuse.h`

Discloses: **none**

| constant | value | class | note |
| --- | --- | --- | --- |
| `kSelectorFilesShown` | `6` | OUTPUT | — |

### `src/serialize.h`

Discloses: `calls_capped`, `inc_capped`, `sibs_capped`

| constant | value | class | note |
| --- | --- | --- | --- |
| `kCap` | `65536` | — | — |
| `kForAnchorBodyBudgetBytes` | `22800` | — | — |
| `kForAutoBodyBudgetBytes` | `6000` | — | — |
| `kForCapTailSigBytes` | `96` | — | — |
| `kForCompactSurfaceBudgetBytes` | `1000` | — | — |
| `kForFileTailShownCap` | `24` | — | — |
| `kForLensDefaultTopN` | `40` | — | — |
| `kForPayloadBudgetBytes` | `7500` | — | — |
| `kMaxExpandIncludes` | `24` | — | inc= cap |
| `kMaxExpandSibs` | `100` | — | sibs= cap — a BLOW-UP GUARD, set above the tail, not a trim of the |
| `kMaxSig` | `240` | OUTPUT | — |
| `kWithGraphNodeCap` | `8` | — | — |

### `src/siblift.h`

Discloses: **none**

| constant | value | class | note |
| --- | --- | --- | --- |
| `kSibliftMaxSeed` | `4` | OUTPUT | env values outside [1, kSibliftMax*] mean OFF, never a clamp-and-guess |
| `kSibliftMaxSib` | `4` | OUTPUT | — |

### `src/situ.h`

Discloses: `tests_capped`, `untested_capped`

| constant | value | class | note |
| --- | --- | --- | --- |
| `kMaxUntestedRows` | `25` | — | — |
| `kSituBlastFilesShown` | `8` | OUTPUT | section [1] — blast-radius file rows; a raisable DEFAULT |
| `kSituPartnerFileRowsShown` | `4` | OUTPUT | section [1] — decl/def partner rows |
| `kSituPartnerRowsShown` | `8` | OUTPUT | section [3] — co-change partner rows; a raisable DEFAULT |

### `src/skillscan.h`

Discloses: **none**

| constant | value | class | note |
| --- | --- | --- | --- |
| `kSkillScanFindingCap` | `200` | INDEXING | generous for one file or a small dir; caps a pathological --scan-skills sweep |

### `src/slice.h`

Discloses: **none**

| constant | value | class | note |
| --- | --- | --- | --- |
| `kSliceFlowDefaultDepth` | `8` | — | the disclosed default bound (depth= always states it) |
| `kSliceFlowDepthMax` | `32` | — | — |
| `kSliceFlowDepthMin` | `1` | — | — |
| `kSliceRdMaxIter` | `64` | OUTPUT | — |

### `src/slicediff.h`

Discloses: `diff_capped`

| constant | value | class | note |
| --- | --- | --- | --- |
| `kMaxDiffRows` | `2000` | — | — |
| `kMaxRenameHops` | `8` | — | — |

### `src/taskroute.h`

Discloses: **none**

| constant | value | class | note |
| --- | --- | --- | --- |
| `kMinWeakSymbolLen` | `5` | — | — |

### `src/tracelocus.h`

Discloses: `name_ladder_capped`

| constant | value | class | note |
| --- | --- | --- | --- |
| `kMeasuredDigitsPricedWidth` | `6` | OUTPUT | — |
| `kNameCandidateCap` | `8` | OUTPUT | — |
| `kTestHopBasenameRowCap` | `3` | OUTPUT | — |
| `kTestHopCalleeRowCap` | `5` | OUTPUT | — |

### `src/verbs_change.h`

Discloses: `seed_files_capped`

| constant | value | class | note |
| --- | --- | --- | --- |
| `kRunTraceRelevantLinesCap` | `40` | — | <lines view="relevant"> cap (first/last half split past it) |

### `src/verbs_doctor.h`

Discloses: **none**

| constant | value | class | note |
| --- | --- | --- | --- |
| `kShown` | `8` | OUTPUT | — |

### `src/verbs_for.h`

Discloses: `coboost_commits_capped`

| constant | value | class | note |
| --- | --- | --- | --- |
| `kJsonEnvelopeDigitsMax` | `10` | — | — |

### `src/verbs_lint.h`

Discloses: `count_capped`, `ellipsis_capped`, `findings_capped`, `hits_capped`, `rows_capped`

| constant | value | class | note |
| --- | --- | --- | --- |
| `kMatchMaxHits` | `5000` | INDEXING | astQuery's per-spec budget, named not implied |

### `src/verbs_navigate.h`

Discloses: `importers_capped`

| constant | value | class | note |
| --- | --- | --- | --- |
| `kEvidenceCap` | `20` | OUTPUT | — |

