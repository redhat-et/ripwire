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
           This is the step that makes it tractable: ~120 caps x 195 commands is 23,400 runs, but most
           commands respond to no cap, so the second phase only pays for the ones that move.
  sweep    per cap x sensitive command, a value ladder -> bytes at each value
  emit     markdown tables -> docs/TUNING.md  (--check compares instead of writing; the gate runs that)

Two phases exist only so test/capsweepcheck.sh can prove the two load-bearing mechanisms WITHOUT a
build — a gate that cannot go red is worse than no gate:

  patch        run the cap patcher against --root SOMETREE and stop. The gate hands it a synthetic
               tree and reads the rewritten line.
  check-corpus run the corpus-cleanliness assertion against --corpus SOMEDIR and stop. The gate hands
               it a synthetic corpus with bench/capsweep/ inside and asserts the refusal, and one with
               a .git ABOVE it and asserts that refusal too.
  plant-history  plant the synthetic git history in --root and stop. `git archive HEAD` leaves no
               .git at all, so without it ~20 git-dependent corpus rows measure their DEGRADED path
               (--handoff reports changed="0"; --cochange/--situ/--map-diff exit 1 with 0 bytes) and
               are scored "responds to NO cap" while measuring a refusal.
  run-corpus   run both screen arms against --binary (a stub) over --corpus-file and stop. The gate
               hands it six synthetic rows — one answering, one cap-sensitive, one refusing, one with an
               unbalanced quote, one naming an undefined variable, one that litters the corpus — and
               reads the census, the refusal and the denominator back out.

EVERY ROW CARRIES A STATE, and only `ok` carries a byte count. `len(stdout)` alone made a REFUSAL
(exit 1, no output) and an ANSWER OF NOTHING the same measurement, which is how 37 corpus rows mangled
by a quoting bug sat inside "responds to NO cap" for a whole round: 0 under both arms is a delta of 0,
and a delta of 0 leaves the sensitive set silently. The split's denominator is the rows that ANSWERED —
a row that emits nothing cannot respond to a cap — and a run in which NO row answered refuses to report
a split at all rather than printing a clean 0%.

Usage: python3 bench/capsweep/capsweep.py prepare|screen|sweep|emit [--scratch DIR] [--jobs N]
       python3 bench/capsweep/capsweep.py emit [--data bench/capsweep] [--out docs/TUNING.md] [--check]
       python3 bench/capsweep/capsweep.py patch --root TREE
       python3 bench/capsweep/capsweep.py check-corpus --corpus DIR
       python3 bench/capsweep/capsweep.py run-corpus --binary B --corpus DIR --corpus-file F [--bump K=V]

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
import argparse, hashlib, os, pathlib, re, shlex, shutil, subprocess, sys, collections

HERE  = pathlib.Path(__file__).resolve().parent
REPO  = HERE.parent.parent
DECL  = re.compile(r'^(\s*inline\s+)constexpr(\s+)([\w:<>, ]*?)(\s+)(k[A-Z][A-Za-z0-9_]*)(\s*=\s*)([0-9][0-9_.eE+-]*)(\s*;)(.*)$')
# Same NAME vocabulary as docs/limits_build.py, and widened on the same day for the same reason: a cap
# whose name carries no keyword is invisible to the WHOLE instrument — not patched, not bumped, never in
# docs/TUNING.md. kHandoffSymbolsPerFile truncated output and disclosed syms_capped="1" while appearing
# in neither this file's census nor the register's, which is how it was raised on 2026-09-10 without
# ever having been listed anywhere. `Per\w*File`, not `PerFile`: a filter that turns on an exact compound
# spelling is the defect, not a smaller instance of it.
KEY   = re.compile(r'Max|Cap|Limit|Top|Budget|Ceil|Threshold|Rows|Len|Depth|Width|Shown|Hits|Per\w*File')
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

# ── what a corpus row DID, which is not the same question as how many bytes it produced ─────────────
# The harness recorded `len(stdout)` and nothing else, so a row that REFUSED (exit 1, no output) and a
# row that ANSWERED with nothing were the same measurement: 0. That is how 37 mangled rows sat inside
# "responds to NO cap" for a whole round — a row measuring 0 under both arms has a delta of 0 and leaves
# the sensitive set silently. Every row now carries a STATE, and only kStateOk carries a byte count; the
# other three record kNullField, because a refusal is not a measurement of zero bytes.
kStateOk          = 'ok'            # exit 0 — the byte count means something
kStateTimeout     = 'timeout'       # neither arm's value is known
kStateUnparseable = 'unparseable'   # shlex could not split the row: a corpus defect, not a result
kStateUnexpanded  = 'unexpanded'    # the row names a variable this harness does not define (see F17)

def state_refused( rc ):
    return 'rc=%d' % rc

def answered( sizes, states, line ):
    """The one definition of "this row produced an answer", used by every count below."""
    return states.get( line ) == kStateOk and ( sizes.get( line ) or 0 ) > 0

