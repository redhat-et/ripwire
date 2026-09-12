#!/usr/bin/env python3
# limits_build.py — generate docs/LIMITS.md: every compile-time cap in src/, what it bounds, and
# whether the file it lives in DISCLOSES a truncation when it fires.
#
# WHY GENERATED. A hand-kept table of two hundred constants is a table that rots. The 2026-09-09 round found a
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
# WHAT THIS REGEX ADMITS, AND WHY IT WAS WIDENED. It used to require the literal `inline constexpr`
# with the value on the SAME line, and to name a cap by a keyword list. Both halves were leaking:
#
#   * `inline` is optional at namespace scope and forbidden on a class member, so `constexpr` and
#     `static constexpr` declarations were invisible. 92 declarations — 81 distinct names — sat outside
#     a register whose own first line says "Every compile-time cap in src/". Among them
#     `kType3MaxBucket` (bounds clone DETECTION, so clone_groups is a floor), `kSkillScanFindingCap`
#     (bounds a SECURITY verdict), `kMaxFlipRows`/`kMaxSitesShown` (whose files emit no disclosure
#     vocabulary at all) and `kChaConeCap`.
#   * the value may be wrapped onto the next line, so the scan is over the file text with re.M rather
#     than line by line.
#   * `Shown|PerFile|Hits` were missing from the NAME filter, which is how `kHandoffSymbolsPerFile` —
#     a cap that truncates output and discloses `syms_capped="1"` — appeared in neither this register
#     nor docs/TUNING.md, and was raised on 2026-09-10 without ever having been listed anywhere.
#
# The published "120 of 202" was the size of a regex's output presented as the size of a population.
# It is now 212 declarations under 200 names, and the recipe is this comment.
DECL = re.compile(r'^[ \t]*(?:static[ \t]+)?(?:inline[ \t]+)?constexpr[ \t]+[\w:<>, ]*?'
                  r'\b(k[A-Z][A-Za-z0-9_]*)[ \t]*=[ \t]*(?:\r?\n[ \t]*)?([0-9][0-9_.eE+-]*)[ \t]*;(.*)$',
                  re.M)
KEY  = re.compile(r'Max|Cap|Limit|Top|Budget|Ceil|Threshold|Rows|Len|Depth|Width|Shown|Hits'
                  r'|Per\w*File')       # Per\w*File, not PerFile: kHandoffCodeSymbolsPerFile and
                                        # kHandoffSymbolsPerCodeFile are the same kind of cap, and a
                                        # NAME filter that turns on a compound spelling is the defect
                                        # this widening exists to remove, not a smaller instance of it.

# A CAP answers "how many of X survive". A HYPERPARAMETER answers "how is X weighted or apportioned".
# They are not the same instrument and must not share a table: a cap is judged by what it truncates and
# gated by shown/total, while a weight is judged by an eval and gated by the EVALS anchor that SET it.
# The tell is the value itself — 0.90 cannot be a row count — plus a small set of names that are ratios
# spelled as integers. Filed here after a review caught six of them sitting in the cap table (2026-09-10).
# `Threshold` appears in BOTH tables below, and deliberately: KEY admits a name to the census, and this
# regex then routes it out of the truncation table. Removing it from KEY would make these constants
# vanish from the document entirely, which is the opposite of the point. Both of this tree's thresholds
# are CLASSIFICATION BOUNDARIES (">5 defs of the same name => common"; "past this => classify into
# pain/useless") — neither truncates anything, so neither can be judged by shown/total. Min(Len|Words|
# Chars) likewise: an ELIGIBILITY threshold for a rank multiplier in the name-scoring family (graph.h,
# the aider heuristic). capsweep measured kSpecificMinLen with the WIDEST blast radius of any constant
# here — 14 invocations across 9 verbs — which is precisely why it must not sit in a table of things
# judged by what they truncate.
# `Mul` is negative-lookahead'd off `Multi`: a future kMultiRowCap is a row cap, not a multiplier, and
# a partition that silently reclassifies a real cap is worse than one that misses a weight.
# Decay/Weight/Prior/Factor/Ratio match nothing in the tree today. They are kept as forward guards so a
# weight added under one of those names lands in the right table on its first day rather than after a
# review notices it; the gate below reports the partition sizes so an empty guard cannot hide.
WEIGHT_NAME = re.compile(r'Mul(?!ti)|Blend|Share|Tolerance|Headroom|Decay|Weight|Prior|Factor|Ratio'
                          r'|Threshold|Min(?:Len|Words|Chars)')
