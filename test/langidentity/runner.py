#!/usr/bin/env python3
"""runner.py -- the engine of test/langidentitycheck.sh (read that file's header for the contract).

Runs one fixed argv set per corpus with a BASE and a HEAD ripwire binary, compares stdout bytes, stderr (after
norm_stderr) and the exit code, and classifies every argv SAME | DIFF | EMPTY | ERROR. Never spawns a shell: every
argv is a list.

usage: runner.py [--base BIN] [--ratchet-only] --head BIN --root REPO --scratch DIR --manifest FILE --ratchet FILE
                 [--langs a,b] [--syms FILE] [--intended FILE] [--repo LANG:DIR]... [--jobs N]
                 [--timeout S] [--keep DIR] [--list]
(--ratchet-only runs just the ratchet line against --head, which needs no --base.)
Exit 0 = every argv SAME (or DIFF with an --intended row), the self-test fired, the ratchet holds.
Exit 2 = an unusable --intended file or --repo spec (nothing was compared).
"""
import argparse
import json
import os
import re
import subprocess
import sys
import time
from concurrent.futures import ThreadPoolExecutor

# The verbs that need no symbol (run once per corpus), and those that take one (run per symbol).
CORPUS_VERBS = [[], ['--deps', '--limit=100000'], ['--skipped'], ['--clones', '--limit=100000'], ['--dead-code'],
                ['--hotspots'], ['--tree'], ['--nonlocal-state']]
SYMBOL_VERBS = ['--callers', '--callees', '--impact', '--uses', '--whereis', '--expand']
TOP_PER_LANG = 5

# Map rows are grouped by file with no language attribute, so the "top 5 per language" filter is by extension.
EXTS = {
    'cpp': ('.cpp', '.cc', '.cxx', '.hpp', '.hh', '.hxx', '.h'), 'c': ('.c', '.h'), 'py': ('.py', '.pyi'),
    'ts': ('.ts', '.tsx'), 'js': ('.js', '.jsx', '.mjs', '.cjs'), 'go': ('.go',), 'rs': ('.rs',),
    'swift': ('.swift',), 'objc': ('.m', '.mm', '.h'), 'sh': ('.sh', '.bash'), 'java': ('.java',),
    'rb': ('.rb',), 'cs': ('.cs',), 'php': ('.php', '.phtml'), 'lua': ('.lua',), 'ex': ('.ex', '.exs'),
    'dart': ('.dart',), 'kt': ('.kt', '.kts'), 'gd': ('.gd',), 'clj': ('.clj', '.cljs', '.cljc', '.bb'),
}

# The only stderr text that may differ between two builds of the same behaviour: the provenance tag a notice ends
# with, "(FILE:LINE, FUNCTION-SIGNATURE — logged once per site)" (src/infra/diagnostics.cpp). Its LINE and SIGNATURE
# move whenever a slice edits that source file; the FILE name and the notice text before the tag are kept, so a
# changed, added or dropped message still reads as DIFF. Each binary's own TMPDIR is the only other variable part.
SITE_TAG = re.compile(rb'\(([A-Za-z0-9_./+-]+):\d+, [^\n]*? \xe2\x80\x94 logged once per site\)')
# A comparison with nothing in it: the root element of BASE's stdout has no child element (count="0" and friends).
ROOT_ELEM = re.compile(rb'<([A-Za-z_][\w-]*) schema="[^"]*"[^>]*>')


def norm_stderr(err, tmpdir):
    """stderr with the provenance tag's line number and signature, and this binary's TMPDIR, replaced by fixed text."""
    for t in {tmpdir, os.path.realpath(tmpdir)}:
        err = err.replace(t.encode(), b'<TMP>')
    return SITE_TAG.sub(lambda m: b'(' + m.group(1) + b':N, <signature> \xe2\x80\x94 logged once per site)', err)


def first_diff(x, y):
    """-> (byte offset, 1-based line in x) of the first difference between two byte strings."""
    n, lim = 0, min(len(x), len(y))
    while n < lim and x[n] == y[n]:
        n += 1
    return n, x.count(b'\n', 0, n) + 1


def zero_rows(out):
    """True when the first schema-tagged element of this stdout has no child element: a SAME that compared no data."""
    m = ROOT_ELEM.search(out)
    if not m:
        return False
    return m.group(0).endswith(b'/>') or out[m.end():].lstrip().startswith(b'</' + m.group(1) + b'>')


