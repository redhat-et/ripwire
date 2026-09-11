#!/usr/bin/env python3
"""capsweep — measure what every compile-time cap in src/ actually costs, per verb.

WHY. docs/LIMITS.md says a cap EXISTS. It cannot say what the cap DOES: which verbs it reaches, how
many bytes it buys, what it hides. That gap is not academic — kMaxExpandSibs sat at 8 justified by
"~3.5 KB per --pack-task bundle", and --pack-task emits no sibs= at all. One measurement would have
caught it; nothing measured it, because measuring meant a rebuild per value.

HOW, AND WHY IT NEVER TOUCHES src/. This copies the tree to a scratch dir and rewrites the cap
declarations there to read an env var, so ONE build sweeps every value. Production source keeps its
`constexpr` and is never patched — a tunable production build would be a G3/G5 regression, and a probe
file dropped into src/ perturbs the crawl other gates measure.

  prepare  copy + patch + build the tunable binary (caps that must stay constexpr are detected by
           compiling and excluded, iteratively, so a cap used as an array bound cannot break the sweep)
  screen   corpus at BASELINE vs ALL-CAPS-BUMPED -> the commands that are cap-sensitive at all.
           This is the step that makes it tractable: 120 caps x 195 commands is 23,400 runs, but most
           commands respond to no cap, so the second phase only pays for the ones that move.
  sweep    per cap x sensitive command, a value ladder -> bytes at each value
  emit     markdown tables -> docs/TUNING.md  (--check compares instead of writing; the gate runs that)

Two phases exist only so test/capsweepcheck.sh can prove the two load-bearing mechanisms WITHOUT a
build — a gate that cannot go red is worse than no gate:

  patch        run the cap patcher against --root SOMETREE and stop. The gate hands it a synthetic
               tree and reads the rewritten line.
  check-corpus run the corpus-cleanliness assertion against --corpus SOMEDIR and stop. The gate hands
               it a synthetic corpus with bench/capsweep/ inside and asserts the refusal.

Usage: python3 bench/capsweep/capsweep.py prepare|screen|sweep|emit [--scratch DIR] [--jobs N]
       python3 bench/capsweep/capsweep.py emit [--data bench/capsweep] [--out docs/TUNING.md] [--check]
       python3 bench/capsweep/capsweep.py patch --root TREE
       python3 bench/capsweep/capsweep.py check-corpus --corpus DIR

WHERE THE MEASUREMENTS LIVE, AND WHY THEY ARE TSV. `prepare`/`screen`/`sweep` write their records into
--scratch, never into the repo and never into the frozen corpus. Publishing a round means copying
tunable.tsv / screen.tsv / sweep.tsv into bench/capsweep/ and running `emit`; from then on docs/TUNING.md
is a pure function of those three files plus the CAP CENSUS read live out of src/, which is what makes the
gate's byte-for-byte arm a real check rather than a round trip through the artifact it is checking. Drop
tunable.tsv's `corpus` row on the way in — it names a --scratch directory, and an operator's filesystem
layout is not a measurement.

The records are TSV and never json because ripwire INDEXES `.json` as config keys (src/ingest_crawl.h's
extension table) while `.tsv` is unindexed prose (src/docparse.h's kUnindexedProseExts, next to `.txt`) —
a harness must not enter the index it measures. That is measured, not hypothetical: as json these three
files dragged the README's own headline example, `--for="incremental cache invalidation"`, from
confidence="high" margin_pct="22" down to confidence="low" margin_pct="0" on this very repo, and put
bench/capsweep/sweep.json into the answer to a query about a cap. assert_corpus_clean below keeps the
harness out of the frozen CORPUS; the file format keeps it out of the INDEX. Same rule, two surfaces.
"""
import argparse, os, pathlib, re, shlex, shutil, subprocess, sys, collections

HERE  = pathlib.Path(__file__).resolve().parent
REPO  = HERE.parent.parent
DECL  = re.compile(r'^(\s*inline\s+)constexpr(\s+)([\w:<>, ]*?)(\s+)(k[A-Z][A-Za-z0-9_]*)(\s*=\s*)([0-9][0-9_.eE+-]*)(\s*;)(.*)$')
KEY   = re.compile(r'Max|Cap|Limit|Top|Budget|Ceil|Threshold|Rows|Len|Depth|Width')
SHIM  = """
// ── capsweep shim (SCRATCH BUILD ONLY — never in src/) ───────────────────────────────────────────
// Guarded, not `#pragma once`-protected: the shim is injected into SEVERAL headers, so a translation
// unit that includes two patched headers would otherwise redefine it. Cost one build cycle.
#ifndef RWCAPSWEEP_SHIM_H
#define RWCAPSWEEP_SHIM_H
#include <cstdlib>
namespace rwcapsweep {
inline long envOr( const char* k, long d )
{ const char* v = std::getenv( k ); return v ? std::atol( v ) : d; }
inline double envOrD( const char* k, double d )
{ const char* v = std::getenv( k ); return v ? std::atof( v ) : d; }
}
#endif
"""

