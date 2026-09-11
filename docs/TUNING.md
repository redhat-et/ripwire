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
| 120 | 119 | 107 | 12 | **23** | 84 |

The first two columns are not the same number, and the gap is not a rounding: `src/` holds
**120 cap declarations** under **119 distinct names** (`kRowCap` declared in more than one file). The
sweep patches by NAME, so `107 + 12` accounts for the 119 NAMES — not the 120 declarations. Quoting
"108 of 120" would be wrong in both halves at once, which is exactly the shape of error a
generated table exists to prevent.

## Read this ratio before the tables

**23 of 107 tunable caps move any invocation at all. 84 move nothing measurable.** That is the
finding, and it says what NOT to do: this is not a 120-cap audit. Most of these constants are
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

Sizes were measured against `2a444edb`, on a corpus frozen with `git archive HEAD` at that commit.
The cap names, values and files below are re-read from `src/` on every run of `emit`, so a
retuned or renamed cap makes `test/capsweepcheck.sh` fail rather than leaving a stale number
standing. The **byte deltas are frozen** and do not re-measure themselves: they are only as
current as the commit above, and a change to what a verb emits can age them without any cap
moving. Re-run `prepare|screen|sweep` to refresh them.

### `kSpecificMinLen` = `8`

`src/graph.h` — discloses: `importers_capped` — probe value `64` — **14 verb(s) respond**

| invocation | default | at probe | delta |
| --- | --- | --- | --- |
| `. --communities` | 17385 B | 17597 B | +212 B |
| `. --zoom --zoom-levels=3` | 12518 B | 12689 B | +171 B |
| `. --zoom` | 8409 B | 8523 B | +114 B |
| `. --no-cache --top-k=3` | 1920 B | 1825 B | -95 B |
| `. --no-ignore --top-k=3` | 1920 B | 1825 B | -95 B |
| `. --no-stable --top-k=3` | 1920 B | 1825 B | -95 B |
| `. --tree` | 11779 B | 11858 B | +79 B |
| `. --pack-top-n=3 --top-k=0` | 65670 B | 65729 B | +59 B |
| `. --impact=rankGraphTeleport` | 7860 B | 7823 B | -37 B |
| `.` | 24432 B | 24403 B | -29 B |
| `. --seams` | 12969 B | 12992 B | +23 B |
| `. --ignore-tests --top-k=5` | 2028 B | 2036 B | +8 B |

*12 of 14 responding invocations shown, largest |delta| first.*

### `kMaxExpandSibs` = `100`

`src/serialize.h` — discloses: `calls_capped`, `inc_capped`, `sibs_capped` — probe value `800` — **5 verb(s) respond**

| invocation | default | at probe | delta |
| --- | --- | --- | --- |
| `. --expand=readAckRecords --top-k=0 --no-redact` | 11317 B | 16612 B | +5295 B |
| `. --expand=compressBody --top-k=0 --compress` | 8077 B | 9675 B | +1598 B |
| `. --expand=rankGraphTeleport --top-k=0` | 4936 B | 6010 B | +1074 B |
| `. --expand=rankGraphTeleport:1-12 --top-k=0` | 4324 B | 5398 B | +1074 B |
| `. --top-k=0 --expand=rankGraphTeleport` | 4936 B | 6010 B | +1074 B |

### `kCommonNameDefThreshold` = `5`

`src/graph.h` — discloses: `importers_capped` — probe value `40` — **4 verb(s) respond**

| invocation | default | at probe | delta |
| --- | --- | --- | --- |
| `. --zoom --zoom-levels=3` | 12518 B | 12590 B | +72 B |
| `. --zoom` | 8409 B | 8457 B | +48 B |
| `. --tree` | 11779 B | 11750 B | -29 B |
| `. --communities` | 17385 B | 17378 B | -7 B |

### `kLintMaxPerRule` = `5000`

`src/lintrules.h` — discloses: **none** — probe value `40000` — **4 verb(s) respond**

| invocation | default | at probe | delta |
| --- | --- | --- | --- |
| `. --lint --sarif` | 1137832 B | 1645970 B | +508138 B |
| `. --lint` | 70938 B | 70885 B | -53 B |
| `. --lint --lint-ignore=naming-,cache-` | 66898 B | 66845 B | -53 B |
| `. --lint --naming-locals` | 73640 B | 73587 B | -53 B |

### `kForLensDefaultTopN` = `40`

`src/serialize.h` — discloses: `calls_capped`, `inc_capped`, `sibs_capped` — probe value `320` — **3 verb(s) respond**

| invocation | default | at probe | delta |
| --- | --- | --- | --- |
| `. --for="rankGraphTeleport" --no-route` | 15836 B | 15628 B | -208 B |
| `. --for="rankGraphTeleport"` | 2128 B | 2130 B | +2 B |
| `. --for="rankGraphTeleport" --signatures-only` | 1523 B | 1525 B | +2 B |

### `kExternalSurfaceRowCap` = `100`

`src/pageview.h` — discloses: `count_capped`, `findings_capped`, `hits_capped`, `importers_capped`, `modules_capped` — probe value `800` — **2 verb(s) respond**

| invocation | default | at probe | delta |
| --- | --- | --- | --- |
| `. --external-surface` | 5593 B | 38690 B | +33097 B |
| `. --external-surface --include-builtins` | 5547 B | 38643 B | +33096 B |