def run(binary, argv, cwd, tmpdir, timeout):
    """-> (rc, stdout, stderr, wall_seconds, error_text). error_text is None when the process ran to exit."""
    env = dict(os.environ, TMPDIR=tmpdir)
    t0 = time.monotonic()
    try:
        r = subprocess.run([binary] + argv, cwd=cwd, env=env, stdin=subprocess.DEVNULL, stdout=subprocess.PIPE,
                           stderr=subprocess.PIPE, timeout=timeout)
    except subprocess.TimeoutExpired:
        return None, b'', b'', time.monotonic() - t0, 'timeout after %ss' % timeout
    except OSError as e:
        return None, b'', b'', time.monotonic() - t0, 'cannot start: %s' % e
    return r.returncode, r.stdout, r.stderr, time.monotonic() - t0, None


def classify(b, h, tmp=None):
    """b, h = run() tuples -> (status, detail). ERROR beats EMPTY beats DIFF beats SAME. A DIFF is stdout first, then
    stderr after norm_stderr (tmp = {'base': TMPDIR, 'head': TMPDIR}; None compares stdout only, as the self-test does)."""
    if b[4] or h[4]:
        return 'ERROR', 'base: %s; head: %s' % (b[4] or 'ran', h[4] or 'ran')
    if b[0] != 0 or h[0] != 0:
        return 'ERROR', 'rc base=%s head=%s' % (b[0], h[0])
    if not b[1] or not h[1]:
        return 'EMPTY', 'stdout bytes base=%d head=%d (a vacuous comparison)' % (len(b[1]), len(h[1]))
    if b[1] != h[1]:
        n, line = first_diff(b[1], h[1])
        return 'DIFF', 'bytes base=%d head=%d, first difference at byte %d (line %d)' % (len(b[1]), len(h[1]), n, line)
    if tmp is not None:
        eb, eh = norm_stderr(b[2], tmp['base']), norm_stderr(h[2], tmp['head'])
        if eb != eh:
            n, line = first_diff(eb, eh)
            return 'DIFF', 'stderr only: bytes base=%d head=%d, first difference at stderr line %d' % (len(eb), len(eh), line)
    return 'SAME', ''


def materialize(root, dirs, dest):
    """Copy each fixture directory (same relative path) into a fresh git repository with one commit at a fixed date.

    A fixture run inside the host checkout pays for that checkout's whole history and every branch it carries
    (--hotspots, --whereis), and its answer would move with that state. In its own repository the answer depends on
    the fixture alone, and the path (test/xfix) still classifies it the way the real tree does."""
    os.makedirs(dest, exist_ok=True)
    for d in dirs:
        target = os.path.join(dest, d)
        os.makedirs(os.path.dirname(target), exist_ok=True)
        if subprocess.run(['cp', '-R', os.path.join(root, d), target], stdout=subprocess.DEVNULL).returncode != 0:
            return None
    env = dict(os.environ, GIT_AUTHOR_DATE='2026-01-01T00:00:00Z', GIT_COMMITTER_DATE='2026-01-01T00:00:00Z',
               GIT_CONFIG_GLOBAL=os.devnull, GIT_CONFIG_SYSTEM=os.devnull)
    for cmd in (['git', 'init', '-q'], ['git', 'add', '-A', '-f'],
                ['git', '-c', 'user.name=fixture', '-c', 'user.email=fixture@example.invalid', 'commit', '-q', '-m', 'fixtures']):
        try:
            if subprocess.run(cmd, cwd=dest, env=env, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL).returncode != 0:
                return None
        except OSError:
            return None
    return dest


def read_tsv(path):
    rows = []
    with open(path, encoding='utf-8', errors='replace') as fh:
        for n, raw in enumerate(fh, 1):
            s = raw.rstrip('\n')
            if not s.strip() or s.lstrip().startswith('#'):
                continue
            rows.append((n, s.split('\t')))
    return rows


def symbols_of(binary, root, cwd, tmpdir, timeout):
    """Every symbol of a corpus, ranked: [(file, name, kind, rank)]; None when the map could not be read."""
    rc, out, _e, _w, err = run(binary, [root, '--top-k=100000', '--json', '--no-cache'], cwd, tmpdir, timeout)
    if err or rc != 0:
        return None
    try:
        doc = json.loads(out.decode('utf-8', 'replace'))
    except ValueError:
        return None
    syms = []
    for row in doc.get('r', []):
        for s in row.get('s', []):
            syms.append((row.get('p', ''), s.get('n', ''), s.get('t', ''), float(s.get('k', 0))))
    return syms


