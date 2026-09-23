#!/usr/bin/env python3
"""score_arise_linerank.py — the R3 ("def-primacy") line-ranking scorer registered in
docs/research/arise-line-ranking-prereg.md, and the fingerprint/verdict machinery around it.

Registered here in harness terms (rv-arise-line-ranking.md MEDIUM-2: "the harness that would score
the attempt does not exist as a command anywhere. ... no command scores the attempt or checks the
fingerprint"):

  hasdef[n] = 1 iff some inventory variable's v1 rows contain <s l=n k="def"|"both">   (seed-free,
              unions over the whole inventory — the SAME population coverage() already ranges over)
  cover[n]  = the number of distinct inventory variables with ANY occurrence (def or use) on line n
              (R1's own already-registered statistic, docs/EVALS.md "def-use row order")
  r3        = sorted(span, key=lambda n: (-hasdef[n], -cover[n], n))

This is the harness-side statement of exactly what src/slice.h's sliceRowHasAnyDef / sliceRowCoverage /
sliceLineRankAttemptOrder compute in the binary. The code<->harness equivalence (rv-arise-line-ranking.md
MEDIUM-2's own phrase) is argued in docs/research/arise-line-ranking-prereg.md §8 and tested at the
BINARY level by test/slicerank_unit.cpp item (6), which runs the real tree-sitter classifier on a real
Python fixture and checks sliceRowHasAnyDef against an independent second computation over the same
real scan data — this script is the harness-side twin of that same rule, not a re-derivation of it.

Fixed after a second review round (rv-arise-line-ranking.md HIGH-6): the tier-(a) gold-line count is
computed from each carried row's own `patch` field via `file_sections()`/`gold_pre_lines()` — ported
from `locbench_gold.py` (docs/research/slice-line-recall.md §1.1's G2 rule), NOT from a `gold_lines`
key the real dataset does not carry. `main()` genuinely STOPS (exit 2, no `verdict` key) on any tier
mismatch, checked against the REGISTERED constants (module-level, hardcoded on purpose — the doc
registers them, so a run that silently drifted onto different expectations would defeat the whole
point of a fingerprint). Tiers (b)/(c) read a `--summary` file; `--drift-summary` gives the §1.3
old-binary re-fingerprint a place to land.

SELF-TEST ONLY on this machine. The LocBench corpus itself (patches, checkouts) is not here and this
script never reads or fetches it. `--self-test` builds small synthetic datasets and patches in-process
and checks this module's own logic against hand-verified answers — it is a unit test for the SCORER,
not a scoring run. It DOES read the committed `--heldout` default (a repo-name list from an unrelated,
already-public measurement round — no patch, no code, no corpus content) to prove the loader works
against the real file; that is reading committed repository configuration, not fetching or scoring
LocBench. The --dataset/--summary/--drift-summary/--results path exists for a FUTURE round that has
the real corpus and a real harness run; running it is not something this lane does.

Usage:
    python3 bench/slice/score_arise_linerank.py --self-test

    # once the corpus, a real per-instance results.json and a results-summary.json exist elsewhere
    # (a future round, not this lane):
    python3 bench/slice/score_arise_linerank.py \
        --dataset DATASET.json --summary results-summary.json \
        --results results.json --verdict-out verdict.json
    # with a binary-drift check (pre-reg §1.3):
    python3 bench/slice/score_arise_linerank.py \
        --dataset DATASET.json --summary results-summary.json --drift-summary drift-summary.json \
        --results results.json --verdict-out verdict.json
"""
from __future__ import annotations

import argparse
import json
import random
import re
import sys
from dataclasses import dataclass
from pathlib import Path
from typing import Optional, Sequence

# the committed 88-repo list this lane cites (rv-arise-line-ranking.md HIGH-1/MEDIUM-6): an unrelated
# measurement round's own held-out split, whose 306 instances' `repo` field is set-equal to the 88
# directories docs/research/arise-line-ranking-prereg.md §1.1 registers as the population's repos.
DEFAULT_HELDOUT = "bench/locbench/results/r3_pathtok/heldout_baseline.json"

