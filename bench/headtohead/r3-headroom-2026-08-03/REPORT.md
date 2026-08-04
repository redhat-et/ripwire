# Head-to-head r3: ripwire vs headroom vs naive grep+read (django corpus)

**2026-08-03.** Third head-to-head; first against a **compression-layer** competitor rather than a
retrieval tool. Pre-registered in [`PREREGISTRATION.md`](PREREGISTRATION.md) (commit `f3f2053`,
frozen before any arm ran); this report and the raw results land in a separate commit on purpose.
Adversarially verified post-run; verifier findings and their dispositions in
[`VERIFIER.md`](VERIFIER.md).

**One-line result: on 12 real mid-task coding questions, headroom's default configuration passed
every code chunk through byte-identical (its own guards fired on all of them) and mildly compressed
four mixed grep chunks for a net −410 tokens (−0.06% of 685,682); ripwire delivered the
correct-answer context at 7.3% of the naive baseline's tokens — but its fixed 2–4-rung verb ladder
satisfied the strict criterion on only 5/12, and those seven misses are the finding.**

## (i) Methodology recap + pins

See `PREREGISTRATION.md` for the full frozen protocol. Pins: ripwire `bf8e90e` (dev build),
`headroom-ai==0.33.0` (repo HEAD `3f2ca99` same day), corpus `django/django @ 70f39e46` (depth-1,
896 py files indexed for ripwire, whole tree for grep), tokenizer tiktoken `cl100k_base`, one
metric implementation (`harness.py`) called from every arm, same Apple Silicon host, ripwire warm
(prebuilt index; cold map is 0.40 s on this corpus — `timing_determinism.json`).

Environment for every headroom call: `HEADROOM_TELEMETRY=off HEADROOM_UPDATE_CHECK=off
HEADROOM_DISABLE_KOMPRESS=1`, Python 3.12 venv with `onnxruntime` (Magika routing active). Two
corrections from verification (VERIFIER.md F5, F10): the `HEADROOM_DISABLE_KOMPRESS` pin is
**proxy-mode-only and was a no-op for the library calls this run made** — that Kompress (the ML
prose compressor) never engaged is instead verified from the transform markers of all 60 arm
results (no `kompress` marker anywhere); and the frozen `harness.py` docstring references a
`run_all.sh` that does not exist — the environment above is the record.

Arms: **A** naive grep+whole-file-reads floor · **B** A's transcript through headroom `compress()`
default config · **B′** labeled non-default override (`protect_analysis_context=False,
protect_recent=0`) · **C** ripwire pre-registered verb ladder · **D** C's transcript through
headroom (composition check).

## (ii) Losses first

### Where the baseline beat or tied ripwire (arm C)

Strict criterion satisfaction: **A 11/12, C 5/12** under the frozen ladder. Every miss re-run and
bucketed by an independent investigator; each bucket names the fix disposition.