def caps_in(root):
    out = []
    for p in sorted(root.joinpath('src').rglob('*.h')) + sorted(root.joinpath('src').rglob('*.cpp')):
        for i, line in enumerate(p.read_text(errors='replace').splitlines(), 1):
            m = DECL.match(line)
            if m and KEY.search(m.group(5)):
                out.append((m.group(5), m.group(7), str(p.relative_to(root)), i))
    return out

def patch(root, exclude):
    """Rewrite cap decls to env-readable. Returns the names actually made tunable."""
    made = []
    for p in sorted(root.joinpath('src').rglob('*.h')) + sorted(root.joinpath('src').rglob('*.cpp')):
        lines = p.read_text(errors='replace').splitlines(keepends=False)
        changed = False
        for idx, line in enumerate(lines):
            m = DECL.match(line)
            if not m or not KEY.search(m.group(5)) or m.group(5) in exclude:
                continue
            name, val, ty = m.group(5), m.group(7), m.group(3).strip()
            fn = 'envOrD' if ('.' in val or 'e' in val.lower()) else 'envOr'
            cast = ty if ty else 'auto'
            lines[idx] = ('%sconst%s%s%s%s%s static_cast<%s>( rwcapsweep::%s( "RWCAP_%s", %s ) )%s%s'
                          % (m.group(1), m.group(2), m.group(3), m.group(4), m.group(5), m.group(6),
                             cast, fn, name, val, m.group(8), m.group(9)))
            changed = True; made.append(name)
        if changed:
            txt = '\n'.join(lines) + '\n'
            if 'rwcapsweep' in txt and 'namespace rwcapsweep' not in txt:
                txt = txt.replace('#pragma once', '#pragma once\n' + SHIM, 1) if '#pragma once' in txt else SHIM + txt
            p.write_text(txt)
    return made

def build(root, jobs):
    # Configure output is part of the log. Swallowing it cost a cycle: configure failed on a missing
    # queries/ dir and the only symptom was make saying "No rule to make target `Makefile'".
    c = subprocess.run(['cmake', '-S', str(root), '-B', str(root / 'build')], capture_output=True, text=True)
    if c.returncode != 0:
        return c.returncode, '=== cmake configure FAILED ===\n' + c.stdout + c.stderr
    r = subprocess.run(['cmake', '--build', str(root / 'build'), '-j', str(jobs)], capture_output=True, text=True)
    return r.returncode, c.stdout + c.stderr + r.stdout + r.stderr

def offenders(log, known):
    """Cap names the compiler rejected as non-constant — they must stay constexpr."""
    bad = set()
    for n in known:
        if re.search(r'\b%s\b' % re.escape(n), log) and re.search(
                r'constant|constexpr|non-type|array bound|case value|static_assert|enumerator', log):
            bad.add(n)
    return bad

def read_corpus():
    """One real invocation per line; `#` lines are provenance, not commands."""
    return [l for l in (HERE / 'corpus.txt').read_text().splitlines()
            if l.strip() and not l.lstrip().startswith('#')]

