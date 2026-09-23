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

SELF-TEST ONLY on this machine. The LocBench corpus is not here and this script never reads or fetches
it (docs/research/arise-line-ranking-prereg.md §1; the standing machine rule against fetching third-party
data from a lane). `--self-test` builds small synthetic datasets in-process and checks this module's own
logic against hand-verified answers — it is a unit test for the SCORER, not a scoring run. The --dataset/
--heldout/--results path exists for a FUTURE round that has the real corpus; running it is not something
this lane does.

Usage:
    python3 bench/slice/score_arise_linerank.py --self-test

    # once the corpus, a held-out repo list and a real per-instance results.json exist elsewhere
    # (a future round, not this lane):
    python3 bench/slice/score_arise_linerank.py --dataset DATASET.json --heldout HELDOUT.json \
        --results RESULTS.json --verdict-out VERDICT.json
"""
from __future__ import annotations

import argparse
import json
import random
import sys
from dataclasses import dataclass
from typing import Sequence


# ── population fingerprint (docs/research/arise-line-ranking-prereg.md §1) ─────────────────────────────
# "Fingerprint the CARRIED set, not the disk cascade" (rv-arise-line-ranking.md HIGH-1): the construction
# rule is dataset-only and needs no binary, no checkout: single-function rows (edit_functions length 1)
# whose repo is one of the held-out directories. Predicted on the real LocBench V1 test-560: 182 rows /
# 1,040 gold lines — that number is NOT hardcoded here; it is what §1's `expected=` argument states when
# a real run checks it, kept out of this module so a dataset drift cannot silently pass by matching a
# stale constant.

def carried_rows(dataset: Sequence[dict], heldout_repos: set) -> list:
    """Every row whose edit_functions has length 1 (single-function) AND whose repo is one of the
    held-out directories — the pre-registered construction rule, verbatim."""
    out = []
    for row in dataset:
        efs = row.get("edit_functions") or []
        if len(efs) == 1 and row.get("repo") in heldout_repos:
            out.append(row)
    return out


def fingerprint_dataset_only(dataset: Sequence[dict], heldout_repos: set) -> dict:
    """Dataset-only cascade counts — the tier that gates (LOW-2's grouping): dataset / multi-function /
    single-function / carried / carried_gold_lines. The disk-state counts ("no local checkout",
    "base_commit absent") are deliberately NOT part of this fingerprint — they are properties of a
    PARTICULAR machine's checkout, not of the population (HIGH-1's own finding: two different disk
    states, 169/1 and 170/0, both carry the identical 182 rows)."""
    multi = [r for r in dataset if len(r.get("edit_functions") or []) > 1]
    single = [r for r in dataset if len(r.get("edit_functions") or []) == 1]
    carried = carried_rows(dataset, heldout_repos)
    gold_lines = sum(len(r.get("gold_lines") or []) for r in carried)
    return {
        "dataset": len(dataset),
        "multi_function": len(multi),
        "single_function": len(single),
        "carried": len(carried),
        "carried_gold_lines": gold_lines,
    }


def check_fingerprint(dataset_only: dict, expected: dict) -> tuple:
    """Exact integer match — no tolerance, these are counts. Pre-reg §1: 'If any one does not
    reproduce ... the run stops there.' Returns (ok, list-of-mismatch-strings)."""
    mismatches = []
    for key, want in expected.items():
        got = dataset_only.get(key)
        if got != want:
            mismatches.append(f"{key}: got {got}, want {want}")
    return (len(mismatches) == 0, mismatches)


# ── the R3 rule itself (pre-reg §3.1, "def-primacy") ────────────────────────────────────────────────

def r3_order(span_size: int, coverage: Sequence[int], hasdef: Sequence[int]) -> list:
    """r3 = sorted(span, key=lambda n: (-hasdef[n], -cover[n], n)) — zero fitted parameters, a pure
    integer lexicographic sort (no float score, no epsilon tie-break; CONTRIBUTING.md "a sort has no
    tolerance band"). `n` ranges over line indices [0, span_size)."""
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


# ── the verdict rule (pre-reg §4, corrected per rv-arise-line-ranking.md HIGH-3) ───────────────────────

MARGIN_BAR = 0.02           # ONE bar (a first draft of the pre-reg doc stated both 0.018 and 0.02 in the
                             # same sentence — HIGH-3 caught the ambiguity; this is the only number that
                             # survives, 3x R1's own +0.006 margin over chance, "no effect worth naming")
BOOTSTRAP_SEED = "ripwire-arise-line-rank-v1"
BOOTSTRAP_RESAMPLES = 10_000


