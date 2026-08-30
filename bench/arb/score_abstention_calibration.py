#!/usr/bin/env python3
"""score_abstention_calibration.py — scores the abstention-calibration round registered in
docs/EVALS.md ("Agent Retrieval Bench — abstention calibration round, PRE-REGISTERED 2026-08-29").

WHY THIS EXISTS. run_arb.py's sweep()/sweep_selective() now record confidence= and margin_pct=
(the two facts --for --json ships, per deriveForConfidence in src/main.cpp) on every per-sample
details row. This script is the SEPARATE scoring pass over those already-written details files —
kept apart from run_arb.py because composing rankings and grading a calibration are different
concerns, and because this script must run AFTER a sweep, never invoke the binary itself.

THE RULE UNDER TEST (verbatim from the registration, not re-derived here):
  predicted_abstain = (confidence == "low")                                   # the DOP
  score = 0.0                        if confidence == "low"
        = 1.0 + margin_pct / 100.0   if confidence == "high"
Positive class for this evaluation is "should abstain": label=="no_gold" (selective splits) or
no_gold==True (the plain abstention task). AUROC is computed over `score` via the rank-based
Mann-Whitney identity (ties get the average rank) — never a re-derivation of confidence itself,
since a single binary feature gives one ROC point, not a curve.

BANDS (from the registration, restated here so a reader does not have to cross-reference to see
what "meets"/"does not meet" means):
  AUROC:            >= 0.65 meets, [0.55,0.65) weak, < 0.55 does not meet
  DOP safety:       false_abstain_rate <= 0.10 AND recall >= 0.20 -> DOP meets floor
  best-F1 threshold: F1 >= 0.35 meets, else does not meet

ROUND TWO (docs/EVALS.md, "Agent Retrieval Bench — abstention round 2: the adaptive cut's
corpus-support facts", PRE-REGISTERED 2026-08-30) runs in the same pass, over the three counts the
binary began emitting for it: kept / scored / corpus, none of which reached any surface when round
one ran. Its PRIMARY is support = scored/corpus with abstain_score = 1 - support; its three
secondaries are reported and decide nothing; its bands are round one's, plus a directional-refutation
band (AUROC <= 0.35 means the signal separates the OPPOSITE way and is NOT a pass). Round-two metric
lines carry an `r2_` prefix, and the behavior-licensing verdict is the AND over BOTH selective splits.

Datasets (details files, produced by run_arb.py --task=abstention and --split=...):
  abstention                    — single-class (all no_gold); recall only, no AUROC/false-abstain
  selective_retrieval_balanced  — full confusion + AUROC + sweep (primary, near-balanced)
  selective_retrieval_natural   — full confusion + AUROC + sweep (secondary, realistic prior)

Output: ARB\tcalib\t<dataset>\t<metric>\t<value> lines on stdout (greppable, same convention as
run_arb.py), plus a summary JSON written to <data>/runs/abstention_calibration_summary.json.
Per the improve-first house rule, this script's OWN output is the local record; nothing here is
published in docs/EVALS.md or README until a fix round re-measures.

Usage:
  python3 bench/arb/score_abstention_calibration.py [--data DIR] [--datasets D1,D2,...]
"""

import argparse
import json
import os
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
REPO = os.path.dirname(os.path.dirname(HERE))

DATASETS = ("abstention", "selective_retrieval_balanced", "selective_retrieval_natural")

AUROC_MEETS, AUROC_WEAK = 0.65, 0.55
DOP_FALSE_ABSTAIN_MAX, DOP_RECALL_MIN = 0.10, 0.20
BEST_F1_MEETS = 0.35


def load_rows(data_dir, dataset):
    path = os.path.join(data_dir, "runs", "%s_details.jsonl" % dataset)
    if not os.path.isfile(path):
        return None
    rows = []
    with open(path, encoding="utf-8") as fh:
        for line in fh:
            line = line.strip()
            if line:
                rows.append(json.loads(line))
    return rows


def row_label(dataset, row):
    """True iff this row's ground truth is 'should abstain' (no gold to retrieve)."""
    if dataset == "abstention":
        return bool(row.get("no_gold"))
    return row.get("selective_label") == "no_gold"


def row_score(row):
    """None (signal_missing) | float, per the registered combined-score rule."""
    confidence = row.get("confidence")
    if confidence == "low":
        return 0.0
    if confidence == "high":
        margin = row.get("margin_pct") or 0
        return 1.0 + margin / 100.0
    return None