def run_corpus(binary, root, corpus, env, timeout=120):
    """Run each corpus line and return its stdout SIZE.

    Two things here were learned the hard way:
      - the corpus lines already carry their own root ("." where the verb takes one), so this must NOT
        prepend one; doing so passed the root twice and every command refused;
      - stdin is DEVNULL, because `--from-trace=-` reads stdin and otherwise blocks until the timeout.

    $VARS in a corpus line are expanded from the environment. The corpus was harvested from a recorded
    showcase run whose scratch directory was a machine-local macOS temp path; committing that literal
    would have pinned the corpus to one laptop and put somebody's filesystem layout in a public file, so
    those occurrences are spelled $RIPWIRE_CAPSWEEP_TMP and bound here.
    """
    e = dict(os.environ)
    e.setdefault('RIPWIRE_CAPSWEEP_TMP', str(pathlib.Path(root).parent / 'corpus-tmp'))
    e.update(env)
    os.makedirs(e['RIPWIRE_CAPSWEEP_TMP'], exist_ok=True)
    out = {}
    for line in corpus:
        try:
            # shlex, not line.split(): 37 of the 195 corpus rows carry a quoted multi-word value
            # (--for="cache invalidation", --exemplar="format byte sizes for humans"). split() hands
            # the binary --for="cache with a literal quote plus `invalidation` as a positional root,
            # which exits 1 with `root path does not exist` and 0 bytes of stdout -- under EVERY cap.
            # A row that measures 0 both sides has a delta of 0 and silently leaves the cap-sensitive
            # set, so those 19% were not measuring the caps they were written to exercise. Verified
            # against the real corpus: shlex.split gives exit 0 / 2530 B where split() gives exit 1 / 0 B.
            argv = [os.path.expandvars(w) for w in shlex.split(line)]
            r = subprocess.run([str(binary)] + argv + ['--no-cache'], cwd=str(root),
                               capture_output=True, stdin=subprocess.DEVNULL, env=e, timeout=timeout)
            out[line] = len(r.stdout)
        except subprocess.TimeoutExpired:
            out[line] = None          # recorded, never silently dropped
    return out

# ── the records: TSV, because the harness must not enter the index it measures ───────────────────────
# The corpus-freeze assertion below keeps this harness out of the TREE being measured. It says nothing
# about the FORMAT the harness writes in, and that gap had teeth: ripwire indexes `.json` as config keys
# (src/ingest_crawl.h's extension table), so three committed json records became indexed symbols in the
# repo's own map. Measured on this branch, `--for="incremental cache invalidation"` — the README's
# headline example — answered confidence="low" margin_pct="0" with them present and confidence="high"
# margin_pct="22" without. `.tsv` sits in src/docparse.h's kUnindexedProseExts beside `.txt`, which is why
# corpus.txt never polluted anything, and it is why these files are TSV.
#
# No quoting scheme, and none is needed: every field is an integer, a cap name, a src/ path or a corpus
# invocation. write_records REFUSES a field carrying a tab or a newline rather than mangling it quietly.
kRecordNote = ( 'TSV not json: ripwire indexes .json as config keys (src/ingest_crawl.h) while .tsv is '
                'unindexed prose (src/docparse.h kUnindexedProseExts) — a harness must not enter the '
                'index it measures' )
kNullField  = '-'          # a timed-out invocation is RECORDED as this, never dropped and never zeroed

def fmt_bytes(v):
    return kNullField if v is None else str(int(v))

def parse_bytes(s, where):
    if s == kNullField:
        return None
    try:    return int(s)
    except ValueError: sys.exit('capsweep: %s: %r is not a byte count' % (where, s))

def write_records(path, what, columns, rows, measured_at):
    """One `#` provenance line naming the columns and the measured commit, then tab-separated data."""
    for r in rows:
        for f in r:
            if '\t' in str(f) or '\n' in str(f):
                sys.exit('capsweep: field %r holds a tab or newline — it cannot be a TSV record' % (f,))
    head = '# capsweep %s — columns: %s — measured_at=%s — %s' % (
        what, ' / '.join(columns), measured_at or 'unrecorded', kRecordNote)
    path.write_text('\n'.join([head] + ['\t'.join(str(f) for f in r) for r in rows]) + '\n')

def read_records(path, ncol):
    """(measured_at, rows). `#` lines are provenance, not data — the rule corpus.txt already follows.

    A row of the wrong width is fatal rather than padded: these files are a measurement of record, and a
    silently short row would publish a byte count against the wrong invocation.
    """
    path = pathlib.Path(path)
    if not path.exists():
        sys.exit('capsweep: %s is missing (%s)' % (rel(path), kRecordNote))
    at, rows = '', []
    for i, line in enumerate(path.read_text().splitlines(), 1):
        if line.startswith('#'):
            m = re.search(r'measured_at=(\S+)', line)
            if m: at = m.group(1)
        elif line.strip():
            f = line.split('\t')
            if len(f) != ncol:
                sys.exit('capsweep: %s line %d has %d field(s), expected %d' % (rel(path), i, len(f), ncol))
            rows.append(f)
    return at, rows

kTunableCols = ('kind', 'value')
kScreenCols  = ('baseline_bytes', 'all_bumped_bytes', 'sensitive', 'invocation')
kSweepCols   = ('cap', 'value', 'probe', 'site', 'default_bytes', 'probe_bytes', 'invocation')

