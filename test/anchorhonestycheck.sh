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
#   N3 a subject that IS a `where` method keeps it in the head;
#   N4 an outer qualifier that places nothing (`Missing.futures.ThreadPoolExecutor`) does not borrow the inner spelling's source anchor.
#   N5 a C++ namespace the definition's file opens (`rw::detail::ConnPool`) still places it; its Missing:: twin does not.
#   N8 a comment word or unrelated identifier in the definition's file is no scope; N9 an unread (>4 MiB) definition file is
#   disclosed on the route (CARD-SWEEP-1113).
#   Fixtures generated at test time; CLI and MCP; determinism; well-formed XML.
# Usage: bash test/anchorhonestycheck.sh [BIN]   |   RIPWIRE_BIN=asan/ripwire bash test/anchorhonestycheck.sh
set -u
ROOT="$( cd "$( dirname "$0" )/.." && pwd )"
. "$ROOT/test/lib/clean-env.sh"
BIN="${1:-${RIPWIRE_BIN:-$ROOT/build/ripwire}}"
[ "${BIN#/}" = "$BIN" ] && BIN="$ROOT/$BIN"
[ -x "$BIN" ] || { echo "no ripwire binary at $BIN - build first"; exit 2; }
TMP="$( mktemp -d )"; trap 'rm -rf "$TMP"' EXIT
fail=0
ok(){ printf '  PASS  %s\n' "$*" || { fail=1; : > "$TMP/failed"; printf '  FAIL  could not write the PASS line for: %s\n' "$*"; }; return 0; }
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

# ═══ N4 an outer qualifier that places nothing does not borrow the inner spelling's source anchor (CodeRabbit 4545021751) ═══
#   `Missing.futures.ThreadPoolExecutor` reduces to (ThreadPoolExecutor, futures), which places Lib/concurrent/futures/thread.py; no
#   path segment or scope says Missing, so it is no source syntax anchor: the frame word stays, the no-source note fires, and an
#   interrogative stays a ranking word (H4's true spelling drops all three).
nM="$( { find "$P" -path '*Missing*'; grep -rl 'Missing' "$P" 2>/dev/null; } | wc -l | tr -d ' ' )"
nC="$( grep -c '^class ThreadPoolExecutor' "$P/Lib/concurrent/futures/thread.py" 2>/dev/null )"
if [ "$nM" -eq 0 ] && [ "${nC:-0}" -ge 1 ]; then ok "N4 premise: ThreadPoolExecutor is defined under Lib/concurrent/futures and nothing in the fixture says Missing"
else no "N4 premise: Missing in $nM path(s)/file(s), class ThreadPoolExecutor x${nC:-0}"; fi
nN=0
R="$( route "$( ask "$P" 'what does Missing.futures.ThreadPoolExecutor call' )" )"
case "$R" in *"$NOSRC"*) nN=$(( nN + 1 )); ok "N4 call: the no-source note fires";; *) no "N4 call: route $R (the reduced spelling backed it)";; esac
case "$R" in *'dropped: call'*) no "N4 call: the frame word was dropped (route $R)";; *) ok "N4 call: the frame word stays";; esac
for q in 'where Missing.futures.ThreadPoolExecutor is defined' 'where Missing::futures::ThreadPoolExecutor is defined'; do
    nW="$( countn "$( ask "$P" "$q" )" where )"
    if [ "$nW" -ge 1 ]; then nN=$(( nN + 1 )); ok "N4 [$q]: where() still ranks ($nW rows)"; else no "N4 [$q]: counted 0 where() rows (the reduced spelling dropped it)"; fi
done
if [ "$nN" -eq 3 ]; then ok "N4 counted $nN outer-qualified wordings read as no source anchor"; else no "N4 counted $nN of 3 outer-qualified wordings read as no source anchor"; fi

# ═══ N5 an outer qualifier the definition's file opens still places it (a C++ namespace is no path segment or scope) ═══
C="$TMP/cpp"; mkdir -p "$C/src/pool"
printf 'namespace rw\n{\nnamespace detail\n{\nclass ConnPool\n{\npublic:\n    void drainAll();\n    int  sizeNow() const;\n};\nvoid ConnPool::drainAll() { sizeNow(); }\nint ConnPool::sizeNow() const { return 0; }\n}\n}\n' >"$C/src/pool/pool.cpp"
printf 'int main() { rw::detail::ConnPool p; p.drainAll(); }\n' >"$C/src/main.cpp"
( cd "$C" && git init -q . && git add -A && git -c user.name=t -c user.email=t@t commit -qm init ) >/dev/null 2>&1
nP=0
for q in 'where rw::detail::ConnPool is defined' 'what does rw::detail::ConnPool::drainAll call'; do
    R="$( route "$( ask "$C" "$q" )" )"
    case "$R" in name-exact*) case "$R" in *"$NOSRC"*) no "N5 [$q]: route $R";; *) nP=$(( nP + 1 )); ok "N5 [$q]: the namespace places it (no note)";; esac;; *) no "N5 [$q]: route $R";; esac