| q | what C missed | bucket | disposition |
|---|---|---|---|
| q01 | `db.py` `_cull`/`_base_set` — `DatabaseCache` absent from `--for`'s ENTIRE candidate pool at any budget on the natural phrasing; the *file-based* cache's `_cull` ranked first instead | **wrong ranking** (sibling-file confusion) | Real defect. Same hypothesis family as the pre-registered locbench r4 sibling-lift stream (`bench/locbench/`, commit `bf8e90e`); regression case recorded there, fix belongs to that stream |
| q03 | nothing — satisfied, but at 819 tokens vs A's 721 (grep's best case: symbol named in question, 11 call sites in 4 files) | **baseline simply better here** | Nothing should change. `--callers`' legend/structure overhead only pays off above ~1 KB of hits; published as the honest counterexample |
| q06 | the class name `MigrationAutodetector` — but `--affected` returned the correct answer (the single test file); the criterion demanded a token the verb's documented path-only schema never carries | **criterion artifact** | Fix the criterion in future runs, not the tool. Documented recovery exists but is not cheap here: best measured chain (`--grep=MigrationAutodetector`, 930 t) puts C+recovery at 1,072 t vs A's 433 t — **the naive arm wins q06 ~2.5× even granting the recovery** (corrected per VERIFIER.md F4) |
| q07 | `ResolverMatch` — never surfaced by `--for` even at 5× budget, although the query's own noun ("match object") is inside the name; graph knows it (`--callers=ResolverMatch` returns exactly the gold construction sites) | **wrong ranking**; secondary: duck-typed `resolver.resolve()` receiver contributes no edge (documented `amb=` honesty policy) | Fix candidate: name-token boost under the conceptual route when a query noun appears inside a symbol name (`XxxMatch`/`XxxResult` pattern). Edge gap stays — guessing among 7 `resolve` defs would violate the honesty policy |
| q08 | `full_clean`, `_clean_fields`, the fields.py hop — `is_valid`, named almost verbatim in the question, ranked **112th**; an unrelated `ManagementForm` topped the list at ~2× the next score, dooming the path/connect rungs to wrong anchors | **wrong ranking** | Fix candidates: (1) verbatim-named-symbol mention boost inside conceptual queries; (2) anchor-quality warning on `--path`/`--connect` when top-1 is a score outlier on a file the query never names. Note: **arm A also lost q08** — fields.py contains neither search term; grep cannot trace call chains at all |
| q09 | `defaultfilters.py`, `filter_tests/`, `register`, `Library` — a 978-line file of 63 tiny same-decorator functions is structurally invisible to symbol-level ranking; `Library.filter`'s docstring contains the verbatim phrase "template filter" and still never surfaced; `--exemplar` returned `ForeignKey` (fan-in-first ordering) | **wrong ranking** (three named mechanisms: docstring phrase underweight, no file-level sibling aggregation, exemplar fan-in bias) | All three recorded as fix candidates in (v). File-level aggregation is the load-bearing one |
| q10 | `global_settings.py` / `PASSWORD_HASHERS` — module-level constants are **not extracted as rankable symbols at all** (0 occurrences in the 42k-symbol map; `t="var"` fired once corpus-wide); `--grep`/`--uses` resolve the identifier perfectly, `--for`/`--pack-task` structurally cannot | **missing symbol kind** | Real gap, worth fixing: index SCREAMING_SNAKE module-level assignments as first-class ranked `var` symbols. No output signal existed to recover from — a genuine, unrecoverable loss |
| q12 | `DisallowedHost` + the catch sites — `--grep`'s default matched-line-only window hid the `raise` 7 lines below; my fixed regex rung couldn't model the documented next hop | **harness protocol artifact** | The tool already solves this: `--grep-context=7` (existing flag) shows the raise for +263 t, and `--uses=DisallowedHost` (1,066 t) completes all remaining gold — corrected recovery 263+1,066 = **1,329 t vs A's 17,364 (13×)**. (First-draft figure used `--expand=get_host`, which multi-def-expands to 9,808 t — corrected per VERIFIER.md F4.) No code change |

Bucket totals: **wrong ranking 4** (q01, q07, q08, q09) · **missing symbol kind 1** (q10) ·
**criterion/protocol artifact 2** (q06, q12) · **baseline better 1** (q03, a satisfied near-tie).
The four ranking losses are conceptual-phrasing failures — consistent with the documented caveat
that broad/common-word conceptual queries are `--for`'s weak shape — but q08 shows the caveat's
implied fallback ("plain rg can still win") does **not** rescue call-chain questions: the naive arm
lost that one too.

### Where headroom beat the naive arm (arm B vs A)

On content, four times, marginally: it compressed one `mixed`-classified grep chunk each on
q01/q02/q06/q10 (−56/−48/−136/−170 t; every other chunk byte-identical passthrough). In the raw
charged column that surfaces as only two negative rows (q06 −101, q10 −94) because the harness's
own packaging (+1,423 t across the arm, charged to B only) swamps the smaller two — decomposition
in VERIFIER.md F1. Ripwire never lost to headroom on any question on either accounting.

## (iii) The paired table

N=12, all arms same questions, same gold, same tokenizer. `ok` = strict criterion satisfied.
B/B′/D "charged" includes the CCR retrieval round-trip rule (unused — nothing was ever lost,
because nothing was ever compressed; survival was `all-retained` on every question).