def write_tunable(path, made, exclude, measured_at, corpus=None):
    rows  = [('tunable', n) for n in sorted(set(made))]
    rows += [('constexpr_only', n) for n in sorted(set(exclude))]
    if corpus is not None:
        rows.append(('corpus', str(corpus)))
    write_records(path, 'tunable', kTunableCols, rows, measured_at)

def read_tunable(path):
    at, rows = read_records(path, len(kTunableCols))
    meta = {'tunable': [], 'constexpr_only': [], 'measured_at': at}
    for kind, val in rows:
        if kind in ('tunable', 'constexpr_only'):  meta[kind].append(val)
        elif kind == 'corpus':                     meta['corpus'] = val
        else: sys.exit('capsweep: %s: unknown kind %r' % (rel(path), kind))
    return meta

def write_screen(path, corpus, base, allb, sens, measured_at):
    hot  = set(sens)
    rows = [(fmt_bytes(base.get(c)), fmt_bytes(allb.get(c)), 1 if c in hot else 0, c) for c in corpus]
    write_records(path, 'screen', kScreenCols, rows, measured_at)

def read_screen(path):
    at, rows = read_records(path, len(kScreenCols))
    base, allb, sens = {}, {}, []
    for b, g, s, cmd in rows:
        base[cmd] = parse_bytes(b, rel(path))
        allb[cmd] = parse_bytes(g, rel(path))
        if s == '1': sens.append(cmd)
    return {'baseline': base, 'all_bumped': allb, 'sensitive': sens}

def write_sweep(path, sweep, measured_at):
    rows = [(cap, sweep[cap]['value'], sweep[cap]['probe'], sweep[cap]['site'], b, g, cmd)
            for cap in sorted(sweep) for cmd, (b, g) in sweep[cap]['moved'].items()]
    write_records(path, 'sweep', kSweepCols, rows, measured_at)

def read_sweep(path):
    at, rows = read_records(path, len(kSweepCols))
    out = {}
    for cap, value, probe, site, b, g, cmd in rows:
        e = out.setdefault(cap, {'value': int(value), 'probe': int(probe), 'site': site, 'moved': {}})
        e['moved'][cmd] = [parse_bytes(b, rel(path)), parse_bytes(g, rel(path))]
    return out

# ── the assertion that makes every number in this file mean something ────────────────────────────────
HARNESS_IN_CORPUS = ('bench/capsweep',)

def assert_corpus_clean(corpus):
    """Refuse to measure a corpus that contains this harness. THE trap this instrument exists past.

    The first sweep measured the live worktree — which holds this harness and the records it writes. The
    bench/capsweep/ dir grew between the baseline pass and the probe passes, so ~18-21 verbs "responded"
    to every cap, including caps that touch nothing those verbs read. Systematic, not random, and it
    read exactly like signal: a plausible number, in the right units, for every row.

    It is a live assertion and not a comment because the failure is INVISIBLE in the output. Nothing in
    a byte count says which bytes came from the subject and which from the observer.

    Note the order in freeze_corpus: `git archive HEAD` is tracked-files-only, and this harness is now
    TRACKED, so the archive ships it. The prune is deliberate and this assertion is the proof the prune
    actually happened — plus the guard for any other harness state that finds its way in later.
    """
    corpus = pathlib.Path(corpus)
    if not corpus.is_dir():
        sys.exit('capsweep: corpus %s is not a directory' % corpus)
    inside = [d for d in HARNESS_IN_CORPUS if (corpus / d).exists()]
    if inside:
        sys.exit('capsweep: REFUSING to measure a corpus that contains the harness measuring it: %s\n'
                 '          (this is the 18-21-verbs-move artifact; see assert_corpus_clean)'
                 % ', '.join(str(corpus / d) for d in inside))
    return corpus

# ── phases ──────────────────────────────────────────────────────────────────────────────────────────
def freeze_corpus(scratch):
    """A corpus that CANNOT move while we measure it. Tracked files only, frozen at a commit."""
    corpus = scratch / 'corpus-tree'
    if corpus.exists(): shutil.rmtree(corpus)
    corpus.mkdir(parents=True)
    tar = subprocess.run(['git', '-C', str(REPO), 'archive', 'HEAD'], capture_output=True)
    if tar.returncode != 0: sys.exit('capsweep: git archive HEAD failed')
    subprocess.run(['tar', '-x', '-C', str(corpus)], input=tar.stdout, check=True)
    for d in HARNESS_IN_CORPUS:                 # the harness is tracked now — prune it back out
        if (corpus / d).exists(): shutil.rmtree(corpus / d)
    return assert_corpus_clean(corpus)