done
R="$( route "$( ask "$C" 'what does rw::detail::ConnPool::drainAll call' )" )"
case "$R" in *'dropped: call'*) ok "N5 call: the frame word leaves beside a namespace-qualified source anchor";; *) no "N5 call: route $R";; esac
R="$( route "$( ask "$C" 'what does Missing::detail::ConnPool::drainAll call' )" )"
case "$R" in *'dropped: call'*) no "N5 Missing:: twin: the frame word was dropped (route $R)";; *) nP=$(( nP + 1 )); ok "N5 Missing:: twin: the frame word stays";; esac
if [ "$nP" -eq 3 ]; then ok "N5 counted $nP namespace wordings read as expected"; else no "N5 counted $nP of 3 namespace wordings read as expected"; fi

# ═══ N8 a qualifier the file only MENTIONS places nothing (ANCHOR-QUALIFIER-OWNERSHIP, CodeRabbit #630) ═══
#   A comment word (`Legacy`) and an unrelated identifier (`Stale`) in the definition's file placed `Legacy::detail::ConnPool` and
#   `Stale::detail::ConnPool` on main cd04d477e (whole word in the file); only a scope opener (`namespace rw`) places now.
Q="$TMP/cppq"; mkdir -p "$Q/src/pool"
printf '// Legacy: this pool replaced the Legacy one
namespace rw
{
namespace detail
{
int Stale = 0;
class ConnPool
{
public:
    void drainAll();
    int  sizeNow() const;
};
void ConnPool::drainAll() { sizeNow(); }
int ConnPool::sizeNow() const { return Stale; }
}
}
' >"$Q/src/pool/pool.cpp"
printf 'int main() { rw::detail::ConnPool p; p.drainAll(); }
' >"$Q/src/main.cpp"
( cd "$Q" && git init -q . && git add -A && git -c user.name=t -c user.email=t@t commit -qm init ) >/dev/null 2>&1
if grep -qw Legacy "$Q/src/pool/pool.cpp" && grep -qw Stale "$Q/src/pool/pool.cpp"; then ok "N8 premise: pool.cpp mentions Legacy (a comment) and Stale (an identifier)"; else no "N8 premise: the fixture lost its mentions"; fi
nQ=0
for w in Legacy Stale; do
    R="$( route "$( ask "$Q" "what does $w::detail::ConnPool::drainAll call" )" )"
    case "$R" in *'dropped: call'*) no "N8 $w:: (a mention, not a scope) placed the definition (route $R)";; *) nQ=$(( nQ + 1 )); ok "N8 $w:: is no source anchor: the frame word stays";; esac
done
R="$( route "$( ask "$Q" 'what does rw::detail::ConnPool::drainAll call' )" )"
case "$R" in *'dropped: call'*) nQ=$(( nQ + 1 )); ok "N8 control: rw:: (namespace rw) still places on the same file";; *) no "N8 control: rw::detail::ConnPool::drainAll route $R";; esac
if [ "$nQ" -eq 3 ]; then ok "N8 counted $nQ qualifier wordings read as expected"; else no "N8 counted $nQ of 3 qualifier wordings read as expected"; fi
# N8b (CodeRabbit 4570578087): a scope keyword and its name on two lines (Rust `mod` / `netio`) still open the scope; the keyword
#   scan stopped at the line break, so netio:: placed nothing (red on 1c920292f: the frame word stayed). Control: zzzio::, which
#   no scope opens, still places nothing.
NL="$TMP/rsnl"; mkdir -p "$NL/src"
printf 'mod\nnetio\n{\n    pub struct Conn;\n    impl Conn\n    {\n        pub fn drain_all(&self) { self.size_now(); }\n        pub fn size_now(&self) -> u32 { 0 }\n    }\n}\n\nfn main() { netio::Conn.drain_all(); }\n' >"$NL/src/lib.rs"
printf '[package]\nname = "x"\nversion = "0.1.0"\n' >"$NL/Cargo.toml"
( cd "$NL" && git init -q . && git add -A && git -c user.name=t -c user.email=t@t commit -qm init ) >/dev/null 2>&1
if grep -qx 'mod' "$NL/src/lib.rs" && grep -qx 'netio' "$NL/src/lib.rs"; then ok "N8b premise: lib.rs spells mod and netio on two lines"; else no "N8b premise: the fixture lost its split mod"; fi
R="$( route "$( ask "$NL" 'what does netio::Conn::drain_all call' )" )"
case "$R" in *'dropped: call'*) ok "N8b netio:: (mod on the line before) places the definition";; *) no "N8b netio:: across a line break placed nothing (route $R)";; esac
R="$( route "$( ask "$NL" 'what does zzzio::Conn::drain_all call' )" )"
case "$R" in *'dropped: call'*) no "N8b control: zzzio:: (no scope opens it) placed the definition (route $R)";; *) ok "N8b control: zzzio:: places nothing";; esac

