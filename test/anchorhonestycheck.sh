#!/usr/bin/env bash
# anchorhonestycheck.sh — ANCHOR-HONESTY + WH-WORD-GUARD (src/subjectanchor.h anchorHonestyRoute / routeAnchorHasSourceDef):
#   short "what does X call" wordings whose X is an identifier-syntax spelling with a SOURCE definition.
#   H1 a test-only word ("call", two spec copies) no longer vetoes the source anchor: name-exact on it, its callers, no false note.
#   H2 a frame verb that names a source symbol elsewhere ("invoke") no longer anchors and heads the answer.
#   H3 a docs-file tie (a reST `.. method:: Model.save` section) never beats the source definition: no false note, the source
#      body and its callers, not the section's.
#   H4 WH-WORD-GUARD: an interrogative ("where", "what") is not a ranking word beside a source syntax anchor.
#   Negatives, each counting its premise and FAILing on zero:
#   N1 a genuinely test-only anchor still says "anchor has no source definition";
#   N2 an interrogative stays a ranking word when no source syntax anchor resolves (a `what` method still ranks);
#   N3 a subject that IS a `where` method keeps it in the head.
#   Fixtures generated at test time; CLI and MCP; determinism; well-formed XML.
# Usage: bash test/anchorhonestycheck.sh [BIN]   |   RIPWIRE_BIN=asan/ripwire bash test/anchorhonestycheck.sh
set -u
ROOT="$( cd "$( dirname "$0" )/.." && pwd )"
BIN="${1:-${RIPWIRE_BIN:-$ROOT/build/ripwire}}"
[ "${BIN#/}" = "$BIN" ] && BIN="$ROOT/$BIN"
[ -x "$BIN" ] || { echo "no ripwire binary at $BIN - build first"; exit 2; }
TMP="$( mktemp -d )"; trap 'rm -rf "$TMP"' EXIT
fail=0
ok(){ printf '  PASS  %s\n' "$*"; }
no(){ printf '  FAIL  %s\n' "$*"; fail=1; : > "$TMP/failed"; }   # the marker survives a $( ) subshell
echo "anchorhonestycheck: BIN=$BIN"
ask(){
    local out rc
    out="$( cd "$1" && HOME="$TMP/home" TMPDIR="$TMP/home/" "$BIN" "$1" --no-cache "--for=$2" 2>/dev/null </dev/null )"; rc=$?
    if [ "$rc" -ne 0 ] || [ -z "$out" ]; then no "ask rc=$rc bytes=${#out}: $2" >&2; printf '@@NOANSWER'; return 0; fi
    printf '%s' "$out"
}
mkdir -p "$TMP/home" "$TMP/mcphome"
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
route(){ printf '%s' "$1" | python3 -c 'import re,sys; m=re.search(r"route=\"([^\"]*)\"",sys.stdin.read()); print(m.group(1) if m else "@@NONE")'; }
# the n= of the ranked <d> row at r=$2
rown(){ printf '%s' "$1" | python3 -c '
import re,sys
b=sys.stdin.read(); r=sys.argv[1]
for m in re.finditer(r"<d [^>]*>",b):
    t=m.group(0)
    if re.search(r" r=\"%s\"" % r,t):
        n=re.search(r" n=\"([^\"]*)\"",t); p=re.search(r" p=\"([^\"]*)\"",t)
        print((n.group(1) if n else "@@NON")+"@"+(p.group(1) if p else "@@NOP")); break
else: print("@@NONE")' "$2"; }
# how many ranked <d> rows whose name (leaf after . : #) is $2
countn(){ printf '%s' "$1" | python3 -c '
import re,sys
b=sys.stdin.read(); n=sys.argv[1]
print(sum(1 for m in re.finditer(r"<d [^>]*>",b) if re.search(r" n=\"(?:[^\"]*[.:#])?%s\"" % re.escape(n),m.group(0))))' "$2"; }
# the first <b> body: its t= and p=
firstb(){ printf '%s' "$1" | python3 -c '
import re,sys
m=re.search(r"<b [^>]*>",sys.stdin.read())
if not m: print("@@NONE")
else:
    t=re.search(r" t=\"([^\"]*)\"",m.group(0)); p=re.search(r" p=\"([^\"]*)\"",m.group(0))
    print((t.group(1) if t else "-")+"@"+(p.group(1) if p else "@@NOP"))'; }
# does a <callers of=> block name $2 (bare, or Scope::$2)?
callersof(){ printf '%s' "$1" | python3 -c '
import re,sys
print("yes" if re.search(r"<callers of=\"(?:[^\"]*(?:::|\.))?%s\"" % re.escape(sys.argv[1]),sys.stdin.read()) else "no")' "$2"; }
# the anchors: clause of a route (up to the next ;)
anchorsof(){ printf '%s' "$1" | python3 -c '
import re,sys
m=re.search(r"anchors: ([^;]*)",sys.stdin.read()); print(m.group(1) if m else "@@NOANCHORS")'; }
has(){ case "$1" in @@NOANSWER*|@@NONE*) no "$3 (no answer)";; *"$2"*) ok "$3";; *) no "$3 (missing: $2)";; esac; }
hasnt(){ case "$1" in @@NOANSWER*|@@NONE*) no "$3 (no answer)";; *"$2"*) no "$3 (present: $2)";; *) ok "$3";; esac; }
eq(){ if [ "$1" = "$2" ]; then ok "$3"; else no "$3 (got $1, want $2)"; fi; }
NOSRC='anchor has no source definition'
NOCOMMIT='not committed'

