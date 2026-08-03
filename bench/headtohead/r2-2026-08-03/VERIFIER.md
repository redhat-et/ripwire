# Adversarial verification — r2 head-to-head (2026-08-03)

An independent adversarial pass was briefed to break the comparison: unequal cache states, metric
duplication, universe asymmetry, imposed-convention bias, silent truncation, and slice shaping.
Verdict: **no finding breaks the comparison** — the metric is single-sourced, the slice is
deterministic (first 60 held-out rows in frozen order, all skip counters zero), and the published
numbers reproduce from the archived artifacts. Six findings survive with the following dispositions.

## Findings and dispositions

**V1 (weakens-claim) — codeseek raw arm is degenerate.** All 60 raw queries returned an empty JSON
array (`raw.bytes == 3` in every record); the 0%/0% row measures a query-protocol incompatibility
(1200-char prose into a function-name matcher), not retrieval quality. The idents arm is partly
self-defeating too: 19/60 instances yielded zero extractable identifiers (guaranteed miss by
construction). *Disposition: adopted — the headline table footnotes the raw row as "0 results
returned in 60/60 queries under this protocol", and codeseek's shipping embedder mode is explicitly
listed as unbenchmarked.*

**V2 (weakens-claim) — the headline gold set is ripwire-universe-defined.** `primary_files` = patch
gold ∩ ripwire's indexed universe; 32/60 instances had gold trimmed (docs/configs, and notably
Cython `.pyx/.pxd` in two sklearn instances), which grows the single-file stratum ripwire dominates.
Scoring is symmetric, but the target set excludes exactly what ripwire cannot see. Sensitivity on
untrimmed all-patch gold: **strict@10 ripwire 26.7% / repowise 16.7% / codeseek-idents 8.3% / raw
0%** — ordering holds, margin halves (+23.4pp → +10.0pp). *Disposition: adopted — the all-patch row
is published beside the headline (§ii of REPORT.md); the trimming rule is stated there. Cython
indexing is a real coverage gap worth its own issue.*

**V3 (weakens-claim, small) — page→file convention costs repowise ~3pp net.** Non-file wiki pages
(avg 2.38/instance) occupy top-10 slots; filtering them gives repowise 36.7%/58.3% (vs 33.3%/53.3%
as scored). The `::` symbol-spotlight stripping cuts the other way and helps it substantially
(547/1200 top-20 results would otherwise be unscoreable). *Disposition: adopted — sensitivity row
published in §ii; the worker doc-comment that misdescribed the filter is fixed. Neither variant
flips any conclusion.*

**V4 (cosmetic → weakens latency claims) — wall asymmetries.** repowise's 1.135 s includes a fresh
MCP server spawn + handshake per query (resident-server usage would be faster); ripwire's index
wall was not measured this run (rich caches prebuilt) while competitor index walls were.
*Disposition: adopted — both facts are footnoted in §ii; index walls are never tabulated
side-by-side with ripwire's.*

**V5 (latent hazard) — worker silently converted a codeseek JSON-decode failure into an empty
result.* Did not fire this run (outputs were legitimately empty JSON). *Disposition: fixed in
`worker.py` (decode failure now raises, honoring zero-silent-skip).*

**V6 (cosmetic) — provenance gaps.** `ripwire_for.json` does not embed `query_chars`/`top_k`, and
stores ranks rather than ranked file lists (competitor records store top-50). The B5.3 strata
(20/40) are not comparable to this run's (32/28) — different evaluator vintage. *Disposition:
noted here and in REPORT.md's header; harness meta enrichment left as a follow-up.*

## Checks that passed outright

Metric single-sourcing (worker imports `file_ranks`/`first_hit`/`norm_path` unmodified; scorer's
`file_worst<10` ≡ harness `acc_all_at(franks,10)`); query construction byte-identical across arms
(shared rows file, hash `5bbcea4b…`); universe/basename-fallback asymmetry empirically inert (0 of
78 credited competitor hits used the basename fallback); spot-checked records internally consistent;
scoring done pre-truncation (3 hits beyond stored rank 50 still credited); slice = exactly the first
60 held-out rows in frozen dataset order.