SCRATCH_STAMP = '.capsweep-scratch'   # written into every scratch dir we create; required before we delete one

def assert_deletable_scratch(scratch):
    """--scratch takes an arbitrary path and cmd_prepare deletes it recursively. A typo (--scratch ~,
    or the repo itself) is unbounded and irreversible, so refuse to delete anything this harness did
    not create. An existing directory must carry our stamp; a fresh path is fine."""
    if not scratch.exists():
        return
    if not scratch.is_dir():
        sys.exit('capsweep: --scratch %s exists and is not a directory — refusing to delete it' % scratch)
    if not (scratch / SCRATCH_STAMP).exists():
        sys.exit('capsweep: --scratch %s was not created by capsweep (no %s) — refusing to delete it.\n'
                 '          Remove it yourself, or point --scratch at a new path.' % (scratch, SCRATCH_STAMP))

def cmd_prepare(a):
    scratch = pathlib.Path(a.scratch)
    assert_deletable_scratch(scratch)
    if scratch.exists(): shutil.rmtree(scratch)
    scratch.mkdir(parents=True)
    (scratch / SCRATCH_STAMP).write_text('capsweep scratch — safe to delete\n')
    # Copy EVERYTHING the build might read. A curated list looked tidy and cost a cycle: CMakeLists.txt
    # globs queries/<lang>/tags.scm, which was not on it, and cmake failed at configure time.
    SKIP = {'.git', 'build', 'asan', 'tsan', 'node_modules', '.cache'}
    for s in REPO.iterdir():
        if s.name in SKIP: continue
        d = scratch / s.name
        if s.is_dir():    shutil.copytree(s, d, symlinks=True, ignore=shutil.ignore_patterns(*SKIP))
        elif s.is_file(): shutil.copy2(s, d)
    known = [c[0] for c in caps_in(scratch)]
    print('caps seen: %d' % len(known))
    exclude, made = set(), []
    for attempt in range(1, 7):
        # restore a clean src/ before each patch attempt
        shutil.rmtree(scratch / 'src'); shutil.copytree(REPO / 'src', scratch / 'src', symlinks=True)
        made = patch(scratch, exclude)
        rc, log = build(scratch, a.jobs)
        if rc == 0:
            print('attempt %d: BUILD OK — %d caps tunable, %d kept constexpr' % (attempt, len(made), len(exclude)))
            break
        new = offenders(log, known) - exclude
        if not new:
            pathlib.Path(a.scratch + '/build.log').write_text(log)
            sys.exit('capsweep: build failed and no new offender identified — see %s/build.log' % a.scratch)
        print('attempt %d: build failed; %d cap(s) must stay constexpr: %s'
              % (attempt, len(new), ', '.join(sorted(new))))
        exclude |= new
    else:
        sys.exit('capsweep: could not converge on a buildable tunable tree')
    corpus = freeze_corpus(scratch)
    print('frozen corpus at %s (tracked files only, from git archive HEAD)' % corpus)
    ref = subprocess.run(['git', '-C', str(REPO), 'rev-parse', 'HEAD'], capture_output=True, text=True)
    out = pathlib.Path(a.scratch) / 'tunable.tsv'
    write_tunable(out, made, exclude, ref.stdout.strip(), corpus)
    print('wrote %s' % out)