def top_names(syms, lang, count):
    """The `count` highest-ranked distinct names whose file extension belongs to `lang`."""
    exts = EXTS.get(lang)
    seen, picked = set(), []
    for p, n, _t, _k in sorted(syms, key=lambda s: -s[3]):
        # <file-scope> and other <pseudo> rows are not symbols a verb can name usefully
        if not n or n.startswith('<') or n in seen or (exts and not p.lower().endswith(exts)):
            continue
        seen.add(n)
        picked.append(n)
        if len(picked) == count:
            break
    return picked


def parse_args():
    ap = argparse.ArgumentParser()
    ap.add_argument('--base', default='')
    ap.add_argument('--head', required=True)
    ap.add_argument('--root', required=True)
    ap.add_argument('--scratch', required=True)
    ap.add_argument('--manifest', required=True)
    ap.add_argument('--ratchet', required=True)
    ap.add_argument('--langs', default='')
    ap.add_argument('--syms', default='')
    ap.add_argument('--intended', default='')
    ap.add_argument('--repo', action='append', default=[])
    ap.add_argument('--jobs', type=int, default=1)
    ap.add_argument('--timeout', type=int, default=600)
    ap.add_argument('--keep', default='')
    ap.add_argument('--list', action='store_true')
    ap.add_argument('--ratchet-only', action='store_true')
    return ap.parse_args()


def select_corpora(a):
    """Manifest fixtures, then caller-supplied repos, filtered by --langs. -> list of dicts, or None after a FAIL line."""
    want = [x for x in a.langs.split(',') if x]
    corpora = []
    for _n, cols in read_tsv(a.manifest):
        if len(cols) < 2 or cols[1] == '-' or (want and cols[0] not in want):
            continue
        corpora.append({'id': '%s/%s' % (cols[0], os.path.basename(cols[1].rstrip('/'))), 'lang': cols[0],
                        'root': cols[1], 'kind': 'fixture', 'cwd': ''})
    for spec in a.repo:
        lang, _sep, path = spec.partition(':')
        if not path or not os.path.isdir(path) or lang not in EXTS:
            print('  FAIL  --repo=%s: expected LANG:DIR, LANG one of %s, DIR an existing directory' % (spec, ' '.join(EXTS)))
            raise SystemExit(2)
        # an explicit --repo always runs: --langs filters manifest rows only, so the untouched-language repository a
        # slice adds is never dropped silently
        corpora.append({'id': '%s/%s' % (lang, os.path.basename(path.rstrip('/'))), 'lang': lang,
                        'root': os.path.abspath(path), 'kind': 'repo', 'cwd': a.root})
    if not corpora:
        print('  FAIL  no corpus selected (--langs=%s matched no manifest row and no --repo)' % a.langs)
        return None
    # the id keys the plan, the corpus line and every --intended row: a repeat would run one corpus's plan on both
    ids = [c['id'] for c in corpora]
    dup = sorted({i for i in ids if ids.count(i) > 1})
    if dup:
        print('  FAIL  duplicate corpus id(s): %s (LANG/basename must be unique; rename or drop one directory)' % ' '.join(dup))
        raise SystemExit(2)
    return corpora


def read_touched(path):
    """--syms: NAME or LANG:NAME per line -> [(lang or '', name)]."""
    touched = []
    if path:
        for _n, cols in read_tsv(path):
            lang, sep, name = cols[0].strip().partition(':')
            touched.append((lang, name) if sep and lang in EXTS else ('', cols[0].strip()))
    return touched


ARM_PATH = re.compile(r'test/[A-Za-z0-9_]+check\.sh')