# ═══ N9 a definition file too big to read says so (ANCHOR-READ-DISCLOSE, CodeRabbit #630) ═══
#   Huge::drainAll lives in a 4.3 MiB file, indexed under --max-file-size=8M but past readWhole's 4 MiB. `Outer::` is in no scope or
#   path, so only the file could place it, and the file cannot be read: the definition is not placed, and the route reason now says
#   the qualifier went unchecked instead of reading `Outer` as absent (silent on main cd04d477e).
#   Generated here, never committed.
H="$TMP/huge"; mkdir -p "$H/src"
{ printf 'namespace rw\n{\nnamespace detail\n{\nclass Huge\n{\npublic:\n    void drainAll();\n    int  sizeNow() const;\n};\nvoid Huge::drainAll() { sizeNow(); }\nint Huge::sizeNow() const { return 0; }\n}\n}\n'
  awk 'BEGIN { for( i = 0; i < 60000; ++i ) printf "// padding padding padding padding padding padding padding padding %05d\n", i }'; } >"$H/src/huge.cpp"
printf 'int main() { rw::detail::Huge h; h.drainAll(); }\n' >"$H/src/main.cpp"
( cd "$H" && git init -q . && git add -A && git -c user.name=t -c user.email=t@t commit -qm init ) >/dev/null 2>&1
hb=$( wc -c <"$H/src/huge.cpp" | tr -d ' ' )
if [ "$hb" -gt 4194304 ] && [ "$hb" -lt 8388608 ]; then ok "N9 premise: huge.cpp is $hb bytes, past the 4 MiB read"; else no "N9 premise: huge.cpp is $hb bytes"; fi
R="$( route "$( cd "$H" && HOME="$TMP/home" TMPDIR="$TMP/home/" "$BIN" "$H" --no-cache --max-file-size=8M '--for=what does Outer::detail::Huge::drainAll call' 2>/dev/null </dev/null )" )"   # status: --for exits 0 on a routed answer; the route reason is the verdict and an empty route FAILs the arm below
case "$R" in *'not placed: the file is unreadable or over 4 MiB'*) ok "N9 the route says the definition's file was too big to check";; *) no "N9 the unread definition file is silent (route $R)";; esac
R="$( route "$( ask "$C" 'what does Missing::detail::ConnPool::drainAll call' )" )"
case "$R" in *'unreadable or over 4 MiB'*) no "N9 precision: a readable file carries the unread note (route $R)";; *) ok "N9 precision: a readable definition file carries no unread note";; esac
# N9b (CodeRabbit 4570578098): the same unread definition beside a READABLE one that `namespace Outer` places: the anchor is source,
#   the frame word drops and that route replaces the first one; the unread note was lost with it (red on 1c920292f).
H2="$TMP/huge2"; mkdir -p "$H2/src"; cp "$H/src/huge.cpp" "$H/src/main.cpp" "$H2/src/"
printf 'namespace Outer\n{\nnamespace detail\n{\nclass Huge\n{\npublic:\n    void drainAll();\n};\nvoid Huge::drainAll() { }\n}\n}\n' >"$H2/src/small.cpp"
( cd "$H2" && git init -q . && git add -A && git -c user.name=t -c user.email=t@t commit -qm init ) >/dev/null 2>&1
R="$( route "$( cd "$H2" && HOME="$TMP/home" TMPDIR="$TMP/home/" "$BIN" "$H2" --no-cache --max-file-size=8M '--for=what does Outer::detail::Huge::drainAll call' 2>/dev/null </dev/null )" )"   # status: --for exits 0 on a routed answer; the route reason is the verdict and an empty route FAILs the arm below
case "$R" in *'dropped: call'*) ok "N9b premise: the readable Outer definition anchors and the frame word drops";; *) no "N9b premise: the route was not replaced (route $R) — the arm is vacuous";; esac
case "$R" in *'not placed: the file is unreadable or over 4 MiB'*) ok "N9b the replaced route keeps the unread-definition note";; *) no "N9b the unread note was lost when the route was replaced (route $R)";; esac

# ═══ N3 a subject that IS a where method keeps it ═══
A="$( ask "$P" 'what does Icon.where call' )"
top3="$( rown "$A" 1 ) $( rown "$A" 2 ) $( rown "$A" 3 )"
has "$top3" 'Icon.where@Lib/tkinter/dnd.py' "N3 Icon.where: the where method is in the top 3"
nW="$( countn "$A" where )"
if [ "$nW" -ge 1 ]; then ok "N3 counted $nW where rows"; else no "N3 counted 0 where rows"; fi

[ -e "$TMP/failed" ] && fail=1
if [ "$fail" -eq 0 ]; then echo "anchorhonestycheck: PASS"; exit 0; fi
echo "anchorhonestycheck: FAIL"; exit 1