# ─────────────────────────────────────────────────────────────────────────────────────────────────
# ROUND TWO — the adaptive cut's corpus-support facts (docs/EVALS.md, "Agent Retrieval Bench —
# abstention round 2: the adaptive cut's corpus-support facts", PRE-REGISTERED 2026-08-30).
#
# Round one is a recorded NEGATIVE: confidence=/margin_pct= separate at chance. Round two tests a
# DIFFERENT signal drawn from the same statistic — not the ranking's SHAPE but the query's GRIP on
# the corpus. The three counts it reads (kept / scored / corpus) reached no output surface at all
# when round one ran, which is precisely why round one could not test them.
#
# The registered PRIMARY, verbatim, and the only thing that decides a band:
#     support(sample)       = scored / corpus            # in [0, 1]
#     abstain_score(sample) = 1.0 - support              # higher = more likely unanswerable
# The DIRECTION is registered too: the hypothesis is that an unanswerable query has THINNER corpus
# support. An AUROC <= 0.35 therefore means the signal separates the OPPOSITE way; that is recorded
# as a refutation of the direction and NOT as a pass, and acting on it would need its own later
# registration.
#
# The SECONDARIES are reported and decide nothing. Naming them secondary in the registration, before
# any row was read, is the guard against picking the best of four out of the finished table
# afterwards and calling it the hypothesis.

DIRECTIONAL_REFUTATION = 0.35


def row_counts(row):
    """The three round-two counts as ints, or None if ANY of them is absent or not an integer — a
    details file written before the instrumentation existed, or a failed invocation. One guard for
    all four scorers below: each of them needs the same "did the binary actually emit this" answer,
    and four private copies of it is how one scorer ends up silently coercing a missing count to 0
    while its neighbours drop the row."""
    kept, scored, corpus = row.get("kept"), row.get("scored"), row.get("corpus")
    triple = (kept, scored, corpus)
    if any(not isinstance(v, int) or isinstance(v, bool) for v in triple):
        return None
    return triple


def row_support(row):
    """None (signal_missing) | float in [0,1]: the fraction of the scored corpus this query's terms
    reach at all. None also when corpus is 0 — 0/0 measures nothing."""
    counts = row_counts(row)
    if counts is None or counts[2] <= 0:
        return None
    return counts[1] / counts[2]


def row_abstain_support(row):
    """The registered PRIMARY abstain score: monotone DECREASING in support, exactly as registered."""
    support = row_support(row)
    return None if support is None else 1.0 - support


def row_abstain_scored_raw(row):
    """SECONDARY (a): raw `scored`, unnormalized, negated so its direction matches the primary's.
    Reported to show how much of any separation is repo SIZE rather than query grip — which is the
    whole reason the primary carries a denominator."""
    counts = row_counts(row)
    return None if counts is None else -float(counts[1])


def row_abstain_headshare(row):
    """SECONDARY (b): the served head's share of everything that matched, kept/scored, negated for
    the same direction. Stated rather than left to a division guard: when nothing matched
    (scored == 0) this maps to the TOP of the range, because under the primary's own logic a query
    that grips nothing is maximal abstain evidence."""
    counts = row_counts(row)
    if counts is None:
        return None
    return 0.0 if counts[1] <= 0 else -(counts[0] / counts[1])


def row_abstain_joint(row):
    """SECONDARY (c): the joint rule `abstain iff confidence == "low" AND support < theta`, as a
    score. Only a "low" row can be abstained on under that rule, so a "high" row is pinned below
    every "low" one instead of competing on support it is not eligible to be judged by."""
    support = row_support(row)
    if support is None or row.get("confidence") not in ("high", "low"):
        return None
    return (1.0 - support) if row.get("confidence") == "low" else -1.0


# name -> (scorer, is_primary). Order is the report order; only the primary decides a band.
ROUND2_SIGNALS = (
    ("support", row_abstain_support, True),
    ("scored_raw", row_abstain_scored_raw, False),
    ("head_share", row_abstain_headshare, False),
    ("joint_low_and_support", row_abstain_joint, False),
)


def confusion(labels, scores, threshold):
    """abstain iff score <= threshold. labels/scores are parallel lists, signal_missing excluded
    by the caller before this is invoked."""
    tp = fn = fp = tn = 0
    for y, s in zip(labels, scores):
        predicted_abstain = s <= threshold
        if y and predicted_abstain:
            tp += 1
        elif y and not predicted_abstain:
            fn += 1
        elif not y and predicted_abstain:
            fp += 1
        else:
            tn += 1
    return tp, fn, fp, tn


