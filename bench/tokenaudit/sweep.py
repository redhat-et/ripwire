#!/usr/bin/env python3
# sweep.py — does ripwire's est_tokens= agree with a real tokenizer, per verb and per corpus?
#
# WHY THIS EXISTS. est_tokens is the number every --token-budget gates on and the number the owner
# named as the user-facing unit, and until this script it was validated only for its PROPERTIES
# (deterministic, present, monotone under a tighter budget — test/tokenbudgetcheck.sh) and by a
# MAPE the T1 author reported by hand in a write-up. Nothing in the tree re-derived the error against
# a tokenizer, and nothing measured it PER VERB. A single-corpus MAPE cannot see a per-verb bias:
# the divisor is a per-language content-byte model, and a --callers answer is ~90% markup while a
# --expand answer is ~70% body, so one rate serving both is a hypothesis, not a measurement.
#
# It also prices THE LEGEND. A third-party evaluation (callstack/agent-device #2400, 2026-09-08)
# measured ripwire spending ~10% MORE tokens than grep-and-read and traced it to the fixed per-call
# preamble. test/legendcostcheck.sh holds --help's BYTE claim to what the binary delivers; this
# script measures the same thing in the unit the claim is read in — real tokenizer tokens — by
# running each invocation twice, --legend=full and --legend=compact, on the same corpus.
#
# WHAT IS MEASURED, PER (corpus, invocation):
#   bytes           len(stdout) in bytes
#   est_tokens      the number ripwire printed, or null if the verb prints none  <-- a finding in itself
#   o200k / cl100k  real token counts (tiktoken), the ground truth this file compares against
#   err_pct         100 * (est - o200k) / o200k    signed: negative = ripwire UNDER-reports its price
#   legend_*        the same numbers for --legend=compact, and the token delta = the legend's price
#
# WHAT IT IS NOT. Not a gate. tiktoken is not a build dependency and never will be (G3: one
# deterministic build step, nothing host-installed), and o200k_base is not Claude's tokenizer —
# it is the closest public stand-in, which is exactly why kTokenCalib was calibrated against it and
# why a gate that needs it at runtime would be a dependency problem. The gate this round adds
# (test/estcalibcheck.sh) reads PINNED counts out of a manifest this script writes; re-running this
# script is how the manifest is regenerated, deliberately by hand.
#
# Usage:
#   python3 bench/tokenaudit/sweep.py --bin build/ripwire --out bench/tokenaudit/results/x.json \
#           [--corpus NAME=PATH ...] [--python PYTHON_WITH_TIKTOKEN]
#
# Determinism: the invocation table below is fixed and ordered; symbol arguments are DERIVED from
# each corpus's own map (highest-ranked symbol with callers) so the table transfers to a corpus this
# file has never seen, and the derived symbol is recorded in the results so a rerun is auditable.

import argparse
import json
import os
import re
import subprocess
import sys

EST_RE = re.compile(rb'est_tokens="(\d+)"')
SYM_RE = re.compile(rb'<s [^>]*\bn="([^"]+)"')
FILE_RE = re.compile(rb'<f p="([^"]+)"')


def run(binpath, root, args, timeout=600):
    """One ripwire invocation. Returns (stdout_bytes, stderr_text, returncode)."""
    cmd = [binpath, root] + args
    p = subprocess.run(cmd, capture_output=True, timeout=timeout)
    return p.stdout, p.stderr.decode("utf-8", "replace"), p.returncode


def derive_targets(binpath, root):
    """Pick a symbol and a file out of the corpus's OWN map, so the table is corpus-portable.

    The choice is the first <s> row of the map (rank 1) and the first <f p=> file. Deterministic
    because the map is; recorded in the output because a number is unauditable without its input.
    """
    out, _, _ = run(binpath, root, ["--top-k=40"])
    syms = SYM_RE.findall(out)
    files = FILE_RE.findall(out)
    sym = syms[0].decode() if syms else "main"
    fil = files[0].decode() if files else ""
    # Prefer a symbol that actually has callers AND is unambiguous, else --callers/--impact answer
    # nothing and --edit-check refuses — the legend share would then be measured on an empty or
    # refused document (true, but not the case anyone runs). The FIRST candidate that satisfies both
    # wins, so the choice stays deterministic and is recorded in the results.
    for cand in syms[:20]:
        c = cand.decode()
        co, _, rc = run(binpath, root, ["--callers=" + c, "--legend=compact"])
        if rc != 0 or co.count(b"<caller") == 0:
            continue
        _, _, erc = run(binpath, root, ["--edit-check=" + c])
        if erc == 0:
            sym = c
            break
    return sym, fil