VAR = re.compile(r'\$(\w+)|\$\{(\w+)\}')

# The variables this harness BINDS. Everything outside this namespace is not an environment reference at
# all and passes through untouched — `. --pattern=\'rankGraphTeleport($A, $B, $C)\'` is a tree-sitter pattern
# whose $A/$B/$C are METAVARIABLES, and the first cut of the rule below refused that row as "unexpanded",
# turning a legitimate measurement into a non-answer. shlex.split has already discarded the quoting by the
# time we see the word, so single-quoted (no expansion) and double-quoted cannot be told apart here; naming
# the namespace is what makes the rule decidable. Caught by the executability census on the re-run — the
# census earns its keep the first time it runs.
HARNESS_VAR = re.compile(r'^RIPWIRE_')

def expandvars_from(word, env):
    """Expand THIS HARNESS's $VARS from the environment the CHILD will get — not from os.environ.

    os.path.expandvars reads os.environ, and the harness binds RIPWIRE_CAPSWEEP_TMP in a dict it hands
    subprocess.run. With the variable unset in the operator's shell — the normal case, and the one the
    corpus comment was written for — all nine rows naming it received the LITERAL string
    `$RIPWIRE_CAPSWEEP_TMP`, and `--cache=`/`--export=`/`--html=` then wrote it as a relative path INSIDE
    the frozen corpus (a 10.4 MB cache blob). `--batch=$RIPWIRE_CAPSWEEP_TMP` read that blob back and
    "responded" to 103 of 108 caps: its input was the accumulated output of the run measuring it.

    An unresolved variable in the HARNESS's own namespace RAISES rather than passing through as a literal:
    os.path.expandvars leaves it alone, which is the shell's rule and exactly the behaviour that turned
    $RIPWIRE_CAPSWEEP_TMP into a relative path inside the frozen corpus. A name outside that namespace is
    not this harness's business and is left exactly as written.
    """
    missing = []
    def one(m):
        name = m.group(1) or m.group(2)
        if name in env:
            return env[name]
        if HARNESS_VAR.match(name):
            missing.append(name)        # ours to bind, and we did not — that is the F17 shape
        return m.group(0)               # not ours: a metavariable, a regex, someone else's literal
    out = VAR.sub(one, word)
    if missing:
        raise KeyError(', '.join(sorted(set(missing))))
    return out

def assert_tmp_outside(tmp, corpus):
    """The scratch path corpus rows write into must not resolve INSIDE the corpus.

    `--cache=`, `--export=`, `--html=` and `--brief=` take a destination, and run_corpus runs with
    cwd=corpus. A destination that lands in the corpus makes the harness write into the tree it is
    measuring — the artifact assert_corpus_clean exists past, arriving through a path that assertion
    does not check.
    """
    t, c = pathlib.Path(tmp).resolve(), pathlib.Path(corpus).resolve()
    if t == c or c in t.parents:
        sys.exit('capsweep: RIPWIRE_CAPSWEEP_TMP (%s) resolves INSIDE the corpus (%s) — corpus rows would\n'
                 '          write into the tree being measured' % (t, c))
    return str(t)