@dataclass
class InstanceScores:
    """Per-instance @1 recall for each arm, ONE number per instance — matching
    run_slice_linerecall.py's rank_scores(), which computes Recall@k once per instance over that
    instance's own gold set, not once per (instance, variable) pair (HIGH-3's bootstrap-unit fix: the
    498 pairs exist only for the separate §R2 set-recall metric and have nothing to pool here)."""
    instance_id: str
    r0_at1: float
    r1_at1: float
    r3_at1: float
    ctl_at1: float   # that instance's own 200-shuffle mean, as the harness already stores it


def paired_bootstrap_ci(instances: Sequence[InstanceScores], get_a, get_b,
                         seed: str = BOOTSTRAP_SEED, resamples: int = BOOTSTRAP_RESAMPLES):
    """Percentile 95% CI (2.5th/97.5th percentile) of the mean of get_a(inst) - get_b(inst) over
    resampled INSTANCES (with replacement, len(instances) draws per resample) — a PAIRED bootstrap,
    since get_a and get_b are read from the SAME resampled instance each time. random.Random(seed),
    a fixed resample count. Returns (point_estimate, (ci_lo, ci_hi))."""
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
    """PASS iff (R3-CTL >= MARGIN_BAR) AND (the CI excludes 0 on the positive side) AND (R3 > R1) AND
    (R3 > R0) — all four, exactly as pre-reg §4 states. Note (pre-reg §4, Attack 3 of the review):
    given the fingerprinted CTL=0.042/R1=0.048/R0=0.029, clearing the margin bar already implies R3 >
    R1 and R3 > R0 — conditions 3-4 are checked explicitly anyway rather than assumed, so the rule does
    not silently depend on the fingerprint holding to the last digit.

    POWER, disclosed rather than hidden (HIGH-3): at n=173 with 0/1-valued-ish per-instance recall,
    the standard error of a mean difference is large enough that a true +0.02 effect can fail the
    CI-excludes-zero clause roughly half the time. A FAIL under this rule reads as "did not clear the
    bar" at this sample size — never as proof the underlying rule does not help."""
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