def cmd_screen(a):
    scratch = pathlib.Path(a.scratch); binary = scratch / 'build' / 'ripwire'
    meta = read_tunable(scratch / 'tunable.tsv')
    corpus = read_corpus()
    croot = assert_corpus_clean(meta.get('corpus') or scratch / 'corpus-tree')   # re-checked per phase
    base = run_corpus(binary, croot, corpus, {})
    # RELATIVE bump, not a flat huge value: several of these are query/work budgets in the 10^5 range,
    # and slamming them all to 999999 makes the screen measure the machine rather than the cap.
    vals = {c[0]: c[1] for c in caps_in(REPO)}
    def bumped(n):
        try:    v = float(vals.get(n, '8'))
        except ValueError: v = 8.0
        return ('%g' % max(v * 8.0, v + 32.0)) if v == int(v) else ('%g' % min(v * 4.0, 1.0))
    bump = {('RWCAP_%s' % n): bumped(n) for n in meta['tunable']}
    allb = run_corpus(binary, croot, corpus, bump)
    # run_corpus records a timeout as None, on purpose ("recorded, never silently dropped"). A row
    # where exactly one arm timed out therefore DIFFERS and lands in `sens`, and the delta print below
    # would then subtract None. Keep it in the sensitive set -- a timeout under one arm and not the
    # other is real signal -- but let it carry the word TIMEOUT instead of crashing the screen.
    sens = sorted(c for c in corpus if base.get(c) != allb.get(c))
    write_screen(scratch / 'screen.tsv', corpus, base, allb, sens, meta.get('measured_at'))
    print('corpus %d — cap-sensitive: %d (%.0f%%); the other %d respond to NO cap'
          % (len(corpus), len(sens), 100.0*len(sens)/len(corpus), len(corpus)-len(sens)))
    for c in sens[:15]:
        if base.get(c) is None or allb.get(c) is None:
            print('  %8s   %s' % ('TIMEOUT', c[:88]))
        else:
            print('  %+8d B   %s' % (allb[c]-base[c], c[:88]))

def cmd_sweep(a):
    """Per cap: which of the sensitive commands actually respond to THIS cap, and by how much.

    Only the 59 cap-sensitive commands are used. The other 136 answered identically with every cap
    bumped at once, so no single cap can move them — running them per-cap would be 16,000 wasted runs.
    """
    scratch = pathlib.Path(a.scratch); binary = scratch / 'build' / 'ripwire'
    meta   = read_tunable(scratch / 'tunable.tsv')
    screen = read_screen(scratch / 'screen.tsv')
    sens, base = screen['sensitive'], screen['baseline']
    croot = assert_corpus_clean(meta.get('corpus') or scratch / 'corpus-tree')   # re-checked per phase
    vals = {c[0]: c[1] for c in caps_in(REPO)}
    sites = {c[0]: '%s:%d' % (c[2], c[3]) for c in caps_in(REPO)}
    out = {}
    for i, cap in enumerate(sorted(meta['tunable']), 1):
        try:    v = float(vals.get(cap, '8'))
        except ValueError: continue
        if v != int(v) or v <= 0:      # ladders only make sense for integral counts
            continue
        hi = '%d' % max(int(v) * 8, int(v) + 32)
        got = run_corpus(binary, croot, sens, {'RWCAP_%s' % cap: hi})
        moved = {c: (base[c], got[c]) for c in sens
                 if got.get(c) is not None and base.get(c) is not None and got[c] != base[c]}
        if moved:
            out[cap] = {'value': int(v), 'probe': int(hi), 'site': sites.get(cap, '?'), 'moved': moved}
        print('[%3d/%3d] %-34s %s' % (i, len(meta['tunable']), cap,
              ('%d invocation(s) move' % len(moved)) if moved else '-'), flush=True)
    write_sweep(scratch / 'sweep.tsv', out, meta.get('measured_at'))
    print('caps that move at least one verb: %d of %d tunable' % (len(out), len(meta['tunable'])))

kRowsPerCap = 12          # rows per cap table; a cap in a document ABOUT caps, so it discloses below

