# Limits

**Generated — do not edit.** `python3 docs/limits_build.py` writes this file and
`test/limitstablecheck.sh` fails if it drifts from `src/`.

Every compile-time cap in `src/`, what it bounds, and whether its file discloses a truncation when
it fires. A cap is a **routing decision**: it decides what an agent can and cannot find. Set one
where the pathological tail is, never near the typical case — and when it fires, say so
(`*_capped="1"` with a `*_total=`), because a silent cut reads to the caller as "none exists". A file that emits
a window (`<x total= shown= capped=>`, or its JSON twin's `"capped":`) discloses `capped`.

A row is pinned by what a cap IS — its file, name, value, class and note — never by the line it sits
on, so a comment rewritten or a helper deleted above a cap changes no row here and cannot stale this
document. To reach a declaration, search its file for the name (`grep -n <name> <file>`, or
`ripwire . --grep=<name>`). A file that declares the same name, value and note more than once shows
it once, marked `×N`.

**Residual — a single pathological match is unbounded on libstdc++, narrowed but NOT closed.** One `std::regex`
call is atomic to its caller, so no caller-side counter can see the work inside one, and libstdc++'s engine
never throws; libc++ returns only because its ENGINE throws `error_complexity`. The screen now REFUSES the two
multi-quantifier shapes it used to admit — `a*a*a*a*a*b` (adjacent unbounded quantifiers whose atoms are not
proven disjoint, flat or grouped as `^(a)*(a)*(a)*(a)*(a)*$`) and `^(ab\w|((.|.){1,3}){1,3}){1,3}$` (an
unprovable alternation repeated within a repeat) — by name and before any engine sees the pattern, which is
`regex-screen-multiquantifier`'s closure (`test/regexmultiquantcheck.sh`). **What remains open is the general
case**, and it is still reachable: any ADMITTED pattern whose cost in the subject is super-linear. The family is
not provable shape-by-shape — `(a|aa){1,100}b$` is admitted (a bounded outer over a branch that repeats itself
only through the outer quantifier, so no clause fires), yet it is exponential on libstdc++: measured 7.8 ms at a
21-byte subject, 517 ms at 29 B, 13.8 s at 37 B, 99.1 s at 41 B (roughly 7x per 4 bytes). On libc++ the same
pattern throws `error_complexity` from an 18-byte subject up, which is the engine giving up, not a bound
holding. That is the class this paragraph keeps open; it is named here rather than left to be discovered. (The
guard's former per-file match budget — `kRegexFileMatchBudget`, removed in the PR #397 review — cannot be
revived against this residual: it counted line-match attempts BETWEEN engine calls, so it refused fast linear
answers and still bounded nothing inside one call.)

| total caps | files | caps whose file discloses | caps whose file discloses NOTHING |
| --- | --- | --- | --- |
| 333 | 122 | 212 | **121** |

Plus 7 ranking and apportionment parameters, in their own table below: they are not caps, they
are not counted as caps, and 333 + 7 is the 340 constants this generator parses out of `src/`.

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

The `class` column below carries that answer where it is known. **143 of 333 caps are classified
(50 INDEXING, 46 OUTPUT, 47 BOUNDARY); the remaining 190 render `—`, which means NOT YET
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

One table for each of the 122 files that declare a cap — the 333 caps counted above, and no parameter.

### `src/abicheck.h`

Discloses: `capped`

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

Discloses: `count_capped`

| constant | value | class | note |
| --- | --- | --- | --- |
| `kAtomsQueryBudget` | `100000` | — | — |

### `src/backhops.h`

Discloses: **none**

| constant | value | class | note |
| --- | --- | --- | --- |
| `kBackHopWidth` | `16` | — | — |
| `kImpactRingRowCap` | `16` | — | — |
| `kImpactRingSlotDepth` | `3` | — | a field-only chain's depth; pathgaps.h pins it to kBridgeSlotCrossings |

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

### `src/callhierarchy.h`

Discloses: `capped`, `closures_capped`

| constant | value | class | note |
| --- | --- | --- | --- |
| `kClosureRows` | `8` | — | rows per block; count= is the closure's distinct callees, capped="1" past it |

### `src/cli.h`

Discloses: `capped`, `bridges_capped`, `count_capped`, `files_capped`, `inc_capped`, `mention_idents_capped`, `mention_syms_capped`, `modules_capped`, `rows_capped`, `sibs_capped`, `syms_capped`, `tests_capped`, `unflagged_capped`, `untested_capped`

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

Discloses: `type3_capped`

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
| `kMaxRenameProbeFiles` | `32` | INDEXING | HEAD copies one rename probe reads; past it the probe stops (a hint, never a claim) |
| `kMaxWorktreePaths` | `8192` | INDEXING | — |
| `kWhereisHits` | `60` | OUTPUT | — |
| `kWhereisParseMaxBlobs` | `256` | — | — |
| `kWhereisTextPreviewCapBytes` | `200` | OUTPUT | the printed preview, the ellipsis included |
| `kWhereisTextWholeMaxBytes` | `300` | OUTPUT | a line up to this prints whole, so a cut drops 100+ bytes |

### `src/darkflags.h`

Discloses: `capped`, `reads_capped`

| constant | value | class | note |
| --- | --- | --- | --- |
| `kMaxAliasDepth` | `8` | INDEXING | — |
| `kMaxEnvNameLen` | `128` | BOUNDARY | longest plausible environment-variable name |
| `kMaxSitesShown` | `8` | OUTPUT | <read> sites per gate; a DEFAULT, raisable by --limit=N (effectiveRowCap), lifted by --detail |

### `src/declinedsites.h`

Discloses: **none**

| constant | value | class | note |
| --- | --- | --- | --- |
| `kDeclinedSiteCandCap` | `8` | — | cand= entries per row on --legend=full; cand_more= counts the rest |
| `kDeclinedSiteCap` | `16` | — | <dc> rows per answer by default; --limit=N raises it (dc_next= does) |

### `src/defattrib.h`

Discloses: **none**

| constant | value | class | note |
| --- | --- | --- | --- |
| `kDefTableCap` | `16` | — | — |

### `src/defslookup.h`

Discloses: **none**

| constant | value | class | note |
| --- | --- | --- | --- |
| `kDefsNamesMax` | `16` | — | — |

### `src/degradedscan.h`

Discloses: **none**

| constant | value | class | note |
| --- | --- | --- | --- |
| `kDegradedScanFiles` | `32` | — | — |

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

Discloses: `capped`, `failed_capped`, `weak_capped`

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

Discloses: `capped`, `unflagged_capped`

| constant | value | class | note |
| --- | --- | --- | --- |
| `kEditCheckSpellingsShown` | `6` | OUTPUT | — |

### `src/editcheckdecl.h`

Discloses: **none**

| constant | value | class | note |
| --- | --- | --- | --- |
| `kEditCheckSigCap` | `16384` | — | disclosed as defaults_untied= beside a nonzero incompatible= |

### `src/editpreview.h`

Discloses: `capped`

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

### `src/epmanifest.h`

Discloses: `entries_capped`, `groups_capped`, `used_capped`

| constant | value | class | note |
| --- | --- | --- | --- |
| `kForEpEntryRows` | `12` | — | entries shown per group |
| `kForEpGroupRows` | `4` | — | groups per answer |
| `kForEpUsedAtRows` | `3` | — | consumer sites shown per group (used_total= counts all) |

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

Discloses: `capped`, `aggs_capped`, `as_loops_capped`, `as_query_capped`

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
| `kPoolLiftFiles` | `10` | — | FIXED, not a grid axis: the @10 window is what this targets |
| `kPoolMaxTopK` | `32` | — | env values outside range mean OFF, never a clamp-and-guess |

### `src/flipimpact.h`

Discloses: `capped`, `hosts_capped`

| constant | value | class | note |
| --- | --- | --- | --- |
| `kMaxBindings` | `32` | INDEXING | value-style constants tracked — bounds pass B's needle count |
| `kMaxChainDepth` | `8` | INDEXING | alias-chain depth cap (mirrors darkflags::kMaxAliasDepth) |
| `kMaxFamily` | `64` | INDEXING | gates one flip may light — an alias fan-out past this is a table, not a switch |
| `kMaxFlipRows` | `25` | OUTPUT | per emitted list; a DEFAULT --limit=N raises and --detail lifts |
| `kMaxNearMisses` | `5` | OUTPUT | "did you mean" suggestions on an unknown gate name; --limit=N raises it |

### `src/forcallerhop.h`

Discloses: `capped`

| constant | value | class | note |
| --- | --- | --- | --- |
| `kForCallerHopDepth2Rows` | `4` | — | — |
| `kForCallerHopRows` | `16` | — | — |
| `kForRankedHopHeadRows` | `3` | BOUNDARY | r=1..3: the emitted head the seed is read from |
| `kForRankedHopMaxCallers` | `3` | BOUNDARY | the narrow-funnel bar: a wider fan-in is the callers verb's page, not a chain |

### `src/forctorhop.h`

Discloses: **none**

| constant | value | class | note |
| --- | --- | --- | --- |
| `kForCtorHopCap` | `16` | — | callee names listed on ctor_calls=; the rest counted in ctor_calls_more= |

### `src/fordispatchhop.h`

Discloses: `capped`

| constant | value | class | note |
| --- | --- | --- | --- |
| `kForDispatchCtorRows` | `4` | — | constructor-caller rows per call |
| `kForDispatchHopRows` | `8` | — | candidate rows per call |

### `src/forfilepage.h`

Discloses: `capped`, `bytes_capped`, `dirs_capped`

| constant | value | class | note |
| --- | --- | --- | --- |
| `kForFilePageCallerFiles` | `3` | — | caller files named per def (by_total= counts all) |
| `kForFilePageDefRows` | `40` | — | def rows per file |
| `kForFilePageDirFiles` | `6` | — | files of a named directory given a page each |
| `kForFilePageListFiles` | `8` | — | paths listed when a name matches several files |
| `kForFilePageMaxAnchors` | `2` | — | file tokens of one subject given a page |
| `kForFilePageMaxBytes` | `16384` | — | the whole page: no file or directory starts past it (the first always does) |
| `kForFilePageNextDepth` | `16` | — | calls the next= closure walks from main (said in the legend: a cap, not a fact) |
| `kForFilePageSigBytes` | `160` | — | one def row's signature text |
| `kForFilePageTopBytes` | `2048` | — | top-level bytes served per file |
| `kForFilePageTopLines` | `40` | — | top-level lines served per file |

### `src/forfold.h`

Discloses: **none**

| constant | value | class | note |
| --- | --- | --- | --- |
| `kForBodyFoldBudgetBytes` | `4000` | — | — |
| `kForBodyFoldRows` | `3` | — | — |

### `src/forliteral.h`

Discloses: `capped`

| constant | value | class | note |
| --- | --- | --- | --- |
| `kForLiteralBodyCapBytes` | `3000` | — | a short body over this many bytes is still served as an excerpt <x> |
| `kForLiteralContextRows` | `2` | — | string sites outside any function served with the lines after them |
| `kForLiteralMinBareCaps` | `10` | — | — |
| `kForLiteralRankedRows` | `256` | — | source sites ordered for the rows (past it: counted in src=, not ranked) |
| `kForLiteralSiteRows` | `8` | — | <ls> rows shown (a runaway guard: shown=/src= count, next= lists all) |
| `kForLiteralTierFiles` | `64` | — | source hit files classified (k=); past it k="?" |

### `src/formembers.h`

Discloses: **none**

| constant | value | class | note |
| --- | --- | --- | --- |
| `kForMemberNameCap` | `8` | — | — |

### `src/forowner.h`

Discloses: `capped`

| constant | value | class | note |
| --- | --- | --- | --- |
| `kForBodySlotMaxBytes` | `6000` | — | — |

### `src/forpage.h`

Discloses: `capped`

| constant | value | class | note |
| --- | --- | --- | --- |
| `kForPageRowsDefault` | `40` | OUTPUT | `--for --limit=N` with no N is never accepted (the flag refuses 0); |
| `kForPageUnionSymbolCap` | `8` | INDEXING | symbols per file whose term masks join that file's union |
| `kForThinMinFiles` | `3` | — | a ranked head over fewer files than this ⇒ thin |

### `src/forreexport.h`

Discloses: `capped`

| constant | value | class | note |
| --- | --- | --- | --- |
| `kReexportDefCap` | `2` | — | definitions per word that carry a chain |
| `kReexportNameCap` | `3` | — | task words served |
| `kReexportRowCap` | `8` | — | hop rows per definition (BFS order); the rest counted in total= |
| `kReexportSpellingCap` | `256` | — | spellings one walk visits; past it total= is a floor (capped="1") |
| `kReexportUseCap` | `2` | — | use-site rows per definition, from task-named files |

### `src/forslots.h`

Discloses: **none**

| constant | value | class | note |
| --- | --- | --- | --- |
| `kForSlotByCap` | `4` | — | — |
| `kForSlotCap` | `16` | — | — |

### `src/gitmine.h`

Discloses: `coboost_commits_capped`, `coboost_partners_capped`

| constant | value | class | note |
| --- | --- | --- | --- |
| `kChurnMergeBombMaxFiles` | `100` | INDEXING | the churn rankers' merge-bomb rule; skipped commits are disclosed as <recent merge_bombs_skipped=> |
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

Discloses: `files_capped`, `importers_capped`

| constant | value | class | note |
| --- | --- | --- | --- |
| `kChaConeCap` | `4096` | INDEXING | per-walk discovery cap, unchanged from the per-call walk |
| `kImpactFileRollupCap` | `20` | — | — |
| `kImpactTypeRollupBandMax` | `200` | — | — |
| `kMaxEdges` | `256` | — | total emitted edge cap |
| `kMaxNodes` | `96` | — | total emitted node cap (§3 size caps) |
| `kMaxRadius` | `12` | — | — |
| `kMaxTerminals` | `16` | — | >16 is the CALLER's usage error; the core CLAMPS (never ASSUMEs on hostile input) |
| `kMemberSpellingsShown` | `6` | OUTPUT | — |
| `kPythonReexportHops` | `4` | — | member-import hops provenBasesOf follows (a package re-exporting a re-export) |

### `src/grepcarrier.h`

Discloses: **none**

| constant | value | class | note |
| --- | --- | --- | --- |
| `kGrepCarrierShown` | `3` | — | reads_at= sites and vals= entries printed per row (reads=/vals_total= count all) |

### `src/handlershape.h`

Discloses: **none**

| constant | value | class | note |
| --- | --- | --- | --- |
| `kMentionsNameMaxDepth` | `512` | INDEXING | undisclosed: a deeper subtree answers "mentions it", so a log-only handler that deep is never flagged |

### `src/handoff.h`

Discloses: `capped`, `syms_capped`

| constant | value | class | note |
| --- | --- | --- | --- |
| `kHandoffCochangeRows` | `8` | OUTPUT | heuristic co-change rows shown |
| `kHandoffDocRows` | `4` | OUTPUT | heuristic doc pointers shown |
| `kHandoffNoteRows` | `8` | OUTPUT | heuristic note rows shown |
| `kHandoffSymbolsPerCodeFile` | `50` | OUTPUT | — |
| `kHandoffSymbolsPerDocFile` | `12` | OUTPUT | — |

### `src/hopbody.h`

Discloses: `capped`

| constant | value | class | note |
| --- | --- | --- | --- |
| `kHopBodyCapBytes` | `4000` | — | — |
| `kPathHopBodyMaxHops` | `2` | — | — |
| `kWrapperFollowDepth` | `2` | — | — |
| `kWrapperFollowMax` | `3` | — | — |

### `src/infra/blanktext.h`

Discloses: **none**

| constant | value | class | note |
| --- | --- | --- | --- |
| `kBlankSpellingMaxCodePoints` | `8` | — | — |

### `src/infra/diagnostics.cpp`

Discloses: **none**

| constant | value | class | note |
| --- | --- | --- | --- |
| `kNoticeByteCap` | `4096` | OUTPUT | a longer notice is cut and says so: " ... [notice truncated: kept K of N bytes]" |

### `src/infra/fieldid.h`

Discloses: **none**

| constant | value | class | note |
| --- | --- | --- | --- |
| `kFieldIdCapacity` | `64` | — | — |

### `src/infra/os_win32_logic.h`

Discloses: **none**

| constant | value | class | note |
| --- | --- | --- | --- |
| `kExtendedLengthThresholdUnits` | `248` | BOUNDARY | — |

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
| `kMaxAstQueryNesting` | `256` | BOUNDARY | — |
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
| `kExtendChainCap` | `16` | INDEXING | factory-of-a-factory links the receiver rule follows (nunjucks: 2); past it, no class |
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
| `kBaseScopeScanCap` | `4096` | INDEXING | statements the unindexed scope scans read (not the index) |
| `kMaxImportContainerDepth` | `256` | INDEXING | — |

### `src/ingest_sidecap.h`

Discloses: **none**

| constant | value | class | note |
| --- | --- | --- | --- |
| `kSideDepthStd` | `256` | INDEXING | FFI / routes / bindings — their own guard |
| `kSideDepthUses` | `512` | INDEXING | value-uses — twice the others, as it always was |

### `src/ingest_valuerefs.h`

Discloses: `value_refs_depth_capped`

| constant | value | class | note |
| --- | --- | --- | --- |
| `kVrMaxDepth` | `512` | INDEXING | the value-uses pass's own depth guard (ingest_sidecap.h kSideDepthUses); a cut is disclosed as value_refs_depth_capped= (valuerefs.h) |
| `kVrTextCap` | `96` | — | a written slot / callee longer than this is cut with "…" |

### `src/jsrunner.h`

Discloses: **none**

| constant | value | class | note |
| --- | --- | --- | --- |
| `kMaxTsModulesWalked` | `64` | BOUNDARY | past it the walk is cut and the answer is run_unknown="1", never a guessed command |

### `src/landingplan.h`

Discloses: **none**

| constant | value | class | note |
| --- | --- | --- | --- |
| `kMaxPlanScout` | `12` | OUTPUT | — |

### `src/lanes.h`

Discloses: `capped`, `blast_capped`, `symbols_capped`, `tests_capped`

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
| `kMaxExtentParens` | `64` | BOUNDARY | `(` nesting DEPTH an extent expression may reach (IntEval recurses per level) |
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
| `kMaxUniqueQueryTerms` | `1024` | INDEXING | — |

### `src/lintcatalog.h`

Discloses: **none**

| constant | value | class | note |
| --- | --- | --- | --- |
| `kMaxEditDistance` | `3` | BOUNDARY | — |

### `src/lintrules.h`

Discloses: `count_capped`

| constant | value | class | note |
| --- | --- | --- | --- |
| `kLintMaxPerRule` | `5000` | — | — |

### `src/listedin.h`

Discloses: `capped`, `files_capped`, `manifests_capped`

| constant | value | class | note |
| --- | --- | --- | --- |
| `kListedShownFiles` | `16` | — | distinct shown files whose ancestors are read |

### `src/main.cpp`

Discloses: **none**

| constant | value | class | note |
| --- | --- | --- | --- |
| `kMaxUnservedSelectors` | `16` | — | — |
| `kRecentRows` | `40` | — | F3: ~45 B a row; the file-level answer, not the file list |

### `src/mapinventory.h`

Discloses: `entries_capped`, `names_capped`

| constant | value | class | note |
| --- | --- | --- | --- |
| `kInventoryEntryCap` | `256` | OUTPUT | — |
| `kInventoryNameCeiling` | `2000` | OUTPUT | — |

### `src/mcp.h`

Discloses: `hits_capped`

| constant | value | class | note |
| --- | --- | --- | --- |
| `kMcpStdioLineMaxBytes` | `33554432` | — | 32 MiB |

### `src/mcpedit.h`

Discloses: `capped`

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

Discloses: `capped`, `blast_radius_capped`, `calledBy_capped`, `coboost_commits_capped`, `forgotten_capped`, `hits_capped`, `siblings_capped`, `terms_capped`, `unindexed_candidates_capped`

| constant | value | class | note |
| --- | --- | --- | --- |
| `kBatchCap` | `16` | — | max sub-queries processed per batch; excess is REPORTED, never silently dropped |
| `kMcpPageValueMax` | `1000000000` | — | == cli.h's kPageValueMax |
| `kMcpRecallTopKMax` | `1000` | — | — |
| `kOtherDefCap` | `4` | OUTPUT | disclosure, not a listing — cap the tail |

### `src/mention.h`

Discloses: `doc_mentions_capped`, `mention_files_capped`, `mention_idents_capped`, `mention_syms_capped`, `mention_tokens_capped`

| constant | value | class | note |
| --- | --- | --- | --- |
| `kDocMentionMaxAnchors` | `8` | INDEXING | consult only the current top-N anchors |
| `kDocMentionMaxDocsPerAnchor` | `2` | INDEXING | strongest-anchor-first, capped per anchor |
| `kDocMentionMaxDocsTotal` | `6` | INDEXING | global cap — bounds token cost regardless of fan-out |
| `kMentionMaxDirectSymbols` | `8` | INDEXING | directly-named (Scope.name / identifier) symbols, task-text order kept |
| `kMentionMaxFiles` | `4` | INDEXING | strongest evidence only: files named first in the text |
| `kMentionMaxIdentLifts` | `2` | INDEXING | identifier-resolved symbols admitted per task, task-text order |
| `kMentionMaxNameFiles` | `3` | BOUNDARY | the same specificity bound as lexical.h kMaxAnchorDefs |
| `kMentionMaxNamedIdents` | `64` | INDEXING | — |
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

Discloses: `capped`, `mention_syms_capped`, `ranking_capped`

| constant | value | class | note |
| --- | --- | --- | --- |
| `kOverCeilingKeyBytes` | `22` | — | `,"over_ceiling":true` + the closing brace |
| `kPackTaskRankTopN` | `12` | — | ranking = the top-12 head, not the full 40 — leaves budget for the later sections |

### `src/pageview.h`

Discloses: `capped`, `count_capped`, `findings_capped`, `hits_capped`, `importers_capped`, `modules_capped`, `symbols_capped`

| constant | value | class | note |
| --- | --- | --- | --- |
| `kCallHierarchyRowCap` | `40` | — | — |
| `kCallSitesPerRowCap` | `16` | — | — |
| `kCallersBandMaxBytes` | `16000` | — | callers rows served whole while their estimated bytes fit (tmux 121 rows = 10.8 KB) |
| `kCochangePartnerCap` | `30` | — | — |
| `kExternalSurfaceRowCap` | `100` | — | names, by ref count (≈ 5.2 KB on this repo) |
| `kImportReachRowCap` | `40` | — | — |
| `kPageDisclosureCap` | `224` | — | — |
| `kTreeRowCap` | `80` | — | files, by best symbol's rank: 80 rows ≈ 11.5 KB on this repo (100 = 14.3 KB) |
| `kTreeSymbolsPerFile` | `3` | — | cut-fix E: --tree's <s> rows per <file>, disclosed by the root's shown_symbols=/symbols_capped= |
| `kUseSiteRowCap` | `100` | — | — |
| `kZoomBridgeCap` | `12` | — | cut-fix E: --zoom's <bridge> rows (traffic desc), a secondary listing disclosed by secondaryCutAttrs |
| `kZoomTopModuleCap` | `40` | — | top-level modules, rank-mass desc then size desc then id (massSizeIdLess; their children ride along: levels_shown=2) |

### `src/partition.h`

Discloses: **none**

| constant | value | class | note |
| --- | --- | --- | --- |
| `kMaxPartitions` | `16` | BOUNDARY | — |

### `src/pathgaps.h`

Discloses: `gap_syms_capped`, `rows_capped`

| constant | value | class | note |
| --- | --- | --- | --- |
| `kBridgeMaxHops` | `8` | — | a longer chain is no answer a reader would follow: none is printed |
| `kHandlerRuleListMax` | `16` | — | the bridge's own width limit: at most this many defs are listed as <h> |
| `kHandlerRuleShown` | `3` | — | <hm> rows: the widest posted classes first |
| `kNearSinkDepth` | `2` | — | proven caller hops back from to= (1 = a direct caller) |
| `kNearSinkRows` | `4` | — | <ns> rows printed; rows= counts them all, rows_capped="1" says so |
| `kPathGapRows` | `3` | — | <gap> rows printed; gap_syms= counts them all, gap_syms_capped="1" says so |
| `kRouteBodyMax` | `4` | — | spew guard: bodies per answer; past it capped="1" next= the first unshown |
| `kRouteBodyMaxHops` | `2` | — | bridge rows 0..2 (from= and the next two), never the to= row |

### `src/pathpairs.h`

Discloses: `alt_capped`

| constant | value | class | note |
| --- | --- | --- | --- |
| `kPathPairAltRows` | `12` | — | knob: <alt> rows printed; alt= counts them all, alt_capped="1" says rows were cut |
| `kPathPairMaxDstGroups` | `16` | — | knob: reverse walks per answer; more to= groups keep today's answer |

### `src/pathroute.h`

Discloses: `route_cands_capped`

| constant | value | class | note |
| --- | --- | --- | --- |
| `kPathRouteCandsCeiling` | `1000000` | — | route_cands= saturates here (a product of per-hop counts); route_cands_capped="1" says so |
| `kPathRouteHedgeNameHops` | `2` | — | knob (knob-census ADDENDUM): by-name hops that hedge the root |
| `kPathRouteRefuseCandsThreshold` | `64` | BOUNDARY | knob: route_cands at which a chain of >= kPathRouteRefuseNameHops by-name hops is refused, not hedged (wrong chains 144..23712, true chains <= 16) |
| `kPathRouteRefuseNameHops` | `4` | — | knob: by-name hops (with route_cands >= the threshold below) that refuse the chain |

### `src/pattern.h`

Discloses: `hits_capped`

| constant | value | class | note |
| --- | --- | --- | --- |
| `kMaxHits` | `5000` | — | same per-verb budget --match spends |
| `kMaxMetavars` | `32` | — | bindings live in a fixed-size env on the stack |
| `kMaxPatternBytes` | `4096` | — | a pattern is a code SHAPE, not a file |

### `src/prcontext.h`

Discloses: `capped`

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
| `kMaxFilesPerCommit` | `30` | — | — |
| `kRenameMaxChain` | `8` | INDEXING | a→b→c… chain depth followed from one current path (disclosed) |
| `kRenameMaxPairs` | `4000` | INDEXING | hard cap on recorded pairs (disclosed when hit) |

### `src/qualitypanel.h`

Discloses: `capped`, `findings_capped`

| constant | value | class | note |
| --- | --- | --- | --- |
| `kPanelRowCap` | `40` | — | — |

### `src/query.h`

Discloses: **none**

| constant | value | class | note |
| --- | --- | --- | --- |
| `kMaxQueryNesting` | `256` | BOUNDARY | — |

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

### `src/receiverevidence.h`

Discloses: **none**

| constant | value | class | note |
| --- | --- | --- | --- |
| `kWalkCap` | `64` | INDEXING | classes visited per base walk; deterministic (sorted chaUp) |

### `src/redact.h`

Discloses: **none**

| constant | value | class | note |
| --- | --- | --- | --- |
| `kGenericMinRunLength` | `32` | — | — |

### `src/regexguard.h`

Discloses: **none**

| constant | value | class | note |
| --- | --- | --- | --- |
| `kRegexMaxGroupDepth` | `64` | BOUNDARY | deeper group nesting is REFUSED by name — the same stack bound, for nesting |
| `kRegexMaxPatternBytes` | `2048` | BOUNDARY | a longer pattern is REFUSED by name, never truncated — the compile-recursion stack bound |

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
| `kAliasPeelDepth` | `4` | — | — |
| `kFieldWalkCap` | `16` | INDEXING | total visited names — bounds depth and width together (methodOnTypeOrBases, memberFieldHides and fieldEntryAt) |
| `kMaxDepth` | `64` | — | — |

### `src/search.h`

Discloses: `hits_capped`

| constant | value | class | note |
| --- | --- | --- | --- |
| `kGrepCollectionBudget` | `4000000` | — | — |
| `kGrepLiftRowCap` | `10` | — | a RANKED code+string answer's default window (CLI and MCP alike) |
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

Discloses: `capped`, `calls_capped`, `entries_capped`, `files_capped`, `importers_capped`, `inc_capped`, `names_capped`, `sibs_capped`, `type_capped`

| constant | value | class | note |
| --- | --- | --- | --- |
| `kCap` | `65536` | — | — |
| `kForAnchorBodyBudgetBytes` | `22800` | — | — |
| `kForAutoBodyBudgetBytes` | `6000` | — | — |
| `kForCapTailSigBytes` | `96` | — | — |
| `kForCompactSurfaceBudgetBytes` | `1000` | — | — |
| `kForFileTailPageRows` | `40` | — | FOLD C: page 0 of the file page (forpage.h kForPageRowsDefault) |
| `kForFileTailShownCap` | `24` | — | the rank rows (deep-tail d2): files outside the shown head |
| `kForLensDefaultTopN` | `40` | — | — |
| `kForPayloadBudgetBytes` | `7500` | — | — |
| `kForTailSigBytes` | `160` | — | — |
| `kHeadRoundRobinRows` | `8` | — | — |
| `kLegoClosureRowCap` | `200` | OUTPUT | — |
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

Discloses: `partners_capped`, `tests_capped`, `untested_capped`

| constant | value | class | note |
| --- | --- | --- | --- |
| `kMaxUntestedRows` | `25` | — | — |
| `kSituBlastFilesShown` | `8` | OUTPUT | section [1] — blast-radius file rows; a raisable DEFAULT |
| `kSituCochangeProbeFiles` | `20` | — | section [3] — changed files probed for co-change (cut-fix E: disclosed) |
| `kSituPartnerFileRowsShown` | `4` | OUTPUT | section [1] — decl/def partner rows |
| `kSituPartnerRowsShown` | `8` | OUTPUT | section [3] — co-change partner rows; a raisable DEFAULT |
| `kSituSiblingRowsShown` | `8` | — | section [1] — L-D lexical sibling rows; a raisable DEFAULT |

### `src/skillscan.h`

Discloses: `capped`

| constant | value | class | note |
| --- | --- | --- | --- |
| `kSkillExcerptMaxBytes` | `120` | — | — |
| `kSkillScanFindingCap` | `200` | INDEXING | generous for one file or a small dir; caps a pathological --scan-skills sweep |

### `src/slice.h`

Discloses: **none**

| constant | value | class | note |
| --- | --- | --- | --- |
| `kMaxSliceDepth` | `2048` | BOUNDARY | — |
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

### `src/testmap.h`

Discloses: `capped`

| constant | value | class | note |
| --- | --- | --- | --- |
| `kClassNewRowCap` | `8` | — | rows shown; the group's total= counts them all, next= is --callers= of the first cut row's class |

### `src/tracelocus.h`

Discloses: `name_ladder_capped`

| constant | value | class | note |
| --- | --- | --- | --- |
| `kMeasuredDigitsPricedWidth` | `6` | OUTPUT | — |
| `kNameCandidateCap` | `8` | OUTPUT | — |
| `kTestHopBasenameRowCap` | `3` | OUTPUT | — |
| `kTestHopCalleeRowCap` | `5` | OUTPUT | — |

### `src/typeuse.h`

Discloses: `type_capped`

| constant | value | class | note |
| --- | --- | --- | --- |
| `kTypeMentionMatchBudget` | `50000` | INDEXING | per pattern; no flag raises it — type_capped="1" marks the floor |

### `src/valuerefs.h`

Discloses: `capped`, `value_refs_depth_capped`

| constant | value | class | note |
| --- | --- | --- | --- |
| `kPatternRowCap` | `8` | — | — |
| `kSlotCallerCap` | `8` | — | — |
| `kSlotTargetCap` | `16` | — | — |
| `kValueRefRowCap` | `64` | — | — |

### `src/verbs_change.h`

Discloses: `capped`, `seed_files_capped`

| constant | value | class | note |
| --- | --- | --- | --- |
| `kRunTraceRelevantLinesCap` | `40` | — | <lines view="relevant"> cap (first/last half split past it) |

### `src/verbs_doctor.h`

Discloses: **none**

| constant | value | class | note |
| --- | --- | --- | --- |
| `kShown` | `8` | OUTPUT | — |

### `src/verbs_for.h`

Discloses: `capped`, `coboost_commits_capped`, `terms_capped`

| constant | value | class | note |
| --- | --- | --- | --- |
| `kForOwnerHopRows` | `3` | — | — |
| `kJsonEnvelopeDigitsMax` | `10` | — | — |

### `src/verbs_grep.h`

Discloses: `capped`, `hits_capped`, `importers_capped`, `unindexed_candidates_capped`

| constant | value | class | note |
| --- | --- | --- | --- |
| `kGrepHitRefsMax` | `4` | — | — |

### `src/verbs_lint.h`

Discloses: `capped`, `count_capped`, `ellipsis_capped`, `findings_capped`, `hits_capped`, `rows_capped`

| constant | value | class | note |
| --- | --- | --- | --- |
| `kMatchMaxHits` | `5000` | INDEXING | astQuery's per-spec budget, named not implied |

### `src/verbs_navigate.h`

Discloses: `capped`, `importers_capped`

| constant | value | class | note |
| --- | --- | --- | --- |
| `kEvidenceCap` | `20` | OUTPUT | — |

