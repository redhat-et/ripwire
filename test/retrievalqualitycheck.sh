#!/usr/bin/env bash
# A7 retrieval gate: adversarial relevance fixtures plus corrected evaluator identity semantics.
set -u
ROOT="$( cd "$( dirname "$0" )/.." && pwd )"
BIN="${1:-${RIPWIRE_BIN:-$ROOT/build/ripwire}}"
[ "${BIN#/}" = "$BIN" ] && BIN="$ROOT/$BIN"
FIX="$ROOT/test/retrievalfix"
TMP="$( mktemp -d )"; trap 'rm -rf "$TMP"' EXIT
fail=0
ok(){ printf '  PASS  %s\n' "$*"; }
no(){ printf '  FAIL  %s\n' "$*"; fail=1; }
run(){ "$BIN" "$FIX" "$1" --format=candidates --top-k=20 --no-cache >"$2" 2>/dev/null; }

run '--for=server request timeout config' "$TMP/path.xml"
first="$( sed -n 's/.*<cand r="1"[^>]* p="\([^"]*\)".*/\1/p' "$TMP/path.xml" )"
# R-R (2026-08-24): root-relative emission drops the leading "./" (and any root prefix), so a path AT the
# top of the corpus no longer has a '/' in front of it. Accept the bare spelling too.
[[ "$first" == *'/server/config.py' || "$first" == 'server/config.py' ]] && ok 'duplicate basename resolved by semantic evidence; evaluator keeps exact path identity' \
    || no "server/config.py not first ($first)"

run '--for=protocol adapter' "$TMP/gen-control.xml"
run '--for=generated protocol adapter' "$TMP/gen.xml"
if grep -q 'generated/client.py' "$TMP/gen.xml" && ! grep -q 'noise_pb2.py' "$TMP/gen.xml" && python3 - "$TMP/gen-control.xml" "$TMP/gen.xml" <<'PY'
import sys, xml.etree.ElementTree as ET
def rank(path):
    for c in ET.parse(path).getroot().findall('cand'):
        # R-R: root-relative emission means a path at the corpus root has no leading '/'
        pp = c.attrib.get('p','')
        if pp.endswith('/generated/client.py') or pp == 'generated/client.py': return int(c.attrib['r'])
    return 10**9
assert rank(sys.argv[2]) < rank(sys.argv[1]), (rank(sys.argv[1]),rank(sys.argv[2]))
PY
then ok 'explicit generated query promotes retained generated artifact; hard-denylisted pb2 stays absent'
else no 'generated explicit-query/control or hard denylist policy regressed'
fi

run '--for=deployment rollback handbook' "$TMP/doc.xml"
run '--for=telemetry bridge dependency' "$TMP/json.xml"
grep -q 'guide.md' "$TMP/doc.xml" && grep -q 'package.json' "$TMP/json.xml" \
    && ok 'documentation and JSON are retrievable' || no 'documentation/JSON retrieval regressed'

run '--for=native checksum binding' "$TMP/ffi.xml"
grep -q 'native_bind.cpp' "$TMP/ffi.xml" && grep -q 'bridge.py' "$TMP/ffi.xml" \
    && ok 'cross-language binding query surfaces both sides despite same-name distractor' || no 'cross-language binding retrieval regressed'

# Unit-test the evaluator's identity rules directly: duplicate basenames get no fallback credit and scope
# is load-bearing for same-name methods. Import through its path without requiring package installation.
python3 - "$ROOT" <<'PY' || fail=1
import importlib.util, pathlib, sys
root=pathlib.Path(sys.argv[1]); p=root/'bench/locbench/run_locbench.py'
s=importlib.util.spec_from_file_location('locbench_eval',p); m=importlib.util.module_from_spec(s); s.loader.exec_module(m)
u=['a/config.py','b/config.py','scoped.py']
assert m.file_ranks(['a/config.py'],{'b/config.py'},u)==[None]
c=[dict(path='scoped.py',name='run',canon='scoped.py::Worker::run'),dict(path='scoped.py',name='run',canon='scoped.py::Server::run')]
assert m.func_ranks(c,[('scoped.py','Server','run')],u)==[1]
print('  PASS  evaluator rejects duplicate-basename and wrong-scope false credit')
PY

[ "$fail" = 0 ] && echo 'ALL PASS' || echo 'FAILURES ABOVE'
exit "$fail"
