#!/usr/bin/env python3
"""Historical Shotgun-Surgery prototype: per-commit DEGREE OF SCATTER (distinct files / dirs touched),
per-file mean scatter over the commits that touched it. Commits with > CAP files are dropped (Code Maat
bulk-commit rule, ripwire's kCoBoostMaxFilesPerCommit=30)."""
import sys, os, collections, statistics
log = sys.argv[1]; cap = int(sys.argv[2]) if len(sys.argv) > 2 else 30
probe = sys.argv[3].split(',') if len(sys.argv) > 3 else []
commits = []; cur = None
for line in open(log, errors='replace'):
    line = line.rstrip('\n')
    if line.startswith('COMMIT '):
        p = line.split(' ', 3); cur = [p[1][:8], p[2], p[3] if len(p) > 3 else '', []]; commits.append(cur)
    elif line.strip() and cur is not None:
        cur[3].append(line.strip())
total = len(commits)
kept = [c for c in commits if 1 <= len(c[3]) <= cap]
dropped_big = sum(1 for c in commits if len(c[3]) > cap)
def dirs(files): return {os.path.dirname(f) or '.' for f in files}
def tops(files): return {f.split('/')[0] for f in files}
per_file = collections.defaultdict(list)
nfiles_all = []; ndirs_all = []; ntops_all = []
for sha, date, subj, files in kept:
    nf, nd, nt = len(files), len(dirs(files)), len(tops(files))
    nfiles_all.append(nf); ndirs_all.append(nd); ntops_all.append(nt)
    for f in files: per_file[f].append((nf, nd, nt, sha, subj))
print(f"commits total={total} kept(1..{cap} files)={len(kept)} dropped_bulk(>{cap})={dropped_big} empty={total-len(kept)-dropped_big}")
print(f"per-commit files: median={statistics.median(nfiles_all)} mean={statistics.mean(nfiles_all):.2f}  dirs: median={statistics.median(ndirs_all)} mean={statistics.mean(ndirs_all):.2f}  top-level: median={statistics.median(ntops_all)} mean={statistics.mean(ntops_all):.2f}")
for k in (2, 3, 4, 5):
    print(f"  commits touching >= {k} dirs: {sum(1 for d in ndirs_all if d >= k)} ({100*sum(1 for d in ndirs_all if d >= k)/len(kept):.0f}%)   >= {k} top-level: {sum(1 for d in ntops_all if d >= k)} ({100*sum(1 for d in ntops_all if d >= k)/len(kept):.0f}%)")
hist = collections.Counter(min(d, 8) for d in ndirs_all)
print("  dirs/commit histogram:", ' '.join(f"{k}{'+' if k==8 else ''}:{hist[k]}" for k in sorted(hist)))
MINN = 5
rows = []
for f, L in per_file.items():
    if len(L) < MINN: continue
    rows.append((statistics.mean(x[1] for x in L), statistics.mean(x[0] for x in L), statistics.mean(x[2] for x in L), len(L), f))
print(f"\nfiles with >= {MINN} commits: {len(rows)}   (ranked by MEAN DIRS per commit that touched the file; support n)")
print(f"{'meanDirs':>8} {'meanFiles':>9} {'meanTop':>7} {'n':>4}  file")
for md, mf, mt, n, f in sorted(rows, key=lambda r: (-r[0], -r[1], r[4]))[:30]:
    print(f"{md:8.2f} {mf:9.2f} {mt:7.2f} {n:4d}  {f}")
# the distribution of per-file mean scatter — is the top of the list SEPARATED from the bulk, or one smear?
if rows:
    mds = sorted(r[0] for r in rows)
    q = lambda p: mds[min(len(mds)-1, int(p*len(mds)))]
    print(f"\nper-file meanDirs quantiles: p50={q(.5):.2f} p75={q(.75):.2f} p90={q(.9):.2f} p95={q(.95):.2f} max={mds[-1]:.2f}")
for f in probe:
    L = per_file.get(f, [])
    print(f"\nPROBE {f}: n={len(L)}", '' if L else '(no commits within cap, or no such path)')
    for nf, nd, nt, sha, subj in L:
        print(f"    files={nf:2d} dirs={nd:2d} {sha} {subj[:70]}")
