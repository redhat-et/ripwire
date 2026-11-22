#!/usr/bin/env bash
# benchxmlpathcheck.sh — bench Python decodes the XML attribute values it reads before using them as paths or names (#719).
#
# WHY. ripwire's emitter (serialize.h escapeXml) writes & < > " ' as &amp; &lt; &gt; &quot; &apos; and \t \n \r as &#9; &#10; &#13;.
# bench/arb/run_arb.py's query_files/trace_files took the <f p=>, <frame p=>, <hop p=> values out with a regex and handed them to
# norm_path undecoded, so a file `src/a&b.py` ranked as `src/a&amp;b.py` and could never match its gold path (affected_tests already
# decoded; the other two did not). The same capture-and-use shape was swept across bench/: tgrep-h2h's rw_hitset (joined to rg's
# decoded paths), tokenaudit's derive_targets (names and a file that ride back in as CLI args). Each is driven here with a fake
# ripwire binary that emits the escaped spellings.
#
# Not covered (needs tiktoken / an MCP server, and its change is one html.unescape): bench/bench_proof.py files_in,
# bench/spec_trace.py seed.
#
# CAN-GO-RED: ARB_ROOT=<a tree> runs the same arms against that tree's bench/. Pointing it at a checkout of a pre-fix main fails
# every arm (recorded in the lane notes); the arms count the rows they saw and fail on zero (a vacuous arm cannot pass).
#
# Usage:  bash test/benchxmlpathcheck.sh   |   ARB_ROOT=/path/to/older/tree bash test/benchxmlpathcheck.sh
set -u
ROOT="$( cd "$( dirname "$0" )/.." && pwd )"
SRC="${ARB_ROOT:-$ROOT}"
TMP="$( mktemp -d )"; trap 'rm -rf "$TMP"' EXIT
fail=0
no() { echo "FAIL: $*"; fail=1; }

SNAP="$TMP/snap"; mkdir -p "$SNAP"
FAKE="$TMP/fakeripwire"
cat > "$FAKE" <<'EOF'
#!/bin/sh
# fake ripwire: argv = <root> <verb>...
snap="$1"; shift
case "$1" in
  --query=*)      printf '<r><f p="%s/src/a&amp;b.py"><s n="x"/></f><f p="src/q&lt;r&gt;.py"/><f p="src/it&apos;s&quot;.py"/></r>\n' "$snap" ;;
  --from-trace=*) printf '<trace><frame n="f" p="src/a&amp;b.py:12"/><hop t="x" p="tests/t&amp;t.py"/><frame n="g" p="src/c.py"/><f p="src/z&amp;.py"/></trace>\n' ;;
  --top-k=*)      printf '<r><f p="src/a&amp;b.py"><s n="operator&lt;" l="1"/></f></r>\n' ;;
  --grep=*)       printf '<grep n="1"><f p="src/a&amp;b.py"><hit l="3"/><at l="9"/></f></grep>\n' ;;
  --affected=*)   printf '<affected><test p="tests/a&amp;b.py"/></affected>\n' ;;
  *) exit 1 ;;
esac
EOF
chmod +x "$FAKE"

out="$( python3 - "$SRC" "$FAKE" "$SNAP" <<'EOF'
import importlib.util, sys
src, fake, snap = sys.argv[1:4]
def load(name, rel):
    spec = importlib.util.spec_from_file_location(name, src + "/" + rel)
    m = importlib.util.module_from_spec(spec); sys.path.insert(0, src + "/" + rel.rsplit("/", 1)[0])
    spec.loader.exec_module(m); return m
bad = 0
def eq(label, got, want):
    global bad
    ok = got == want and len(want) > 0
    print(("ok   " if ok else "FAIL ") + label + ("" if ok else "\n       got  %r\n       want %r" % (got, want)))
    bad += not ok
arb = load("run_arb", "bench/arb/run_arb.py")
eq("query_files <f p=> decoded (& < > ' \")", arb.query_files(fake, snap, "q"),
   ["src/a&b.py", "src/q<r>.py", "src/it's\".py"])
eq("trace_files <frame p=>, <hop p=>, <f p=> decoded, hop spliced after frame 1", arb.trace_files(fake, snap, "t"),
   ["src/a&b.py", "tests/t&t.py", "src/c.py", "src/z&.py"])
eq("affected_tests still decoded (control)", arb.affected_tests(fake, snap, "x"), ["tests/a&b.py"])
try:
    arms = load("tgrep_arms", "bench/tgrep-h2h/arms.py")
    out = b'<grep n="1"><f p="src/a&amp;b.py"><hit l="3"/><at l="9"/></f></grep>'
    eq("tgrep-h2h rw_hitset path decoded", sorted(arms.rw_hitset(out, snap)), [("src/a&b.py", 3), ("src/a&b.py", 9)])
except Exception as e:
    print("FAIL tgrep-h2h arms import/run: %r" % (e,)); bad += 1
try:
    ta = load("tokenaudit_sweep", "bench/tokenaudit/sweep.py")
    eq("tokenaudit derive_targets symbol + file decoded", list(ta.derive_targets(fake, snap)), ["operator<", "src/a&b.py"])
except Exception as e:
    print("FAIL tokenaudit sweep import/run: %r" % (e,)); bad += 1
sys.exit(1 if bad else 0)
EOF
)"; rc=$?
echo "$out"
[ $rc -eq 0 ] || no "an XML-encoded bench path/name was not decoded (rc=$rc)"
[ $fail -eq 0 ] && { echo "benchxmlpathcheck: PASS"; exit 0; }
echo "benchxmlpathcheck: FAIL"; exit 1