def prf(tp, fn, fp, tn):
    recall = tp / (tp + fn) if (tp + fn) else None
    false_abstain_rate = fp / (fp + tn) if (fp + tn) else None
    precision = tp / (tp + fp) if (tp + fp) else None
    f1 = (2 * precision * recall / (precision + recall)
          if precision is not None and recall is not None and (precision + recall) > 0 else 0.0)
    return {"recall": recall, "false_abstain_rate": false_abstain_rate, "precision": precision, "f1": f1,
            "tp": tp, "fn": fn, "fp": fp, "tn": tn}


def auroc(labels, scores):
    """Rank-based Mann-Whitney AUROC, ties averaged. Requires both classes present."""
    n_pos = sum(1 for y in labels if y)
    n_neg = len(labels) - n_pos
    if n_pos == 0 or n_neg == 0:
        return None
    order = sorted(range(len(scores)), key=lambda i: scores[i])
    ranks = [0.0] * len(scores)
    i = 0
    while i < len(order):
        j = i
        while j + 1 < len(order) and scores[order[j + 1]] == scores[order[i]]:
            j += 1
        avg_rank = (i + 1 + j + 1) / 2.0  # 1-based, average over the tied block
        for k in range(i, j + 1):
            ranks[order[k]] = avg_rank
        i = j + 1
    rank_sum_pos = sum(r for r, y in zip(ranks, labels) if y)
    return (rank_sum_pos - n_pos * (n_pos + 1) / 2.0) / (n_pos * n_neg)


def sweep_thresholds(labels, scores):
    """Every distinct score value as a candidate threshold; returns the best-F1 candidate
    (ties broken toward the SMALLER threshold — the more conservative, less-abstaining choice)
    plus the full per-threshold table."""
    table = []
    for c in sorted(set(scores)):
        stats = prf(*confusion(labels, scores, c))
        table.append({"threshold": c, **stats})
    best = max(table, key=lambda row: (row["f1"], -row["threshold"])) if table else None
    return best, table


def score_dataset(data_dir, dataset):
    rows = load_rows(data_dir, dataset)
    if rows is None:
        print("ARB\tcalib\t%s\tstatus\tMISSING (run run_arb.py --task=%s or --split=%s first)" %
              (dataset, dataset, dataset))
        return None

    scored_rows = [r for r in rows if "skipped" not in r]
    signal_missing = sum(1 for r in scored_rows if row_score(r) is None)
    usable = [(row_label(dataset, r), row_score(r)) for r in scored_rows if row_score(r) is not None]
    labels = [y for y, _ in usable]
    scores = [s for _, s in usable]
    n_pos = sum(1 for y in labels if y)
    n_neg = len(labels) - n_pos

    print("ARB\tcalib\t%s\trows\t%d" % (dataset, len(rows)))
    print("ARB\tcalib\t%s\tskipped_snapshots\t%d" % (dataset, len(rows) - len(scored_rows)))
    print("ARB\tcalib\t%s\tsignal_missing\t%d" % (dataset, signal_missing))
    print("ARB\tcalib\t%s\tno_gold\t%d" % (dataset, n_pos))
    print("ARB\tcalib\t%s\tpositive\t%d" % (dataset, n_neg))

    summary = {"dataset": dataset, "rows": len(rows), "skipped_snapshots": len(rows) - len(scored_rows),
               "signal_missing": signal_missing, "no_gold": n_pos, "positive": n_neg}

    dop = prf(*confusion(labels, scores, 0.0))
    summary["dop"] = dop
    print("ARB\tcalib\t%s\tdop_recall\t%s" % (dataset, "%.4f" % dop["recall"] if dop["recall"] is not None else "n/a"))
    if n_neg > 0:
        print("ARB\tcalib\t%s\tdop_false_abstain_rate\t%.4f" % (dataset, dop["false_abstain_rate"]))
        print("ARB\tcalib\t%s\tdop_precision\t%s" %
              (dataset, "%.4f" % dop["precision"] if dop["precision"] is not None else "n/a"))
        print("ARB\tcalib\t%s\tdop_f1\t%.4f" % (dataset, dop["f1"]))
        dop_meets = (dop["false_abstain_rate"] is not None and dop["false_abstain_rate"] <= DOP_FALSE_ABSTAIN_MAX
                     and dop["recall"] is not None and dop["recall"] >= DOP_RECALL_MIN)
    else:
        dop_meets = dop["recall"] is not None and dop["recall"] >= DOP_RECALL_MIN
    summary["dop_band_met"] = dop_meets
    print("ARB\tcalib\t%s\tdop_band_met\t%s" % (dataset, dop_meets))

    if n_pos > 0 and n_neg > 0:
        auc = auroc(labels, scores)
        summary["auroc"] = auc
        auc_band = "meets" if auc >= AUROC_MEETS else ("weak" if auc >= AUROC_WEAK else "does_not_meet")
        summary["auroc_band"] = auc_band
        print("ARB\tcalib\t%s\tauroc\t%.4f" % (dataset, auc))
        print("ARB\tcalib\t%s\tauroc_band\t%s" % (dataset, auc_band))

        best, table = sweep_thresholds(labels, scores)
        summary["best_f1_threshold"] = best
        summary["threshold_sweep"] = table
        best_meets = best["f1"] >= BEST_F1_MEETS
        summary["best_f1_band_met"] = best_meets
        print("ARB\tcalib\t%s\tbest_f1_threshold\t%.4f" % (dataset, best["threshold"]))
        print("ARB\tcalib\t%s\tbest_f1\t%.4f" % (dataset, best["f1"]))
        print("ARB\tcalib\t%s\tbest_f1_recall\t%s" %
              (dataset, "%.4f" % best["recall"] if best["recall"] is not None else "n/a"))
        print("ARB\tcalib\t%s\tbest_f1_false_abstain_rate\t%s" %
              (dataset, "%.4f" % best["false_abstain_rate"] if best["false_abstain_rate"] is not None else "n/a"))
        print("ARB\tcalib\t%s\tbest_f1_band_met\t%s" % (dataset, best_meets))
    else:
        print("ARB\tcalib\t%s\tauroc\tn/a (single-class dataset)" % dataset)

    summary["round2"] = score_round2(dataset, scored_rows)
    return summary