# The REGISTERED tier-(a) population, hardcoded on purpose (rv-arise-line-ranking.md HIGH-6: "the doc
# registers them, so hardcoding them is the point; the current [round-1] comment arguing against it is
# wrong" — an earlier draft of this module kept the expectation out of the module so "a dataset drift
# cannot silently pass"; that reasoning was backwards, because keeping the expectation OUT of the
# module is exactly what let a caller pass any expectation it liked, including a wrong one. The
# expectation is the whole point of a pre-registered fingerprint, so it lives here, checked the same
# way on every run — score()'s registered_tier_a parameter defaults to this and only a test passes
# anything else).
REGISTERED_TIER_A = {
    "dataset": 560,
    "multi_function": 208,
    "single_function": 352,
    "carried": 182,
    "carried_gold_lines": 1040,
}

# Tier (b): binary-dependent counts (docs/research/arise-line-ranking-prereg.md §1.2b).
TIER_B_COUNTS = {"scored_instances": 173, "var_instances": 498}
TIER_B_SKIPS = {
    "selector_refused_plain": 3,
    "selector_refused_scoped": 2,
    "expand_no_body": 2,
    "gold_outside_span": 2,
}

# Tier (c): statistics, tolerance +-0.0005+1e-9 per figure (§1.2c; served_syms' own HIGH-2 fix).
TIER_C_TOLERANCE = 0.0005 + 1e-9
TIER_C_RECALL_AT_1 = {"r0": 0.029, "ctl": 0.042, "r1": 0.048, "r2": 0.048}
TIER_C_MRR = {"r0": 0.154, "ctl": 0.234, "r1": 0.289, "r2": 0.289}


# ── gold-line extraction, ported from locbench_gold.py (docs/research/slice-line-recall.md §1.1 G2) ──
# Ported, not imported: locbench_gold.py lives on origin/lane/research-arise-slice (unmerged) and this
# lane does not pull code from an unreviewed branch wholesale. The port is a direct, line-for-line
# translation of file_sections()/gold_pre_lines() (read there for reference while writing this), covered
# by a self-test row with a real-shaped patch (a hunk with one '-' line and one '+' run, hand-verified).

HUNK = re.compile(r"^@@ -(\d+)(?:,(\d+))? \+(\d+)(?:,(\d+))? @@")


def file_sections(patch: str) -> dict:
    """split a unified diff into {post_path: [lines]} sections, keyed by the b/ path."""
    out, cur, path = {}, None, None
    for line in patch.splitlines():
        if line.startswith("diff --git "):
            cur, path = [], None
        elif line.startswith("+++ b/") and cur is not None:
            path = line[6:]
            out[path] = cur
        elif line.startswith("+++ ") and cur is not None:
            path = None
        elif cur is not None:
            cur.append(line)
    return out


def gold_pre_lines(section: Sequence[str]):
    """pre-image gold line numbers for one file section — docs/research/slice-line-recall.md §1.1 G2:
    every '-' line contributes its pre-image line number; a run of '+' lines with no '-' line of its
    own contributes ONE anchor (the pre-image line just before the insertion, or the hunk's first
    pre-image line when the run opens the hunk). Returns (gold, deleted, anchors), each sorted."""
    deleted, anchors = set(), set()
    pre_ln, hunk_start, consumed, plus_run_open = None, None, False, False
    for line in section:
        m = HUNK.match(line)
        if m:
            hunk_start = int(m.group(1))
            pre_ln, consumed, plus_run_open = hunk_start, False, False
            continue
        if pre_ln is None:
            continue
        if line.startswith("-") and not line.startswith("---"):
            deleted.add(pre_ln)
            pre_ln += 1
            consumed = True
            plus_run_open = False
        elif line.startswith("+") and not line.startswith("+++"):
            if not plus_run_open:
                anchors.add(pre_ln - 1 if consumed else hunk_start)
                plus_run_open = True
        elif line.startswith("\\"):
            continue
        else:   # context (leading space, or empty line)
            pre_ln += 1
            consumed = True
            plus_run_open = False
    return sorted(deleted | (anchors - deleted)), sorted(deleted), sorted(anchors - deleted)


