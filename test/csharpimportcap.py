"""C# slice 1a arms, invoked by csharpcheck.sh. Every output comes from the supplied binary."""
import pathlib
import shutil
import subprocess
import sys
import xml.etree.ElementTree as ET

binary, root, scratch = map(pathlib.Path, sys.argv[1:4])
assert sys.argv[4:] in ([], ['--legacy']), 'unknown C# test contract'
legacy = sys.argv[4:] == ['--legacy']


def run(where, *args):
    proc = subprocess.run([str(binary), str(where), *args], capture_output=True, text=True)
    if proc.returncode != 0:
        raise RuntimeError((args, proc.returncode, proc.stderr))
    return proc.stdout


def targets(where):
    xml = ET.fromstring(run(where, '--deps', '--limit=100000', '--no-cache'))
    assert xml.tag == 'deps'
    return [(f.attrib['p'], [i.attrib['t'] for i in f.findall('inc')]) for f in xml.findall('f')]


fixture = root / 'test/csharpimportcapfix'
expected = ['System', 'Demo.Widget', 'Alias', 'GlobalAlias', 'Demo.Widget', 'Demo.Widget', 'Demo',
            'global::Demo.Widget', 'Generic', 'Pair', 'Items', 'Maybe', 'Ptr', 'Demo', 'Demo',
            'Demo /* middle */ . Widget', 'CommentAlias', 'Nested']


def check_rows(where):
    assert targets(where) == [('Imports.cs', expected)], targets(where)


check_rows(fixture)
print('  PASS  C# C1: exact targets, directive order, duplicates, comments, static/global and complex aliases')
for name, line in [('System', 1), ('Alias', 3), ('GlobalAlias', 4), ('Generic', 9), ('Nested', 21)]:
    xml = ET.fromstring(run(fixture, '--uses=' + name, '--no-cache'))
    assert any(u.get('role') == 'import' and u.get('p') == 'Imports.cs:' + str(line) for u in xml.findall('u')), (name, line)
print('  PASS  C# C2: Import use-sites stay at their directives, including global and nested aliases')

# Known gap, slice 2b after the shared binds channel (2a): an alias still names itself in Include,
# and using/static do not narrow these three calls to the RHS class. This refactor must not fix it.
xml = ET.fromstring(run(fixture, '--callees=Run', '--no-cache'))
assert xml.get('graph_ambiguous') == '3', xml.attrib
assert [(s.get('n'), s.get('p')) for s in xml.findall('s')] == [('Ping', 'Types.cs:1'), ('Ping', 'Types.cs:2')]
print('  PASS  C# C3 known-gap (2b): alias remains Alias; all three Ping calls retain both candidates')

# Mutate real source and run the identical row checker. A changed alias and a missing directive
# must each fail it; checking the mutation itself is only the presence guard, never the verdict.
for name, old, new in [('rename', 'using Alias =', 'using Renamed ='), ('remove', 'using System;\n', '')]:
    work = scratch / name
    shutil.copytree(fixture, work)
    source = work / 'Imports.cs'
    original = source.read_text()
    assert old in original
    source.write_text(original.replace(old, new, 1))
    assert source.read_text() != original
    try:
        check_rows(work)
    except AssertionError:
        print('  PASS  C# C4 control: identical row checker rejects actual ' + name + ' mutation')
    else:
        raise AssertionError('row checker accepted ' + name)

cache = scratch / 'using.cache'
fresh = run(fixture, '--deps', '--no-cache')
cold = run(fixture, '--deps', '--cache=' + str(cache))
warm = run(fixture, '--deps', '--cache=' + str(cache))
assert fresh == cold == warm
print('  PASS  C# C5: using fixture fresh/cold/warm dependency bytes identical')

# Observable rows alone also pass on the old walk. Check the actual embedded query, not merely
# the new source beside an old binary. --legacy validates BASE's old contract before implementation.
captured = b'(using_directive) @import.path' in binary.read_bytes()
retired = 'csharpUsingTarget' not in (root / 'src/ingest_relations.h').read_text()
assert captured == (not legacy), 'C# capture mechanism does not match the requested BASE/HEAD contract'
if not legacy:
    assert retired, 'retired C# extractor remains in HEAD source'
print('  PASS  C# C7: ' + ('BASE still uses the old walk' if legacy else 'embedded @import.path; old extractor deleted'))

# Shared-capture disclosure, as in Python #382: a nonempty import beyond the bound is partial;
# deep containers without an import no longer trigger the retired walk's disclosure. Edges do not widen.
for depth in [254, 255, 256, 257, 258]:
    for mode in ['using', 'empty', 'top']:
        work = scratch / ('depth-' + str(depth) + '-' + mode)
        work.mkdir()
        pairs, pp = divmod(depth, 2)
        source = ('using Top.Level;\n' if mode == 'top' else '')
        source += ''.join('namespace N%d {\n' % i for i in range(pairs))
        source += '#if FLAG\n' if pp else ''
        source += 'using Deep.Target;\n' if mode == 'using' else '\n'
        source += '#endif\n' if pp else ''
        source += '}\n' * pairs
        (work / 'Probe.cs').write_text(source)
        expected_rows = [('Probe.cs', ['Top.Level'])] if mode == 'top' else (
            [('Probe.cs', ['Deep.Target'])] if mode == 'using' and depth <= 256 else [])
        assert targets(work) == expected_rows, (depth, mode, targets(work))
        cache_file = scratch / (work.name + '.cache')
        cold_stat = None
        for cache_arg in ['--no-cache', '--cache=' + str(scratch / (work.name + '.cache')),
                          '--cache=' + str(scratch / (work.name + '.cache'))]:
            skipped = ET.fromstring(run(work, '--skipped', cache_arg)).find('skipped')
            assert skipped is not None
            partial = depth > 256 and (legacy or mode == 'using')
            assert int(skipped.get('extract_partial', '0')) == int(partial), (depth, mode, skipped.attrib)
            if cache_arg != '--no-cache':
                stat = cache_file.stat()
                stamp = (stat.st_ino, stat.st_mtime_ns)
                if cold_stat is not None:
                    assert (stamp != cold_stat) == partial, (depth, mode, cold_stat, stamp)
                cold_stat = stamp
print('  PASS  C# C6: 254/255/256/257/258 boundary, using/empty/top; cold/warm disclosure and cache eligibility')