# Two names the widened census brought in that WEIGHT_NAME would misfile. A duration is not a weight —
# 30.0 is thirty days, not a proportion — and `kRadixThreshold` is the point at which a sort switches
# algorithm, which apportions nothing. Both would have rendered in the parameter table as **unsourced**
# ranking parameters, which is a claim about them that is simply false. They are BOUNDARY caps below.
NOT_A_WEIGHT = re.compile(r'AgeDays|RadixThreshold')

def is_weight(name, val):
    if NOT_A_WEIGHT.search(name):
        return False
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
        for m in DECL.finditer(txt):
            if not KEY.search(m.group(1)):
                continue
            note = m.group(3).strip().lstrip('/ ').strip()
            caps.append((m.group(1), m.group(2), rel, txt[:m.start()].count('\n') + 1, note))
    return caps, disc

def partition(caps):
    real  = [c for c in caps if not is_weight(c[0], c[1])]
    weights = [c for c in caps if is_weight(c[0], c[1])]
    return real, weights

# ── the ANCHOR column ───────────────────────────────────────────────────────────────────────────────
# A weight is judged by the eval that CHOSE it, so the one thing this table must record about each one
# is whether such an eval exists. The anchor is read out of the constant's OWN trailing comment — the
# only place that can be right, because it moves with the constant — and anything that does not cite a
# measurement renders as the literal word "unsourced". That word is the point of the column. A row
# admitting it is unsourced is honest and actionable; a row pointing at a section that does not exist
# is worse than either, so validate() below refuses to write the document when it finds one.
ANCHOR = re.compile(r'(?:docs/)?EVALS\.md\s*(§\s*[0-9][0-9A-Za-z.]*)|(?:EVALS\.md)\s+([A-Za-z][\w -]{2,40})')

def anchor_of(note):
    m = ANCHOR.search(note or '')
    if not m:
        return None
    return 'EVALS.md ' + (m.group(1) or m.group(2)).replace(' ', '')

def validate_anchors(weights, evals_text):
    """A cited anchor that docs/EVALS.md does not contain is a dangling promise wearing a citation."""
    bad = []
    for n, v, rel, ln, note in weights:
        a = anchor_of(note)
        if a and a.split(' ', 1)[1] not in evals_text.replace(' ', ''):
            bad.append('%s (%s:%d) cites "%s", which docs/EVALS.md does not contain' % (n, rel, ln, a))
    return bad

# ── the INDEXING / OUTPUT column ────────────────────────────────────────────────────────────────────
# See docs/limits_classes.tsv for the taxonomy and for why it is a sidecar rather than an inline tag.
def read_classes(path):
    out = {}
    if not path.exists():
        return out
    for i, line in enumerate(path.read_text().splitlines(), 1):
        if not line.strip() or line.lstrip().startswith('#'):
            continue
        parts = line.split('\t')
        if len(parts) != 2 or parts[1].strip() not in ('INDEXING', 'OUTPUT', 'BOUNDARY'):
            sys.exit('limits_build: %s:%d is not "<capName>\\t(INDEXING|OUTPUT|BOUNDARY)": %r' % (path, i, line))
        out[parts[0].strip()] = parts[1].strip()
    return out

def validate_classes(classes, caps):
    """Every row must name a cap that still exists. A sidecar keyed by name rots exactly this way, and
    a stale row is a classification silently applied to nothing."""
    live = {c[0] for c in caps}
    return sorted(set(classes) - live)