def row_gold_line_count(row: dict) -> int:
    """the gold-line count for ONE carried row, restricted to edit_functions[0]'s path — exactly the
    quantity `carry_row()`'s `len(got["gold"])` computes, without needing the checkout/binary stages
    that also gate `carry_row` (this module's carried_rows() already restricts to single-function AND
    held-out-repo; for the REGISTERED 182-row population the review verified those two conditions alone
    reproduce locbench_gold.py's fuller carried set exactly, so no further filtering is applied here)."""
    efs = row.get("edit_functions") or []
    if len(efs) != 1:
        return 0
    path = efs[0].rpartition(":")[0]
    secs = file_sections(row.get("patch") or "")
    sec = secs.get(path)
    if sec is None:
        return 0
    gold, _deleted, _anchors = gold_pre_lines(sec)
    return len(gold)


# ── population fingerprint (docs/research/arise-line-ranking-prereg.md §1) ─────────────────────────────

def carried_rows(dataset: Sequence[dict], heldout_repos: set) -> list:
    """Every row whose edit_functions has length 1 (single-function) AND whose repo is one of the
    held-out repos — the pre-registered construction rule (§1.1: base_commit presence is a
    PRECONDITION of the checkout being complete, not a filter this function applies)."""
    out = []
    for row in dataset:
        efs = row.get("edit_functions") or []
        if len(efs) == 1 and row.get("repo") in heldout_repos:
            out.append(row)
    return out


def fingerprint_dataset_only(dataset: Sequence[dict], heldout_repos: set) -> dict:
    """Dataset-only cascade counts — computable from the dataset json and the held-out repo set alone,
    no checkout and no binary. carried_gold_lines is now the REAL gold-line count (row_gold_line_count,
    via each row's own patch) — rv-arise-line-ranking.md HIGH-6.1 fixed this from a nonexistent
    `gold_lines` field, which silently summed to 0 on the real dataset."""
    multi = [r for r in dataset if len(r.get("edit_functions") or []) > 1]
    single = [r for r in dataset if len(r.get("edit_functions") or []) == 1]
    carried = carried_rows(dataset, heldout_repos)
    gold_lines = sum(row_gold_line_count(r) for r in carried)
    return {
        "dataset": len(dataset),
        "multi_function": len(multi),
        "single_function": len(single),
        "carried": len(carried),
        "carried_gold_lines": gold_lines,
    }


def check_fingerprint(dataset_only: dict, expected: dict):
    """Exact integer match — no tolerance, these are counts. Returns (ok, list-of-mismatch-strings)."""
    mismatches = []
    for key, want in expected.items():
        got = dataset_only.get(key)
        if got != want:
            mismatches.append(f"{key}: got {got}, want {want}")
    return (len(mismatches) == 0, mismatches)


def load_heldout_repos(path) -> set:
    """The default (DEFAULT_HELDOUT) is a dict with an "instances" list, each carrying its own `repo`
    — read the DISTINCT repo values from it. A bare JSON list of repo strings is also accepted, for a
    lighter-weight file (or a self-test fixture)."""
    with open(path, encoding="utf-8") as f:
        d = json.load(f)
    if isinstance(d, list):
        return set(d)
    if isinstance(d, dict) and "instances" in d:
        return set(i["repo"] for i in d["instances"])
    raise ValueError(f"{path}: cannot find a repo list (expected a JSON list, or a dict with an "
                      f"'instances' list of {{'repo': ...}} objects)")


# ── tiers (b)/(c): binary-dependent counts and statistics, from a --summary file ───────────────────────

def check_tier_b(summary: dict):
    mismatches = []
    for key, want in TIER_B_COUNTS.items():
        got = summary.get(key)
        if got != want:
            mismatches.append(f"{key}: got {got}, want {want}")
    skips = summary.get("skips") or {}
    for key, want in TIER_B_SKIPS.items():
        got = skips.get(key)
        if got != want:
            mismatches.append(f"skips.{key}: got {got}, want {want}")
    return (len(mismatches) == 0, mismatches)