| q | cat | A tok | B tok | B−A | B′ tok | C tok | C/A | D tok | D−C | A | C |
|---|-----|-------|-------|-----|--------|-------|-----|-------|-----|---|---|
| q01 | C1 | 28,342 | 28,350 | +8 | 28,350 | 11,974 | 42.2% | 12,060 | +86 | ok | miss |
| q02 | C1 | 111,376 | 111,444 | +68 | 32,098 | 1,636 | 1.5% | 1,708 | +72 | ok | ok |
| q03 | C2 | 721 | 761 | +40 | 761 | 819 | 113.6% | 860 | +41 | ok | ok |
| q04 | C2 | 27,385 | 27,445 | +60 | 27,445 | 518 | 1.9% | 552 | +34 | ok | ok |
| q05 | C3 | 16,414 | 16,526 | +112 | 16,526 | 522 | 3.2% | 566 | +44 | ok | ok |
| q06 | C3 | 433 | 332 | −101 | 332 | 142 | 32.8% | 183 | +41 | ok | miss |
| q07 | C4 | 115,900 | 116,130 | +230 | 116,130 | 13,198 | 11.4% | 13,308 | +110 | ok | miss |
| q08 | C4 | 248,578 | 248,913 | +335 | 248,913 | 11,192 | 4.5% | 11,306 | +114 | **miss** | miss |
| q09 | C5 | 25,044 | 25,254 | +210 | 25,254 | 4,873 | 19.5% | 4,962 | +89 | ok | miss |
| q10 | C5 | 30,798 | 30,704 | −94 | 30,704 | 4,721 | 15.3% | 4,825 | +104 | ok | miss |
| q11 | C6 | 63,327 | 63,397 | +70 | 63,397 | 280 | 0.4% | 329 | +49 | ok | ok |
| q12 | C6 | 17,364 | 17,439 | +75 | 17,439 | 263 | 1.5% | 308 | +45 | ok | miss |
| **Σ** | | **685,682** | **686,695** | **+1,013** | **607,349** | **50,138** | **7.3%** | **50,967** | **+829** | 11/12 | 5/12 |

Readings the table supports — **with the packaging decomposition from verification (VERIFIER.md
F1/F2) applied.** The B and D columns charge the harness's own message framing (the user-question
text plus `[tool result …]` wrapper labels, +1,423 t across B, +829 across D) that arms A/C are
never charged for; the per-arm deltas decompose exactly:

- **Headroom default = passthrough on code, −410 t net on content.** Every code chunk came back
  byte-identical — its own guards fired throughout (`protected:analysis_context` ×27 chunks,
  `protected:recent_code` ×28, `protected:user_message` ×12, `protected:error_output` ×9) — and
  four grep chunks classified `mixed` compressed mildly (q01 −56, q02 −48, q06 −136, q10 −170:
  net −410 t, −0.06% of the 685,682-token workload). The raw B−A of +1,013 is +1,423 packaging
  −410 headroom. The passthrough behavior matches headroom's own published limitations ("Code —
  Passthrough"; 0.0% on Python source and grep results — GitHub README/wiki @ `3f2ca99`); the
  loss here is *the headline's* ("15-20% fewer tokens (for coding agents)", packaged METADATA
  line 172), not the implementation's.
- **The labeled override fired once** (q02: 111k→32k, −71%): the only transcript headroom acted on
  (silently-skipped chunks leave no marker, so classification vs ratio-gating is indistinguishable
  from outputs). Verification strengthened this: q07/q08 re-run under the override, plus
  `min_tokens_to_compress=50`, `target_ratio=0.3`, and headroom's own shipped high-savings
  `agent-90` profile — ratio 0.000 in every case. Even when it fires, q02's 32,098 t is 20× arm
  C's 1,636 t on the same question — and it is non-default because headroom itself judges
  compression during analysis a quality risk.
- **Composition adds exactly nothing:** headroom passed ripwire's output through untouched on all
  12 questions (+0 t attributable; the D−C of +829 is entirely harness framing). Ripwire's
  minified XML is already past the density headroom targets.
- **Tokens-to-answer, satisfied questions only** (both arms ok: q02–q05, q11): C = 3,775 t vs
  A = 219,223 t — **58× fewer** where the ladder completed. Across all 12 including misses: 13.7×.
- **The honest caveat on that 13.7× (VERIFIER.md F3): 92.5% of C's 50,138 tokens were spent on
  the seven questions it failed** — cheap partly because the frozen ladder gives up early while
  arm A keeps reading until it succeeds. The deployment-realistic composite — C first, naive
  fallback on the six misses the naive arm can recover (q08 is unrecoverable for A too) — costs
  ≈268,019 t, **39% of A, at the same 11/12 satisfaction**. Both framings are published; the
  per-question median C/A of 8.0% shows the sum ratio is not aggregation skew.

## (iv) Wall time and determinism

Medians of 5 (`timing_determinism.json`), same host, cache states named:

| measurement | median |
|---|---|
| ripwire warm full map | 0.153 s |
| ripwire warm `--callers` | 0.135 s |
| ripwire **cold** (`--no-cache`) full map | 0.400 s |
| naive grep (one term, corpus-wide) | 0.251 s |
| headroom `compress()` on a 50 KB code read (default cfg) | 0.011 s — **a no-op** (ratio 0.0, `protected:recent_code`) |

