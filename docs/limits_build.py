#!/usr/bin/env python3
# limits_build.py — generate docs/LIMITS.md: every compile-time cap in src/, what it bounds, and
# whether the file it lives in DISCLOSES a truncation when it fires.
#
# WHY GENERATED. A hand-kept table of 120 constants is a table that rots. The 2026-09-09 round found a
# published figure that had been wrong for four days because one number lived in six places and only
# four were wired together; the fix is to make the doc a build product with a gate, not a promise.
#
# WHY IT MATTERS BEYOND BOOKKEEPING. A cap is a routing decision. kMaxExpandSibs=8 fired on 68.5% of
# bodies and hid 89.3% of all sibling names while its stated cost — "~3.5 KB per --pack-task bundle" —
# was not reproducible, because --pack-task emits no sibs= at all. Nobody could see that, because
# nothing listed the caps next to each other.
#
# Usage: python3 docs/limits_build.py [--out docs/LIMITS.md] [--check]
#   --check prints the table to stdout and exits 1 if it differs from --out (this is what the gate runs).
import re, sys, pathlib, collections, argparse

ROOT = pathlib.Path(__file__).resolve().parent.parent
DECL = re.compile(r'^\s*inline\s+constexpr\s+[\w:<>, ]*?\b(k[A-Z][A-Za-z0-9_]*)\s*=\s*([0-9][0-9_.eE+-]*)\s*;(.*)$')
KEY  = re.compile(r'Max|Cap|Limit|Top|Budget|Ceil|Threshold|Rows|Len|Depth|Width')

# A CAP answers "how many of X survive". A HYPERPARAMETER answers "how is X weighted or apportioned".
# They are not the same instrument and must not share a table: a cap is judged by what it truncates and
# gated by shown/total, while a weight is judged by an eval and gated by the EVALS anchor that SET it.
# The tell is the value itself — 0.90 cannot be a row count — plus a small set of names that are ratios
# spelled as integers. Filed here after a review caught five ratios sitting in the cap table (2026-09-10).
# `Threshold` is here, not in KEY: both of this tree's thresholds are CLASSIFICATION BOUNDARIES
# (">5 defs of the same name => common"; "past this => classify into pain/useless"). Neither truncates
# anything, so neither can be judged by shown/total. Min(Len|Words|Chars) likewise: the tree's only
# two are kSpecificMinLen/kSpecificMinWords, ELIGIBILITY thresholds for a rank multiplier in the
# name-scoring family (graph.h, the aider heuristic). capsweep found kSpecificMinLen to have the
# WIDEST measured blast radius of any constant here — 14 invocations across 9 verbs — which is
# precisely why it must not sit in a table of things judged by what they truncate.
WEIGHT_NAME = re.compile(r'Mul|Blend|Share|Tolerance|Headroom|Decay|Weight|Prior|Factor|Ratio|Threshold'
                          r'|Min(?:Len|Words|Chars)')
def is_weight(name, val):
    if WEIGHT_NAME.search(name):
        return True
    try:
        f = float(val)
    except ValueError:
        return False
    return f != int(f)                      # a fractional "cap" is a proportion, not a count

def scan():
    caps, disc = [], collections.defaultdict(set)
    files = sorted(ROOT.joinpath('src').rglob('*.h')) + sorted(ROOT.joinpath('src').rglob('*.cpp'))
    for p in files:
        rel = p.relative_to(ROOT).as_posix()
        txt = p.read_text(errors='replace')
        for a in re.findall(r'([a-z_]+)_capped', txt):
            disc[rel].add(a)
        for i, line in enumerate(txt.splitlines(), 1):
            m = DECL.match(line)
            if not m or not KEY.search(m.group(1)):
                continue
            note = m.group(3).strip().lstrip('/ ').strip()
            caps.append((m.group(1), m.group(2), rel, i, note))
    return caps, disc

def partition(caps):
    real  = [c for c in caps if not is_weight(c[0], c[1])]
    weights = [c for c in caps if is_weight(c[0], c[1])]
    return real, weights

def render(caps, disc):
    out = []
    w = out.append
    w('# Limits\n')
    w('**Generated — do not edit.** `python3 docs/limits_build.py` writes this file and')
    w('`test/limitstablecheck.sh` fails if it drifts from `src/`.\n')
    w('Every compile-time cap in `src/`, what it bounds, and whether its file discloses a truncation when')
    w('it fires. A cap is a **routing decision**: it decides what an agent can and cannot find. Set one')
    w('where the pathological tail is, never near the typical case — and when it fires, say so')
    w('(`*_capped="1"` with a `*_total=`), because a silent cut reads to the caller as "none exists".\n')
    caps, weights = partition(caps)
    silent = [c for c in caps if not disc.get(c[2])]
    w('| total caps | files | caps whose file discloses | caps whose file discloses NOTHING |')
    w('| --- | --- | --- | --- |')
    w('| %d | %d | %d | **%d** |\n' % (len(caps), len({c[2] for c in caps}),
                                       len(caps) - len(silent), len(silent)))
    if weights:
        w = out.append
        w('## Not caps — ranking and apportionment parameters\n')
        w('These decide **how** something is weighted or apportioned, not **how many** of it survive, so')
        w('they are judged by a different instrument: an eval that sets the value, not a `shown=`/`total=`')
        w('pair. A value of `0.90` cannot be a row count. Each needs a `docs/EVALS.md` anchor naming the')
        w('measurement that chose it; listing them beside truncation caps invites tuning them by intuition.\n')
        w('| constant | value | site | note |')
        w('| --- | --- | --- | --- |')
        for n, v, rel, ln, note in sorted(weights):
            w('| `%s` | `%s` | `%s:%d` | %s |' % (n, v, rel, ln, note.replace('|', '\\|')[:130] or '—'))
        w('')
    for rel in sorted({c[2] for c in caps}):
        rows = [c for c in caps if c[2] == rel]
        d = ', '.join('`%s_capped`' % a for a in sorted(disc.get(rel, []))) or '**none**'
        w('### `%s`\n' % rel)
        w('Discloses: %s\n' % d)
        w('| constant | value | line | note |')
        w('| --- | --- | --- | --- |')
        for n, v, _, ln, note in sorted(rows):
            w('| `%s` | `%s` | %d | %s |' % (n, v, ln, note.replace('|', '\\|')[:150] or '—'))
        w('')
    return '\n'.join(out) + '\n'

ap = argparse.ArgumentParser()
ap.add_argument('--out', default=str(ROOT / 'docs' / 'LIMITS.md'))
ap.add_argument('--check', action='store_true')
# --root retargets the scan at a synthetic tree. It exists so test/limitstablecheck.sh can prove this
# generator CAN go red on a real source change without editing the tree it is gating — a probe copy
# dropped into src/ would perturb the very crawl other gates measure.
ap.add_argument('--root', default=None)
a = ap.parse_args()
if a.root:
    ROOT = pathlib.Path(a.root).resolve()
caps, disc = scan()
if not caps:
    sys.exit('limits_build: parsed 0 caps — the declaration shape changed')
body = render(caps, disc)
if a.check:
    cur = pathlib.Path(a.out).read_text() if pathlib.Path(a.out).exists() else ''
    if cur != body:
        sys.exit('limits_build: %s is STALE — run: python3 docs/limits_build.py' % a.out)
    print('limits_build: %s matches src/ (%d caps)' % (a.out, len(caps)))
else:
    pathlib.Path(a.out).write_text(body)
    print('limits_build: wrote %s — %d caps, %d silent' %
          (a.out, len(caps), sum(1 for c in caps if not disc.get(c[2]))))
