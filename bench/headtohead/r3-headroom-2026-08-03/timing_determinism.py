#!/usr/bin/env python3
"""Pass 2: wall-time medians (N=5) and determinism byte-checks for both tools.

Timing arms (cache state in the name):
  ripwire_warm_map      full map, live cache
  ripwire_warm_verb     --callers on the corpus, live cache
  ripwire_cold_map      --no-cache full map
  grep_naive            grep -rnF over the corpus (arm A's first step)
  headroom_compress_50k compress() on a fixed ~50k-char transcript, default config

Determinism:
  ripwire: two warm full-map runs byte-identical?
  headroom: two compress() calls on the identical transcript byte-identical?
"""

import json
import statistics
import subprocess
import time
from pathlib import Path

HERE = Path(__file__).resolve().parent
CORPUS = Path(
    "/private/tmp/claude-501/-Users-qgames-AppDevelopLocal-project2-ripwire/"
    "8ebe7d31-1cf3-4a60-aa6c-cafea943c4df/scratchpad/repos/django__django"
)
RIPWIRE = "/Users/qgames/AppDevelopLocal/project2/ripwire/build/ripwire"
N = 5


def med(argv):
    ts = []
    for _ in range(N):
        t0 = time.perf_counter()
        subprocess.run(argv, capture_output=True, timeout=600)
        ts.append(time.perf_counter() - t0)
    return {"median_s": round(statistics.median(ts), 4), "min_s": round(min(ts), 4), "max_s": round(max(ts), 4)}


def main():
    out = {"n_runs": N}
    out["ripwire_warm_map"] = med([RIPWIRE, str(CORPUS)])
    out["ripwire_warm_verb_callers"] = med([RIPWIRE, str(CORPUS), "--callers=parse_cookie"])
    out["ripwire_cold_map"] = med([RIPWIRE, str(CORPUS), "--no-cache"])
    out["grep_naive"] = med(["grep", "-rnF", "--include=*.py", "-r", "parse_cookie", str(CORPUS)])

    # fixed transcript for compress timing + determinism: first ~50k chars of a big corpus file
    big = (CORPUS / "django/db/models/query.py").read_text(errors="replace")[:50000]
    msgs = [
        {"role": "user", "content": "how does queryset iteration hit the database?"},
        {"role": "tool", "content": "[tool result read:django/db/models/query.py]\n" + big},
    ]
    from headroom import compress

    ts, outs = [], []
    for _ in range(N):
        t0 = time.perf_counter()
        r = compress(msgs, model="claude-sonnet-4-5-20250929")
        ts.append(time.perf_counter() - t0)
        outs.append(json.dumps(r.messages, sort_keys=True))
    out["headroom_compress_50k"] = {
        "median_s": round(statistics.median(ts), 4),
        "min_s": round(min(ts), 4),
        "max_s": round(max(ts), 4),
        "transforms": r.transforms_applied,
        "ratio": r.compression_ratio,
    }
    out["headroom_deterministic"] = len(set(outs)) == 1

    a = subprocess.run([RIPWIRE, str(CORPUS)], capture_output=True).stdout
    b = subprocess.run([RIPWIRE, str(CORPUS)], capture_output=True).stdout
    out["ripwire_deterministic"] = a == b

    (HERE / "timing_determinism.json").write_text(json.dumps(out, indent=1))
    print(json.dumps(out, indent=1))


if __name__ == "__main__":
    main()