def read_intended(path, root):
    """--intended: CORPUS <TAB> ARGV <TAB> ARM, matched exactly (no globs; a row waives one argv of one corpus).
    ARM must start with an existing test/*check.sh, the gate arm that pins the new behaviour. -> rows, or None after
    a FAIL line (the caller exits 2: nothing is compared against a waiver list that cannot be trusted)."""
    rows, bad = [], False
    if path:
        for n, cols in read_tsv(path):
            cols = [c.strip() for c in cols]
            why = ''
            if len(cols) < 3 or not all(cols[:3]):
                why = 'an intended row is CORPUS<TAB>ARGV<TAB>ARM, all three non-empty'
            elif any(ch in cols[0] + cols[1] for ch in '*?['):
                why = 'no wildcards: name one corpus id and one argv exactly as the report prints them (one row per DIFF)'
            elif not ARM_PATH.match(cols[2]) or not os.path.isfile(os.path.join(root, ARM_PATH.match(cols[2]).group(0))):
                why = 'ARM must start with an existing test/<name>check.sh (the arm that pins the change), got "%s"' % cols[2]
            if why:
                print('  FAIL  %s line %d: %s' % (path, n, why))
                bad = True
                continue
            rows.append({'line': n, 'corpus': cols[0], 'argv': cols[1], 'arm': cols[2], 'hits': 0})
    return None if bad else rows


def check_intended_targets(intended, plans, path):
    """Every row must name a selected corpus and an argv in that corpus's plan. -> False after FAIL lines."""
    ok = True
    for row in intended:
        verbs = plans.get(row['corpus'])
        if verbs is None:
            print('  FAIL  %s line %d: corpus "%s" is not among the selected corpora (%s)' % (
                path, row['line'], row['corpus'], ' '.join(sorted(plans)) or 'none'))
            ok = False
        elif row['argv'] not in [verb_text(v) for v in verbs]:
            print('  FAIL  %s line %d: argv "%s" is not in the plan of %s' % (path, row['line'], row['argv'], row['corpus']))
            ok = False
    return ok


def verb_text(verb):
    return ' '.join(verb) if verb else '(map)'


