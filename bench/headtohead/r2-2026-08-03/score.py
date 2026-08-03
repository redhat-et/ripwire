#!/usr/bin/env python3
# Pair the 4 arms per instance and print the scoreboard + win/loss matrix + ripwire losses.
# Ranks were computed per-arm by the SAME RL.file_ranks import; this script only aggregates.
import json, pathlib, statistics

HERE = pathlib.Path(__file__).resolve().parent
R = HERE / "results"

rip = json.load(open(R / "ripwire_for.json"))["instances"]
def load_jsonl(p):
    return {r["instance_id"]: r for r in (json.loads(l) for l in open(p))} if p.exists() else {}
cs = load_jsonl(R / "codeseek.jsonl")
rw = load_jsonl(R / "repowise.jsonl")

ARMS = ["ripwire", "codeseek_raw", "codeseek_idents", "repowise"]
def arm_ranks(iid, inst):
    out = {}
    out["ripwire"] = (inst["arms"]["for"]["file_worst"], inst["arms"]["for"]["file_first"], inst["arms"]["for"]["wall_median"])
    c = cs.get(iid); w = rw.get(iid)
    out["codeseek_raw"]    = (c["raw"]["file_worst"],    c["raw"]["file_first"],    c["raw"]["wall"])    if c else None
    out["codeseek_idents"] = (c["idents"]["file_worst"], c["idents"]["file_first"], c["idents"]["wall"]) if c else None
    out["repowise"]        = (w["search"]["file_worst"], w["search"]["file_first"], w["search"]["wall"]) if w else None
    return out

rows, missing = [], 0
for inst in rip:
    iid = inst["instance_id"]
    a = arm_ranks(iid, inst)
    if any(v is None for v in a.values()): missing += 1; continue
    rows.append((iid, len(inst["primary_files"]), a))

n = len(rows)
print(f"paired N={n} (missing from a competitor arm: {missing})\n")
def strict10(v): return v[0] is not None and v[0] < 10
def any10(v):    return v[1] is not None and v[1] < 10

hdr = f"{'arm':16} | strict@10 | any@10 | wall median"
print(hdr); print("-" * len(hdr))
for arm in ARMS:
    s = sum(strict10(a[arm]) for _, _, a in rows)
    y = sum(any10(a[arm]) for _, _, a in rows)
    wm = statistics.median(a[arm][2] for _, _, a in rows)
    print(f"{arm:16} |   {100*s/n:5.1f}%  | {100*y/n:5.1f}% | {wm:7.3f}s")

for stratum, keep in (("single", lambda k: k == 1), ("multi", lambda k: k > 1)):
    sub = [r for r in rows if keep(r[1])]
    print(f"\n{stratum}-file stratum n={len(sub)}:")
    for arm in ARMS:
        s = sum(strict10(a[arm]) for _, _, a in sub); y = sum(any10(a[arm]) for _, _, a in sub)
        print(f"  {arm:16} strict@10 {100*s/len(sub):5.1f}%  any@10 {100*y/len(sub):5.1f}%")

print("\nwin/loss vs ripwire (strict@10):")
for arm in ARMS[1:]:
    both = sum(strict10(a["ripwire"]) and strict10(a[arm]) for _, _, a in rows)
    ronly = sum(strict10(a["ripwire"]) and not strict10(a[arm]) for _, _, a in rows)
    aonly = sum(not strict10(a["ripwire"]) and strict10(a[arm]) for _, _, a in rows)
    neither = n - both - ronly - aonly
    print(f"  vs {arm:16} both={both} ripwire-only={ronly} {arm}-only={aonly} neither={neither}")

print("\nripwire strict losses (competitor strict-hit where ripwire missed):")
for iid, k, a in rows:
    losers = [arm for arm in ARMS[1:] if strict10(a[arm]) and not strict10(a["ripwire"])]
    if losers:
        print(f"  {iid} (gold files={k}): won by {','.join(losers)} "
              f"rip(worst={a['ripwire'][0]},first={a['ripwire'][1]}) "
              + " ".join(f"{arm}(worst={a[arm][0]},first={a[arm][1]})" for arm in losers))

print("\nany@10 losses (competitor any-hit where ripwire had none):")
for iid, k, a in rows:
    losers = [arm for arm in ARMS[1:] if any10(a[arm]) and not any10(a["ripwire"])]
    if losers:
        print(f"  {iid}: {','.join(losers)}")