def run_corpus(binary, root, corpus, env, timeout=120):
    """Run each corpus line; return ({line: stdout size or None}, {line: state}).

    Two things here were learned the hard way:
      - the corpus lines already carry their own root ("." where the verb takes one), so this must NOT
        prepend one; doing so passed the root twice and every command refused;
      - stdin is DEVNULL, because `--from-trace=-` reads stdin and otherwise blocks until the timeout.

    $VARS in a corpus line are expanded from the environment THIS FUNCTION BUILDS (expandvars_from — not
    os.path.expandvars). The corpus was harvested from a recorded showcase run whose scratch directory
    was a machine-local macOS temp path; committing that literal would have pinned the corpus to one
    laptop and put somebody's filesystem layout in a public file, so those occurrences are spelled
    $RIPWIRE_CAPSWEEP_TMP and bound here.

    GIT_CEILING_DIRECTORIES stops the `git` processes ripwire spawns from walking out of the corpus.
    It is NOT the whole guard: ripwire walks up for `.git` in its own code (src/gitmine.h,
    src/ingest_crawl.h) and honours no such variable, so assert_corpus_clean's ancestor scan is what
    actually keeps a git verb from measuring the operator's repository.
    """
    e = dict(os.environ)
    if not e.get('RIPWIRE_CAPSWEEP_TMP'):     # not setdefault: an EMPTY value is not a binding, and
        e['RIPWIRE_CAPSWEEP_TMP'] = str(pathlib.Path(root).parent / 'corpus-tmp')   # Path('') is the CWD
    e.update(env)
    e['RIPWIRE_CAPSWEEP_TMP'] = assert_tmp_outside(e['RIPWIRE_CAPSWEEP_TMP'], root)
    e['GIT_CEILING_DIRECTORIES'] = str(pathlib.Path(root).resolve().parent)
    os.makedirs(e['RIPWIRE_CAPSWEEP_TMP'], exist_ok=True)
    sizes, states = {}, {}
    for line in corpus:
        try:
            # shlex, not line.split(): 37 of the 195 corpus rows carry a quoted multi-word value
            # (--for="cache invalidation", --exemplar="format byte sizes for humans"). split() hands
            # the binary --for="cache with a literal quote plus `invalidation` as a positional root,
            # which exits 1 with `root path does not exist` and 0 bytes of stdout -- under EVERY cap.
            # A row that measures 0 both sides has a delta of 0 and silently leaves the cap-sensitive
            # set, so those 19% were not measuring the caps they were written to exercise. Verified
            # against the real corpus: shlex.split gives exit 0 / 2530 B where split() gives exit 1 / 0 B.
            #
            # And shlex RAISES on an unbalanced quote, which two corpus rows carry. Catching only
            # TimeoutExpired turned the fix into a hard crash of the whole phase. NOT `as e`: the child
            # environment two lines above is named `e`, Python DELETES an except-name at block end, and
            # the obvious one-line repair therefore kills the NEXT row with UnboundLocalError.
            argv = [expandvars_from(w, e) for w in shlex.split(line)]
        except ValueError as parseErr:
            sizes[line], states[line] = None, '%s: %s' % (kStateUnparseable, parseErr)
            continue
        except KeyError as missingVar:
            sizes[line], states[line] = None, '%s: $%s' % (kStateUnexpanded, missingVar.args[0])
            continue
        try:
            r = subprocess.run([str(binary)] + argv + ['--no-cache'], cwd=str(root),
                               capture_output=True, stdin=subprocess.DEVNULL, env=e, timeout=timeout)
        except subprocess.TimeoutExpired:
            sizes[line], states[line] = None, kStateTimeout   # recorded, never silently dropped
            continue
        if r.returncode != 0:
            # A refusal is a DISTINCT state, never a byte count of zero. Most of these are refusals the
            # corpus deliberately contains (--callers=DoesNotExist, --rank-by=bogus); they belong in the
            # corpus and they do not belong in any denominator.
            sizes[line], states[line] = None, state_refused(r.returncode)
        else:
            sizes[line], states[line] = len(r.stdout), kStateOk
    return sizes, states

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

def write_records(path, what, columns, rows, measured_at, recipe=()):
    """`#` provenance lines naming the columns, the measured commit and the RECIPE, then the data.

    `recipe` is not decoration. A published ratio whose denominator is unstated is one list counted four
    defensible ways: the round that published "59 of 195" was counting 56 rows that emit nothing at all
    into the half that "responds to NO cap". The recipe travels with the records so the next reader does
    not have to re-derive which population a number was over.
    """
    for r in rows:
        for f in r:
            if '\t' in str(f) or '\n' in str(f):
                sys.exit('capsweep: field %r holds a tab or newline — it cannot be a TSV record' % (f,))
    head = ['# capsweep %s — columns: %s — measured_at=%s — %s' % (
        what, ' / '.join(columns), measured_at or 'unrecorded', kRecordNote)]
    head += ['# %s' % line for line in recipe]
    path.write_text('\n'.join(head + ['\t'.join(str(f) for f in r) for r in rows]) + '\n')

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
kScreenCols  = ('baseline_bytes', 'all_bumped_bytes', 'sensitive', 'baseline_state', 'all_bumped_state', 'invocation')
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

def write_screen(path, corpus, base, allb, sens, measured_at, bstate, gstate, recipe=()):
    hot  = set(sens)
    rows = [(fmt_bytes(base.get(c)), fmt_bytes(allb.get(c)), 1 if c in hot else 0,
             bstate.get(c, '?'), gstate.get(c, '?'), c) for c in corpus]
    write_records(path, 'screen', kScreenCols, rows, measured_at, recipe)

def read_screen(path):
    at, rows = read_records(path, len(kScreenCols))
    base, allb, sens, bst = {}, {}, [], {}
    for b, g, s, bs, gs, cmd in rows:
        base[cmd] = parse_bytes(b, rel(path))
        allb[cmd] = parse_bytes(g, rel(path))
        bst[cmd]  = bs
        if s == '1': sens.append(cmd)
    return {'baseline': base, 'all_bumped': allb, 'sensitive': sens, 'baseline_state': bst}

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
    assert_no_git_above(corpus)
    return corpus

