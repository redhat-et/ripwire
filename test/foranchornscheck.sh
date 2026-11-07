#!/usr/bin/env bash
# foranchornscheck.sh — two anchor choices of a --for answer (lane anchor-ns):
#   N1 ANCHOR-TEST-ONLY (src/subjectanchor.h routeAnchorUncommitted): a name-exact anchor with no source-class definition among two
#      or more definitions does not commit the route: it ranks the words (route= subtoken+body..., "not committed", the anchors as a
#      hint, confidence low). Silent: ONE definition (a test-only helper is the only thing by that name) and NO definition (an env
#      var: the <shortkey>/<lit> route) stay name-exact, as does a source-backed anchor.
#   N4 PATH-WORD-NAMESAKE (src/mention.h namesakeFileByPathWord): an identifier with several definitions is lifted at the ONE whose
#      file stem or parent directory another task word names. Silent: two words naming two of them, a word naming several, no
#      such word.
#   Each arm with a positive twin; CLI and MCP; determinism; well-formed XML.
# Usage: bash test/foranchornscheck.sh [BIN]   |   RIPWIRE_BIN=asan/ripwire bash test/foranchornscheck.sh
set -u
ROOT="$( cd "$( dirname "$0" )/.." && pwd )"
BIN="${1:-${RIPWIRE_BIN:-$ROOT/build/ripwire}}"
[ "${BIN#/}" = "$BIN" ] && BIN="$ROOT/$BIN"
[ -x "$BIN" ] || { echo "no ripwire binary at $BIN - build first"; exit 2; }
TMP="$( mktemp -d )"; trap 'rm -rf "$TMP"' EXIT
fail=0
ok(){ printf '  PASS  %s\n' "$*" || { fail=1; : > "$TMP/failed"; printf '  FAIL  could not write the PASS line for: %s\n' "$*"; }; return 0; }
no(){ printf '  FAIL  %s\n' "$*"; fail=1; : > "$TMP/failed"; }   # the marker file survives a $( ) subshell, where fail=1 would not
echo "foranchornscheck: BIN=$BIN"
# every answer an arm reads must exist: a crash or an empty answer is a FAIL, never an absence
ask(){
    local out rc
    out="$( cd "$1" && "$BIN" "$1" --no-cache "--for=$2" 2>/dev/null </dev/null )"; rc=$?
    if [ "$rc" -ne 0 ] || [ -z "$out" ]; then no "ask rc=$rc bytes=${#out}: $2" >&2; printf '@@NOANSWER'; return 0; fi
    printf '%s' "$out"
}
mcpfor(){ ( cd "$1" && HOME="$TMP/mcphome" TMPDIR="$TMP/mcphome/" python3 - "$BIN" "$1" "$2" <<'X'
import json,subprocess,sys
b,repo,q=sys.argv[1:4]
req=json.dumps({"jsonrpc":"2.0","id":1,"method":"tools/call","params":{"name":"for","arguments":{"path":repo,"task":q}}})+"\n"
p=subprocess.run([b,"--mcp"],input=req.encode(),capture_output=True,timeout=300,cwd=repo)
out=""
for l in p.stdout.decode('utf8','replace').splitlines():
    try:d=json.loads(l)
    except Exception:continue
    if d.get("id")==1:
        out="".join(x.get("text","") for x in d["result"]["content"])
print(out if (p.returncode==0 and out) else "@@NOANSWER")
X
) ; }
mkdir -p "$TMP/mcphome"
route(){ printf '%s' "$1" | python3 -c 'import re,sys; b=sys.stdin.read(); m=re.search(r"route=\"([^\"]*)\"",b); print(m.group(1) if m else "@@NONE")'; }
conf(){ printf '%s' "$1" | python3 -c 'import re,sys; m=re.search(r"confidence=\"(\w+)\"",sys.stdin.read()); print(m.group(1) if m else "@@NONE")'; }
# the p= of the first ranked row named $2 (CLI <d n= p=>, MCP rows carry the same attributes)
firstp(){ printf '%s' "$1" | python3 -c '
import re,sys
b=sys.stdin.read(); n=sys.argv[1]
for m in re.finditer(r"<d [^>]*>",b):
    t=m.group(0)
    if re.search(r" n=\"(?:[^\"]*[.:#])?%s\"" % re.escape(n),t):
        p=re.search(r" p=\"([^\"]*)\"",t); print(p.group(1) if p else "@@NOP"); break
else: print("@@NONE")' "$2"; }
has(){ case "$1" in *"$2"*) ok "$3";; *) no "$3 (missing: $2)";; esac; }
hasnt(){ case "$1" in @@NOANSWER*|@@NONE*) no "$3 (no answer)";; *"$2"*) no "$3 (present: $2)";; *) ok "$3";; esac; }
NOCOMMIT='not committed: ranked as words'
NOSRC='anchor has no source definition'