Per-question compress overhead in the real run ranged 0.004–0.373 s (the top end is first-call
pipeline init). Labeling per VERIFIER.md F8: ripwire medians include full process spawn; headroom
is timed in-process after import (defensible — it deploys as a resident proxy — but not
symmetrical; Python spawn+import adds ≈0.05 s if charged).

Determinism: ripwire byte-identical across runs (its standing gate). For headroom, the original
same-process check proved only passthrough stability; the stronger evidence is the verifier's
fresh-process re-runs, which reproduced the compressing paths to the byte (q02 B′ 32,835 t exact,
all four mixed-chunk deltas exact). Scope: Kompress never engaged in any run (verified by absence
of its transform marker); with that ML path active we make no determinism claim either way.

## (v) What to build next (from the loss buckets)

1. **Module-level constant indexing (q10)** — SCREAMING_SNAKE top-level assignments become ranked
   `var` symbols. The only unrecoverable loss in the run; `--grep`/`--uses` already prove the
   resolution layer handles them. Gate: a `--for="...selectable/config..."` fixture must surface a
   settings constant.
2. **Verbatim-name mention boost inside conceptual queries (q07, q08)** — a query noun appearing
   inside a symbol name (`match`→`ResolverMatch`) or a near-verbatim method name (`is_valid`)
   should not rank below 100 generic rows. Belongs to the locbench r4 pre-registered stream —
   calibrate on train, pre-register, do not ship from this n=12 audit.
3. **File-level sibling aggregation (q01, q09)** — many small same-shaped siblings (63 registered
   filters; the db/filebased backend pair) need file-level evidence pooling before symbol-level
   ranking can see them. Also r4-stream material.
4. **Anchor-quality warning on `--path`/`--connect` (q08)** — when the top-1 seed is a score
   outlier on a file the query never names, say so instead of silently traversing.
5. **Criterion discipline for r4+ (q06)** — verb-appropriate gold: don't demand symbol tokens from
   path-schema verbs.
6. Nothing for q03 and q12 — one is grep's honest best case, the other already has two shipped
   solutions.

## (vi) What this comparison does NOT show

- **Not measured: headroom's home turf** — JSON/log tool-output compression (its 60–95% headline),
  provider-cache alignment, conversation-history economics, output steering. On those axes ripwire
  does not compete and this run makes no claim. The two tools compose in principle; arm D shows the
  composition is pointless *for ripwire's output specifically*, not in general.
- Library-mode single-shot `compress()` stands in for the proxy; a live multi-turn proxy could
  behave differently turn-by-turn (headroom's own docs warn compression is not idempotent across
  turns). Kompress (ML prose) disabled throughout.
- One corpus, one language, N=12, protocol-fixed idealized agents on every arm — category-level
  and directional, not a universal ranking. The strict-criterion satisfaction numbers measure the
  FROZEN LADDERS (2–4 rungs, no adaptive reading), not an interactive agent; the q06/q12 buckets
  show a real agent recovers two of the seven misses for a few hundred tokens.
- History-dependent ripwire verbs (churn, hotspots) unmeasured (depth-1 checkout).

---

## Addendum (2026-08-03, post-run): q10 mechanism correction + fix landed

The frozen sections above are unchanged. Re-verification while fixing §(v) item 1 showed the q10
LOSS is real but the stated MECHANISM was wrong: Python module-level constants ARE extracted (the
vendored tree-sitter-python tags capture every module-level assignment — the django@base index
holds ~956 `var` symbols, PASSWORD_HASHERS among them, and `--grep` shows `in="PASSWORD_HASHERS"`).
The "t=var fired once" observation was the default map's rank-truncated WINDOW, not the index. Two
distinct causes, and §(v) item 1's fix shape only covers the second:

1. **Ranking (Python residual, still open):** with q10's exact phrasing the constant sits at
   lexical rank ~175 — outside every lens window. A config-phrased query ("which setting lists the
   selectable password hashers…") surfaces it. This is a calibration item for the pre-registered
   locbench stream (same lane as §(v) items 2–3), NOT shippable from this n=12 audit.
2. **Extraction (fixed):** the audit's generalized claim was TRUE for TypeScript, JavaScript,
   Rust, Ruby, Java, C#, C and C++ — none captured module-level constants, so a settings module in
   those languages contributed zero rankable symbols. Fixed by the `@definition.constant` patterns
   (queries/*/tags.scm) + the SCREAMING_SNAKE capture gate (src/ingest.cpp), gated red-first by
   test/constcheck.sh (18 assertions red at b6068c3, all green post-fix).
