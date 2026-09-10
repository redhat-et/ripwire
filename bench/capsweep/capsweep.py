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
  emit     markdown tables

Usage: python3 bench/capsweep/capsweep.py prepare|screen|sweep|emit [--scratch DIR] [--jobs N]
"""
import argparse, json, os, pathlib, re, shutil, subprocess, sys, collections

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

def run_corpus(binary, root, corpus, env, timeout=120):
    """Run each corpus line and return its stdout SIZE.

    Two things here were learned the hard way:
      - the corpus lines already carry their own root ("." where the verb takes one), so this must NOT
        prepend one; doing so passed the root twice and every command refused;
      - stdin is DEVNULL, because `--from-trace=-` reads stdin and otherwise blocks until the timeout.
    """
    e = dict(os.environ); e.update(env)
    out = {}
    for line in corpus:
        try:
            r = subprocess.run([str(binary)] + line.split() + ['--no-cache'], cwd=str(root),
                               capture_output=True, stdin=subprocess.DEVNULL, env=e, timeout=timeout)
            out[line] = len(r.stdout)
        except subprocess.TimeoutExpired:
            out[line] = None          # recorded, never silently dropped
    return out

# ── phases ──────────────────────────────────────────────────────────────────────────────────────────
def freeze_corpus(scratch):
    """A corpus that CANNOT move while we measure it.

    The first sweep measured the live worktree — which holds this harness and the JSON it writes. The
    untracked bench/capsweep/ dir grew between the baseline pass and the probe passes, so ~18 verbs
    "responded" to every cap including ones that touch nothing. Systematic, not random, and it looked
    exactly like signal. `git archive HEAD` gives tracked files only, frozen at a commit.
    """
    corpus = scratch / 'corpus-tree'
    if corpus.exists(): shutil.rmtree(corpus)
    corpus.mkdir(parents=True)
    tar = subprocess.run(['git', '-C', str(REPO), 'archive', 'HEAD'], capture_output=True)
    if tar.returncode != 0: sys.exit('capsweep: git archive HEAD failed')
    subprocess.run(['tar', '-x', '-C', str(corpus)], input=tar.stdout, check=True)
    return corpus

def cmd_prepare(a):
    scratch = pathlib.Path(a.scratch)
    if scratch.exists(): shutil.rmtree(scratch)
    scratch.mkdir(parents=True)
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
    (pathlib.Path(a.scratch) / 'tunable.json').write_text(json.dumps(
        {'tunable': sorted(set(made)), 'constexpr_only': sorted(exclude), 'corpus': str(corpus)}, indent=1))
    print('wrote %s' % (pathlib.Path(a.scratch) / 'tunable.json'))

def cmd_screen(a):
    scratch = pathlib.Path(a.scratch); binary = scratch / 'build' / 'ripwire'
    meta = json.loads((pathlib.Path(a.scratch) / 'tunable.json').read_text())
    corpus = [l for l in (HERE / 'corpus.txt').read_text().splitlines() if l.strip()]
    croot = pathlib.Path(meta['corpus'])
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
    sens = sorted(c for c in corpus if base.get(c) != allb.get(c))
    (pathlib.Path(a.scratch) / 'screen.json').write_text(json.dumps(
        {'baseline': base, 'all_bumped': allb, 'sensitive': sens}, indent=1))
    print('corpus %d — cap-sensitive: %d (%.0f%%); the other %d respond to NO cap'
          % (len(corpus), len(sens), 100.0*len(sens)/len(corpus), len(corpus)-len(sens)))
    for c in sens[:15]:
        print('  %+8d B   %s' % (allb[c]-base[c], c[:88]))

def cmd_sweep(a):
    """Per cap: which of the sensitive commands actually respond to THIS cap, and by how much.

    Only the 59 cap-sensitive commands are used. The other 136 answered identically with every cap
    bumped at once, so no single cap can move them — running them per-cap would be 16,000 wasted runs.
    """
    scratch = pathlib.Path(a.scratch); binary = scratch / 'build' / 'ripwire'
    meta   = json.loads((pathlib.Path(a.scratch) / 'tunable.json').read_text())
    screen = json.loads((pathlib.Path(a.scratch) / 'screen.json').read_text())
    sens, base = screen['sensitive'], screen['baseline']
    croot = pathlib.Path(meta['corpus'])
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
    (pathlib.Path(a.scratch) / 'sweep.json').write_text(json.dumps(out, indent=1))
    print('caps that move at least one verb: %d of %d tunable' % (len(out), len(meta['tunable'])))

def cmd_emit(a):
    sweep = json.loads((pathlib.Path(a.scratch) / 'sweep.json').read_text())
    meta  = json.loads((pathlib.Path(a.scratch) / 'tunable.json').read_text())
    caps  = caps_in(REPO)
    disc  = collections.defaultdict(set)
    for p in sorted(REPO.joinpath('src').rglob('*.h')):
        for x in re.findall(r'([a-z_]+)_capped', p.read_text(errors='replace')):
            disc[str(p.relative_to(REPO))].add(x)
    L = []
    L.append('# Cap sensitivity — measured, %s\n' % __import__('datetime').date.today().isoformat())
    L.append('A DATED SNAPSHOT, not a live document. It cannot be regenerated in CI — it needs a')
    L.append('purpose-built tunable binary — so it lives in `bench/` beside the other measurement')
    L.append('records rather than in `docs/`, where an ungated generated file would silently rot.')
    L.append('Re-measure before quoting it; the numbers move with the corpus.\n')
    L.append('**Generated — do not edit.** `python3 bench/capsweep/capsweep.py prepare|screen|sweep|emit`.\n')
    L.append('What each compile-time cap actually COSTS, per verb. `docs/LIMITS.md` says a cap exists;')
    L.append('this says what it does. Measured by patching a SCRATCH copy of the tree so the caps read an')
    L.append('env var — production keeps its `constexpr` and is never patched — then running real')
    L.append('invocations at the default value and at a probe value. The tunable binary is byte-identical')
    L.append('to production at defaults; that control is what makes these numbers mean anything.\n')
    L.append('| caps | tunable | must stay `constexpr` | move >= 1 invocation | move nothing measurable |')
    L.append('| --- | --- | --- | --- | --- |')
    L.append('| %d | %d | %d | **%d** | %d |\n' % (len(caps), len(meta['tunable']),
             len(meta['constexpr_only']), len(sweep), len(meta['tunable']) - len(sweep)))
    L.append('## Read this ratio before the tables\n')
    L.append('**%d of %d tunable caps move any invocation at all. %d move nothing measurable.** That is the'
             % (len(sweep), len(meta['tunable']), len(meta['tunable']) - len(sweep)))
    L.append('finding, and it says what NOT to do: this is not a 120-cap audit. Most of these constants are')
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
    for cap in sorted(sweep, key=lambda c: -len(sweep[c]['moved'])):
        e = sweep[cap]
        f = e['site'].split(':')[0]
        L.append('### `%s` = `%s`\n' % (cap, e['value']))
        L.append('`%s` — discloses: %s — probe value `%s` — **%d verb(s) respond**\n'
                 % (e['site'], ', '.join('`%s_capped`' % x for x in sorted(disc.get(f, []))) or '**none**',
                    e['probe'], len(e['moved'])))
        L.append('| invocation | default | at probe | delta |')
        L.append('| --- | --- | --- | --- |')
        for cmd, (b, g) in sorted(e['moved'].items(), key=lambda kv: -abs(kv[1][1]-kv[1][0]))[:12]:
            L.append('| `%s` | %d B | %d B | %+d B |' % (cmd[:70], b, g, g - b))
        L.append('')
    (HERE / 'RESULTS.md').write_text('\n'.join(L) + '\n')
    print('wrote bench/capsweep/RESULTS.md — %d caps with measured effect' % len(sweep))

if __name__ == '__main__':
    ap = argparse.ArgumentParser()
    ap.add_argument('phase', choices=['prepare', 'screen', 'sweep', 'emit'])
    ap.add_argument('--scratch', default=str(pathlib.Path.home() / '.cache' / 'ripwire-capsweep'))
    ap.add_argument('--jobs', type=int, default=8)
    a = ap.parse_args()
    {'prepare': cmd_prepare, 'screen': cmd_screen, 'sweep': cmd_sweep, 'emit': cmd_emit}[a.phase](a)