class Session:
    """One harness run: the binaries, the per-binary TMPDIRs, the tallies and the failure list."""

    def __init__(self, a, intended, touched):
        self.a = a
        self.intended = intended
        self.touched = touched
        self.binary = {'base': a.base, 'head': a.head}
        self.tmp = {}
        for label in ('base', 'head'):
            self.tmp[label] = os.path.join(a.scratch, 'tmp-' + label)
            os.makedirs(self.tmp[label], exist_ok=True)
        self.fails = []
        self.counts = {'SAME': 0, 'DIFF': 0, 'EMPTY': 0, 'ERROR': 0, 'intended': 0, 'zero': 0}
        self.wall = {'base': 0.0, 'head': 0.0}
        self.biggest = (0, None)  # (symbol count, corpus) for the self-test
        self.headers = {}

    def both(self, c, verb):
        """Run one argv with BASE and HEAD. They overlap: the answers are independent, and a run is mostly process start."""
        argv = [c['root']] + verb + ['--no-cache']
        with ThreadPoolExecutor(max_workers=2) as pair:
            fb = pair.submit(run, self.binary['base'], argv, c['cwd'], self.tmp['base'], self.a.timeout)
            fh = pair.submit(run, self.binary['head'], argv, c['cwd'], self.tmp['head'], self.a.timeout)
            return verb, fb.result(), fh.result()

    def plan(self, c):
        """The argv list of one corpus, or None when its symbol list cannot be read."""
        base_syms = symbols_of(self.binary['base'], c['root'], c['cwd'], self.tmp['base'], self.a.timeout)
        head_syms = symbols_of(self.binary['head'], c['root'], c['cwd'], self.tmp['head'], self.a.timeout)
        if base_syms is None or head_syms is None:
            print('corpus %s (%s)' % (c['id'], c['root']))
            print('  ERROR  (symbol list)  the %s map could not be read as JSON' % ('base' if base_syms is None else 'head'))
            self.counts['ERROR'] += 1
            self.fails.append('%s: symbol list unreadable' % c['id'])
            return None
        if len(base_syms) > self.biggest[0]:
            self.biggest = (len(base_syms), c)
        names = top_names(base_syms, c['lang'], TOP_PER_LANG)
        known = {s[1] for s in base_syms} | {s[1] for s in head_syms}
        extra, absent = [], 0
        for lang, name in self.touched:
            if lang and lang != c['lang']:
                continue
            if name not in known:
                absent += 1
            elif name not in names and name not in extra:
                extra.append(name)
        verbs = list(CORPUS_VERBS)
        for name in names + extra:
            verbs += [[v + '=' + name] for v in SYMBOL_VERBS]
        self.headers[c['id']] = ('corpus %s (%s): %d symbols, %d top + %d touched named, %d argv%s' % (
            c['id'], c['root'], len(base_syms), len(names), len(extra), len(verbs),
            ('; %d touched name(s) absent from both maps' % absent) if absent else ''))
        return verbs

    def explain(self, corpus_id, text):
        """The --intended arm that explains a DIFF of this argv in this corpus, or ''."""
        for row in self.intended:
            if corpus_id == row['corpus'] and text == row['argv']:
                row['hits'] += 1
                return row['arm']
        return ''

    def keep(self, c, text, b, h):
        d = os.path.join(self.a.keep, c['id'].replace('/', '_'), re.sub(r'[^A-Za-z0-9._=-]', '_', text))
        os.makedirs(d, exist_ok=True)
        for lab, r in (('base', b), ('head', h)):
            for ext, data in (('.out', r[1]), ('.err', r[2])):
                with open(os.path.join(d, lab + ext), 'wb') as fh:
                    fh.write(data)

    def report(self, c, verb, b, h):
        status, detail = classify(b, h, self.tmp)
        text = verb_text(verb)
        if status == 'SAME' and zero_rows(b[1]):
            self.counts['zero'] += 1
            detail = '(zero rows in both)'
        self.wall['base'] += b[3]
        self.wall['head'] += h[3]
        arm = self.explain(c['id'], text) if status == 'DIFF' else ''
        if arm:
            self.counts['intended'] += 1
        elif status != 'SAME':
            self.fails.append('%s %s: %s' % (c['id'], text, 'unexplained DIFF' if status == 'DIFF' else status))
        self.counts[status] += 1
        print('  %-5s %-36s base=%.2fs head=%.2fs%s%s' % (status, text, b[3], h[3], ('  ' + detail) if detail else '',
                                                       ('  [intended: %s]' % arm) if arm else ''))
        if status != 'SAME' and self.a.keep:
            self.keep(c, text, b, h)

    def run_corpus(self, c, verbs):
        if verbs is None:
            return
        print(self.headers[c['id']])
        with ThreadPoolExecutor(max_workers=max(1, self.a.jobs)) as ex:
            results = list(ex.map(lambda v: self.both(c, v), verbs))
        for verb, b, h in results:
            self.report(c, verb, b, h)

    def summary(self, ncorpora):
        n = self.counts
        total = n['SAME'] + n['DIFF'] + n['EMPTY'] + n['ERROR']
        for row in self.intended:
            if row['hits']:
                print('  NOTE  intended row %d (%s) waived %d DIFF: %s | %s' % (
                    row['line'], row['arm'], row['hits'], row['corpus'], row['argv']))
            else:
                print('  NOTE  intended row %d matched no DIFF (stale): %s | %s | %s' % (
                    row['line'], row['corpus'], row['argv'], row['arm']))
        text = ('%d argv over %d corpora: %d SAME (%d with zero rows in both), %d DIFF (%d intended), %d EMPTY, %d ERROR; '
                'wall base=%.1fs head=%.1fs') % (total, ncorpora, n['SAME'], n['zero'], n['DIFF'], n['intended'],
                                                 n['EMPTY'], n['ERROR'], self.wall['base'], self.wall['head'])
        if not self.fails:
            print('  PASS  ' + text)
            return
        print('  FAIL  ' + text)
        for f in self.fails[:30]:
            print('        - ' + f)
        if len(self.fails) > 30:
            print('        ... %d more' % (len(self.fails) - 30))

    def self_test(self):
        """An arm that cannot fail proves nothing: HEAD with a smaller --top-k MUST read as DIFF. -> True when it fired."""
        n_syms, corpus = self.biggest
        if corpus is None or n_syms < 2:
            print('  FAIL  self-test cannot fire: no selected corpus has a map of at least 2 symbols')
            return False
        k = 199 if n_syms > 199 else n_syms - 1
        argv = [corpus['root'], '--no-cache']
        b = run(self.binary['base'], argv, corpus['cwd'], self.tmp['base'], self.a.timeout)
        h = run(self.binary['head'], argv + ['--top-k=%d' % k], corpus['cwd'], self.tmp['head'], self.a.timeout)
        status, detail = classify(b, h)
        if status == 'DIFF':
            print('  PASS  self-test: head with --top-k=%d on %s reads as DIFF (%s)' % (k, corpus['id'], detail))
            return True
        print('  FAIL  self-test: head with --top-k=%d on %s read as %s, so a real change could read as SAME' % (
            k, corpus['id'], status))
        return False