# ── pinned by what a cap IS, never by the line it sits on ───────────────────────────────────────────
# This table used to carry each cap's LINE. A line is where a cap happens to sit, not a claim about it,
# and pinning it made the document stale on every edit ABOVE a cap: a rewritten comment, a deleted
# helper. On 2026-09-10 PRs #115, #116 and #117 all went red on test/limitstablecheck.sh (B) for nothing
# else — each of #117's six failed CI jobs was `fail=1 limitstablecheck.sh`, caused only by
# kPrDefaultBudgetTokens moving from line 452 of src/prcontext.h to 431 after an unrelated deletion — and
# because every src/ PR cut from one main pins the same lines, each landing re-staled the next. A row is
# now keyed by what --check SHOULD be strict about: file, name, value, class and note, beside its file's
# disclosure vocabulary. docs/TUNING.md made the same call for the same reason (bench/capsweep render()).
# The line survives only where it is read at once and never committed: the validate_anchors() refusal.
#
# Without a line, one file declaring the same name, value and note twice (two namespaces, two function
# bodies) would render two indistinguishable rows. They collapse into ONE row marked ×N — never into a
# silent drop of the duplicate, because a multiplicity is part of the cap set and deleting one of the two
# must still make --check fail (limitstablecheck arm J).
def pinned(cells):
    """Each distinct rendered row with the number of declarations that render it, in content order — never
    source order, which is the line by another name."""
    return sorted(collections.Counter(cells).items())

def times(k):
    return ' ×%d' % k if k > 1 else ''