# ═══ N1 ANCHOR-TEST-ONLY ═══
P1="$TMP/n1"; mkdir -p "$P1/tests" "$P1/src"
printf 'def thread_knob():\n    return 4\n\ndef test_a():\n    assert thread_knob() == 4\n' > "$P1/tests/test_one.py"
printf 'def thread_knob():\n    return 8\n\ndef test_b():\n    assert thread_knob() == 8\n' > "$P1/tests/test_two.py"
printf 'def configure_pool(settings):\n    knob = settings.get("thread_knob", 16)\n    return knob\n' > "$P1/src/pool.py"
printf 'def lonely_helper(x):\n    return x\n\ndef test_c():\n    assert lonely_helper(1) == 1\n' > "$P1/tests/test_lonely.py"
printf 'import os\n\ndef read_env():\n    return os.environ.get("ZZ_ENV_KNOB_VALUE", "")\n' > "$P1/src/env.py"
printf 'def source_knob():\n    return 2\n' > "$P1/src/knobs.py"
# fires: two test-only definitions, no source one
A="$( ask "$P1" 'thread_knob default' )"; R="$( route "$A" )"
case "$R" in subtoken+body*) ok "N1 two test-only defs: the words rank (subtoken+body)";; *) no "N1 two test-only defs: route $R";; esac
has "$R" "$NOCOMMIT" "N1 two test-only defs: route= says the anchor is not committed"
has "$R" "$NOSRC" "N1 two test-only defs: and why"
has "$R" 'hint anchors: thread_knob(' "N1 two test-only defs: the anchors ride as a hint"
hasnt "$R" 'name-exact(' "N1 two test-only defs: no second ranker code in route="
if [ "$( conf "$A" )" = low ]; then ok "N1 fires: confidence low"; else no "N1 fires: confidence $( conf "$A" )"; fi
P="$( firstp "$A" configure_pool )"
if [ "$P" = 'src/pool.py' ]; then ok "N1 fires: the source row that reads the key is a ranked <d> row"; else no "N1 fires: configure_pool row $P"; fi
M="$( mcpfor "$P1" 'thread_knob default' )"
has "$( route "$M" )" "$NOCOMMIT" "N1 MCP twin: not committed"
# sibling: TypeScript, two spec copies (another language, a camelCase spelling)
P1T="$TMP/n1ts"; mkdir -p "$P1T/test" "$P1T/src"
printf 'export function makeFixture() { return 1; }\n' > "$P1T/test/a.spec.ts"
printf 'export function makeFixture() { return 2; }\n' > "$P1T/test/b.spec.ts"
printf 'export function buildFixtureData() { const makeFixture = 3; return makeFixture; }\n' > "$P1T/src/data.ts"
A="$( ask "$P1T" 'makeFixture' )"; has "$( route "$A" )" "$NOCOMMIT" "N1 TS sibling, one word, two spec defs: not committed"
case "$( route "$A" )" in subtoken+body:broad*) ok "N1 TS sibling: one word codes :broad";; *) no "N1 TS sibling: $( route "$A" )";; esac
# silent: ONE test-only definition is the only thing by that name -> stays committed (low, with the note)
A="$( ask "$P1" 'lonely_helper' )"; R="$( route "$A" )"
has "$R" 'name-exact(lonely_helper)' "N1 silent, one test-only def: name-exact stays"
has "$R" "$NOSRC" "N1 silent, one test-only def: the note stays"
hasnt "$R" "$NOCOMMIT" "N1 silent, one test-only def: committed"
if [ "$( conf "$A" )" = low ]; then ok "N1 silent one def: low"; else no "N1 silent one def: $( conf "$A" )"; fi
# silent: a REPEATED word naming the one test-only definition counts it once (CR-570): still one definition, still committed
for q in 'lonely_helper lonely_helper' 'Lonely_helper LONELY_HELPER'; do
    R="$( route "$( ask "$P1" "$q" )" )"
    has "$R" 'name-exact(' "N1 silent, repeated one-def word ($q): name-exact stays"; hasnt "$R" "$NOCOMMIT" "N1 silent, repeated ($q): committed"