def prepare_fixtures(a, corpora):
    """Point every fixture corpus at the scratch repository holding its copy. -> False after a FAIL line."""
    fixtures = [c for c in corpora if c['kind'] == 'fixture']
    if not fixtures:
        return True
    fixrepo = materialize(a.root, sorted({c['root'] for c in fixtures}), os.path.join(a.scratch, 'fixrepo'))
    if not fixrepo:
        print('  FAIL  could not copy the fixture directories into a scratch git repository (is git installed?)')
        return False
    for c in fixtures:
        c['cwd'] = fixrepo
    return True


def main():
    a = parse_args()
    if a.ratchet_only:
        tmp = os.path.join(a.scratch, 'tmp-head')
        os.makedirs(tmp, exist_ok=True)
        return 1 if ratchet(a, a.head, tmp) else 0
    corpora = select_corpora(a)
    if corpora is None:
        return 1
    intended = read_intended(a.intended, a.root)
    if intended is None:
        return 2
    if a.list:
        for c in corpora:
            print('%s\t%s\t%s' % (c['id'], c['kind'], c['root']))
        return 0
    if not prepare_fixtures(a, corpora):
        return 1
    session = Session(a, intended, read_touched(a.syms))
    plans = {c['id']: session.plan(c) for c in corpora}
    if not check_intended_targets(intended, plans, a.intended):
        return 2
    for c in corpora:
        session.run_corpus(c, plans[c['id']])
    session.summary(len(corpora))
    fired = session.self_test()
    ratchet_fail = ratchet(a, a.head, session.tmp['head'])  # printed last
    return 1 if (session.fails or not fired or ratchet_fail) else 0


PREDICATE = re.compile(r'[=!]=\s*(?<![A-Za-z0-9_])Lang::|(?<![A-Za-z0-9_])Lang::\w+\s*[=!]=')


def count_predicates(listing, perlang):
    """`==`/`!=` lines against a Lang:: enumerator in a --regex listing, one per distinct file:line, per-language files and
    `case` labels left out."""
    seen, count = set(), 0
    for path, body in re.findall(r'<f p="([^"]+)"[^>]*>(.*?)</f>', listing, re.S):
        if os.path.basename(path) in perlang:
            continue
        # honest-lex prints a line holding the pattern twice as ONE row with occ="N" (train 34): read that row too, or every
        # line with two Lang:: mentions drops out of the count (336 -> 250 on the composed tree).
        for line, code in re.findall(r'<hit l="(\d+)" in="[^"]*"(?: occ="\d+")?><!\[CDATA\[(.*?)\]\]></hit>', body, re.S):
            if (path, line) in seen:
                continue
            seen.add((path, line))
            if not re.search(r'\bcase\s+Lang::', code) and PREDICATE.search(code):
                count += 1
    return count


def ratchet(a, head, tmpdir):
    """Print the ratchet line: shared-file `== Lang::X` predicates may not rise. -> True when it FAILS."""
    ceiling, perlang = None, set()
    for _n, cols in read_tsv(a.ratchet):
        if cols[0] == 'ceiling' and len(cols) > 1 and cols[1].isdigit():
            ceiling = int(cols[1])
        elif cols[0] == 'perlang' and len(cols) > 1:
            perlang.add(cols[1])
    if ceiling is None:
        print('  FAIL  ratchet: %s has no "ceiling<TAB>N" row' % a.ratchet)
        return True
    rc, out, _e, _w, err = run(head, [os.path.join(a.root, 'src'), '--regex=Lang::[A-Z][A-Za-z]+', '--limit=100000',
                                      '--no-cache'], a.root, tmpdir, a.timeout)
    if err or rc != 0 or not out:
        print('  FAIL  ratchet: the HEAD binary could not list Lang:: mentions (%s, rc=%s)' % (err or 'ran', rc))
        return True
    count = count_predicates(out.decode('utf-8', 'replace'), perlang)
    if count > ceiling:
        print('  FAIL  ratchet: shared-file "== Lang::" predicates %d > ceiling %d (move the new one into a LangFacts column or a per-language file)' % (count, ceiling))
        return True
    print('  PASS  ratchet: shared-file "== Lang::" predicates %d (ceiling %d)%s' % (
        count, ceiling, '' if count == ceiling else ' -- lower the ceiling in %s to %d' % (os.path.basename(a.ratchet), count)))
    return False


if __name__ == '__main__':
    sys.stdout.reconfigure(line_buffering=True)  # a long run must show progress through a pipe
    sys.exit(main())