def render(caps, disc, classes):
    out = []
    w = out.append
    w('# Limits\n')
    w('**Generated — do not edit.** `python3 docs/limits_build.py` writes this file and')
    w('`test/limitstablecheck.sh` fails if it drifts from `src/`.\n')
    w('Every compile-time cap in `src/`, what it bounds, and whether its file discloses a truncation when')
    w('it fires. A cap is a **routing decision**: it decides what an agent can and cannot find. Set one')
    w('where the pathological tail is, never near the typical case — and when it fires, say so')
    w('(`*_capped="1"` with a `*_total=`), because a silent cut reads to the caller as "none exists".\n')
    w('A row is pinned by what a cap IS — its file, name, value, class and note — never by the line it sits')
    w('on, so a comment rewritten or a helper deleted above a cap changes no row here and cannot stale this')
    w('document. To reach a declaration, search its file for the name (`grep -n <name> <file>`, or')
    w('`ripwire . --grep=<name>`). A file that declares the same name, value and note more than once shows')
    w('it once, marked `×N`.\n')
    allcaps = caps
    caps, weights = partition(caps)
    silent = [c for c in caps if not disc.get(c[2])]
    w('| total caps | files | caps whose file discloses | caps whose file discloses NOTHING |')
    w('| --- | --- | --- | --- |')
    w('| %d | %d | %d | **%d** |\n' % (len(caps), len({c[2] for c in caps}),
                                       len(caps) - len(silent), len(silent)))
    w('Plus %d ranking and apportionment parameters, in their own table below: they are not caps, they' % len(weights))
    w('are not counted as caps, and %d + %d is the %d constants this generator parses out of `src/`.\n'
      % (len(caps), len(weights), len(allcaps)))
    ix = sum(1 for c in caps if classes.get(c[0]) == 'INDEXING')
    op = sum(1 for c in caps if classes.get(c[0]) == 'OUTPUT')
    bd = sum(1 for c in caps if classes.get(c[0]) == 'BOUNDARY')
    w('## INDEXING, OUTPUT or BOUNDARY — which half of the answer a cap bounds\n')
    w('**INDEXING** caps bound what can EVER be found. A silent one is unrecoverable by the caller: no')
    w('flag, no budget, no second call gets the answer back, and the output reads as "none exists".')
    w('**OUTPUT** caps bound what is SHOWN from what was found; a silent one is still a defect, but a')
    w('`--detail`, a page or a follow-up call can recover the answer. The two are not the same severity')
    w('and a single table that does not distinguish them invites fixing the cheap one first.\n')
    w('**BOUNDARY** is the third answer and it is not a cap at all — it is the one the census kept')
    w('getting wrong. `kUnitSizeLowRiskMax = 15` decides which SIDE of a rule a unit falls on ("15 lines')
    w('or fewer is low-risk"); `kMaxNameLen = 96` decides that a 97-character backticked token is a')
    w('sentence rather than an identifier; `kMaxPartitions = 16` bounds a hand-written `--partition=N`.')
    w('None of them truncates anything, so none can be judged by `shown=`/`total=` and none should carry')
    w('a disclosure — labelling them OUTPUT would ask for a `capped="1"` that could never honestly fire.')
    w('The distinction was named in review on #108 and the rows below now carry it.\n')
    w('The `class` column below carries that answer where it is known. **%d of %d caps are classified'
      % (ix + op + bd, len(caps)))
    w('(%d INDEXING, %d OUTPUT, %d BOUNDARY); the remaining %d render `—`, which means NOT YET'
      % (ix, op, bd, len(caps) - ix - op - bd))
    w('CLASSIFIED — never "neither".** Classifications live in `docs/limits_classes.tsv`, a sidecar with')
    w('a known expiry:')
    w('the tag belongs on the declaration itself, and this file exists only because the round that')
    w('produced the taxonomy could not touch `src/`. `test/limitstablecheck.sh` fails if a row there')
    w('names a cap that no longer exists.\n')
    w('## Refuted by re-derivation — do not re-propose\n')
    w('A cap that shortens an answer is measured by `docs/TUNING.md`. A cap that could make an answer')
    w('WRONG needs a different instrument: recompute the value without the bound and compare. Two were')
    w('taken through it on 2026-09-10 and both came back inert, recorded here so the next reader does')
    w('not spend the afternoon again.\n')
    w('- **`kSliceRdMaxIter` = 64 cannot fire.** 4,528 reaching-definition fixpoints were observed and')
    w('  the maximum iteration count reached was **1**. The bound is 63 iterations above anything real.')
    w('- **The `src/ingest_metrics.h` parameter-walk depth of 12 fires 97 times and changes nothing.**')
    w('  Output is byte-identical at 12, at 64 and at 256: the frames past depth 12 carry no parameter.\n')
    w('The second one is the transferable lesson. "The bound trips 97 times" reads like a finding and is')
    w('not one — a fidelity cap is judged by whether re-derivation changes the ANSWER, never by whether')
    w('the bound trips. A tripping counter is a hypothesis; the re-derivation is the measurement.\n')
    if weights:
        w = out.append
        w('## Not caps — ranking and apportionment parameters\n')
        w('These decide **how** something is weighted or apportioned, not **how many** of it survive, so')
        w('they are judged by a different instrument: an eval that sets the value, not a `shown=`/`total=`')
        w('pair. A value of `0.90` cannot be a row count. Each needs a `docs/EVALS.md` anchor naming the')
        w('measurement that chose it; listing them beside truncation caps invites tuning them by intuition.\n')
        w('The **anchor** column is read from each constant\'s own trailing comment. **unsourced** means the')
        w('comment cites no measurement — the value came from somewhere, but not from anything a reader can')
        w('check. All %d read unsourced today, which is the finding, not an omission: `kSpecificMinLen` has'
          % len(weights))
        w('the widest measured blast radius of any constant in this tree (14 invocations across 9 verbs, per')
        w('`docs/TUNING.md`) and its entire stated provenance is the parenthetical `(aider\'s)`. Sourcing them')
        w('means editing `src/`; a cited anchor that `docs/EVALS.md` does not contain makes this generator')
        w('refuse to write, so the column cannot be satisfied by pointing at nothing.\n')
        w('| constant | value | site | anchor | note |')
        w('| --- | --- | --- | --- | --- |')
        cells = ((n, v, rel, '`%s`' % anchor_of(note) if anchor_of(note) else '**unsourced**',
                  note.replace('|', '\\|')[:130] or '—') for n, v, rel, _, note in weights)
        for (n, v, rel, anchor, note), k in pinned(cells):
            w('| `%s`%s | `%s` | `%s` | %s | %s |' % (n, times(k), v, rel, anchor, note))
        w('')
    # The per-file tables get a `##` of their own. Without one, every `### `src/…`` heading was a child of the
    # last `##` written above it — the parameter section — so GitHub's outline and --grep's enclosing-section
    # attribution filed every cap in this document under "Not caps" (limitstablecheck arm K). It is written
    # unconditionally: with no parameters, the tables would fall under the refuted section instead.
    w('## Caps, by file\n')
    w('One table for each of the %d files that declare a cap — the %d caps counted above, and no parameter.\n'
      % (len({c[2] for c in caps}), len(caps)))
    for rel in sorted({c[2] for c in caps}):
        rows = [c for c in caps if c[2] == rel]
        d = ', '.join('`%s_capped`' % a for a in sorted(disc.get(rel, []))) or '**none**'
        w('### `%s`\n' % rel)
        w('Discloses: %s\n' % d)
        w('| constant | value | class | note |')
        w('| --- | --- | --- | --- |')
        cells = ((n, v, classes.get(n, '—'), note.replace('|', '\\|')[:150] or '—') for n, v, _, _, note in rows)
        for (n, v, cls, note), k in pinned(cells):
            w('| `%s`%s | `%s` | %s | %s |' % (n, times(k), v, cls, note))
        w('')
    return '\n'.join(out) + '\n'

