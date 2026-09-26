# MULocBench — adapter design, pre-registration, and open questions (no run yet)

Status 2026-09-20: **no MULocBench data is on disk anywhere on this machine** (checked
`bench-assets/`, `$ORCH`, and the whole `project2` tree — nothing). **No number exists yet.** This
document is the design and the pre-registration that must exist *before* any row is scored — the
house rule `bench/multiswe/run_multiswe.py` and `bench/locbench/run_locbench.py` both follow
(`docs/METHODOLOGY.md` §9; every `dataset.lock` in this repo is a frozen, content-hashed instance
list committed before the first scored run). It also names the owner-run fetch steps and the
questions worth putting to the benchmark's authors before we publish anything comparative.

This follows a private conversation with the benchmark's authors that is **not reproduced here in
any form** — no quotes, no paraphrase, no "they said". Everything below is sourced from the public
paper (arXiv:2509.25242) and the public dataset card
(<https://huggingface.co/datasets/somethingone/MULocBench>), read via `WebFetch`, cited inline, and
restated in our own words. Where the source is ambiguous or silent, this document says so rather
than guessing — see §4.

`bench/multiswe/README.md`'s existing "Future set: MULocBench" section is the prior note that
flagged this as future work; this document is that follow-through, and `bench/multiswe/README.md`
now points here instead of restating it.

## 0. What MULocBench is (from the public sources, restated)

**MULocBench** (Zhang et al., arXiv:2509.25242, 2025, "A Benchmark for Localizing Code and Non-Code
Issues in Software Projects") is a Python-only issue-localization benchmark: **1,100 issues from 46
popular GitHub Python projects**, each linked to a resolving pull request, commit, or
resolution-confirming comment, with gold **location** records carrying project, file path, class
name (if applicable), function name (if applicable), and line numbers (if applicable). Its stated
point of difference from LocBench/SWE-bench is that gold locations are **not restricted to code**:
the paper's own taxonomy — **code 889 (80.8%), test 258 (23.5%), documentation 259 (23.5%),
configuration 167 (15.2%), asset 48 (4.4%)** of issues (percentages exceed 100% because one issue
can carry gold locations of more than one type) — is exactly the "non-code gold location" distribution
that `bench/locbench`, `bench/cppbench`, and `bench/multiswe` structurally cannot score, because all
three mine their gold from a source-code fix diff. The paper reports every tested method — BM25 and
four LLM-prompted / agentic methods (Agentless, LocAgent, OpenHands, each on Claude 3.5) — **under
40% Acc@5/F1 at file level**, and lower at function level (best observed: LocAgent 21.9% Acc@5, 18.5%
F1). The headroom is real and open on every method the paper tried, not just a static one.

The dataset card (`somethingone/MULocBench`, single `train` split) lists **3,052 rows**, 21.4 MB as
auto-converted Parquet, against the paper's **1,100 issues** — this is flagged, not resolved, in §3
Q2; it most likely means one row per (issue, location) pair rather than one row per issue, but that
is a guess pending confirmation, not a fact this document asserts.

## 1. What a MULocBench adapter must change, versus what we have

Read: `bench/locbench/run_locbench.py` (the LocBench harness `$ORCH/sim/r4/run_locbench.py` names —
confirmed identical in content to the committed `bench/locbench/run_locbench.py`; the `$ORCH` copy is
a working mirror, not a second source), and `bench/multiswe/run_multiswe.py`, which already
demonstrates the reuse pattern (`sys.path.insert` + `import run_locbench as lb`) this adapter follows.
`bench-assets/r4/r4_worker.py` / `r4_score.py` are the **head-to-head** harness's worker/scorer
(`bench/headtohead/`, a different instrument — it re-runs *other tools*, not just ripwire, against the
same LocBench gold); they share `run_locbench`'s metric code but are not what a MULocBench adapter
extends. The adapter extends `run_locbench`/`run_multiswe`'s lineage directly, the same way
`run_multiswe` extended `run_locbench`.

**1. Gold definition — the biggest change.** `run_locbench.gold_for_instance` and
`run_multiswe.gold_from_fix_patch` both derive gold by **diffing a fix patch**: files touched, and
(LocBench) a colon-delimited `edit_functions`/`added_functions` field, or (Multi-SWE-bench) git's own
hunk-header function context. MULocBench's gold is not diff-derived at all — it is **dataset-native
structured fields** (`file_loc`, `own_code_loc`, `ass_file_loc`, `other_rep_loc`, each apparently
carrying file/class/function/line, plus a `loctype` dict categorizing code/test/config/doc/asset and
an `analysis` dict with issue type/reason/location scope — field names per the dataset card, **not
yet verified against one real row**, see §4). The adapter needs a new `gold_from_mulocbench_row()`
that reads these fields directly instead of parsing a patch, and must decide, per §2.3, which of the
four location fields are in-scope (in particular: `other_rep_loc` — "third-party-file" — is
structurally unscoreable by a harness that checks out only the target repo, and is excluded at
mining time, counted, never silently dropped).

**2. Scoring — needs a metric this repo has never shipped.** Every existing harness here
(`run_locbench`, `run_multiswe`, `bench/headtohead`) scores **strict Acc@k** (`acc_all_at` — ALL gold
locations inside the top-k of one flat rank, LocAgent's definition, arXiv:2503.09089 §4.1) plus a
lenient any-gold@10 and first-hit MRR. MULocBench's own paper scores **Acc@k (their definition reads
as the same ALL-in-top-k shape as LocAgent's, restated in §2.2) *and* per-issue F1** (precision/recall
over the location set, treating each gold location as an independent TP/FP/FN) at **three
granularities — file, class, function** (`run_locbench`/`run_multiswe` score file and function only;
neither has ever scored class-level). The adapter needs: (a) a class-level rank function alongside
the existing `file_ranks`/`func_ranks`, and (b) an F1 accumulator alongside the existing strict/lenient
accumulators — genuinely new code, not a re-parametrization of what exists.

**3. Task-to-verb mapping — smaller than feared, verified empirically, not assumed.** The worry
going in was that `--for`'s ranked output is code-symbols-only and structurally blind to doc/config
gold. Checked directly against this repo with the freshly built worktree binary (dogfood rule; see
§6) rather than inferred from docs:

```
$ ./build/ripwire . --for="applyDocMentionBoost mention anchoring" --format=candidates --top-k=200 \
    | grep -o 'p="[^"]*\.md"' | sort -u
CHANGELOG.md
bench/headtohead/REPORT.md
bench/multiswe/README.md
docs/COMMANDS.md
docs/EVALS.md
docs/LIMITS.md

$ ./build/ripwire . --for="applyDocMentionBoost mention anchoring" --format=candidates --top-k=200 \
    | grep -o '<cand[^>]*p="bench/multiswe/README.md"[^>]*>'
<cand r="28" s="20.6716" n="Future set: MULocBench (documented, not yet built)" ... k="sec"
      p="bench/multiswe/README.md" l="170">

$ ./build/ripwire . --for="ci workflow matrix python version config" --format=candidates --top-k=200 \
    | grep -o 'p="[^"]*\.\(json\|yml\|yaml\|toml\)"' | sort -u
.github/workflows/ci.yml
```

**Markdown headings are indexed and ranked as ordinary candidate rows** (`k="sec"`, per
`CLAUDE.md`'s language table: "Markdown — headings are section symbols with spans"), and **YAML/JSON/
TOML config keys are indexed the same way** (`queries/{yaml,json,toml}/tags.scm` all exist). Both
already flow through `lb.parse_candidates`/`lb.file_ranks` at the file level **with no change to
either function's behavior for any existing caller** — both already read `p=`/`n=`/`id=`/`r=` off any
`<cand>` row and don't care what `k=` says. This means **file-level scoring for doc and config gold
needs zero new retrieval code**, only new gold extraction and the F1/class additions below.
`lb.parse_candidates` did gain one additive field in this same commit — `kind=` (the `k=` attribute,
previously read by nothing) — because `class_ranks()` (§2.1) needs it and a first pass forked a
second copy of the function to get it; `./build/ripwire . --quality-delta` caught that fork as a
gating `new-clone-of-reused-helper` finding before this branch was pushed, and the fix was to extend
the one shared function every harness already imports instead of shipping a duplicate — exactly the
gate doing its job. The one thing this test does *not* establish: whether
`RIPWIRE_NO_DOC_MENTION=1` (the R5 doc-mention-boost kill switch, `src/mention.h::applyDocMentionBoost`)
changes `--format=candidates` ranking specifically, as opposed to just the human-readable bundle — a
probe query that already lexically named the target symbol produced byte-identical candidate output
with the env var on and off, which is exactly what the boost's own "inert without an indirect mention"
contract predicts for that query shape, so the probe was inconclusive, not negative. This is called
out as unverified in §2.1's arm table rather than asserted either way.

Binary (no gold, so structurally out of reach for any static, non-runtime tool): **asset** locations
(images, binaries — 48 issues per the paper's taxonomy) get no candidate rows at all; ripwire indexes
parseable text. These are retained in the gold set and scored as automatic misses, counted and
reported by category (§2.4), the same honesty convention `bench/locbench` already applies to
`added_functions` and `bench/multiswe` to non-language-extension patch files.

**4. Eligibility rule — mostly reusable, with one new exclusion.** `run_multiswe.classify_row`'s
filters (non-empty query ≥4 words, no embedded local home-directory path, resolvable base commit) all
transfer unchanged. New: MULocBench's `other_rep_loc` (third-party-file gold) is out of scope for a
harness that checks out only the target repo — excluded at mining time, not silently dropped (see
§2.3). `ass_file_loc` ("runtime-file location information") has no confirmed operational meaning
yet — see the open question in §3 — and is provisionally excluded pending an answer, also counted.

## 2. Adapter design and pre-registration

Nothing below has been run against real data. This section is the commitment made *before* any row
is seen — the same discipline `run_multiswe.py`'s `dataset.lock` content-hash freeze enforces after
the fact, done here in writing before mining exists at all. A future mining step must match this
section or the mismatch is itself the finding (and gets written up, not silently reconciled).

### 2.1 Verb mapping — fixed in writing

| Gold location type (paper's taxonomy) | ripwire invocation | Scoring path | Status |
|---|---|---|---|
| Code — function/method | `--for="<title>\n<body>"` (primary), `--query=...` (BM25 control) | `lb.file_ranks` (unchanged) + `func_ranks` (unchanged: `k="fn"`/`"method"` rows) | Verified reusable |
| Code — class | same run as above | **new** `class_ranks()`: first candidate with `k∈{"cls","struct"}` and `n==`gold class, or (no direct class candidate) the best-ranked member whose `id=` canon contains `::<Class>::` | New code, untested |
| Doc — markdown file (+ line, if MULocBench gives one) | same run as above, same `--format=candidates` export | `lb.file_ranks` (unchanged) — `k="sec"` rows are ordinary candidates | Verified reusable |
| Config — YAML/JSON/TOML key | same run as above | `lb.file_ranks` (unchanged); a named key, if MULocBench gives one, scored like `func_ranks` with a kind check once real field names are confirmed | File-level verified reusable; key-level granularity depends on §4 field confirmation |
| Test — test-file gold | same run as above | `lb.file_ranks` (unchanged) — a `test/*.py` file is ordinary Python source to ripwire, no special-casing | Verified reusable |
| Asset — binary/non-text gold | **no invocation** — not indexable | reported as `asset_unindexable` count per instance, never scored as a miss silently folded into the denominator | Structural, not a gap to close |
| `other_rep_loc` (third-party-file) | **no invocation** — excluded at mining, `mining_stats["other_repo_excluded"]` | n/a | Excluded by design, counted |

**Arms** (mirrors `run_multiswe.ARMS`, plus the one lever this specific benchmark exists to
evaluate): `for` (shipping default, incl. B8 mention-anchor and R5 doc-mention boost) ·
`for-no-mention` (`--no-mention-boost`, B8 off) · `for-no-docmention` (`RIPWIRE_NO_DOC_MENTION=1`, R5
off — **the direct test of whether doc-mention boost earns its keep on a benchmark built to score
exactly that**) · `query` (`--query=`, pure lexical BM25, no lens framing). Four arms, not three —
`for-no-docmention` is new relative to both existing harnesses, because neither LocBench nor
Multi-SWE-bench's gold set ever contained enough doc-type gold to make the ablation meaningful; this
one's gold set is built for it (259 doc issues per the paper).

### 2.2 Metric definitions, restated in our own words from the public card/paper

- **Acc@k (k=1, k=5 — the paper's own k values, both reported; we additionally report @10 for
  continuity with our own house metric family):** identical shape to `acc_all_at` — an instance
  scores 1 only if **every** gold location of the scored type is within the top-k of one flat rank,
  else 0. Same strict, no-partial-credit definition LocAgent uses and this repo already implements;
  no new code needed for Acc@k itself, only new gold and (for class-level) a new rank function feeding
  it.
- **F1 (new to this repo):** per issue, over the set of gold locations of the scored granularity —
  precision = (predicted locations that are gold) / (predicted locations), recall = (gold locations
  found) / (gold locations), F1 = 2·P·R/(P+R). Two design choices this document fixes now, before any
  row is scored, because both are silently variable and would change the number: **(a) "predicted
  locations"** = the top-k ranked candidates, k fixed at the same value used for that run's Acc@k
  (k=5, matching the paper's reported F1@5); **(b)** an issue with zero gold locations of the scored
  type is excluded from that granularity's F1 average (never scored as F1=1 by an empty-set
  vacuous-truth, never scored as F1=0 by an empty-denominator crash) — both choices are guesses about
  the paper's own convention, not confirmed; §3 Q3 asks the authors directly, and the adapter's
  docstring will say which convention it used the moment it ships, alongside the alternative's number
  where cheap to also compute.
- **Parse coverage (this repo's own honesty instrument, not the paper's):** the fraction of gold
  locations whose file even appears in the indexed candidate universe, reported per location-type
  category, the same convention `run_locbench` already applies (`skipped_nonpy`,
  "PARSE COVERAGE is reported as its own number" in its own header comment) and `run_multiswe`'s
  `skipped_unindexable`.

### 2.3 Eligibility and exclusion rules (pre-registered)

An instance is **mined** (kept in `dataset.lock`) only if:
1. it has a resolving reference (`pr_html_url`, `commit_html_url`, or an equivalent resolution
   marker) and a `base_commit`/equivalent pinned SHA before the fix;
2. the joined issue `title`+`body` is non-empty and ≥4 words (same floor `run_multiswe` uses,
   for the same reason: a query that short cannot be a real localization task);
3. the query does not embed a contributor's own local home-directory path (reuse
   `run_cppbench.LOCAL_PATH_RE`, same hygiene rule already shared by `bench/cppbench` and
   `bench/multiswe`);
4. it has **at least one gold location in `file_loc` or `own_code_loc`** (in-project) — an instance
   whose only gold is `other_rep_loc` (third-party) is excluded here, counted in
   `mining_stats["other_repo_only"]`;
5. `ass_file_loc` locations, if present alongside an otherwise-eligible instance, are **retained in
   the row but excluded from the scored gold set** pending §3 Q4 — the instance is not dropped, only
   that location category is withheld from scoring until its meaning is confirmed.

Every exclusion is a **counted mining_stats bucket**, never a silent drop — the same zero-fabrication
contract `run_multiswe.mine_lang` already enforces (`stats["kept"]`, printed per language).

### 2.4 What we would report, and what we would withhold

**Report:** Acc@1/Acc@5/Acc@10 and F1@5, at file/class/function granularity, each broken out **by
location-type category** (code/test/config/doc — never pooled into one number the way a first release
of this table would be tempted to, because pooling would hide exactly the non-code headroom this
benchmark exists to measure); parse-coverage per category; the asset-unindexable count as its own
disclosed line, never folded into a miss; wall-clock per instance; the four-arm table from §2.1,
with the `for` vs `for-no-docmention` delta called out explicitly (that delta is this benchmark's
whole point for us). Single-location vs multi-location strata, mirroring the single/multi-file split
`bench/multiswe`'s README already reports.

**Withhold, until the open questions in §3 are answered:** any head-to-head framing against the
paper's own published BM25/Agentless/LocAgent/OpenHands numbers as a same-conditions comparison — our
harness, checkout state, and (pending Q3) F1 convention are not yet confirmed to match theirs, and
publishing a "ripwire beats LocAgent" table built on an unconfirmed metric convention would be the
same mistake `bench/multiswe/README.md` already warns against for its own LLM-vs-deterministic
framing ("measures the $0 deterministic FLOOR, not parity"). We would report our own numbers, cite
theirs as published, and say plainly that the two are not yet proven comparable. Also withheld: the
raw per-row dataset text — pending the license confirmation in §3 Q1, only a derived `dataset.lock`
(instance ids, gold sets, content hash) would be committed, the same posture `bench/multiswe` already
takes with Multi-SWE-bench's raw JSONL.

## 3. Questions worth putting to the benchmark's authors ("what we would like help with")

Derived from reading the paper and the dataset card, not from anything else:

1. **License.** Multi-SWE-bench's card states CC0 explicitly (quoted verbatim in
   `bench/multiswe/README.md`); MULocBench's HF card does not appear to state a data license for the
   derived instance/location records. Before we commit even a derived `dataset.lock` (instance ids +
   gold sets + content hash, no raw issue text — our standing posture per §2.4), what license governs
   redistributing that derived form?
2. **Row count vs issue count.** The card's `train` split lists 3,052 rows; the paper states 1,100
   issues. Is a row one (issue, location) pair, or is there another split we should be collapsing
   before treating "row" as "instance" for mining purposes?
3. **F1 partial-credit convention.** Is F1 computed at a fixed k (and if so, which k — 5, matching
   the paper's reported number, or unbounded over however many locations an approach returns), and
   how is an issue with an empty gold set at a given granularity handled — excluded from that
   granularity's average, or scored some other way? (§2.2 states our provisional choice; we'd rather
   match yours than diverge silently.)
4. **`ass_file_loc` ("runtime-file location").** What does this category mean operationally — a
   location discovered only by running the code, as opposed to reading it? If so, is it fair for a
   purely static tool with no runtime component to be scored against it at all, or is it intended to
   be out of scope for exactly that class of localizer?
5. **`other_rep_loc` (third-party-file locations).** We're planning to exclude instances whose only
   gold is in a dependency repo, since our harness checks out only the target repo. Is there an
   intended convention (checking out the named third-party repo too, e.g.) we'd be missing by
   excluding these?
6. **Comparability for a deterministic, non-agentic tool.** Every baseline in the paper is either
   BM25 or an LLM-prompted/agentic method. Is there a recommended harness version, top-k convention,
   or submission format that would make a $0 deterministic ranker's numbers legible next to yours, or
   is the benchmark's scoring code itself the right thing for us to run rather than reimplementing it
   (which would also resolve Q3 for free)?

## 4. Owner-run fetch steps

Same shape as `$ORCH/sim/msb/README_OWNER.md`'s Multi-SWE-bench pattern (also mirrored at
`$ORCH/sim/mulocbench/README_OWNER.md` for this round). **Nothing below has been run.** No agent in
this lane downloads the dataset or clones a repository — that is the owner's step, same reasoning as
Multi-SWE-bench: **do not download the dataset or clone any repository** is a hard constraint on the
agent, not on the owner.

**Step 1 — fetch the dataset's row/schema metadata only (JSON, minutes, low disk).** Confirms the
real field names/shapes before any mining code is trusted (closes the gap §1 flags: field names above
are sourced from the dataset card's prose, not yet verified against one real row).
```sh
bash $ORCH/sim/mulocbench/1_fetch_rows.sh
# writes bench-assets/mulocbench/datasets/{splits.json, mulocbench_rows.jsonl, SHA256SUMS}
```
Uses the same public HF `datasets-server` JSON API `1_fetch_rows.sh` in `sim/msb` already uses
(`/splits`, then paginated `/rows`), pointed at `somethingone/MULocBench`, `train` split — JSON rows
only, no Parquet/pickle download, no code execution. **Disk budget: well under 200 MB** (the card's
own Parquet auto-conversion is 21.4 MB; JSON row text is typically 2-4x a Parquet size for
text-heavy columns like `body`, so a 200 MB ceiling is a generous estimate, not a measurement — will
be corrected against the real number the first time this runs).

**Step 2 — tell the agent step 1 is done.** The orchestrator then works out, from the real
`file_loc`/`own_code_loc`/`ass_file_loc`/`other_rep_loc`/`loctype` shapes, whether §1/§2's field-name
assumptions held, fixes the mining/eligibility code in writing if not, and writes
`bench/mulocbench/dataset.lock` (frozen instance list, content-hash sealed, same shape as
`bench/multiswe/dataset.lock`).

**Step 3 — clone the checkouts the lock names.** Single-commit, shallow, hooks/LFS off, same shape
as `sim/msb/3_clone.sh`:
```sh
bash $ORCH/sim/mulocbench/3_clone.sh
# reads bench-assets/mulocbench/datasets/checkouts.tsv (org/repo <TAB> base_commit <TAB> dir)
# writes bench-assets/mulocbench/repos/<dir>/
```
**Disk budget: 8 GB, hard-capped in the script (checks `du -sk` before each clone and stops), same
budget-then-stop shape as `sim/msb/3_clone.sh`'s 15 GB cap.** This is a placeholder estimate, not a
measurement — only 46 distinct repos total (versus Multi-SWE-bench's many-repos-per-language spread),
but MULocBench's "top-50 most-starred Python projects" sampling frame plausibly includes some large
monorepo-style checkouts; the real figure will be known after step 1 lists the actual 46 repos, and
the cap should be revised in the same commit as the real number, not left as a guess.

**Step 4 — tell the agent step 3 is done.** Agents mine `dataset.lock` (already written after step 2)
against the checkouts, run the four arms from §2.1, and score per §2.2-2.4. This step produces the
first real MULocBench number this repo will have.

## 5. Current status (task 5)

No MULocBench data exists on this disk — checked `bench-assets/`, every `$ORCH/sim/*` directory, and
the repo tree; nothing under any spelling of `mulocbench`/`MULocBench` exists except this document and
the adapter skeleton in `bench/mulocbench/`. **No number exists yet, and none is claimed here.**
Everything in §2 is the pre-registration; §4 is what the owner needs to run before §2 can be tested
against reality.

## 6. Dogfood gaps

Per this repo's dogfood rule — navigated with the shipped binary itself before grep/reads,
built fresh in this worktree (`cmake -S . -B build && cmake --build build -j8`, clean configure +
build, no prior binary reused). The §1 findings above (`k="sec"` markdown rows, `.yml` config rows
in `--format=candidates`) were produced by `./build/ripwire . --for=... --format=candidates`, not by
reading source and guessing.
- `[--for --format=candidates]` "does a doc/config file show up as a candidate row" → confirmed yes
  for `.md` (`k="sec"`) and `.yml` → no fallback needed.
- `[RIPWIRE_NO_DOC_MENTION=1 probe]` "does the R5 doc-mention kill switch change `--format=candidates`
  ranking" → inconclusive on the probe query tried (byte-identical output, consistent with the
  boost's own inert-without-an-indirect-mention contract for a query that already named the target
  symbol directly) → fell back to reading `src/mention.h`'s header comment for the mechanism
  description rather than constructing a second, more targeted probe query → cost: the arm's exact
  ranking effect is asserted as "to be measured", not "measured", in §2.1; a real MULocBench issue
  body (prose that doesn't lexically match code but whose target doc backtick-mentions the right
  symbol) is a much better probe than anything hand-built here, so this is deferred to the real run
  rather than spending more of this lane on a synthetic query.
- `[--for candidates, class-kind rows]` "what `k=` values exist for class-level gold" → `--format=candidates`
  directly listed `k="cls"`/`k="struct"` alongside `"fn"`/`"method"`/`"sec"`/`"var"` → no fallback
  needed, confirms §2.1's `class_ranks()` design has real kind tags to match against.