def render(sweep, meta, caps, disc):
    """docs/TUNING.md as a PURE FUNCTION of (frozen measurements, live cap census).

    Line numbers are deliberately absent. They belong to docs/LIMITS.md, which is regenerated against
    src/ on every change; carrying them here as well would make this doc drift on any edit ANYWHERE
    above a cap, which is churn that says nothing about the measurement. What DOES belong here — the
    cap's name, its value and its file — is re-read from src/ every run, so a retuned cap reds the gate.
    """
    names   = sorted({c[0] for c in caps})
    vals    = {c[0]: c[1] for c in caps}
    files   = {c[0]: c[2] for c in caps}
    tun, ce = meta['tunable'], meta['constexpr_only']
    L = []
    L.append('# Cap sensitivity — measured\n')
    L.append('**Generated — do not edit.** `python3 bench/capsweep/capsweep.py prepare|screen|sweep|emit`.\n')
    L.append('The measurements it is generated from live in `bench/capsweep/*.tsv` rather than json because')
    L.append('ripwire indexes `.json` as config keys while `.tsv` is unindexed prose (`kUnindexedProseExts` in')
    L.append('`src/docparse.h`) — a harness must not enter the index it measures.\n')
    L.append('What each compile-time cap actually COSTS, per verb. `docs/LIMITS.md` says a cap exists;')
    L.append('this says what it does. Measured by patching a SCRATCH copy of the tree so the caps read an')
    L.append('env var — production keeps its `constexpr` and is never patched — then running real')
    L.append('invocations at the default value and at a probe value. The tunable binary is byte-identical')
    L.append('to production at defaults; that control is what makes these numbers mean anything.\n')
    L.append('| cap declarations | distinct names | tunable | must stay `constexpr` | move >= 1 invocation | move nothing measurable |')
    L.append('| --- | --- | --- | --- | --- | --- |')
    L.append('| %d | %d | %d | %d | **%d** | %d |\n'
             % (len(caps), len(names), len(tun), len(ce), len(sweep), len(tun) - len(sweep)))
    dup = sorted(n for n in names if sum(1 for c in caps if c[0] == n) > 1)
    L.append('The first two columns are not the same number, and the gap is not a rounding: `src/` holds')
    L.append('**%d cap declarations** under **%d distinct names** (%s declared in more than one file). The'
             % (len(caps), len(names), ', '.join('`%s`' % n for n in dup) or 'no name'))
    L.append('sweep patches by NAME, so `%d + %d` accounts for the %d NAMES — not the %d declarations. Quoting'
             % (len(tun), len(ce), len(names), len(caps)))
    L.append('"%d of %d" would be wrong in both halves at once, which is exactly the shape of error a')
    L.append('generated table exists to prevent.\n')
    L[-2] = L[-2] % (len(tun) + 1, len(caps))
    L.append('## Read this ratio before the tables\n')
    L.append('**%d of %d tunable caps move any invocation at all. %d move nothing measurable.** That is the'
             % (len(sweep), len(tun), len(tun) - len(sweep)))
    L.append('finding, and it says what NOT to do: this is not a %d-cap audit. Most of these constants are' % len(caps))
    L.append('inert on real invocations and should be left alone. The work worth doing is the small set below,')
    L.append('plus the caps that fire SILENTLY — a cap that bites without disclosing is a defect independent of')
    L.append('whether its value is right, and that fix is both cheaper and larger than any retuning.\n')
    L.append('## What this instrument CANNOT see\n')
    L.append('This measures output **size**. A cap that makes an answer WRONG rather than shorter is invisible')
    L.append('to it: a truncated complexity walk emits a `cx=` that is simply too low, a truncated parameter')
    L.append('walk emits an arity that is simply wrong, and both produce bytes that look perfectly fine. A')
    L.append('wrong number with `capped="1"` beside it is still a wrong number. That class needs')
    L.append('**re-derivation** as its instrument — recompute the value without the bound and compare — and it')
    L.append('cannot be folded into this sweep. Do not read a cap\'s absence from these tables as safety.\n')
    L.append('Two caps have been through that second instrument. Both came back inert, and `docs/LIMITS.md`')
    L.append('records them under "Refuted by re-derivation" so neither is proposed again.\n')
    L.append('## Provenance\n')
    L.append('Sizes were measured against `%s`, on a corpus frozen with `git archive HEAD` at that commit.'
             % (meta.get('measured_at') or 'an unrecorded commit')[:8])
    L.append('The cap names, values and files below are re-read from `src/` on every run of `emit`, so a')
    L.append('retuned or renamed cap makes `test/capsweepcheck.sh` fail rather than leaving a stale number')
    L.append('standing. The **byte deltas are frozen** and do not re-measure themselves: they are only as')
    L.append('current as the commit above, and a change to what a verb emits can age them without any cap')
    L.append('moving. Re-run `prepare|screen|sweep` to refresh them.\n')
    for cap in sorted(sweep, key=lambda c: (-len(sweep[c]['moved']), c)):
        e = sweep[cap]
        f = files.get(cap, e['site'].split(':')[0])
        L.append('### `%s` = `%s`\n' % (cap, vals.get(cap, e['value'])))
        L.append('`%s` — discloses: %s — probe value `%s` — **%d verb(s) respond**\n'
                 % (f, ', '.join('`%s_capped`' % x for x in sorted(disc.get(f, []))) or '**none**',
                    e['probe'], len(e['moved'])))
        L.append('| invocation | default | at probe | delta |')
        L.append('| --- | --- | --- | --- |')
        rows = sorted(e['moved'].items(), key=lambda kv: (-abs(kv[1][1]-kv[1][0]), kv[0]))
        for cmd, (b, g) in rows[:kRowsPerCap]:
            L.append('| `%s` | %d B | %d B | %+d B |' % (cmd[:70], b, g, g - b))
        L.append('')
        if len(rows) > kRowsPerCap:                 # this table has a cap of its own; say so
            L.append('*%d of %d responding invocations shown, largest |delta| first.*\n'
                     % (kRowsPerCap, len(rows)))
    return '\n'.join(L) + '\n'