def check_tier_c(summary: dict):
    mismatches = []
    recall = summary.get("recall_at_k") or {}
    for arm, want in TIER_C_RECALL_AT_1.items():
        got = (recall.get(arm) or {}).get("1")
        if got is None or abs(got - want) > TIER_C_TOLERANCE:
            mismatches.append(f"recall_at_k.{arm}.1: got {got}, want {want} (+-{TIER_C_TOLERANCE})")
    mrr_summary = summary.get("mrr") or {}
    for arm, want in TIER_C_MRR.items():
        got = mrr_summary.get(arm)
        if got is None or abs(got - want) > TIER_C_TOLERANCE:
            mismatches.append(f"mrr.{arm}: got {got}, want {want} (+-{TIER_C_TOLERANCE})")
    return (len(mismatches) == 0, mismatches)


# ── the R3 rule itself (pre-reg §3.1, "def-primacy") ────────────────────────────────────────────────

def r3_order(span_size: int, coverage: Sequence[int], hasdef: Sequence[int]) -> list:
    """r3 = sorted(span, key=lambda n: (-hasdef[n], -cover[n], n)) — zero fitted parameters, a pure
    integer lexicographic sort (no float score, no epsilon tie-break)."""
    if len(coverage) != span_size or len(hasdef) != span_size:
        raise ValueError("coverage/hasdef must cover the whole span")
    return sorted(range(span_size), key=lambda n: (-hasdef[n], -coverage[n], n))


def recall_at_k(order: Sequence[int], gold: set, k: int) -> float:
    if not gold:
        return 0.0
    top_k = set(order[:k])
    return len(top_k & gold) / len(gold)


def mrr(order: Sequence[int], gold: set) -> float:
    for rank, n in enumerate(order, start=1):
        if n in gold:
            return 1.0 / rank
    return 0.0


# ── the verdict rule (pre-reg §4.1/§4.2) ────────────────────────────────────────────────────────────

MARGIN_BAR = 0.02
BOOTSTRAP_SEED = "ripwire-arise-line-rank-v1"
BOOTSTRAP_RESAMPLES = 10_000


@dataclass
class InstanceScores:
    instance_id: str
    r0_at1: float
    r1_at1: float
    r3_at1: float
    ctl_at1: float


def paired_bootstrap_ci(instances: Sequence[InstanceScores], get_a, get_b,
                         seed: str = BOOTSTRAP_SEED, resamples: int = BOOTSTRAP_RESAMPLES):
    n = len(instances)
    if n == 0:
        return 0.0, (0.0, 0.0)
    rng = random.Random(seed)
    point = sum(get_a(i) - get_b(i) for i in instances) / n
    means = []
    for _ in range(resamples):
        sample = [instances[rng.randrange(n)] for _ in range(n)]
        means.append(sum(get_a(i) - get_b(i) for i in sample) / n)
    means.sort()
    lo = means[int(0.025 * resamples)]
    hi = means[min(int(0.975 * resamples), resamples - 1)]
    return point, (lo, hi)


def verdict(instances: Sequence[InstanceScores]) -> dict:
    n = len(instances)
    r3_mean = sum(i.r3_at1 for i in instances) / n if n else 0.0
    r1_mean = sum(i.r1_at1 for i in instances) / n if n else 0.0
    r0_mean = sum(i.r0_at1 for i in instances) / n if n else 0.0
    ctl_mean = sum(i.ctl_at1 for i in instances) / n if n else 0.0

    margin_point, (ci_lo, ci_hi) = paired_bootstrap_ci(instances, lambda i: i.r3_at1, lambda i: i.ctl_at1)
    ci_excludes_zero = ci_lo > 0.0

    clears_margin = margin_point >= MARGIN_BAR
    beats_r1 = r3_mean > r1_mean
    beats_r0 = r3_mean > r0_mean

    passed = clears_margin and ci_excludes_zero and beats_r1 and beats_r0
    return {
        "pass": passed,
        "n_instances": n,
        "r3_at1_mean": r3_mean,
        "r1_at1_mean": r1_mean,
        "r0_at1_mean": r0_mean,
        "ctl_at1_mean": ctl_mean,
        "margin_r3_minus_ctl": margin_point,
        "margin_ci95": [ci_lo, ci_hi],
        "clears_margin_bar": clears_margin,
        "ci_excludes_zero": ci_excludes_zero,
        "beats_r1": beats_r1,
        "beats_r0": beats_r0,
        "bootstrap_seed": BOOTSTRAP_SEED,
        "bootstrap_resamples": BOOTSTRAP_RESAMPLES,
        "margin_bar": MARGIN_BAR,
    }