# ═══ TS fixture (the nest shape) ═══
T="$TMP/ts"; mkdir -p "$T/packages/core/injector" "$T/packages/router" "$T/packages/common" "$T/integration/a/test" "$T/integration/b/test" "$T/packages/core/test"
cat > "$T/packages/core/injector/injector.ts" <<'EOF'
export class Injector {
  public loadProvider(wrapper: any, moduleRef: any): any {
    const token = this.resolveToken(wrapper);
    const deps = this.resolveConstructorParams(wrapper, moduleRef, token);
    return this.instantiateClass(deps, wrapper);
  }
  public resolveToken(wrapper: any): any { return wrapper.token; }
  public resolveConstructorParams(wrapper: any, moduleRef: any, token: any): any[] { return [wrapper, moduleRef, token]; }
  public instantiateClass(deps: any[], wrapper: any): any { return { deps, wrapper }; }
}
EOF
cat > "$T/packages/core/injector/instance-loader.ts" <<'EOF'
import { Injector } from './injector';
export class InstanceLoader {
  private readonly injector = new Injector();
  public createInstancesOfProviders(moduleRef: any): void {
    for (const wrapper of moduleRef.providers) {
      this.injector.loadProvider(wrapper, moduleRef);
    }
  }
}
EOF
cat > "$T/packages/router/node-router.ts" <<'EOF'
export class NodeRouter {
  public invoke(req: any, res: any): any {
    const handler = this.lookup(req.path);
    return handler(req, res);
  }
  public lookup(path: string): any { return (req: any, res: any) => [path, req, res]; }
}
EOF
cat > "$T/packages/common/runtime.exception.ts" <<'EOF'
export class RuntimeException extends Error {
  constructor(private readonly msg = '') { super(msg); }
  public what(): string { return this.msg; }
}
export class InvalidItemException extends RuntimeException {
  public what(): string { return 'invalid item'; }
}
EOF
for d in a b; do
cat > "$T/integration/$d/test/request-chain.spec.ts" <<'EOF'
export function call(fn: () => number): number { return fn(); }
describe('chain', () => { it('calls', () => { expect(call(() => 1)).toBe(1); }); });
EOF
done
cat > "$T/packages/core/test/spec-helper.spec.ts" <<'EOF'
export class SpecHarness {
  public runAll(): number { return this.count(); }
  public count(): number { return 2; }
}
describe('harness', () => { it('runs', () => { expect(new SpecHarness().runAll()).toBe(2); }); });
EOF
mkdir -p "$T/integration/c/test"
cat > "$T/integration/c/test/harness.spec.ts" <<'EOF'
export class SpecHarness {
  public runAll(): number { return 3; }
}
EOF

