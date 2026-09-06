#!/usr/bin/env python3
"""Derive the 30 head-to-head questions + gold from the corpus, by the
arithmetic frozen in docs/EVALS.md's registration. Nothing here is hand-written.

Rule (registration, verbatim):
  1. window = the 1200 first-parent commits ending at the pin
  2. src(c) = touched files matching ^(db|table|util|file|utilities|memtable|cache|
              env|options|monitoring)/.*\.(cc|h)$ and NOT [^/]*test[^/]*\.(cc|h)$
     test(c) = touched files matching _test\.cc$
  3. shapes in decreasing restrictiveness; a commit serves at most one shape
  4. per shape: eligible list in first-parent order, stride = floor(L/6),
     indices 0, stride, ..., 5*stride
  5. question text = a fixed template per shape, filled from the commit
"""
import re, subprocess, sys, json, os

CORPUS = sys.argv[1]
PIN = "0e2801ac30b3f283c3b14e523ba3667eca024f09"

SRC_RE  = re.compile(r'^(db|table|util|file|utilities|memtable|cache|env|options|monitoring)/.*\.(cc|h)$')
NOTEST_RE = re.compile(r'[^/]*test[^/]*\.(cc|h)$')
TEST_RE = re.compile(r'_test\.cc$')

def git(*a):
    return subprocess.run(['git','-C',CORPUS,*a], capture_output=True, text=True, check=True).stdout

head = git('rev-parse','HEAD').strip()
assert head == PIN, f"corpus is at {head}, registration pins {PIN}"

shas = git('rev-list','--first-parent','-n','1200','HEAD').split()
assert len(shas) == 1200, len(shas)

# one batched log so we do not spawn 1200 processes
raw = git('log','--first-parent','-n','1200','--name-only','--pretty=format:%x00%H%x01%s')
commits = {}
order = []
for chunk in raw.split('\x00'):
    if not chunk.strip():
        continue
    header, _, body = chunk.partition('\n')
    sha, _, subject = header.partition('\x01')
    files = [l for l in body.split('\n') if l.strip()]
    src  = [f for f in files if SRC_RE.match(f) and not NOTEST_RE.search(f)]
    tst  = [f for f in files if TEST_RE.search(f)]
    commits[sha] = dict(sha=sha, subject=subject, files=files, src=src, test=tst)
    order.append(sha)
assert len(order) == 1200, len(order)

SHAPES = [
    ('S4', lambda c: len(c['src']) >= 3),
    ('S3', lambda c: len(c['src']) >= 1 and len(c['test']) >= 1),
    ('S2', lambda c: len(c['src']) >= 2),
    ('S1', lambda c: len(c['src']) >= 1),
    ('S5', lambda c: len(c['src']) >= 1),
]

claimed = set()
picked  = []
strides = {}
for name, pred in SHAPES:
    elig = [s for s in order if s not in claimed and pred(commits[s])]
    L = len(elig)
    stride = L // 6
    strides[name] = (L, stride)
    for i in range(6):
        s = elig[i*stride]
        claimed.add(s)
        picked.append((name, s))

def gold_and_text(shape, c):
    src, tst = c['src'], c['test']
    if shape == 'S1':
        return f"Where is {c['subject']} implemented?", list(src)
    if shape == 'S2':
        return f"If I change {src[0]}, what else has to change with it?", src[1:]
    if shape == 'S3':
        return f"Which tests cover {src[0]}?", list(tst)
    if shape == 'S4':
        return f"How does {src[0]} reach {src[-1]}?", src[1:-1]
    if shape == 'S5':
        d = os.path.dirname(src[0]) + '/'
        return f"What changed recently in {d}?", list(src)

rows = []
for idx, (shape, sha) in enumerate(picked, start=1):
    c = commits[sha]
    q, gold = gold_and_text(shape, c)
    rows.append(dict(qid=idx, shape=shape, commit=sha, short=sha[:9],
                     subject=c['subject'], question=q, gold=gold, n=len(gold),
                     src=c['src'], test=c['test']))

print("eligible/stride:", " · ".join(f"{k} L={v[0]} stride={v[1]}" for k,v in strides.items()))
json.dump(rows, open(os.path.join(os.path.dirname(__file__),'questions.json'),'w'), indent=1)
for r in rows:
    print(f"{r['qid']:2d} {r['shape']} {r['short']} n={r['n']:2d} {r['question'][:88]}")