### `kOrdinalWindowCap` = `40`

`src/ensemble.h` — discloses: `files_capped`, `findings_capped`, `syms_capped` — probe value `320` — **2 verb(s) respond**

| invocation | default | at probe | delta |
| --- | --- | --- | --- |
| `. --quality-panel` | 15876 B | 15974 B | +98 B |
| `. --ensemble --limit=8` | 10616 B | 10647 B | +31 B |

### `kZoomTopModuleCap` = `40`

`src/pageview.h` — discloses: `count_capped`, `findings_capped`, `hits_capped`, `importers_capped`, `modules_capped` — probe value `320` — **2 verb(s) respond**

| invocation | default | at probe | delta |
| --- | --- | --- | --- |
| `. --zoom --zoom-levels=3` | 12518 B | 72408 B | +59890 B |
| `. --zoom` | 8409 B | 49550 B | +41141 B |

### `kBatchCap` = `16`

`src/mcpverbs.h` — discloses: `coboost_commits_capped`, `hits_capped`, `unindexed_candidates_capped` — probe value `128` — **1 verb(s) respond**

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
| `. --nonlocal-state --limit=8` | 10220 B | 10394 B | +174 B |

### `kDefsPerNameCap` = `8`

`src/contextratio.h` — discloses: `defs_capped`, `files_capped`, `syms_capped` — probe value `64` — **1 verb(s) respond**

| invocation | default | at probe | delta |
| --- | --- | --- | --- |
| `. --context-ratio --limit=8` | 13312 B | 13708 B | +396 B |

### `kEnsembleFileRowCap` = `20`

`src/ensemble.h` — discloses: `files_capped`, `findings_capped`, `syms_capped` — probe value `160` — **1 verb(s) respond**

| invocation | default | at probe | delta |
| --- | --- | --- | --- |
| `. --ensemble --limit=8` | 10616 B | 27723 B | +17107 B |

### `kFileRowCap` = `40`

`src/contextratio.h` — discloses: `defs_capped`, `files_capped`, `syms_capped` — probe value `320` — **1 verb(s) respond**

| invocation | default | at probe | delta |
| --- | --- | --- | --- |
| `. --context-ratio --limit=8` | 13312 B | 64424 B | +51112 B |

### `kForAutoBodyBudgetBytes` = `6000`

`src/serialize.h` — discloses: `calls_capped`, `inc_capped`, `sibs_capped` — probe value `48000` — **1 verb(s) respond**

| invocation | default | at probe | delta |
| --- | --- | --- | --- |
| `. --for="rankGraphTeleport" --no-route` | 15836 B | 22117 B | +6281 B |

### `kForFileTailShownCap` = `24`

`src/serialize.h` — discloses: `calls_capped`, `inc_capped`, `sibs_capped` — probe value `192` — **1 verb(s) respond**

| invocation | default | at probe | delta |
| --- | --- | --- | --- |
| `. --for="rankGraphTeleport" --no-route` | 15836 B | 21403 B | +5567 B |

### `kForPayloadBudgetBytes` = `7500`

`src/serialize.h` — discloses: `calls_capped`, `inc_capped`, `sibs_capped` — probe value `60000` — **1 verb(s) respond**

| invocation | default | at probe | delta |
| --- | --- | --- | --- |
| `. --for="rankGraphTeleport" --no-route` | 15836 B | 29649 B | +13813 B |

### `kGrepMatchedLineMaxBytes` = `512`

`src/search.h` — discloses: `hits_capped` — probe value `4096` — **1 verb(s) respond**

| invocation | default | at probe | delta |
| --- | --- | --- | --- |
| `. --grep=deterministic` | 44342 B | 63729 B | +19387 B |

### `kMaxExpandIncludes` = `24`

`src/serialize.h` — discloses: `calls_capped`, `inc_capped`, `sibs_capped` — probe value `192` — **1 verb(s) respond**

| invocation | default | at probe | delta |
| --- | --- | --- | --- |
| `. --expand=readAckRecords --top-k=0 --no-redact` | 11317 B | 11632 B | +315 B |

### `kPanelRowCap` = `40`

`src/qualitypanel.h` — discloses: `findings_capped` — probe value `320` — **1 verb(s) respond**

| invocation | default | at probe | delta |
| --- | --- | --- | --- |
| `. --quality-panel` | 15876 B | 63771 B | +47895 B |

### `kSliceFlowDefaultDepth` = `8`

`src/slice.h` — discloses: **none** — probe value `64` — **1 verb(s) respond**

| invocation | default | at probe | delta |
| --- | --- | --- | --- |
| `. --slice=rankGraphTeleport:teleport --slice-flow=fwd` | 7203 B | 7204 B | +1 B |

### `kSymbolRowCap` = `40`

`src/contextratio.h` — discloses: `defs_capped`, `files_capped`, `syms_capped` — probe value `320` — **1 verb(s) respond**

| invocation | default | at probe | delta |
| --- | --- | --- | --- |
| `. --quality-panel` | 15876 B | 18013 B | +2137 B |

### `kTreeRowCap` = `80`

`src/pageview.h` — discloses: `count_capped`, `findings_capped`, `hits_capped`, `importers_capped`, `modules_capped` — probe value `640` — **1 verb(s) respond**

| invocation | default | at probe | delta |
| --- | --- | --- | --- |
| `. --tree` | 11779 B | 93405 B | +81626 B |

