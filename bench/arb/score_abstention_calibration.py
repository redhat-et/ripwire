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

    return summary


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

    out_path = os.path.join(args.data, "runs", "abstention_calibration_summary.json")
    os.makedirs(os.path.dirname(out_path), exist_ok=True)
    with open(out_path, "w", encoding="utf-8") as fh:
        json.dump(summaries, fh, indent=2, sort_keys=True)
    print("ARB\tcalib\tsummary\t%s" % os.path.relpath(out_path, REPO))


if __name__ == "__main__":
    main()