def auroc_band(auc):
    """The registration's band table, INCLUDING the directional-refutation rung: an AUROC at or below
    0.35 means the signal separates the OPPOSITE way to the registered hypothesis. That rung is a
    distinct verdict string rather than a bare `does_not_meet`, because it is a different finding and
    the registration forbids reading it as a pass."""
    if auc >= AUROC_MEETS:
        return "meets"
    if auc >= AUROC_WEAK:
        return "weak"
    return "does_not_meet_opposite_direction" if auc <= DIRECTIONAL_REFUTATION else "does_not_meet"


def safe_operating_point(table):
    """The registered operating point: the highest-recall threshold whose false-abstain rate is still
    under the ceiling. None when no threshold satisfies both floors — which is itself the answer, not
    a missing measurement."""
    safe = [r for r in table
            if r["false_abstain_rate"] is not None and r["false_abstain_rate"] <= DOP_FALSE_ABSTAIN_MAX
            and r["recall"] is not None and r["recall"] >= DOP_RECALL_MIN]
    return max(safe, key=lambda r: r["recall"]) if safe else None


def score_round2_signal(dataset, scored_rows, name, scorer, is_primary):
    """One round-two signal, scored and printed. Split out of score_round2 so the loop stays a loop:
    the per-signal body is the whole statistic (AUROC, band, sweep, operating point) and the caller
    is only the join over four of them."""
    usable = [(row_label(dataset, r), scorer(r)) for r in scored_rows if scorer(r) is not None]
    labels = [y for y, _ in usable]
    scores = [s for _, s in usable]
    n_pos = sum(1 for y in labels if y)
    n_neg = len(labels) - n_pos
    missing = len(scored_rows) - len(usable)
    base = {"primary": is_primary, "signal_missing": missing, "no_gold": n_pos, "positive": n_neg}
    print("ARB\tcalib\t%s\tr2_%s_signal_missing\t%d" % (dataset, name, missing))
    if n_pos == 0 or n_neg == 0:
        print("ARB\tcalib\t%s\tr2_%s_auroc\tn/a (single-class dataset)" % (dataset, name))
        return dict(base, auroc=None)

    auc = auroc(labels, scores)
    band = auroc_band(auc)
    best, table = sweep_thresholds(labels, scores)
    safe_best = safe_operating_point(table)
    pct = lambda v: "%.4f" % v if v is not None else "n/a"   # noqa: E731 — one local formatter, six call sites

    print("ARB\tcalib\t%s\tr2_%s_auroc\t%.4f%s" % (dataset, name, auc, "  (PRIMARY)" if is_primary else ""))
    print("ARB\tcalib\t%s\tr2_%s_auroc_band\t%s" % (dataset, name, band))
    print("ARB\tcalib\t%s\tr2_%s_best_f1\t%.4f" % (dataset, name, best["f1"]))
    print("ARB\tcalib\t%s\tr2_%s_best_f1_threshold\t%.6f" % (dataset, name, best["threshold"]))
    print("ARB\tcalib\t%s\tr2_%s_best_f1_recall\t%s" % (dataset, name, pct(best["recall"])))
    print("ARB\tcalib\t%s\tr2_%s_best_f1_false_abstain_rate\t%s" % (dataset, name, pct(best["false_abstain_rate"])))
    print("ARB\tcalib\t%s\tr2_%s_safe_operating_point\t%s" %
          (dataset, name, "none" if safe_best is None else
           "theta=%.6f recall=%.4f false_abstain=%.4f" %
           (safe_best["threshold"], safe_best["recall"], safe_best["false_abstain_rate"])))
    return dict(base, auroc=auc, auroc_band=band, best_f1=best, safe_operating_point=safe_best,
                threshold_sweep_size=len(table))