def assert_no_git_above(corpus):
    """No `.git` in any STRICT ancestor of the corpus. The corpus's own `.git` is the fixture; anything
    above it is somebody else's repository.

    ripwire walks UP the directory chain looking for `.git` (src/gitmine.h:2792, src/ingest_crawl.h:929)
    and honours no ceiling variable. A frozen corpus sitting inside a checkout therefore measures THAT
    checkout's history: the round of 2026-09-10 recorded `. --stray-content=lane/ --plan` at 11,670,369 B
    on a corpus produced by `git archive`, which has no branches at all. Eleven megabytes of somebody
    else's branch names, recorded as a cap measurement.

    This is not covered by the harness-in-corpus check above: that one looks INSIDE the corpus and this
    failure is entirely OUTSIDE it. GIT_CEILING_DIRECTORIES (set in run_corpus) confines the `git`
    processes ripwire spawns; only this scan confines ripwire's own walk.
    """
    d = pathlib.Path(corpus).resolve().parent
    while True:
        if (d / '.git').exists():
            sys.exit('capsweep: REFUSING to measure a corpus with a git repository ABOVE it: %s\n'
                     '          ripwire walks up for .git, so every git verb would measure that\n'
                     '          repository instead of the frozen corpus. Point --scratch outside it.'
                     % (d / '.git'))
        if d.parent == d:
            return
        d = d.parent

# ── the corpus must not change while it is being measured ───────────────────────────────────────────
# assert_corpus_clean guards ONE hardcoded directory name against an unbounded class. The class is what
# actually bit: `--cache=$RIPWIRE_CAPSWEEP_TMP` with the variable unexpanded wrote a 10.4 MB cache blob
# into the frozen corpus mid-sweep, and `--batch=` read it back. A name-based assertion could never have
# seen it. A file LIST taken after the freeze and re-checked after every arm sees any of it.
FINGERPRINT = 'corpus.filelist'          # lives in --scratch, never in the corpus

def file_digest(path):
    """sha256 of one file's bytes. hashlib's own chunked reader where the interpreter has it (3.11+),
    so this is NOT a third hand-rolled copy of the chunk loop bench/svectorab.py::sha already spells —
    --quality-delta flagged exactly that clone when this function first landed as one."""
    with open(path, 'rb') as fh:
        if hasattr(hashlib, 'file_digest'):
            return hashlib.file_digest(fh, 'sha256').hexdigest()
        return hashlib.sha256(fh.read()).hexdigest()

def fingerprint_corpus(corpus):
    """The corpus's file list WITH each entry's type and content digest, `.git/` excluded.

    `.git/` is excluded deliberately and it is the one place a git verb may legitimately write:
    reading a repository refreshes the index stat cache and can write ORIG_HEAD or a reflog. Those are
    git's bookkeeping about the fixture, not the tree being measured. Everything else is the subject.

    CONTENTS, not just names (CodeRabbit #127 / 3985249656). A name list cannot see a file being
    OVERWRITTEN in place, and overwriting is not a hypothetical: `--cache=$RIPWIRE_CAPSWEEP_TMP` with
    the variable unexpanded wrote a 10.4 MB blob into the frozen corpus, and a second run of the same
    row would have rewritten the same path — same list, changed subject, every later immutability check
    green. An arbitrary `run-corpus --binary` is by construction able to write anything anywhere.

    A SYMLINK is fingerprinted by its TARGET TEXT, unfollowed: following it would digest something
    outside the corpus (and could hang on a cycle), and a RETARGETED symlink is exactly the change this
    is here to catch. `is_symlink()` is asked FIRST because `is_file()` follows.

    Each line is `<kind>\t<digest>\t<relpath>`, sorted by PATH so the file diffs like a list.
    """
    corpus = pathlib.Path(corpus)
    out = []
    for p in corpus.rglob('*'):
        rp = p.relative_to(corpus)
        if rp.parts and rp.parts[0] == '.git':
            continue
        if p.is_symlink():
            kind = 'l'
            digest = hashlib.sha256(os.readlink(p).encode('utf-8', 'surrogateescape')).hexdigest()
        elif p.is_file():
            kind, digest = 'f', file_digest(p)
        else:
            continue                      # a directory is not a subject; its files are
        out.append('%s\t%s\t%s' % (kind, digest, rp))
    return sorted(out, key=lambda line: line.split('\t', 2)[2])

def fingerprint_index(lines):
    """{relpath: (kind, digest)} — so a CHANGED file reads as one `~` row, not a `+` and a `-`."""
    out = {}
    for line in lines:
        parts = line.split('\t', 2)
        if len(parts) != 3:
            sys.exit('capsweep: %s holds a name-only fingerprint, which cannot see a file being\n'
                     '          overwritten in place. Re-run `prepare` to record type+digest per entry.'
                     % FINGERPRINT)
        out[parts[2]] = (parts[0], parts[1])
    return out

def write_fingerprint(scratch, corpus):
    pathlib.Path(scratch, FINGERPRINT).write_text('\n'.join(fingerprint_corpus(corpus)) + '\n')

def read_fingerprint(scratch):
    f = pathlib.Path(scratch, FINGERPRINT)
    if not f.exists():
        sys.exit('capsweep: %s is missing — the corpus was never fingerprinted.\n'
                 '          Re-run `prepare`; a corpus nobody took a fingerprint of cannot be shown to\n'
                 '          have held still while it was measured.' % f)
    return [l for l in f.read_text().splitlines() if l]