# ═══ Python fixture (the django docs-tie and cpython where shapes) ═══
P="$TMP/py"; mkdir -p "$P/pkg/models" "$P/pkg/forms" "$P/docs/ref/models" "$P/Lib/concurrent/futures" "$P/Lib/tkinter"
cat > "$P/pkg/models/base.py" <<'EOF'
class Model:
    def save(self, force_insert=False, using=None):
        self.full_clean()
        return self.save_base(using=using, force_insert=force_insert)

    def save_base(self, using=None, force_insert=False):
        return (using, force_insert)

    def full_clean(self):
        return True
EOF
mkdir -p "$P/pkg/utils"
printf 'def call(fn, *args):\n    return fn(*args)\n' > "$P/pkg/utils/functional.py"
cat > "$P/pkg/forms/models.py" <<'EOF'
def submit_form(instance):
    instance.save()
    return instance
EOF
printf 'project = "pkg"\nsource_suffix = {".txt": "restructuredtext"}\n' > "$P/docs/conf.py"
cat > "$P/docs/ref/models/instances.txt" <<'EOF'
========================
Model instance reference
========================

Saving objects
==============

To save an object back to the database, call ``save()``:

.. method:: Model.save(force_insert=False, using=DEFAULT_DB_ALIAS)

For details on using the ``force_insert`` argument, see below.

.. method:: Model.full_clean()

Validates the model.
EOF
cat > "$P/Lib/concurrent/futures/thread.py" <<'EOF'
from concurrent.futures import _base


class ThreadPoolExecutor(_base.Executor):
    def __init__(self, max_workers=None):
        self._max_workers = max_workers

    def submit(self, fn, *args):
        return fn(*args)
EOF
cat > "$P/Lib/concurrent/futures/_base.py" <<'EOF'
class Executor:
    def map(self, fn, *iterables):
        return [fn(*a) for a in zip(*iterables)]

    def __enter__(self):
        return self
EOF
cat > "$P/Lib/concurrent/futures/__init__.py" <<'EOF'
from concurrent.futures.thread import ThreadPoolExecutor
EOF
cat > "$P/Lib/tkinter/dnd.py" <<'EOF'
class Icon:
    def where(self, canvas, event):
        x_org = canvas.winfo_rootx()
        return event.x_root - x_org

    def press(self, event):
        return self.where(None, event)


def where_helper(icon, canvas, event):
    return icon.where(canvas, event)


def drag(icon, event):
    return icon.where(None, event)
EOF

# ═══ H1 a test-only word does not veto the source anchor ═══
A="$( ask "$T" 'what does Injector.loadProvider call' )"; R="$( route "$A" )"
case "$R" in name-exact\(Injector.loadProvider\)*) ok "H1 call: name-exact on the source anchor";; *) no "H1 call: route $R";; esac
hasnt "$R" "$NOSRC" "H1 call: no false 'no source definition' note"
hasnt "$R" "$NOCOMMIT" "H1 call: committed"
has "$R" 'dropped: call' "H1 call: the dropped frame verb is disclosed"
eq "$( rown "$A" 1 )" 'Injector.loadProvider@packages/core/injector/injector.ts' "H1 call: r=1 is the anchor"
eq "$( callersof "$A" loadProvider )" yes "H1 call: the anchor's callers print"
eq "$( countn "$A" call )" 0 "H1 call: no ranked test-only call row"
M="$( mcpfor "$T" 'what does Injector.loadProvider call' )"
hasnt "$( route "$M" )" "$NOSRC" "H1 MCP twin: no false note"
case "$( route "$M" )" in name-exact*) ok "H1 MCP twin: name-exact";; *) no "H1 MCP twin: route $( route "$M" )";; esac
B="$( ask "$T" 'what does Injector.loadProvider call' )"
if [ "$A" = "$B" ]; then ok "H1 deterministic"; else no "H1 two runs differ"; fi
if command -v xmllint >/dev/null 2>&1; then
    if printf '%s' "$A" | xmllint --noout - 2>/dev/null; then ok "H1 well-formed XML"; else no "H1 xmllint"; fi
fi

# ═══ H2 a frame verb that names a source symbol elsewhere does not anchor ═══
A="$( ask "$T" 'what does Injector.loadProvider invoke' )"; R="$( route "$A" )"
hasnt "$R" "$NOSRC" "H2 invoke: no false note"
hasnt "$( anchorsof "$R" )" 'invoke' "H2 invoke: invoke is not an anchor"
eq "$( rown "$A" 1 )" 'Injector.loadProvider@packages/core/injector/injector.ts' "H2 invoke: r=1 is the anchor, not invoke"
eq "$( callersof "$A" invoke )" no "H2 invoke: no callers block for invoke"
eq "$( callersof "$A" loadProvider )" yes "H2 invoke: the anchor's callers print"
eq "$( countn "$A" what )" 0 "H2+H4 invoke: no ranked what() row"