# ── the one pipeline main() and the self-test both drive (rv-arise-line-ranking.md HIGH-6.2) ──────────

def score(dataset: Sequence[dict], heldout_repos: set, summary: Optional[dict] = None,
          drift_summary: Optional[dict] = None, results: Optional[Sequence[dict]] = None,
          registered_tier_a: dict = REGISTERED_TIER_A) -> dict:
    """The full fingerprint-then-verdict pipeline, in memory. NEVER computes or returns a "pass" on a
    tier mismatch — a mismatch sets verdict=None and stopped_at to which tier failed, which
    exit_code_for() turns into exit 2. main() and the self-test share this one function so the CLI
    entry point cannot silently skip a check the self-test exercises. `registered_tier_a` defaults to
    the module's own REGISTERED_TIER_A; only the self-test ever passes anything else, to prove the
    tier-a stop fires without needing a 560-row synthetic dataset."""
    fp = fingerprint_dataset_only(dataset, heldout_repos)
    ok, mismatches = check_fingerprint(fp, registered_tier_a)
    if not ok:
        return {"fingerprint": fp, "verdict": None, "stopped_at": "tier_a", "mismatches": mismatches}

    drift_disclosed = False
    if summary is not None:
        ok_b, mism_b = check_tier_b(summary)
        ok_c, mism_c = check_tier_c(summary)
        if not (ok_b and ok_c):
            if drift_summary is not None:
                ok_bd, mism_bd = check_tier_b(drift_summary)
                ok_cd, mism_cd = check_tier_c(drift_summary)
                if ok_bd and ok_cd:
                    drift_disclosed = True   # population PASS with disclosed binary drift (pre-reg §1.3)
                else:
                    return {"fingerprint": fp, "verdict": None, "stopped_at": "tier_b_c_drift",
                            "mismatches": mism_b + mism_c, "drift_mismatches": mism_bd + mism_cd}
            else:
                return {"fingerprint": fp, "verdict": None, "stopped_at": "tier_b_c",
                         "mismatches": mism_b + mism_c}

    if results is None:
        return {"fingerprint": fp, "binary_drift_disclosed": drift_disclosed, "verdict": None,
                "stopped_at": None}

    instances = [InstanceScores(r["instance_id"], r["r0_at1"], r["r1_at1"], r["r3_at1"], r["ctl_at1"])
                 for r in results]
    v = verdict(instances)
    return {"fingerprint": fp, "binary_drift_disclosed": drift_disclosed, "verdict": v, "stopped_at": None}


def exit_code_for(result: dict) -> int:
    """0 unless a tier genuinely stopped the run (stopped_at names one) — "checks passed, nothing to
    score because --results was not given" is stopped_at=None and exits 0, not a failure."""
    return 2 if result.get("stopped_at") else 0


# ── self-test: synthetic rows only (plus the committed --heldout default, not corpus content) ─────────

# A real-shaped unified-diff hunk (one deleted line and one insertion run), hand-verified to gold=[12]
# by walking gold_pre_lines() by hand: context lines 10,11 advance pre_ln to 12 at the '-' line; the '+'
# run's anchor is pre_ln-1=12, already in `deleted`, so gold = {12} exactly.
REAL_SHAPED_PATCH = """diff --git a/pkg/mod.py b/pkg/mod.py
index e69de29..4b825dc 100644
--- a/pkg/mod.py
+++ b/pkg/mod.py
@@ -10,4 +10,5 @@
 def compute(a, b):
     total = a + b
-    scale = 2
+    scale = 3
+    extra = 1
     return total * scale
"""