done
# silent: NO definition (an env var): the shortkey/lit route stays
A="$( ask "$P1" 'ZZ_ENV_KNOB_VALUE' )"; R="$( route "$A" )"
has "$R" 'name-exact(ZZ_ENV_KNOB_VALUE)' "N1 silent, no def: name-exact stays"; hasnt "$R" "$NOCOMMIT" "N1 silent, no def: committed"
has "$A" '<lit ' "N1 silent, no def: the literal block still serves it"
# silent: a source definition backs the anchor
A="$( ask "$P1" 'source_knob' )"; R="$( route "$A" )"
has "$R" 'name-exact(source_knob)' "N1 silent, source def: name-exact"; hasnt "$R" "$NOSRC" "N1 silent, source def: no note"
M="$( mcpfor "$P1" 'lonely_helper' )"; hasnt "$( route "$M" )" "$NOCOMMIT" "N1 MCP silent twin: committed"

# ═══ N4 PATH-WORD-NAMESAKE ═══
P4="$TMP/n4"
for b in iptables ipvs nftables winkernel; do
    mkdir -p "$P4/pkg/proxy/$b"
    printf 'package %s\n\ntype Proxier struct{ n int }\n\nfunc (p *Proxier) syncProxyRules() {\n\tp.n++\n}\n\nfunc (p *Proxier) Sync() {\n\tp.syncProxyRules()\n}\n' "$b" > "$P4/pkg/proxy/$b/proxier.go"
done
mkdir -p "$P4/cmd/kube-proxy"
printf 'package main\n\nfunc main() {\n\trunProxy()\n}\n\nfunc runProxy() {}\n' > "$P4/cmd/kube-proxy/main.go"
# a head the words own outright: the lift lands below it (a score promise), so the chosen namesake must come next among its namesakes
printf 'package main\n\n// kube proxy nftables kube proxy nftables ipvs winkernel\nfunc kubeProxyNftablesIpvsWinkernelSetup() {\n\t_ = "kube-proxy nftables ipvs winkernel"\n}\n' > "$P4/cmd/kube-proxy/setup.go"
A="$( ask "$P4" 'kube-proxy nftables syncProxyRules' )"
P="$( firstp "$A" syncProxyRules )"
if [ "$P" = 'pkg/proxy/nftables/proxier.go' ]; then ok "N4 dir word: the nftables namesake is the first syncProxyRules row"; else no "N4 dir word: first row $P"; fi
M="$( mcpfor "$P4" 'kube-proxy nftables syncProxyRules' )"
P="$( firstp "$M" syncProxyRules )"
if [ "$P" = 'pkg/proxy/nftables/proxier.go' ]; then ok "N4 MCP twin: nftables first"; else no "N4 MCP twin: first row $P"; fi
# positive twin of the silent arms: another directory word chooses that one (the arm can see a choice)
A="$( ask "$P4" 'ipvs syncProxyRules work' )"; P="$( firstp "$A" syncProxyRules )"
if [ "$P" = 'pkg/proxy/ipvs/proxier.go' ]; then ok "N4 dir word ipvs: the ipvs namesake first"; else no "N4 dir word ipvs: first row $P"; fi
# silent: two words naming two different namesakes -> no choice (neither is lifted: the words order stays, iptables first)
A="$( ask "$P4" 'ipvs winkernel syncProxyRules' )"; P="$( firstp "$A" syncProxyRules )"
case "$P" in pkg/proxy/ipvs/proxier.go|pkg/proxy/winkernel/proxier.go) no "N4 silent two words: one was chosen ($P)";; @@*) no "N4 silent two words: no row";; *) ok "N4 silent two words: no lift ($P)";; esac
B="$( ask "$P4" 'syncProxyRules' )"; Q="$( ask "$P4" 'proxier syncProxyRules' )"
if [ "$( firstp "$B" syncProxyRules )" = pkg/proxy/iptables/proxier.go ] && [ "$( firstp "$Q" syncProxyRules )" = "$( firstp "$B" syncProxyRules )" ]; then ok "N4 silent: a word placing all of them chooses none"; else no "N4 silent: 'proxier' moved the first row"; fi
# silent: a QUALIFIER segment is not a separate path word (barrelshortkeycheck B1/B3/C2): `Nftables.` and `Nftables::` miss the
# case-exact qualifier proof, so no namesake is chosen from them; the positive twin is the separate word `nftables` above
for q in 'Nftables.syncProxyRules work' 'Nftables::syncProxyRules work'; do
    A="$( ask "$P4" "$q" )"; P="$( firstp "$A" syncProxyRules )"
    case "$P" in pkg/proxy/nftables/proxier.go) no "N4 qualifier segment ($q): chose nftables as a path word";; @@*) no "N4 qualifier segment ($q): no row";; *) ok "N4 qualifier segment ($q): no path-word choice ($P)";; esac