def assert_corpus_unchanged(corpus, before, where):
    was    = fingerprint_index(before)
    now    = fingerprint_index(fingerprint_corpus(corpus))
    new    = sorted(set(now) - set(was))
    gone   = sorted(set(was) - set(now))
    edited = sorted(f for f in set(was) & set(now) if was[f] != now[f])
    if new or gone or edited:
        lines = ['capsweep: the frozen corpus CHANGED during %s — every byte count in this run is a' % where,
                 '          measurement of the harness as much as of the subject.']
        lines += ['          + %s' % f for f in new[:20]]
        lines += ['          - %s' % f for f in gone[:20]]
        lines += ['          ~ %s (%s -> %s)' % (f, was[f][0] + ':' + was[f][1][:12], now[f][0] + ':' + now[f][1][:12])
                  for f in edited[:20]]
        shown = min(len(new), 20) + min(len(gone), 20) + min(len(edited), 20)
        if len(new) + len(gone) + len(edited) > shown:
            lines.append('          (%d more)' % (len(new) + len(gone) + len(edited) - shown))
        sys.exit('\n'.join(lines))

# ── phases ──────────────────────────────────────────────────────────────────────────────────────────
# The files the synthetic history touches. Four, and all four are prose: a marker line appended to a
# markdown file adds no symbol to the map, so the perturbation this fixture costs the OTHER 190 corpus
# rows is four lines of comment. Chosen over src/ headers for exactly that reason.
FIXTURE_FILES = ('CONTRIBUTING.md', 'docs/ARCHITECTURE.md', 'docs/METHODOLOGY.md', 'docs/EVALS.md')
FIXTURE_MARK  = '<!-- capsweep history fixture: commit %d — not part of the document -->'

def plant_history(corpus):
    """Give the frozen corpus a real, tiny history — because `git archive HEAD` leaves none.

    Without this, every git-dependent row in the corpus measures its DEGRADED path and says nothing
    about any cap: `--handoff` reports `changed="0"` with no <f> rows at all, and `--cochange`, `--situ`,
    `--map-diff`, `--quality-delta`, `--rank-by=churn` and `--merge-scout` exit 1 with 0 bytes. Roughly
    twenty corpus rows, scored as "responds to NO cap" while measuring a refusal.

    Three commits and one uncommitted edit, all over the same four files, is the smallest shape that
    gives each of those verbs its real path: >1 commit for a diff, the SAME files twice for a co-change
    pair, and a dirty working tree for the verbs that default to `git diff`.

    It does NOT exercise per-file symbol caps (kHandoffSymbolsPerFile and its kind): one appended line
    is one changed symbol, and a cap of 6 never fires on that. Those need a real diff of a real commit,
    which is a different instrument — do not read a per-file cap's silence in the sweep as evidence.
    """
    env = dict(os.environ)
    env.update({'GIT_AUTHOR_NAME': 'capsweep', 'GIT_AUTHOR_EMAIL': 'capsweep@invalid',
                'GIT_COMMITTER_NAME': 'capsweep', 'GIT_COMMITTER_EMAIL': 'capsweep@invalid',
                'GIT_AUTHOR_DATE': '2001-01-01T00:00:00+00:00',
                'GIT_COMMITTER_DATE': '2001-01-01T00:00:00+00:00',
                'GIT_CONFIG_GLOBAL': os.devnull, 'GIT_CONFIG_SYSTEM': os.devnull})
    present = [f for f in FIXTURE_FILES if (corpus / f).exists()]
    if len(present) < 2:
        sys.exit('capsweep: the history fixture found %d of its %d files in the corpus — it would plant\n'
                 '          an empty history and every git row would still measure a refusal.\n'
                 '          Update FIXTURE_FILES: %s' % (len(present), len(FIXTURE_FILES),
                                                         ', '.join(FIXTURE_FILES)))
    def git(*args, **kw):
        r = subprocess.run(['git', '-C', str(corpus)] + list(args), capture_output=True, text=True, env=env)
        if r.returncode != 0 and not kw.get('soft'):
            sys.exit('capsweep: history fixture: git %s failed:\n%s%s' % (' '.join(args), r.stdout, r.stderr))
        return r
    git('init', '-q')
    git('symbolic-ref', 'HEAD', 'refs/heads/main')
    git('add', '-A')
    git('-c', 'user.name=capsweep', '-c', 'user.email=capsweep@invalid',
        'commit', '-q', '-m', 'capsweep fixture: the frozen corpus')
    for n in (2, 3):
        for f in present:
            with (corpus / f).open('a') as fh:
                fh.write(FIXTURE_MARK % n + '\n')
        git('-c', 'user.name=capsweep', '-c', 'user.email=capsweep@invalid',
            'commit', '-q', '-a', '-m', 'capsweep fixture: commit %d over the same files' % n)
    for f in present:                      # left UNCOMMITTED: the verbs that default to `git diff`
        with (corpus / f).open('a') as fh:
            fh.write(FIXTURE_MARK % 4 + '\n')
    head = git('rev-list', '--count', 'HEAD').stdout.strip()
    dirty = git('diff', '--name-only').stdout.split()
    if head != '3' or len(dirty) != len(present):
        sys.exit('capsweep: history fixture planted %s commit(s) and %d dirty file(s) — expected 3 and %d'
                 % (head, len(dirty), len(present)))
    return len(present)

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
    assert_corpus_clean(corpus)                 # ancestor scan included — BEFORE we plant a .git
    n = plant_history(corpus)
    print('planted a 3-commit history over %d file(s) — the git verbs measure their real path' % n)
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
    write_fingerprint(scratch, corpus)
    print('frozen corpus at %s (tracked files only, from git archive HEAD) — %d files fingerprinted'
          % (corpus, len(read_fingerprint(scratch))))
    ref = subprocess.run(['git', '-C', str(REPO), 'rev-parse', 'HEAD'], capture_output=True, text=True)
    out = pathlib.Path(a.scratch) / 'tunable.tsv'
    write_tunable(out, made, exclude, ref.stdout.strip(), corpus)
    print('wrote %s' % out)