def _self_test() -> int:
    passes = 0
    failures = 0

    def check(label: str, ok: bool, detail: str = ""):
        nonlocal passes, failures
        tag = "PASS" if ok else "FAIL"
        print(f"  {tag}  {label}" + (f" — {detail}" if not ok and detail else ""))
        if ok:
            passes += 1
        else:
            failures += 1

    # -- gold_pre_lines / file_sections on a REAL-SHAPED patch (HIGH-6.1's own ask) -------------------
    secs = file_sections(REAL_SHAPED_PATCH)
    check("file_sections finds exactly one path: pkg/mod.py", list(secs.keys()) == ["pkg/mod.py"],
          f"got {list(secs.keys())}")
    gold, deleted, anchors = gold_pre_lines(secs["pkg/mod.py"])
    check("gold_pre_lines on the real-shaped hunk: gold=[12] (one deleted line, its own anchor)",
          gold == [12], f"got gold={gold} deleted={deleted} anchors={anchors}")

    row_with_real_patch = {"edit_functions": ["pkg/mod.py:compute"], "patch": REAL_SHAPED_PATCH}
    check("row_gold_line_count on the real-shaped row: 1",
          row_gold_line_count(row_with_real_patch) == 1,
          f"got {row_gold_line_count(row_with_real_patch)}")

    # -- fingerprint_dataset_only computes REAL gold-line counts, not a nonexistent field ------------
    heldout = {"repoA", "repoB"}
    dataset = [
        {"repo": "repoA", "edit_functions": ["pkg/mod.py:compute"], "patch": REAL_SHAPED_PATCH},   # carried, 1 gold line
        {"repo": "repoB", "edit_functions": ["pkg/mod.py:compute"], "patch": REAL_SHAPED_PATCH},   # carried, 1 gold line
        {"repo": "repoC", "edit_functions": ["pkg/mod.py:compute"], "patch": REAL_SHAPED_PATCH},   # not held out
        {"repo": "repoA", "edit_functions": ["a:f", "b:g"], "patch": REAL_SHAPED_PATCH},            # multi-function
    ]
    fp = fingerprint_dataset_only(dataset, heldout)
    check("fingerprint_dataset_only: dataset=4", fp["dataset"] == 4)
    check("fingerprint_dataset_only: multi_function=1", fp["multi_function"] == 1)
    check("fingerprint_dataset_only: single_function=3", fp["single_function"] == 3)
    check("fingerprint_dataset_only: carried=2 (single-function AND held-out)", fp["carried"] == 2)
    check("fingerprint_dataset_only: carried_gold_lines=2 (real patch parsing, not a fake field)",
          fp["carried_gold_lines"] == 2, f"got {fp['carried_gold_lines']}")

    ok, mism = check_fingerprint(fp, {"dataset": 4, "carried": 2})
    check("check_fingerprint: matching expectations pass", ok, "; ".join(mism))
    ok2, mism2 = check_fingerprint(fp, {"dataset": 4, "carried": 99})
    check("check_fingerprint: a wrong expectation is caught, not silently accepted",
          (not ok2) and len(mism2) == 1)

    # -- HIGH-6.2: score() genuinely STOPS on a tier-a mismatch, verdict=None, exit 2 -----------------
    empty_result = score([], set())
    check("score() on a 0-row population: verdict is None, not a silent pass",
          empty_result["verdict"] is None, json.dumps(empty_result))
    check("score() on a 0-row population: stopped_at='tier_a'",
          empty_result["stopped_at"] == "tier_a", json.dumps(empty_result))
    check("exit_code_for(): a tier_a stop is exit 2", exit_code_for(empty_result) == 2)

    mismatched_result = score(dataset, heldout)   # 4-row synthetic dataset != the REGISTERED 560/etc
    check("score() against the REGISTERED constants (the real default) on a non-matching dataset also"
          " stops at tier_a",
          mismatched_result["verdict"] is None and mismatched_result["stopped_at"] == "tier_a")

    # -- tier (b)/(c): a matching summary, a drifted one, and a drift-summary rescue ------------------
    good_summary = {
        "scored_instances": 173, "var_instances": 498,
        "skips": {"selector_refused_plain": 3, "selector_refused_scoped": 2,
                  "expand_no_body": 2, "gold_outside_span": 2},
        "recall_at_k": {"r0": {"1": 0.029}, "ctl": {"1": 0.042}, "r1": {"1": 0.048}, "r2": {"1": 0.048}},
        "mrr": {"r0": 0.154, "ctl": 0.234, "r1": 0.289, "r2": 0.289},
    }
    okb, mismb = check_tier_b(good_summary)
    check("check_tier_b: a matching summary passes", okb, "; ".join(mismb))
    okc, mismc = check_tier_c(good_summary)
    check("check_tier_c: a matching summary passes (within tolerance)", okc, "; ".join(mismc))

    drifted_summary = dict(good_summary)
    drifted_summary["recall_at_k"] = dict(good_summary["recall_at_k"])
    drifted_summary["recall_at_k"]["r1"] = {"1": 0.060}   # moved well outside tolerance
    okc2, mismc2 = check_tier_c(drifted_summary)
    check("check_tier_c: a drifted r1@1 is caught (outside +-0.0005+1e-9)", not okc2 and len(mismc2) == 1)

    # -- score() end-to-end, tier_a bypassed via an explicit `registered_tier_a` stand-in (the only
    #    caller ever allowed to do this — main() never passes anything but the module default) --------
    stand_in_registered = {
        "dataset": 4, "multi_function": 1, "single_function": 3, "carried": 2, "carried_gold_lines": 2,
    }
    results = [{"instance_id": "i0", "r0_at1": 0.0, "r1_at1": 0.0, "r3_at1": 1.0, "ctl_at1": 0.0}]

    end_to_end = score(dataset, heldout, summary=good_summary, results=results,
                        registered_tier_a=stand_in_registered)
    check("score(): tier_a + tier_b/c pass + results given -> a real verdict, not None",
          end_to_end["verdict"] is not None and end_to_end["stopped_at"] is None, json.dumps(end_to_end))
    check("exit_code_for(): a real verdict (tiers passed) is exit 0", exit_code_for(end_to_end) == 0)

    end_to_end_bad_summary = score(dataset, heldout, summary=drifted_summary, results=results,
                                    registered_tier_a=stand_in_registered)
    check("score(): tier_a passes but tier_c fails with no drift-summary -> stop, no verdict",
          end_to_end_bad_summary["verdict"] is None and end_to_end_bad_summary["stopped_at"] == "tier_b_c",
          json.dumps(end_to_end_bad_summary))
    check("exit_code_for(): a tier_b_c stop is exit 2", exit_code_for(end_to_end_bad_summary) == 2)

    end_to_end_drift_rescue = score(dataset, heldout, summary=drifted_summary, drift_summary=good_summary,
                                     results=results, registered_tier_a=stand_in_registered)
    check("score(): tier_c fails on the CURRENT summary but the drift-summary (old binary) matches ->"
          " population PASS with disclosed binary drift, a real verdict is still computed",
          end_to_end_drift_rescue["verdict"] is not None
          and end_to_end_drift_rescue["binary_drift_disclosed"] is True, json.dumps(end_to_end_drift_rescue))

    end_to_end_drift_fails_too = score(dataset, heldout, summary=drifted_summary,
                                        drift_summary=drifted_summary, results=results,
                                        registered_tier_a=stand_in_registered)
    check("score(): tier_c fails on BOTH the current and the drift summary -> genuine population FAIL,"
          " no verdict",
          end_to_end_drift_fails_too["verdict"] is None
          and end_to_end_drift_fails_too["stopped_at"] == "tier_b_c_drift", json.dumps(end_to_end_drift_fails_too))

    # -- r3_order / recall_at_k / mrr — unchanged from round 1, re-verified -------------------------
    order = r3_order(3, coverage=[3, 2, 1], hasdef=[0, 1, 1])
    check("r3_order matches the C++ unit test's hand-verified fixture: [1,2,0]", order == [1, 2, 0],
          f"got {order}")
    check("recall_at_k([1,2,0], {1}, k=1) == 1.0", recall_at_k([1, 2, 0], {1}, 1) == 1.0)
    check("mrr([1,2,0], {0}) == 1/3", abs(mrr([1, 2, 0], {0}) - (1 / 3)) < 1e-12)

    # -- verdict(): engineered PASS / FAIL, deterministic CI ------------------------------------------
    pass_instances = [
        InstanceScores(f"i{n}", r0_at1=0.0, r1_at1=0.0, r3_at1=1.0, ctl_at1=0.0) for n in range(200)
    ]
    v_pass = verdict(pass_instances)
    check("verdict: an engineered dataset where R3=1.0 always and everything else=0.0 PASSes",
          v_pass["pass"] is True, json.dumps(v_pass))
    fail_instances = [
        InstanceScores(f"i{n}", r0_at1=0.05, r1_at1=0.05, r3_at1=0.05, ctl_at1=0.05) for n in range(200)
    ]
    v_fail = verdict(fail_instances)
    check("verdict: R3 identical to CTL/R1/R0 on every instance FAILs (margin=0, not >= 0.02)",
          (v_fail["pass"] is False) and (v_fail["clears_margin_bar"] is False), json.dumps(v_fail))
    check("verdict: the bootstrap CI is deterministic (fixed seed, same instances, run twice)",
          v_pass["margin_ci95"] == verdict(pass_instances)["margin_ci95"])

    # -- load_heldout_repos against the REAL committed default file (not corpus content: repo names
    #    and coarse stats from an unrelated, already-public measurement round) -----------------------
    default_path = Path(__file__).resolve().parents[2] / DEFAULT_HELDOUT
    if default_path.is_file():
        repos = load_heldout_repos(default_path)
        check(f"load_heldout_repos({DEFAULT_HELDOUT}): exactly 88 distinct repos",
              len(repos) == 88, f"got {len(repos)}")
    else:
        check(f"load_heldout_repos: {DEFAULT_HELDOUT} not found relative to the repo root "
              f"(skipping — a missing committed file would be caught by other gates)", True)

    print(f"score_arise_linerank self-test: {passes} pass, {failures} fail")
    return 0 if failures == 0 else 1