def invocations(sym, fil):
    """The fixed table. `legend` marks the ones for which a --legend=compact twin is also run."""
    t = [
        ("map",                 [],                                                     True),
        ("map-topk10",          ["--top-k=10"],                                         True),
        ("map-json",            ["--json"],                                             False),
        ("metrics",             ["--metrics", "--top-k=40"],                             True),
        ("pack-signatures",     ["--pack-signatures", "--top-k=40"],                     True),
        ("for-conceptual",      ["--for=how are tokens counted and budgeted"],           True),
        ("for-named",           ["--for=" + sym],                                        True),
        ("for-json",            ["--for=how are tokens counted and budgeted", "--json"], False),
        ("pack-task",           ["--pack-task=fix the token estimate"],                  True),
        ("expand",              ["--expand=" + sym],                                     True),
        ("callers",             ["--callers=" + sym],                                    True),
        ("callees",             ["--callees=" + sym],                                    True),
        ("impact",              ["--impact=" + sym],                                     True),
        ("uses",                ["--uses=" + sym],                                       True),
        ("around",              ["--around=" + sym],                                     True),
        ("edit-check",          ["--edit-check=" + sym],                                 True),
        ("grep",                ["--grep=token"],                                        True),
        ("hotspots",            ["--hotspots"],                                          True),
        ("lint",                ["--lint"],                                              True),
        ("tree",                ["--tree"],                                              True),
        ("clones",              ["--clones"],                                            True),
        ("situ",                ["--situ"],                                              False),
        ("recall",              ["--recall=how are tokens counted"],                     False),
        ("test-gate",           ["--test-gate"],                                         True),
    ]
    if fil:
        t.append(("affected", ["--affected=" + fil], True))
    return t


def count_tokens(encs, data):
    text = data.decode("utf-8", "replace")
    return {name: len(enc.encode(text, disallowed_special=())) for name, enc in encs.items()}


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--bin", default="build/ripwire")
    ap.add_argument("--out", default="bench/tokenaudit/results/tokenaudit.json")
    ap.add_argument("--corpus", action="append", default=[],
                    help="NAME=PATH, repeatable; defaults to the checkout this script lives in")
    args = ap.parse_args()

    binpath = os.path.abspath(args.bin)
    corpora = []
    for spec in args.corpus:
        name, _, path = spec.partition("=")
        corpora.append((name, os.path.abspath(path)))
    if not corpora:
        here = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
        corpora.append(("self", here))

    import tiktoken
    encs = {"o200k": tiktoken.get_encoding("o200k_base"),
            "cl100k": tiktoken.get_encoding("cl100k_base")}

    result = {"bin": binpath, "corpora": {}, "schema": "ripwire.tokenaudit/v1"}
    ver, _, _ = run(binpath, ".", ["--version"])
    result["version"] = ver.decode("utf-8", "replace").strip().splitlines()[0] if ver else ""

    for name, path in corpora:
        sym, fil = derive_targets(binpath, path)
        rows = []
        for label, argv, has_legend in invocations(sym, fil):
            out, err, rc = run(binpath, path, argv)
            m = EST_RE.search(out)
            row = {
                "verb": label,
                "argv": argv,
                "rc": rc,
                "bytes": len(out),
                "est_tokens": int(m.group(1)) if m else None,
            }
            row.update(count_tokens(encs, out))
            if row["o200k"]:
                row["bytes_per_o200k"] = round(row["bytes"] / row["o200k"], 4)
            if row["est_tokens"] is not None and row["o200k"]:
                row["err_pct"] = round(100.0 * (row["est_tokens"] - row["o200k"]) / row["o200k"], 2)
            if has_legend:
                cout, cerr, crc = run(binpath, path, argv + ["--legend=compact"])
                if crc == 0 and cout:
                    ct = count_tokens(encs, cout)
                    row["compact_bytes"] = len(cout)
                    row["compact_o200k"] = ct["o200k"]
                    row["legend_o200k"] = row["o200k"] - ct["o200k"]
                    row["legend_bytes"] = row["bytes"] - len(cout)
                    if row["o200k"]:
                        row["legend_share_pct"] = round(100.0 * row["legend_o200k"] / row["o200k"], 2)
                    cm = EST_RE.search(cout)
                    row["compact_est_tokens"] = int(cm.group(1)) if cm else None
                    if row["compact_est_tokens"] is not None and ct["o200k"]:
                        row["compact_err_pct"] = round(
                            100.0 * (row["compact_est_tokens"] - ct["o200k"]) / ct["o200k"], 2)
                else:
                    row["compact_refused"] = cerr.strip()[:200]
            rows.append(row)
        result["corpora"][name] = {"root": path, "symbol": sym, "file": fil, "rows": rows}

    os.makedirs(os.path.dirname(os.path.abspath(args.out)), exist_ok=True)
    with open(args.out, "w") as f:
        json.dump(result, f, indent=1, sort_keys=True)
        f.write("\n")
    print("wrote", args.out)


if __name__ == "__main__":
    main()