def census(corpus, sizes, states):
    """The four states a corpus row can be in. `ok` is the only one that carries a byte count."""
    ok   = [c for c in corpus if answered(sizes, states, c)]
    unp  = [c for c in corpus if states.get(c, '').startswith(kStateUnparseable)]
    unx  = [c for c in corpus if states.get(c, '').startswith(kStateUnexpanded)]
    to   = [c for c in corpus if states.get(c) == kStateTimeout]
    ref  = [c for c in corpus if states.get(c, '').startswith('rc=')]
    zero = [c for c in corpus if states.get(c) == kStateOk and (sizes.get(c) or 0) == 0]
    return ok, unp, unx, to, ref, zero

def classify_split(corpus, base, bstate, allb, gstate, ok):
    """The four ways a row can differ between the two arms, by EXECUTION STATE rather than raw value.

    CodeRabbit #127 / 3985249659. `base.get(c)` is None for every non-answer — a timeout, a refusal, an
    unparseable row — and 0 for an exit-0 run that printed nothing, which `answered()` already defines as
    NO answer. Comparing those values directly counted two things that are not byte sensitivity:
      * 100 bytes at the default, TIMEOUT when bumped: base=100, allb=None, "different" -> counted as
        cap-sensitive. It is a regression the bump introduced, and it inflated the numerator.
      * refused at the default, exit 0 with ZERO bytes when bumped: base=None, allb=0, "different" ->
        counted as "answers only when a cap is bumped", about a row that still answers nothing.

    So: hot compares BYTES only where BOTH arms answered; late is a bumped-only answer by answered()'s
    own definition; lost answered at the default and stopped; moved never answered in either arm yet the
    records differ. Only hot is the numerator; the other three are reported, never counted.
    """
    answBase = set(ok)
    answBump = set(c for c in corpus if answered(allb, gstate, c))
    hot   = sorted(c for c in corpus if c in answBase and c in answBump and base.get(c) != allb.get(c))
    late  = sorted(answBump - answBase)
    lost  = sorted(answBase - answBump)
    moved = sorted(c for c in corpus if c not in answBase and c not in answBump
                   and (bstate.get(c) != gstate.get(c) or base.get(c) != allb.get(c)))
    return hot, late, lost, moved