def main() -> int:
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--self-test", action="store_true",
                     help="run the synthetic-rows self-test only (no corpus content touched)")
    ap.add_argument("--dataset", help="LocBench-shaped dataset JSON (not read unless given)")
    ap.add_argument("--heldout", default=DEFAULT_HELDOUT,
                     help=f"held-out repo list (default: the committed {DEFAULT_HELDOUT})")
    ap.add_argument("--summary", help="results-summary.json (tiers b/c)")
    ap.add_argument("--drift-summary", help="the same shape, scored under the original 755f9026f binary")
    ap.add_argument("--results", help="a real per-instance results.json (r0/r1/r3/ctl @1 per instance)")
    ap.add_argument("--verdict-out", help="where to write the verdict JSON")
    args = ap.parse_args()

    if args.self_test or not args.dataset:
        if not args.self_test:
            print("no --dataset given; running --self-test instead "
                  "(this script never reads a real corpus on its own)", file=sys.stderr)
        return _self_test()

    with open(args.dataset, encoding="utf-8") as f:
        dataset = json.load(f)
    heldout = load_heldout_repos(args.heldout)
    summary = None
    if args.summary:
        with open(args.summary, encoding="utf-8") as f:
            summary = json.load(f)
    drift_summary = None
    if args.drift_summary:
        with open(args.drift_summary, encoding="utf-8") as f:
            drift_summary = json.load(f)
    results = None
    if args.results:
        with open(args.results, encoding="utf-8") as f:
            results = json.load(f)

    result = score(dataset, heldout, summary, drift_summary, results)
    print(f"fingerprint (dataset-only): {json.dumps(result['fingerprint'])}", file=sys.stderr)
    text = json.dumps(result, indent=2)
    if args.verdict_out:
        with open(args.verdict_out, "w", encoding="utf-8") as f:
            f.write(text)
    else:
        print(text)
    return exit_code_for(result)


if __name__ == "__main__":
    raise SystemExit(main())
