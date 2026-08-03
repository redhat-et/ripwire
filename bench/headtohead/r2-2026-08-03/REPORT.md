# Head-to-head r2: ripwire vs repowise vs codeseek (LocBench held-out slice)

**2026-08-03.** Second head-to-head, same shape as [`../REPORT.md`](../REPORT.md) (B5.3, 2026-07-13):
same dataset snapshot, same frozen split, same first-60 held-out slice, same gold definition, same
metric code imported unmodified. Primary deliverable: the loss buckets and what to build from them.

**Not comparable number-for-number to B5.3.** The ripwire binary, router, and evaluator have all
moved since 2026-07-13 (B5.3's own "what to build next" items #1/#4 landed in between), and the
single/multi stratum split differs (32/28 here vs 20/40 there under the then-current evaluator).
This run's four arms are internally paired and comparable; cross-run deltas are directional only.

## (i) Methodology + exact versions

**Dataset.** LocBench (`czlll/Loc-Bench_V1`, test split), the harness's frozen 560-row snapshot,
re-fetched 2026-08-03 from the HF datasets-server and hash-verified: SHA-256
`5bbcea4bff11396f38f8aca3e64d697a8ea1da2bc54d705da7f6e34886804c97` (matches the pin in
`run_locbench.py`).

**Slice.** First 60 scored held-out instances in stable dataset order (frozen repo-disjoint
salted-SHA-256 split `ripwire-a7-v2`), via `--split=heldout --max-scored 60 --n 560`.
**Zero exclusions in any arm; N(paired)=60.** Mix under the current evaluator: 32 single-file gold,
28 multi-file.

**Checkouts.** Depth-1 shallow fetch of `base_commit` (`run_locbench.checkout()`,
`history_depth=1`). The ripwire arm used the harness's own workdir; competitor arms used a separate
checkout tree produced by the same `checkout()` function (byte-identical content, no shared caches).

**Gold + metric.** Gold = the harness's `primary_files` (patch-touched files present in the indexed
universe — identical gold for all arms, exported from the ripwire arm's `--json-out`). Metric = the
harness's own strict file@k (`file_ranks` + `acc_all_at`, imported unmodified). Universe for
competitor-arm rank matching = `git ls-files` of the checkout (B5.3 convention); the unique-basename
fallback applies identically to every arm.

**Query.** All arms received the identical query: the whitespace-normalized 1200-char prefix of
`problem_statement`.

**Arms.**

| arm | version / pinning | invocation |
|---|---|---|
| ripwire `--for` (routed, default flags) | binary sha256 `50d72fbe581a0c02ed1acafba1f34e48ceb9417b188ee5db7b38b1a7aaf04c85`, repo @ `6147762` (clean tree) | `RIPWIRE=<build> run_locbench.py --split=heldout --max-scored 60 --arms for --n 560` → per instance `--for=<issue 1200ch> --top-k=200 --format=candidates --cache=<rich>` |
| repowise | **0.37.0** (PyPI, venv, AGPL-3.0), Python 3.14 | `repowise init --no-prose -y` (LLM-free structural wiki; full mode, never `--mode fast`) then MCP stdio `search_codebase(query, limit=300, mode=auto)` → FTS (no embedder configured). Ranked files = first appearance of each result's `target_path` (`file.py::Symbol` spotlight targets mapped to `file.py`; non-file wiki pages skipped by rank matching). |
| codeseek raw | **0.1.31** (npm + signed release binary, MIT) | `codeseek init` then `codeseek search "<issue 1200ch>" --limit 300 --json`, **fallback mode: no embedding endpoint configured** (config written with no `embedding` block — the tool's documented graceful-degrade path). |
| codeseek idents | same binary | imposed convention (aider-persona analog): code-shaped identifier mentions regex-extracted from the issue (snake_case/camelCase, cap 8), each searched with `--limit 50`, merged by (per-ident rank, ident order). |

**Excluded arms (documented, not selective).**
- **Vexp** (vexp.dev): free tier is ≤2,000 nodes / single-repo workspace / 20 pipeline calls per day —
  structurally unable to run a fair 60-instance sweep over sympy-scale repos. Excluded rather than
  run truncated; revisit with a Pro license.
- **CodeIndexer** (codeindexer.dev): the CLI/MCP binary is account-gated; the free tier is capped at
  3 indexed projects / 100,000 chunks total, and the **call graph and cascade search are Pro-tier
  features**. A free-tier run would measure the paywall, not the technology. Claims noted; excluded.
- **Graphify**: already measured in B5.3 (strict file@10 21.7% on the then-slice); not re-run.

**codeseek capability note (fairness).** The raw arm's 0/60 is genuine tool behavior, hand-verified:
a fresh `codeseek init` on the django checkout succeeds (1,377 files / 21,672 functions), yet both
the full NL query and the **exact class name `BoundField`** return `[]`. Keyless fallback search
appears to match *function* names only. Its advertised semantic mode requires an external
OpenAI-compatible embedding endpoint, which would have broken this run's LLM-free posture. The
idents arm exists to show what its graph does when fed the input shape it expects.

**repowise capability note (fairness).** `--no-prose` is repowise's own documented LLM-free path
("every other page is structural either way"); its LLM-written concept pages and semantic embedder
mode were not exercised. `search_codebase` ran with `limit=300` vs ripwire's `--top-k=200` — the
asymmetry favors repowise and was left in place.

## (ii) Headline (N=60 paired, strict file@k)

| arm | strict file@10 | any@10 | wall median (query, warm) | index wall median/max |
|---|---|---|---|---|
| **ripwire `--for`** | **56.7%** | **83.3%** | **0.114 s** | not measured this run (rich cache prebuilt outside timing; see `bench/perfgate.sh` budgets) |
| repowise | 33.3% | 53.3% | 1.135 s | 30.0 s / 315.5 s |
| codeseek idents | 15.0% | 20.0% | 0.042 s | 3.2 s / 91.9 s |
| codeseek raw | 0.0% | 0.0% | 0.025 s | 3.2 s / 91.9 s |

Strata: single-file (n=32) ripwire 87.5% / repowise 50.0%; multi-file (n=28) ripwire 21.4% strict
but 78.6% any@10 — the first gold file is almost always found, the siblings are what's missed.

**Sensitivity rows (adversarial verification, see `VERIFIER.md`):**
- *All-patch gold (untrimmed — includes files outside ripwire's indexed universe):* strict@10
  ripwire **26.7%** / repowise 16.7% / codeseek-idents 8.3% / codeseek-raw 0.0%. The headline gold
  is `primary_files` = patch gold ∩ ripwire's indexed universe (32/60 instances had non-indexable
  gold trimmed: docs, configs, and Cython `.pyx/.pxd` — a real coverage gap). Ordering holds on the
  untrimmed set; the margin over repowise halves.
- *repowise junk-filtered (non-file wiki pages dropped from its ranking):* 36.7% / 58.3% — ~3pp
  better than as-scored; does not flip any conclusion.
- *codeseek raw:* returned **0 results in 60/60 queries** under this protocol — the row measures a
  query-shape incompatibility (prose into a function-name matcher), not retrieval quality; its
  embedder-backed shipping mode was not benchmarked. 19/60 idents-arm instances had no extractable
  identifiers (guaranteed miss by construction).
- *Walls:* repowise's 1.135 s includes a fresh MCP server spawn + JSON-RPC handshake per query
  (resident-server usage is faster); ripwire's index wall was not measured this run, so index costs
  must never be tabulated side-by-side from these artifacts.

Payload: ripwire production bundle median ≈ 2,303 tokens (2.36 B/token ceiling); repowise
`search_codebase` JSON median ≈ 160 KB at limit=300 (its default limit is 5; the inflation is our
export convention, not its normal usage — noted, not scored).

Win/loss matrix (strict@10, vs ripwire): repowise both=17 · ripwire-only=17 · repowise-only=3 ·
neither=23. codeseek idents: both=9 · ripwire-only=25 · idents-only=0. codeseek raw: ripwire-only=34.

## (iii) Losses first (all verified by exact re-run: per-instance commit + per-instance rich cache)

Strict losses (3, all to repowise):

| instance | gold | ripwire (first/worst) | repowise (first/worst) | bucket |
|---|---|---|---|---|
| `micropython__micropython-lib-947` | `python-ecosys/requests/requests/__init__.py` | 35 / 35 | 0 / 0 | **R1 package-name mention** |
| `huggingface__transformers-22498` | modeling_utils.py, trainer.py, training_args.py | 0 / 44 | 0 / 8 | **R2 sibling near-miss** |
| `django__django-19043` | forms/{fields,forms,renderers}.py | 0 / 13 | 2 / 9 | **R2 sibling near-miss** |

any@10 losses (2): `micropython-lib-947` (above) and `zulip__zulip-31168` (gold
`zerver/views/streams.py` at 11, `zerver/lib/users.py` at 51; repowise first-hit 6) — **R2**.

### R1 — package/module-name mention → package files (1 strict loss)

The issue backticks the `requests` *module*; gold is the package's `__init__.py`, which contains no
matching symbol name. `--for`'s mention anchor ran (`anchored=3`) but a bare backticked package name
that matches a **directory** is not an anchorable mention today — only files, dotted modules, and
`Type.method` are. repowise wins because its file-page FTS counts **path tokens** as page text.
This is the residue of B5.3 bucket B1: the anchoring shipped for files/dotted modules/symbols and
this is the bare-directory-name case it doesn't cover.

### R2 — multi-file sibling recovery (2 strict + 1 any losses; and the multi-stratum ceiling)

ripwire puts one gold file at #1 and the sibling gold lands at 11/13/44/51 — just past the cutoff.
The siblings are 1 structural hop from the found gold (trainer.py imports modeling_utils.py and
training_args.py; django/forms/fields.py sits beside forms.py and renderers.py; zulip's
views/streams.py beside lib/users.py). This is B5.3's #2 recommendation ("buddy-boost"), still
unbuilt, now the single biggest lever: it attacks the 3 remaining losses *and* the multi-file
stratum gap (21.4% strict vs 78.6% any@10 ≈ 16 flippable instances at the ceiling).

### Where competitors simply lost (for completeness)

repowise's 17 strict losses to ripwire are dominated by symbol-level issues its file-page FTS can't
resolve (wiki pages rank, files don't) and by non-source gold its wiki does not page. codeseek's
fallback boundary is described above; its idents arm never beat ripwire on any instance.

## (iv) What to build next (ranked by expected flipped instances)

1. **Sibling/buddy recovery for multi-file gold (R2).** After ranking, lift the strongest
   structural neighbors (import partners, callers/callees, co-change) of the top-3 files into
   ranks ~5–10 when their raw score is within a band. Directly attacks 2 strict + 1 any losses and
   the ~16-instance multi-file ceiling. This was B5.3 recommendation #2 and is now the highest-value
   unbuilt item — expected to move strict@10 well past 60%.
2. **Package-directory mention anchoring (R1).** Extend the existing mention anchor: a backticked or
   quoted bare name that equals a source-bearing directory (package with `__init__.py`, or a dir of
   source files) anchors that package's files, `__init__.py` first. One strict loss today, and it
   closes the last of B5.3's B1.
3. **(Observational) path-token lexical mass.** repowise's single clean win-shape is path-tokens-as-
   text. Worth a calibration experiment in the subtoken ranker (path components as low-weight terms)
   — but do it gated; it can add noise on generic dir names (`utils`, `lib`).

## (iv-b) R1 fix, landed same day and re-measured

The package-directory mention lift (`src/mention.h liftPackageDirMention`, gate:
`test/mentioncheck.sh` case vi) re-run on the identical slice, checkouts, and caches — binary sha256
`9ffe29c6333ef82080ceee8e789eba9344e69e127e7e8487f50215febbad5200`:

| metric | before | after |
|---|---|---|
| strict file@10 | 56.7% | **58.3%** |
| any@10 | 83.3% | **85.0%** |
| single-file stratum strict@10 | 87.5% | 90.6% |
| all-patch strict@10 | 26.7% | 28.3% |
| wall median | 0.18 s | 0.18 s |

Per-instance paired diff: **exactly one instance changed** — `micropython__micropython-lib-947`
(gold worst rank 35 → 2); zero movement anywhere else, so the lift is precision-clean on this slice.
Artifact: `results/ripwire_for_pkgfix.json`. The strict-loss ledger vs repowise is now 17–2.
This is 60-slice evidence, not a formal acceptance run; the two-tier acceptance protocol
(`bench/locbench/GATE_DECISION.md`, 243-instance held-out) remains the ship gate for quoting a new
headline in `docs/EVALS.md`.

## (v) Adversarial verification

An independent adversarial pass was briefed to break the comparison (unequal cache states, metric
duplication, universe asymmetry, convention bias, silent truncation, slice shaping). Findings and
their resolutions: see `VERIFIER.md` in this directory.

## Artifacts

- `results/ripwire_for.json` — harness `--json-out` (per-instance ranks, walls, coverage)
- `results/codeseek.jsonl`, `results/repowise.jsonl` — per-instance competitor records (ranked
  top-50, full-rank metrics computed pre-truncation, walls, raw top pages)
- `worker.py`, `score.py` — arm runner + aggregator (metric imported from `run_locbench.py`)

Reproduce: re-fetch the snapshot (hash above), `run_locbench.py` with the flags above at repo
`6147762`, `pip install repowise==0.37.0`, codeseek 0.1.31 release binary, worker + score scripts.