def screen_core(binary, croot, corpus, bump, out_path, measured_at, before):
    """Both arms, the executability census, the refusal, and the split — over the ANSWERING rows.

    Two rules live here and nowhere else:

      1. A run in which no row answered must not report anything. The harness used to print
         `cap-sensitive: 0 (0%)` and exit 0 for a corpus that was 100% inert — a green result from an
         instrument that measured nothing, which is how a whole round's worth of retrieval rows passed
         unnoticed. Refusing costs one `if`; not refusing cost a night.
      2. The denominator is the rows that ANSWERED, not every row in the file. 56 of the 195 rows never
         produce an answer under any cap (deliberate refusals like --callers=DoesNotExist, plus rows the
         corpus harvest truncated). A row that emits nothing cannot respond to a cap, and counting it in
         the half that "responds to NO cap" inflated that half by 56.
    """
    base, bstate = run_corpus(binary, croot, corpus, {})
    assert_corpus_unchanged(croot, before, 'the baseline arm')
    allb, gstate = run_corpus(binary, croot, corpus, bump)
    assert_corpus_unchanged(croot, before, 'the all-bumped arm')

    ok, unp, unx, to, ref, zero = census(corpus, base, bstate)
    print('EXECUTABILITY (baseline arm): %d/%d answered | %d unparseable | %d unexpanded variable | '
          '%d timed out | %d refused (non-zero exit) | %d exit 0 with 0 bytes'
          % (len(ok), len(corpus), len(unp), len(unx), len(to), len(ref), len(zero)))
    # The state is printed in FULL. Truncating it to a column width hid which variable was unexpanded,
    # which is the whole content of that row's finding.
    for c in unp + unx:  print('  %-28s %s' % (bstate[c], c[:88]))
    for c in to:         print('  %-28s %s' % (kStateTimeout, c[:88]))
    for c in zero:       print('  %-28s %s' % ('ok but 0 bytes', c[:88]))
    if not ok:
        sys.exit('capsweep: 0 of %d rows produced an answer — REFUSING to write records or report a\n'
                 '          split. A ratio over a population that measured nothing is not a result.'
                 % len(corpus))

    hot, late, lost, moved = classify_split(corpus, base, bstate, allb, gstate, ok)
    sens = sorted(set(hot) | set(late))          # the rows cmd_sweep will probe cap by cap
    recipe = ('split recipe: DENOMINATOR = rows that answered under the BASELINE arm (state=ok, >0 bytes).',
              'A row that emits nothing cannot respond to a cap; %d row(s) of %d never answer and are'
              % (len(corpus) - len(ok), len(corpus)),
              'recorded here but excluded from the ratio.',
              'NUMERATOR = rows where BOTH arms answered and the byte counts differ. A row whose STATE',
              'moved between the arms is not byte sensitivity and is reported separately, never counted:',
              '%d answered only when bumped, %d stopped answering when bumped, %d moved between two'
              % (len(late), len(lost), len(moved)),
              'non-answering states.',
              'cap-sensitive=%d of %d answering (%.0f%%); %d row(s) answer only when a cap is bumped.'
              % (len(hot), len(ok), 100.0 * len(hot) / len(ok), len(late)))
    write_screen(out_path, corpus, base, allb, sens, measured_at, bstate, gstate, recipe)
    print('corpus %d — %d answered — cap-sensitive: %d of %d answering rows (%.0f%%); the other %d '
          'answering rows respond to NO cap'
          % (len(corpus), len(ok), len(hot), len(ok), 100.0 * len(hot) / len(ok), len(ok) - len(hot)))
    for c in late:
        print('  %8s   %s' % ('BY-CAP', c[:88]))       # refused at the default, ANSWERS when bumped
    # The two transitions that are NOT cap sensitivity, printed with their states so the reason is on the
    # screen rather than inferred from a byte count that was never comparable.
    for c in lost:
        print('  %8s   %s  [%s -> %s]' % ('LOST', c[:66], bstate.get(c, '?'), gstate.get(c, '?')))
    for c in moved:
        print('  %8s   %s  [%s -> %s]' % ('STATE', c[:66], bstate.get(c, '?'), gstate.get(c, '?')))
    for c in hot[:15]:
        if base.get(c) is None or allb.get(c) is None:
            print('  %8s   %s' % ('TIMEOUT', c[:88]))
        else:
            print('  %+8d B   %s' % (allb[c] - base[c], c[:88]))
    return sens

def cmd_screen(a):
    scratch = pathlib.Path(a.scratch); binary = scratch / 'build' / 'ripwire'
    meta = read_tunable(scratch / 'tunable.tsv')
    corpus = read_corpus()
    croot = assert_corpus_clean(meta.get('corpus') or scratch / 'corpus-tree')   # re-checked per phase
    before = read_fingerprint(scratch)
    # RELATIVE bump, not a flat huge value: several of these are query/work budgets in the 10^5 range,
    # and slamming them all to 999999 makes the screen measure the machine rather than the cap.
    vals = {c[0]: c[1] for c in caps_in(REPO)}
    def bumped(n):
        try:    v = float(vals.get(n, '8'))
        except ValueError: v = 8.0
        return ('%g' % max(v * 8.0, v + 32.0)) if v == int(v) else ('%g' % min(v * 4.0, 1.0))
    bump = {('RWCAP_%s' % n): bumped(n) for n in meta['tunable']}
    screen_core(binary, croot, corpus, bump, scratch / 'screen.tsv', meta.get('measured_at'), before)