def rel(p):
    """Repo-relative when possible. A gate's PASS line is committed evidence in CI logs; an operator's
    absolute path in it is machine layout nobody asked to publish."""
    try:    return str(pathlib.Path(p).resolve().relative_to(REPO))
    except ValueError: return str(p)

def cmd_emit(a):
    data  = pathlib.Path(a.data)
    sweep = read_sweep(data / 'sweep.tsv')
    meta  = read_tunable(data / 'tunable.tsv')
    caps  = caps_in(REPO)
    if not caps:
        sys.exit('capsweep: parsed 0 caps out of src/ — the declaration shape changed')
    disc  = collections.defaultdict(set)
    for p in sorted(REPO.joinpath('src').rglob('*.h')):
        for x in re.findall(r'([a-z_]+)_capped', p.read_text(errors='replace')):
            disc[str(p.relative_to(REPO))].add(x)
    # A measured cap that no longer holds the value it was measured at makes every byte in its table a
    # claim about a constant that is gone. Refuse; do not quietly re-render around it.
    vals  = {c[0]: c[1] for c in caps}
    stale = ['%s (measured %s, src/ says %s)' % (c, sweep[c]['value'], vals.get(c, 'GONE'))
             for c in sorted(sweep) if str(vals.get(c)) != str(sweep[c]['value'])]
    if stale:
        sys.exit('capsweep: %d measured cap(s) no longer match src/ — the sweep is STALE, re-run it:\n  %s'
                 % (len(stale), '\n  '.join(stale)))
    body = render(sweep, meta, caps, disc)
    out  = pathlib.Path(a.out)
    if a.check:
        cur = out.read_text() if out.exists() else ''
        if cur != body:
            sys.exit('capsweep: %s is STALE — run: python3 bench/capsweep/capsweep.py emit' % rel(a.out))
        print('capsweep: %s matches bench/capsweep/*.tsv + src/ (%d caps with measured effect)'
              % (rel(a.out), len(sweep)))
    else:
        out.write_text(body)
        print('wrote %s — %d caps with measured effect' % (rel(a.out), len(sweep)))

def cmd_patch(a):
    """Patch a tree's cap declarations and stop. --root is REQUIRED: this rewrites source in place, and
    defaulting it to the repo is how a convenience flag becomes a G3/G5 regression on somebody's tree."""
    root = pathlib.Path(a.root).resolve()
    if root == REPO:
        sys.exit('capsweep: refusing to patch the repository itself — patch a scratch copy')
    made = patch(root, set())
    print('capsweep: patched %d cap declaration(s) under %s' % (len(made), rel(root)))
    for n in sorted(set(made)):
        print('  %s' % n)

def cmd_checkcorpus(a):
    assert_corpus_clean(a.corpus)
    print('capsweep: corpus %s is clean of the harness' % rel(a.corpus))

if __name__ == '__main__':
    ap = argparse.ArgumentParser()
    ap.add_argument('phase', choices=['prepare', 'screen', 'sweep', 'emit', 'patch', 'check-corpus'])
    ap.add_argument('--scratch', default=str(pathlib.Path.home() / '.cache' / 'ripwire-capsweep'))
    ap.add_argument('--jobs', type=int, default=8)
    ap.add_argument('--data', default=str(HERE), help='emit: dir holding the frozen tunable/sweep TSV')
    ap.add_argument('--out',  default=str(REPO / 'docs' / 'TUNING.md'), help='emit: the document to write')
    ap.add_argument('--check', action='store_true', help='emit: compare instead of writing; exit 1 on drift')
    ap.add_argument('--root', default=None, help='patch: the SCRATCH tree to rewrite (never the repo)')
    ap.add_argument('--corpus', default=None, help='check-corpus: the frozen corpus to assert on')
    a = ap.parse_args()
    if a.phase == 'patch' and not a.root:
        ap.error('patch requires --root TREE')
    if a.phase == 'check-corpus' and not a.corpus:
        ap.error('check-corpus requires --corpus DIR')
    {'prepare': cmd_prepare, 'screen': cmd_screen, 'sweep': cmd_sweep, 'emit': cmd_emit,
     'patch': cmd_patch, 'check-corpus': cmd_checkcorpus}[a.phase](a)