def rel(p):
    """Repo-relative when possible: a gate's PASS line lands in a public CI log, and an operator's
    absolute path in it is machine layout nobody asked to publish."""
    try:    return str(pathlib.Path(p).resolve().relative_to(ROOT))
    except ValueError: return str(p)

ap = argparse.ArgumentParser()
ap.add_argument('--out', default=str(ROOT / 'docs' / 'LIMITS.md'))
ap.add_argument('--check', action='store_true')
# --root retargets the scan at a synthetic tree. It exists so test/limitstablecheck.sh can prove this
# generator CAN go red on a real source change without editing the tree it is gating — a probe copy
# dropped into src/ would perturb the very crawl other gates measure.
ap.add_argument('--root', default=None)
# --classes retargets the INDEXING/OUTPUT sidecar, so the gate can feed a mutated copy without editing
# the committed one. Same reason as --root: a gate that has to modify the tree to prove it can go red
# perturbs the population every other gate measures.
ap.add_argument('--classes', default=None)
a = ap.parse_args()
if a.root:
    ROOT = pathlib.Path(a.root).resolve()
caps, disc = scan()
if not caps:
    sys.exit('limits_build: parsed 0 caps — the declaration shape changed')
classes = read_classes(pathlib.Path(a.classes) if a.classes else ROOT / 'docs' / 'limits_classes.tsv')

# Both validations run on WRITE as well as on --check. A generator that only refuses under the gate is
# a generator that writes a broken document every time a human runs it by hand.
stale = validate_classes(classes, caps)
if stale:
    sys.exit('limits_build: %d row(s) in limits_classes.tsv name a cap that no longer exists in src/ —\n'
             '  %s\n  Retire the row, or fix the name.' % (len(stale), '\n  '.join(stale)))
_evals = (ROOT / 'docs' / 'EVALS.md')
_txt = _evals.read_text(errors='replace') if _evals.exists() else ''
bad = validate_anchors(partition(caps)[1], _txt)
if bad:
    sys.exit('limits_build: %d parameter(s) cite an anchor docs/EVALS.md does not contain —\n  %s\n'
             '  A row pointing at nothing is worse than one admitting it is unsourced.'
             % (len(bad), '\n  '.join(bad)))

body = render(caps, disc, classes)
_real, _wts = partition(caps)
if a.check:
    cur = pathlib.Path(a.out).read_text() if pathlib.Path(a.out).exists() else ''
    if cur != body:
        sys.exit('limits_build: %s is STALE — run: python3 docs/limits_build.py' % rel(a.out))
    print('limits_build: %s matches src/ (%d caps, %d parameters, %d classified)'
          % (rel(a.out), len(_real), len(_wts), sum(1 for c in _real if c[0] in classes)))
else:
    pathlib.Path(a.out).write_text(body)
    print('limits_build: wrote %s — %d caps (%d silent), %d parameters, %d caps classified' %
          (rel(a.out), len(_real), sum(1 for c in _real if not disc.get(c[2])), len(_wts),
           sum(1 for c in _real if c[0] in classes)))