def cmd_sweep(a):
    """Per cap: which of the sensitive commands actually respond to THIS cap, and by how much.

    Only the cap-sensitive commands are used. The rest answered identically with every cap bumped at
    once, so no single cap can move them — running them per-cap would be 16,000 wasted runs.

    The corpus fingerprint is re-checked after EVERY cap's arm, not once at the end: the failure this
    guards against (the harness writing into the corpus it measures) is cumulative, and the arm that
    created the file is the one worth naming.
    """
    scratch = pathlib.Path(a.scratch); binary = scratch / 'build' / 'ripwire'
    meta   = read_tunable(scratch / 'tunable.tsv')
    screen = read_screen(scratch / 'screen.tsv')
    sens, base = screen['sensitive'], screen['baseline']
    croot = assert_corpus_clean(meta.get('corpus') or scratch / 'corpus-tree')   # re-checked per phase
    before = read_fingerprint(scratch)
    vals = {c[0]: c[1] for c in caps_in(REPO)}
    sites = {c[0]: '%s:%d' % (c[2], c[3]) for c in caps_in(REPO)}
    out = {}
    for i, cap in enumerate(sorted(meta['tunable']), 1):
        try:    v = float(vals.get(cap, '8'))
        except ValueError: continue
        if v != int(v) or v <= 0:      # ladders only make sense for integral counts
            continue
        hi = '%d' % max(int(v) * 8, int(v) + 32)
        got, gstate = run_corpus(binary, croot, sens, {'RWCAP_%s' % cap: hi})
        assert_corpus_unchanged(croot, before, 'the %s arm' % cap)
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

    Line numbers are deliberately absent, here and (since 2026-09-10) in docs/LIMITS.md: a line would
    make either doc drift on any edit ANYWHERE above a cap, which is churn that says nothing about the
    measurement. What DOES belong here — the cap's name, its value and its file — is re-read from src/
    every run, so a retuned cap reds the gate.
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
    print('capsweep: corpus %s is clean of the harness and has no git repository above it' % rel(a.corpus))

def cmd_planthistory(a):
    """Plant the history fixture in --root and stop, so the gate can drive it without a full prepare."""
    root = pathlib.Path(a.root).resolve()
    if root == REPO:
        sys.exit('capsweep: refusing to plant a fixture history in the repository itself')
    n = plant_history(root)
    print('capsweep: planted a 3-commit fixture history over %d file(s) in %s' % (n, rel(root)))

def cmd_runcorpus(a):
    """Both screen arms against an ARBITRARY binary and corpus, and stop.

    This exists so test/capsweepcheck.sh can drive the real screen_core — the census, the refusal, the
    denominator and the corpus fingerprint — against a stub binary and a six-row synthetic corpus,
    WITHOUT a patched build. Every one of those rules was added because it had already failed silently
    once; a rule whose gate cannot go red is a comment.
    """
    croot  = assert_corpus_clean(a.corpus)
    corpus = [l for l in pathlib.Path(a.corpus_file).read_text().splitlines()
              if l.strip() and not l.lstrip().startswith('#')]
    bump   = {}
    for kv in (a.bump or []):
        if '=' not in kv:
            sys.exit('capsweep: --bump takes NAME=VALUE, got %r' % kv)
        k, v = kv.split('=', 1)
        bump[k] = v
    before = fingerprint_corpus(croot)
    # NOT --out: that flag already means "the document emit writes" and defaults to docs/TUNING.md, so
    # reusing it here would overwrite the generated document with a record file.
    screen_core(pathlib.Path(a.binary).resolve(), croot, corpus, bump,
                pathlib.Path(a.records or (pathlib.Path(a.corpus).parent / 'screen.tsv')),
                'synthetic', before)

if __name__ == '__main__':
    ap = argparse.ArgumentParser()
    ap.add_argument('phase', choices=['prepare', 'screen', 'sweep', 'emit', 'patch', 'check-corpus',
                                     'run-corpus', 'plant-history'])
    ap.add_argument('--scratch', default=str(pathlib.Path.home() / '.cache' / 'ripwire-capsweep'))
    ap.add_argument('--jobs', type=int, default=8)
    ap.add_argument('--data', default=str(HERE), help='emit: dir holding the frozen tunable/sweep TSV')
    ap.add_argument('--out',  default=str(REPO / 'docs' / 'TUNING.md'), help='emit: the document to write')
    ap.add_argument('--check', action='store_true', help='emit: compare instead of writing; exit 1 on drift')
    ap.add_argument('--root', default=None, help='patch: the SCRATCH tree to rewrite (never the repo)')
    ap.add_argument('--corpus', default=None, help='check-corpus/run-corpus: the frozen corpus')
    ap.add_argument('--binary', default=None, help='run-corpus: the binary (or stub) to run')
    ap.add_argument('--corpus-file', default=None, help='run-corpus: the invocation list to run')
    ap.add_argument('--bump', action='append', default=None, help='run-corpus: NAME=VALUE for the bumped arm')
    ap.add_argument('--records', default=None, help='run-corpus: where to write the screen records')
    a = ap.parse_args()
    if a.phase == 'patch' and not a.root:
        ap.error('patch requires --root TREE')
    if a.phase == 'check-corpus' and not a.corpus:
        ap.error('check-corpus requires --corpus DIR')
    if a.phase == 'run-corpus' and not (a.corpus and a.binary and a.corpus_file):
        ap.error('run-corpus requires --binary, --corpus and --corpus-file')
    if a.phase == 'plant-history' and not a.root:
        ap.error('plant-history requires --root TREE')
    {'prepare': cmd_prepare, 'screen': cmd_screen, 'sweep': cmd_sweep, 'emit': cmd_emit,
     'patch': cmd_patch, 'check-corpus': cmd_checkcorpus, 'run-corpus': cmd_runcorpus,
     'plant-history': cmd_planthistory}[a.phase](a)