def score_round2(dataset, scored_rows):
    """The round-two pass: the PRIMARY corpus-support statistic and its three reported secondaries.
    Emits under a `r2_` metric prefix so a reader (and a grep) can never mistake a round-two number
    for a round-one one — the two rounds share a dataset, a positive class and a band table, and
    that is exactly the shape in which numbers get quoted against the wrong registration."""
    out = {"signals": {name: score_round2_signal(dataset, scored_rows, name, scorer, is_primary)
                       for name, scorer, is_primary in ROUND2_SIGNALS}}
    primary = out["signals"].get("support") or {}
    out["primary_auroc"] = primary.get("auroc")
    out["primary_band"] = primary.get("auroc_band")
    out["primary_operating_point"] = primary.get("safe_operating_point")
    # the verdict this dataset contributes. The registration licenses a behavior change only when the
    # PRIMARY meets AND an operating point exists — on BOTH selective splits, which main() joins.
    out["licenses_behavior"] = bool(primary.get("auroc_band") == "meets"
                                    and primary.get("safe_operating_point") is not None)
    print("ARB\tcalib\t%s\tr2_primary_band\t%s" % (dataset, out["primary_band"]))
    print("ARB\tcalib\t%s\tr2_licenses_behavior\t%s" % (dataset, out["licenses_behavior"]))
    return out


def main():
    parser = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    parser.add_argument("--data", default=os.environ.get("RIPWIRE_ARB_DATA",
                                                         os.path.join(REPO, "bench", "external", "arb")))
    parser.add_argument("--datasets", default=",".join(DATASETS),
                        help="comma-separated subset of: %s" % ", ".join(DATASETS))
    args = parser.parse_args()

    datasets = [d.strip() for d in args.datasets.split(",") if d.strip()]
    for d in datasets:
        if d not in DATASETS:
            sys.stderr.write("score_abstention_calibration: unknown dataset %r\n" % d)
            sys.exit(2)

    summaries = []
    for dataset in datasets:
        summary = score_dataset(args.data, dataset)
        if summary is not None:
            summaries.append(summary)

    # ROUND TWO's verdict is a JOIN, not a per-dataset result: the registration requires the PRIMARY
    # to meet AND an operating point to exist on BOTH selective splits. Printed here so nobody has to
    # assemble it by eye from two dataset blocks and get the AND wrong in the direction that ships.
    splits = [s for s in summaries if s["dataset"].startswith("selective_retrieval_")]
    if len(splits) == 2:
        licensed = all((s.get("round2") or {}).get("licenses_behavior") for s in splits)
        print("ARB\tcalib\tROUND2\tprimary_auroc_by_split\t%s" %
              "  ".join("%s=%s" % (s["dataset"], "n/a" if (s.get("round2") or {}).get("primary_auroc") is None
                                   else "%.4f" % s["round2"]["primary_auroc"]) for s in splits))
        print("ARB\tcalib\tROUND2\tbehavior_licensed\t%s" % licensed)
        print("ARB\tcalib\tROUND2\tverdict\t%s" %
              ("POSITIVE — wire the abstention behavior per the registration" if licensed else
               "NEGATIVE — registered negative; --for behavior unchanged, axis stays disclosed-not-acted-on"))
    else:
        print("ARB\tcalib\tROUND2\tverdict\tINCOMPLETE (both selective splits are required by the registration)")

    out_path = os.path.join(args.data, "runs", "abstention_calibration_summary.json")
    os.makedirs(os.path.dirname(out_path), exist_ok=True)
    with open(out_path, "w", encoding="utf-8") as fh:
        json.dump(summaries, fh, indent=2, sort_keys=True)
    print("ARB\tcalib\tsummary\t%s" % os.path.relpath(out_path, REPO))


if __name__ == "__main__":
    main()