# ── self-test: synthetic rows only, no corpus read ──────────────────────────────────────────────────

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

    # -- fingerprint: a tiny synthetic dataset with a known carried population ---------------------
    heldout = {"repoA", "repoB"}
    dataset = [
        {"repo": "repoA", "edit_functions": ["f1"], "gold_lines": [1, 2]},          # carried
        {"repo": "repoB", "edit_functions": ["f2"], "gold_lines": [3]},             # carried
        {"repo": "repoC", "edit_functions": ["f3"], "gold_lines": [4]},             # not held out
        {"repo": "repoA", "edit_functions": ["f1", "f4"], "gold_lines": [5, 6]},    # multi-function
    ]
    fp = fingerprint_dataset_only(dataset, heldout)
    check("fingerprint_dataset_only: dataset=4", fp["dataset"] == 4)
    check("fingerprint_dataset_only: multi_function=1", fp["multi_function"] == 1)
    check("fingerprint_dataset_only: single_function=3", fp["single_function"] == 3)
    check("fingerprint_dataset_only: carried=2 (single-function AND held-out)", fp["carried"] == 2)
    check("fingerprint_dataset_only: carried_gold_lines=3", fp["carried_gold_lines"] == 3)

    ok, mism = check_fingerprint(fp, {"dataset": 4, "carried": 2})
    check("check_fingerprint: matching expectations pass", ok, "; ".join(mism))
    ok2, mism2 = check_fingerprint(fp, {"dataset": 4, "carried": 99})
    check("check_fingerprint: a wrong expectation is caught, not silently accepted",
          (not ok2) and len(mism2) == 1)

    # -- r3_order: the hand-verified fixture from test/slicerank_unit.cpp item (2) -- three lines,
    #    coverage [3,2,1], hasdef [0,1,1] (0-indexed lines standing in for source lines 10,11,12) --
    #    expect order [1,2,0] (the C++ unit test's own "11,12,10").
    order = r3_order(3, coverage=[3, 2, 1], hasdef=[0, 1, 1])
    check("r3_order matches the C++ unit test's hand-verified fixture: [1,2,0]", order == [1, 2, 0],
          f"got {order}")

    order_r1_equiv = r3_order(3, coverage=[3, 2, 1], hasdef=[0, 0, 0])
    check("r3_order with hasdef all-zero reduces to coverage-descending (R1's own order)",
          order_r1_equiv == [0, 1, 2], f"got {order_r1_equiv}")

    # -- recall_at_k / mrr on a known order/gold pair --------------------------------------------
    check("recall_at_k([1,2,0], {1}, k=1) == 1.0", recall_at_k([1, 2, 0], {1}, 1) == 1.0)
    check("recall_at_k([1,2,0], {0}, k=1) == 0.0", recall_at_k([1, 2, 0], {0}, 1) == 0.0)
    check("mrr([1,2,0], {0}) == 1/3", abs(mrr([1, 2, 0], {0}) - (1 / 3)) < 1e-12)

    # -- verdict: an engineered PASS case (R3 clearly beats CTL/R1/R0 on every instance) -----------
    pass_instances = [
        InstanceScores(f"i{n}", r0_at1=0.0, r1_at1=0.0, r3_at1=1.0, ctl_at1=0.0) for n in range(200)
    ]
    v_pass = verdict(pass_instances)
    check("verdict: an engineered dataset where R3=1.0 always and everything else=0.0 PASSes",
          v_pass["pass"] is True, json.dumps(v_pass))

    # -- verdict: an engineered FAIL case (R3 identical to CTL/R1/R0 -- zero true margin) -----------
    fail_instances = [
        InstanceScores(f"i{n}", r0_at1=0.05, r1_at1=0.05, r3_at1=0.05, ctl_at1=0.05) for n in range(200)
    ]
    v_fail = verdict(fail_instances)
    check("verdict: R3 identical to CTL/R1/R0 on every instance FAILs (margin=0, not >= 0.02)",
          (v_fail["pass"] is False) and (v_fail["clears_margin_bar"] is False), json.dumps(v_fail))

    # -- verdict: deterministic given the fixed seed (same instances -> same CI twice) --------------
    v_pass_2 = verdict(pass_instances)
    check("verdict: the bootstrap CI is deterministic (fixed seed, same instances, run twice)",
          v_pass["margin_ci95"] == v_pass_2["margin_ci95"])

    # -- power note demo (HIGH-3): a realistic MARGINAL true effect at n=173 exercises the same code
    #    path without crashing, whichever way the coin lands -- the point is that a FAIL here is not
    #    proof of "no effect", which is why §4 states the power explicitly rather than only in this
    #    script's comment.
    rng = random.Random("power-demo")
    marginal_instances = [
        InstanceScores(f"i{n}", r0_at1=0.0, r1_at1=0.0,
                        r3_at1=1.0 if rng.random() < 0.05 else 0.0,
                        ctl_at1=1.0 if rng.random() < 0.03 else 0.0)
        for n in range(173)
    ]
    v_marginal = verdict(marginal_instances)
    check("verdict: a marginal-effect synthetic dataset at n=173 produces a coherent verdict (no crash)",
          isinstance(v_marginal["pass"], bool), json.dumps(v_marginal))

    print(f"score_arise_linerank self-test: {passes} pass, {failures} fail")
    return 0 if failures == 0 else 1


def main() -> int:
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--self-test", action="store_true",
                     help="run the synthetic-rows self-test only (no dataset/results files touched)")
    ap.add_argument("--dataset", help="LocBench-shaped dataset JSON (not read unless given)")
    ap.add_argument("--heldout", help="JSON list of held-out repo names")
    ap.add_argument("--results", help="a real per-instance results.json (r0/r1/r3/ctl @1 per instance)")
    ap.add_argument("--verdict-out", help="where to write the verdict JSON")
    args = ap.parse_args()

    if args.self_test or not (args.dataset and args.heldout and args.results):
        if not args.self_test:
            print("no --dataset/--heldout/--results given; running --self-test instead "
                  "(this script never reads a real corpus on its own)", file=sys.stderr)
        return _self_test()

    with open(args.dataset, encoding="utf-8") as f:
        dataset = json.load(f)
    with open(args.heldout, encoding="utf-8") as f:
        heldout = set(json.load(f))
    with open(args.results, encoding="utf-8") as f:
        results = json.load(f)

    fp = fingerprint_dataset_only(dataset, heldout)
    print(f"fingerprint (dataset-only): {json.dumps(fp)}", file=sys.stderr)

    instances = [
        InstanceScores(r["instance_id"], r["r0_at1"], r["r1_at1"], r["r3_at1"], r["ctl_at1"])
        for r in results
    ]
    v = verdict(instances)
    out = {"fingerprint": fp, "verdict": v}
    text = json.dumps(out, indent=2)
    if args.verdict_out:
        with open(args.verdict_out, "w", encoding="utf-8") as f:
            f.write(text)
    else:
        print(text)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