# ═══ H3 a docs-file tie never beats a source definition ═══
for q in 'what does Model.save call' 'Model.save'; do
    A="$( ask "$P" "$q" )"; R="$( route "$A" )"
    case "$R" in name-exact*) ok "H3 [$q]: name-exact";; *) no "H3 [$q]: route $R";; esac
    hasnt "$R" "$NOSRC" "H3 [$q]: no false 'no source definition' note"
    hasnt "$R" 'instances.txt' "H3 [$q]: the anchor is not the docs section"
    eq "$( rown "$A" 1 )" 'Model.save@pkg/models/base.py' "H3 [$q]: r=1 is the source definition"
    case "$( firstb "$A" )" in section@*|*@docs/*) no "H3 [$q]: first body is the docs section ($( firstb "$A" ))";; @@NONE) no "H3 [$q]: no body";; *) ok "H3 [$q]: first body is source ($( firstb "$A" ))";; esac
    eq "$( callersof "$A" save )" yes "H3 [$q]: the source definition's callers print"
done

# ═══ H4 WH-WORD-GUARD ═══
A="$( ask "$P" 'where concurrent.futures.ThreadPoolExecutor is defined' )"; R="$( route "$A" )"
case "$R" in name-exact*) ok "H4 where: name-exact";; *) no "H4 where: route $R";; esac
eq "$( countn "$A" where )" 0 "H4 where: no ranked where() row"
hasnt "$R" 'anchor is not the ranked head' "H4 where: the anchor heads the answer"
eq "$( rown "$A" 1 )" 'ThreadPoolExecutor@Lib/concurrent/futures/thread.py' "H4 where: r=1 is the class"

# ═══ N1 a genuinely test-only anchor still says so (premise: the spelling has test-only definitions) ═══
nT="$( grep -l 'runAll' "$T"/packages/core/test/*.spec.ts "$T"/integration/*/test/*.spec.ts 2>/dev/null | wc -l | tr -d ' ' )"
if [ "$nT" -ge 2 ]; then ok "N1 premise: $nT test-only files define SpecHarness.runAll"; else no "N1 premise: $nT test-only definitions"; fi
A="$( ask "$T" 'what does SpecHarness.runAll call' )"; R="$( route "$A" )"
has "$R" "$NOSRC" "N1 test-only anchor: the note still fires"
nN=0; for q in 'what does SpecHarness.runAll call' 'SpecHarness.runAll'; do case "$( route "$( ask "$T" "$q" )" )" in *"$NOSRC"*) nN=$(( nN + 1 ));; esac; done
if [ "$nN" -ge 1 ]; then ok "N1 counted $nN test-only wordings with the note"; else no "N1 counted 0 test-only wordings with the note"; fi

# ═══ N2 an interrogative stays a ranking word when no source syntax anchor resolves ═══
A="$( ask "$T" 'what does UnknownThing.notDefinedAnywhere call' )"; R="$( route "$A" )"
nW="$( countn "$A" what )"
if [ "$nW" -ge 1 ]; then ok "N2 no source anchor: what() still ranks ($nW rows)"; else no "N2 no source anchor: counted 0 what() rows (route $R)"; fi

# ═══ N3 a subject that IS a where method keeps it ═══
A="$( ask "$P" 'what does Icon.where call' )"
top3="$( rown "$A" 1 ) $( rown "$A" 2 ) $( rown "$A" 3 )"
has "$top3" 'Icon.where@Lib/tkinter/dnd.py' "N3 Icon.where: the where method is in the top 3"
nW="$( countn "$A" where )"
if [ "$nW" -ge 1 ]; then ok "N3 counted $nW where rows"; else no "N3 counted 0 where rows"; fi

[ -e "$TMP/failed" ] && fail=1
if [ "$fail" -eq 0 ]; then echo "anchorhonestycheck: PASS"; exit 0; fi
echo "anchorhonestycheck: FAIL"; exit 1