done
# a dot ENDING a word is punctuation, not a qualifier (CR-570): the path word still chooses; the qualifier arms above stay silent
for qp in 'how does syncProxyRules work in nftables.|pkg/proxy/nftables/proxier.go' 'syncProxyRules work (ipvs).|pkg/proxy/ipvs/proxier.go' 'is syncProxyRules slow in winkernel...|pkg/proxy/winkernel/proxier.go'; do
    q="${qp%|*}"; want="${qp#*|}"
    A="$( ask "$P4" "$q" )"; P="$( firstp "$A" syncProxyRules )"
    if [ "$P" = "$want" ]; then ok "N4 sentence dot ($q): $want first"; else no "N4 sentence dot ($q): first row $P"; fi
done
# a path word placing only a bodyless PROTOTYPE beside definitions elsewhere places nothing (CR-570): the definitions are lifted
P4C="$TMP/n4c"; mkdir -p "$P4C/api" "$P4C/posix" "$P4C/win" "$P4C/tools"
printf 'int widget_reset(int x);\n' > "$P4C/api/widget.h"
printf '#include "../api/widget.h"\nint widget_reset(int x)\n{\n    return x + 1;\n}\n' > "$P4C/posix/widget.c"
printf '#include "../api/widget.h"\nint widget_reset(int x)\n{\n    return x + 2;\n}\n' > "$P4C/win/widget.c"
# a head the words own outright, so the lifted row shows right below it (as setup.go above)
printf '// api widget reset win posix api widget reset win posix\nvoid apiWidgetResetWinPosixNotes(void)\n{\n    const char *s = "api widget reset win posix";\n    (void)s;\n}\n' > "$P4C/tools/notes.c"
A="$( ask "$P4C" 'how does api widget_reset work' )"; P="$( firstp "$A" widget_reset )"
if [ "$P" = 'posix/widget.c' ]; then ok "N4 prototype word: the definitions are lifted, posix/widget.c first"; else no "N4 prototype word: first row $P"; fi
A="$( ask "$P4C" 'how does win widget_reset work' )"; P="$( firstp "$A" widget_reset )"
if [ "$P" = 'win/widget.c' ]; then ok "N4 definition word (positive twin): win/widget.c first"; else no "N4 definition word: first row $P"; fi
# sibling: Python, the FILE STEM names one of several definitions
P4P="$TMP/n4py"; mkdir -p "$P4P/store"
for s in disk memory redis s3cache; do printf 'def flush_all_entries(conn):\n    return conn\n' > "$P4P/store/$s.py"; done
printf 'def redis_flush_all_entries_cli():\n    """redis flush all entries redis flush"""\n    return "redis flush all entries"\n' > "$P4P/cli.py"
# (a conceptual route: a two-word `redis flush_all_entries` routes name-exact, whose anchor is the first definition; N4 is the lift only)
A="$( ask "$P4P" 'how does redis flush_all_entries work' )"; P="$( firstp "$A" flush_all_entries )"
if [ "$P" = 'store/redis.py' ]; then ok "N4 file stem (Python): redis.py first"; else no "N4 file stem: first row $P"; fi
A="$( ask "$P4P" 'how does flush_all_entries work' )"; P="$( firstp "$A" flush_all_entries )"
if [ "$P" = 'store/disk.py' ]; then ok "N4 silent no path word: file order (disk.py) first"; else no "N4 silent no path word: first row $P"; fi
# silent: a qualifier already places it (the narrowed reading), unchanged
A="$( ask "$P4P" 'memory.flush_all_entries' )"; P="$( firstp "$A" flush_all_entries )"
if [ "$P" = 'store/memory.py' ]; then ok "N4 qualifier: memory.py first as before"; else no "N4 qualifier: first row $P"; fi

# determinism + well-formed
A1="$( ask "$P4" 'kube-proxy nftables syncProxyRules' )"; A2="$( ask "$P4" 'kube-proxy nftables syncProxyRules' )"
if [ "${A1#@@}" = "$A1" ] && [ "$( printf '%s' "$A1" | sed -E 's/ at="[^"]*"//' )" = "$( printf '%s' "$A2" | sed -E 's/ at="[^"]*"//' )" ]; then ok "determinism"; else no "determinism"; fi
if command -v xmllint >/dev/null 2>&1; then
    for q in 'kube-proxy nftables syncProxyRules'; do if ask "$P4" "$q" | xmllint --noout - 2>/dev/null; then ok "xml well formed N4"; else no "xml N4"; fi; done
    if ask "$P1" 'thread_knob default' | xmllint --noout - 2>/dev/null; then ok "xml well formed N1"; else no "xml N1"; fi
else
    echo "  SKIP  xml well formed (no xmllint)"
fi
[ "$fail" = 0 ] && [ ! -e "$TMP/failed" ] && { echo "foranchornscheck: PASS"; exit 0; }
echo "foranchornscheck: FAIL"; exit 1
