#!/usr/bin/env python3
# S1 term derivation — reads SKILL BODIES ONLY (never eval prompts, never miss lists).
# Rule (pre-registered): per-skill tf x idf over the 17 bodies, minus subtokens already in the
# description; candidates need tf >= 3 in own body AND df <= 4/17 across the OTHER bodies.
import glob, math, os, re
from collections import Counter

ROOT = os.path.normpath( os.path.join( os.path.dirname( os.path.abspath( __file__ ) ), '..', '..' ) )

def subtokens( text ):
    out = []; cur = ''
    for ch in text:
        if ch.isascii() and (ch.isalpha() or ch.isdigit()):
            if ch.isupper() and cur and not cur[-1].isupper():
                if len(cur) >= 2: out.append(cur.lower())
                cur = ''
            cur += ch
        else:
            if len(cur) >= 2: out.append(cur.lower())
            cur = ''
    if len(cur) >= 2: out.append(cur.lower())
    return out

skills = {}
for f in sorted(glob.glob(ROOT + '/skills/ripwire-*/SKILL.md')):
    name = f.split('/')[-2]
    if name == 'ripwire-router': continue
    txt = open(f).read()
    parts = txt.split('---', 2)          # frontmatter fence
    fm, body = parts[1], parts[2]
    m = re.search(r'description:.*?(?=\n[a-zA-Z-]+:|\Z)', fm, re.S)
    desc = m.group(0)
    skills[name] = (set(subtokens(desc)), Counter(subtokens(body)))

names = sorted(skills)
K = len(names)
print("skills:", K)

# df across bodies
df = Counter()
for n in names:
    for t in set(skills[n][1]): df[t] += 1

STOP = set('''the and for you your this that what which before after when how is it to of an in on
do does not no my me we or so at be are was with as have has one two three run runs running use
using used its they them each every all any can could should would will just even more most into
out over under about need want give show tell find make like get gets when where why who whom whose
if then than because also very only same other another such still yet may might must shall between
these those there here from by ripwire skill skills code file files line lines src dir example
examples backed deterministic path'''.split())

for n in names:
    descToks, tf = skills[n]
    cands = []
    for t, c in tf.items():
        if c < 3: continue
        otherDf = df[t] - 1          # df across the OTHER bodies
        if otherDf > 4: continue
        if t in descToks: continue
        if t in STOP: continue
        if t.isdigit(): continue
        idf = math.log(K / (1 + otherDf))
        cands.append((c * idf, c, otherDf, t))
    cands.sort(reverse=True)
    print("\n== %s" % n)
    for score, c, odf, t in cands[:18]:
        print("   %-24s tf=%-3d df_other=%d  tfidf=%.1f" % (t, c, odf, score))
