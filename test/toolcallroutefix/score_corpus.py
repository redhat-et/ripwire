#!/usr/bin/env python3
# test/toolcallroutefix/score_corpus.py — scores test/toolcallroutecheck.sh's corpus pass. A separate
# committed file rather than an inline heredoc in the gate script: macOS's shipped /bin/bash (3.2.57)
# mis-parses a `<<'HEREDOC'` body containing an apostrophe when the heredoc sits inside a `$(...)`
# command substitution ("unexpected EOF while looking for matching `''"`, confirmed with a two-line
# repro) -- a real parser limitation of that bash, not a quoting mistake in the script.
#
# Reads test/toolcallroutecheck.sh's per-row RESULTS file (one JSON object per corpus row: {expect,
# out, rc, logged}) and prints the precision/harmful breakdown the gate's registered bar checks.
# Exit 0 when precision >= 0.95 AND harmful == 0 AND no bad rc/json; exit 1 otherwise.
#
# Usage: python3 test/toolcallroutefix/score_corpus.py RESULTS_JSONL
import json
import sys

path = sys.argv[1]
tp = fp = fn = tn = harmful = badrc = badjson = 0
by_class = {}

for line in open(path, encoding="utf-8"):
    line = line.strip()
    if not line:
        continue
    r = json.loads(line)
    exp = r["expect"]
    out = r["out"]
    rc = r["rc"]
    logged = r["logged"]
    cls = exp["class"]
    by_class.setdefault(cls, {"n": 0, "fail": 0})
    by_class[cls]["n"] += 1

    if rc != 0:
        badrc += 1
        by_class[cls]["fail"] += 1
        continue

    got_recommend = bool(out.strip())
    if got_recommend:
        try:
            obj = json.loads(out)
            ctx = obj["hookSpecificOutput"]["additionalContext"]
        except Exception:
            badjson += 1
            by_class[cls]["fail"] += 1
            continue
    else:
        ctx = ""

    expect_status = exp["expect_status"]
    expect_recommended = exp.get("expect_recommended") or []
    row_ok = True

    if expect_status == "recommend":
        if got_recommend and any(("%s=" % v) in ctx for v in expect_recommended):
            tp += 1
        else:
            fn += 1
            row_ok = False
    else:
        # abstain or none -- must NOT have injected anything
        if got_recommend:
            fp += 1
            row_ok = False
            # harmful: any route on a notification/poll-labelled shape, full stop.
            if cls in ("notification", "poll", "cat-sed"):
                harmful += 1
            else:
                # harmful: the injected verb does not belong to this shape's own correct verb family.
                # grep-shaped classes recommend --grep only; read-shaped classes recommend --expand/--for.
                grep_family = (cls.startswith("grep") or cls.startswith("rg") or
                               cls in ("pipe", "quoted", "regex"))
                read_family = cls.startswith("read")
                if grep_family and "--grep=" not in ctx:
                    harmful += 1
                elif read_family and not any(v in ctx for v in ("--expand=", "--for=")):
                    harmful += 1
        else:
            tn += 1
            # reason check, when the corpus names one
            expect_reason = exp.get("expect_reason")
            if expect_reason and logged is not None and logged.get("reason") != expect_reason:
                row_ok = False

    if not row_ok:
        by_class[cls]["fail"] += 1

total_recommended = tp + fp
precision = (tp / total_recommended) if total_recommended else 1.0
total = tp + fp + fn + tn
harmful_rate = harmful / total if total else 0.0

print("N=%d TP=%d FP=%d FN=%d TN=%d bad_rc=%d bad_json=%d" % (total, tp, fp, fn, tn, badrc, badjson))
print("precision=%.4f (TP=%d / recommended=%d)" % (precision, tp, total_recommended))
print("harmful=%d harmful_rate=%.4f" % (harmful, harmful_rate))
worst = sorted(((v["fail"], k, v["n"]) for k, v in by_class.items() if v["fail"]), reverse=True)
for failn, cls, n in worst:
    print("  class %-20s %d/%d rows failed" % (cls, failn, n))

is_ok = (precision >= 0.95) and (harmful == 0) and (badrc == 0) and (badjson == 0)
sys.exit(0 if is_ok else 1)
