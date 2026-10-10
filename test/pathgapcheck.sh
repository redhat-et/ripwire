#!/usr/bin/env bash
# pathgapcheck.sh — a reachable="0" path answer never claims "no path" when its search met a call the graph holds no
# edge for (src/pathgaps.h).
#
# THE DEFECT. --path=A,B answered `reachable="0" hint="no directed call path"` whenever the BFS over resolved call edges
# did not reach B — also when that search had walked past a DECLINED call (several same-language candidates, none
# local, nothing chose one), an UNRESOLVED call, a function handed off as a VALUE (`.then( handleResponse )`) or a call
# THROUGH a parameter. Any of those may be the hop that joins A to B, so the answer's wholeness claim was false.
#
# THE CONTRACT. When the search cone met such a call: searched= gaps= gap_syms= on the root, <gap t= n= p= gaps=> rows
# (nearest from= first, at most 3, gap_syms_capped="1" past that), a hint that says the search is incomplete, a next=
# that reads the rows' bodies — and never the text "no directed call path". When the cone met none, the old answer
# stands byte for byte. Ambiguous calls are NOT a gap (every candidate has an edge the search follows). The MCP twin
# (path_between) carries the same clause.
#
# ARMS
#   (P1) declined: a platform-split callee (two same-language defs in sibling dirs, none in the caller's) — gaps=declined.
#   (P2) value: a callback handed to .then() — gaps=value, the row names the function that hands it off.
#   (P3) through: a call through a parameter — gaps=through.
#   (P4) unresolved: a call whose only same-named definition is in another language — gaps=unresolved.
#   (P5) runaway guard: 6 gap symbols — 3 rows, gap_syms="6", gap_syms_capped="1", nearest first.
#   (P6) next= is pasteable: running it serves the gap row's body.
#   (P7) name: run(obj) calls obj.process(), bound by name alone (via="name") to the same-directory A.process only; the
#        tree's other/B.process (same language, same kind, calls the target) is never searched — gaps=name, row run.
#   (P8) next= is built with nextFlag: a gap row whose path holds a space is quoted, so the selector pastes as one argument.
#   (N1) a fully resolved graph with truly no path keeps "no directed call path" and no gap attribute.
#   (N2) a gap OUTSIDE the search cone (a declined call reachable only from elsewhere) does not count.
#   (N3) ambiguous-only cone (a k-way split the search followed) with no path keeps "no directed call path".
#   (N4) a found path (reachable="1") through a cone with gaps carries no gap clause.
#   (N5) a function passed as a value that the search ALSO reaches by a call is not a gap.
#   (N6) a via="name" call whose namesakes are a DIFFERENT language (Ruby) or a different KIND (a Python variable) is not a gap.
#   (N7) a via="name" call whose unlisted namesake the search REACHED anyway (another cone symbol calls it) is not a gap:
#        helper's B().process() lists only other/B.process, but pkg/x/A.process is in the cone through run, so it was searched.
#   (N3) above doubles as the name-gap near miss: run's obj.process() is via="name" too, but it has an edge to EVERY
#        same-language definition of process, so nothing was left unsearched.
#   (M)  MCP path_between carries the same searched/gaps/gap_syms/rows/next as the CLI (P1-P3, P7), and the same no-gap hint shape.
#
# Usage: test/pathgapcheck.sh [BIN]   (BIN defaults to RIPWIRE_BIN, then build/ripwire)
set -u
ROOT="$( cd "$( dirname "$0" )/.." && pwd )"
BIN="${1:-${RIPWIRE_BIN:-$ROOT/build/ripwire}}"
[ "${BIN#/}" = "$BIN" ] && BIN="$ROOT/$BIN"
TMP="$( mktemp -d )"; trap 'rm -rf "$TMP"' EXIT
fail=0
ok(){ printf '  PASS  %s\n' "$*" || { fail=1; printf '  FAIL  could not write the PASS line for: %s\n' "$*"; }; return 0; }
no(){ printf '  FAIL  %s\n' "$*"; fail=1; }

[ -x "$BIN" ] || { echo "no ripwire binary at $BIN — build first"; exit 2; }
command -v python3 >/dev/null 2>&1 || { echo "python3 required"; exit 2; }

# ── fixtures ────────────────────────────────────────────────────────────────────────────────────────────────────────
mkdir -p "$TMP/decl/core" "$TMP/decl/linux" "$TMP/decl/darwin" "$TMP/val" "$TMP/thr" "$TMP/unr" "$TMP/clean" \
         "$TMP/out/core" "$TMP/out/linux" "$TMP/out/darwin" "$TMP/amb" "$TMP/many/core" "$TMP/many/linux" "$TMP/many/darwin" \
         "$TMP/found" "$TMP/valin" "$TMP/lpy/pkg/x" "$TMP/lpy/other" "$TMP/lpyx/pkg/x" "$TMP/lpyx/other" \
         "$TMP/lpyin/pkg/x" "$TMP/lpyin/other"
cat > "$TMP/decl/core/machine.c" <<'EOF'
void Machine_scan( void );
void Machine_run( void ) { Machine_scan(); }
EOF
cat > "$TMP/decl/linux/scan.c" <<'EOF'
void Process_update( void ) { }
void Machine_scan( void ) { Process_update(); }
EOF
cat > "$TMP/decl/darwin/scan.c" <<'EOF'
void Machine_scan( void ) { }
EOF
cat > "$TMP/val/app.js" <<'EOF'
function respond(ctx) { return ctx; }
function handleResponse(ctx) { return respond(ctx); }
function runMiddleware(ctx) { return Promise.resolve(ctx); }
function handleRequest(ctx) { return runMiddleware(ctx).then(handleResponse); }
function listen() { return handleRequest({}); }
module.exports = { listen };
EOF
cat > "$TMP/thr/t.py" <<'EOF'
def target():
    return 1

def apply(fn):
    return fn()

def start():
    return apply(None)

def wire():
    return apply(target)
EOF
cat > "$TMP/unr/main.py" <<'EOF'
def finish():
    return 0

def begin():
    return render_page()
EOF
cat > "$TMP/unr/render.rb" <<'EOF'
def render_page
  finish
end
EOF
cat > "$TMP/clean/c.c" <<'EOF'
static int d( void ) { return 1; }
static int c( void ) { return d(); }
static int b( void ) { return 2; }
int a( void ) { return b(); }
int z( void ) { return c(); }
EOF
# N2: the declined call lives in other(), which only elsewhere() reaches; start() -> helper() is fully resolved.
cat > "$TMP/out/core/m.c" <<'EOF'
void scan( void );
static int sink( void ) { return 1; }
static int helper( void ) { return 2; }
int start( void ) { return helper(); }
int other( void ) { scan(); return 0; }
int elsewhere( void ) { return other() + sink(); }
EOF
cat > "$TMP/out/linux/s.c" <<'EOF'
void scan( void ) { }
EOF
cat > "$TMP/out/darwin/s.c" <<'EOF'
void scan( void ) { }
EOF
# N3: two same-file definitions of one method name: obj.process() splits over both (ambiguous, every arm an edge).
cat > "$TMP/amb/a.py" <<'EOF'
class A:
    def process(self):
        return 1

class B:
    def process(self):
        return 2

def unrelated():
    return 3

def run(obj):
    return obj.process()
EOF
# P5: six functions each with a declined call (f1..f4, mid, root), all reachable from root().
cat > "$TMP/many/core/m.c" <<'EOF'
void scan( void );
static int end_( void ) { return 0; }
int f1( void ) { scan(); return 1; }
int f2( void ) { scan(); return 2; }
int f3( void ) { scan(); return 3; }
int f4( void ) { scan(); return 4; }
int mid( void ) { scan(); return f3() + f4(); }
int root( void ) { scan(); return f1() + f2() + mid(); }
EOF
cat > "$TMP/many/linux/s.c" <<'EOF'
void scan( void ) { }
EOF
cat > "$TMP/many/darwin/s.c" <<'EOF'
void scan( void ) { }
EOF
# N4: a real path through a cone that also holds a declined call.
mkdir -p "$TMP/found/core" "$TMP/found/linux" "$TMP/found/darwin"
cat > "$TMP/found/core/m.c" <<'EOF'
void scan( void );
static int goal( void ) { return 1; }
int step( void ) { scan(); return goal(); }
int go( void ) { return step(); }
EOF
cat > "$TMP/found/linux/s.c" <<'EOF'
void scan( void ) { }
EOF
cat > "$TMP/found/darwin/s.c" <<'EOF'
void scan( void ) { }
EOF
# N5: handleResponse is passed as a value AND called directly, so the search reaches it anyway.
cat > "$TMP/valin/app.js" <<'EOF'
function other() { return 1; }
function handleResponse(ctx) { return ctx; }
function runMiddleware(ctx) { return Promise.resolve(ctx); }
function handleRequest(ctx) { handleResponse(ctx); return runMiddleware(ctx).then(handleResponse); }
module.exports = { handleRequest, other };
EOF

# P7 / N6: a call bound by name alone (FE-B via="name"). In lpy the namesake other/B.process is Python, a method, and
# calls the target; in lpyx the only other process definitions are a Ruby method and a Python variable.
cat > "$TMP/lpy/pkg/x/a.py" <<'EOF'
class A:
    def process(self):
        return 1
EOF
cat > "$TMP/lpy/pkg/x/c.py" <<'EOF'
def run(obj):
    return obj.process()
EOF
cat > "$TMP/lpy/other/b.py" <<'EOF'
def target():
    return 2

class B:
    def process(self):
        return target()
EOF
cp "$TMP/lpy/pkg/x/a.py" "$TMP/lpy/pkg/x/c.py" "$TMP/lpyx/pkg/x/"
cat > "$TMP/lpyx/other/b.rb" <<'EOF'
def target
  2
end

class B
  def process
    target
  end
end
EOF
cat > "$TMP/lpyx/other/v.py" <<'EOF'
process = 3
EOF
# N7: every namesake is in the cone. run reaches A.process (by name) and helper; helper's B().process() lists B.process
# only, and its unlisted namesake A.process is searched through run. Nothing reaches target.
cp "$TMP/lpy/pkg/x/a.py" "$TMP/lpyin/pkg/x/"
cat > "$TMP/lpyin/pkg/x/c.py" <<'EOF'
from other.b import helper
def run(obj):
    obj.process()
    helper()
EOF
cat > "$TMP/lpyin/other/b.py" <<'EOF'
class B:
    def process(self):
        return 2
def helper():
    B().process()
def target():
    return 3
EOF

# One --path answer, run unpiped so rc is ripwire's; the <path ...> head and the rest are read off the saved file.
path(){   # $1 dir, $2 FROM,TO, $3 out file
    "$BIN" "$1" --no-cache --path="$2" > "$3" 2>&1
}
attr(){   # $1 file, $2 attribute name -> its value on the <path> root (empty if absent)
    python3 - "$1" "$2" <<'PY'
import re, sys
t = open(sys.argv[1], encoding="utf-8", errors="replace").read()
m = re.search(r'<path [^>]*>', t)
if not m: sys.exit(0)
a = re.search(r'\s' + re.escape(sys.argv[2]) + r'="([^"]*)"', m.group(0))
print(a.group(1) if a else "")
PY
}
rows(){ grep -o '<gap [^>]*/>' "$1"; }
premise(){   # $1 label, $2 rc, $3 file — the answer ran and printed a <path> root (checklist 14: an absence is read only off a real answer)
    if [ "$2" -ne 0 ] || ! grep -q '<path ' "$3"; then no "$1 (premise) --path ran (rc=$2) and printed a <path> root: $( head -c 300 "$3" )"; return 1; fi
    return 0
}
gapArm(){   # $1 label, $2 dir, $3 FROM,TO, $4 expected gaps=, $5 expected first row name
    local f="$TMP/$( echo "$1" | tr -cd 'A-Za-z0-9' ).xml" rc
    path "$2" "$3" "$f"; rc=$?
    premise "$1" "$rc" "$f" || return
    local g; g="$( attr "$f" gaps )"
    local first; first="$( rows "$f" | head -1 | sed 's/.* n="\([^"]*\)".*/\1/' )"
    if [ "$( attr "$f" reachable )" = "0" ] && [ "$g" = "$4" ] && ! grep -q 'no directed call path' "$f" \
       && [ -n "$( attr "$f" searched )" ] && [ "$first" = "$5" ] && grep -q 'search is incomplete' "$f"; then
        ok "$1 reachable=0, gaps=\"$g\", first row $first, no \"no directed call path\""
    else
        no "$1 expected gaps=\"$4\" first row $5 and no 'no directed call path'; got gaps=\"$g\" first=[$first]: $( grep -o '<path .*' "$f" | head -c 700 )"
    fi
}
cleanArm(){   # $1 label, $2 dir, $3 FROM,TO — the old "no path" answer, no gap clause
    local f="$TMP/$( echo "$1" | tr -cd 'A-Za-z0-9' ).xml" rc
    path "$2" "$3" "$f"; rc=$?
    premise "$1" "$rc" "$f" || return
    if [ "$( attr "$f" reachable )" = "0" ] && grep -q 'hint="no directed call path' "$f" && [ -z "$( attr "$f" searched )" ] \
       && [ -z "$( attr "$f" gaps )" ] && [ -z "$( rows "$f" )" ] && ! grep -q 'search is INCOMPLETE\|search is incomplete' "$f"; then
        ok "$1 keeps \"no directed call path\" with no gap clause"
    else
        no "$1 should keep the plain no-path answer: $( grep -o '<path .*' "$f" | head -c 700 )"
    fi
}

echo "(P) positive arms: a gap in the search cone"
gapArm "(P1) declined" "$TMP/decl" "Machine_run,Process_update" "declined:1" "Machine_run"
gapArm "(P2) value"    "$TMP/val"  "listen,respond"             "value:1"    "handleRequest"
gapArm "(P3) through"  "$TMP/thr"  "start,target"               "through:1"  "apply"
gapArm "(P4) unresolved" "$TMP/unr" "begin,finish"              "unresolved:1" "begin"

# P7's premise: the call really is bound by name alone to A.process only (else the arm would test the old resolver)
f="$TMP/lpycallees.xml"; "$BIN" "$TMP/lpy" --no-cache --callees=run > "$f" 2>&1
if [ "$( grep -o '<s [^>]*n="process"[^>]*/>' "$f" | wc -l | tr -d ' ' )" = "1" ] && grep -q '<s [^>]*n="process" p="pkg/x/a.py:2" via="name"' "$f"; then
    ok "(P7) premise: run's obj.process() is via=\"name\" to pkg/x/a.py's A.process only"
    gapArm "(P7) name" "$TMP/lpy" "run,target" "name:1" "run"
else
    no "(P7) premise: run's callees are not the one via=name A.process row: $( grep -o '<callees .*' "$f" | head -c 500 )"
fi

# P8 (CodeRabbit on #383, pathgaps.h:342): lpy with a space in a directory name. The row's p= is the same, and next= must
# quote the selector (nextFlag), else `--expand=pkg x/c.py:run` splits into two argv words when pasted.
mkdir -p "$TMP/lpysp/pkg x" "$TMP/lpysp/other"
cp "$TMP/lpy/pkg/x/a.py" "$TMP/lpy/pkg/x/c.py" "$TMP/lpysp/pkg x/"
cp "$TMP/lpy/other/b.py" "$TMP/lpysp/other/"
f="$TMP/P8space.xml"; path "$TMP/lpysp" "run,target" "$f"; rc=$?
if premise "(P8) space" "$rc" "$f"; then
    nx="$( attr "$f" next )"   # the raw attribute text: the shell quote is &apos; on the wire, as every next= with a quote is
    if [ "$( attr "$f" gaps )" = "name:1" ] && [ "$nx" = "--expand=&apos;pkg x/c.py:run&apos;" ]; then
        ok "(P8) a gap row under a directory with a space: next=\"$nx\" is one quoted selector"
        # pasteable: XML-unescape, split the way a shell would, run it, and the gap row's body is served
        python3 -c 'import html,shlex,subprocess,sys; sys.exit(subprocess.run([sys.argv[1], sys.argv[2], "--no-cache"] + shlex.split(html.unescape(sys.argv[3])), stdout=open(sys.argv[4], "wb"), stderr=subprocess.STDOUT).returncode)' \
            "$BIN" "$TMP/lpysp" "$nx" "$TMP/P8next.xml"; rc=$?
        if [ "$rc" -eq 0 ] && grep -q 'obj.process()' "$TMP/P8next.xml"; then
            ok "(P8) the quoted next= pastes as one argument and serves run's body"
        else
            no "(P8) the quoted next= did not serve run's body (rc=$rc): $( head -c 300 "$TMP/P8next.xml" )"
        fi
    else
        no "(P8) want gaps=\"name:1\" and next=\"--expand=&apos;pkg x/c.py:run&apos;\"; got gaps=\"$( attr "$f" gaps )\" next=\"$nx\""
    fi
fi

echo "(P5) runaway guard: rows capped at 3, nearest first, the cut disclosed"
f="$TMP/many.xml"; path "$TMP/many" "root,end_" "$f"; rc=$?
if premise "(P5)" "$rc" "$f"; then
    names="$( rows "$f" | sed 's/.* n="\([^"]*\)".*/\1/' | tr '\n' ' ' )"
    if [ "$( attr "$f" gap_syms )" = "6" ] && [ "$( attr "$f" gap_syms_capped )" = "1" ] && [ "$( attr "$f" gaps )" = "declined:6" ] \
       && [ "$names" = "root f1 f2 " ]; then
        ok "(P5) gap_syms=6 gap_syms_capped=1 gaps=declined:6, rows [$names] (depth 0, then depth 1 by id)"
    else
        no "(P5) gap_syms=$( attr "$f" gap_syms ) capped=$( attr "$f" gap_syms_capped ) gaps=$( attr "$f" gaps ) rows [$names]"
    fi
fi

echo "(P6) next= is pasteable and serves the gap row's body"
f="$TMP/P2value.xml"
nx="$( attr "$f" next )"
if [ "$nx" = "--expand=app.js:handleRequest" ]; then
    # shellcheck disable=SC2086
    "$BIN" "$TMP/val" --no-cache $nx > "$TMP/next.xml" 2>&1; rc=$?
    if [ "$rc" -eq 0 ] && grep -q 'then(handleResponse)' "$TMP/next.xml"; then
        ok "(P6) next=\"$nx\" serves handleRequest's body, where the value hand-off is"
    else
        no "(P6) next=\"$nx\" rc=$rc did not serve the body: $( head -c 300 "$TMP/next.xml" )"
    fi
else
    no "(P6) next= on the value arm is [$nx], expected --expand=app.js:handleRequest"
fi

echo "(N) near-miss negatives"
cleanArm "(N1) fully resolved, no path" "$TMP/clean" "a,d"
cleanArm "(N2) a gap outside the cone"  "$TMP/out"   "start,sink"
f="$TMP/ambprobe.xml"; "$BIN" "$TMP/amb" --no-cache > "$f" 2>&1
if grep -q '<s [^>]*n="run"[^>]*amb="1"' "$f"; then
    ok "(N3) premise: run's obj.process() is an ambiguous split (amb=1 on its row)"
    cleanArm "(N3) ambiguous-only cone" "$TMP/amb" "run,unrelated"
else
    no "(N3) premise: run's call is not an ambiguous split here, the arm would assert nothing: $( grep -o '<s [^>]*n="run"[^>]*>' "$f" )"
fi
f="$TMP/found.xml"; path "$TMP/found" "go,goal" "$f"; rc=$?
if premise "(N4)" "$rc" "$f"; then
    if [ "$( attr "$f" reachable )" = "1" ] && [ -z "$( attr "$f" gaps )" ] && [ -z "$( attr "$f" hint )" ] && [ -z "$( rows "$f" )" ]; then
        ok "(N4) a found path carries no gap clause and no hint"
    else
        no "(N4) found path: $( grep -o '<path .*' "$f" | head -c 500 )"
    fi
fi
cleanArm "(N5) a value the search also calls" "$TMP/valin" "handleRequest,other"
f="$TMP/lpyxcallees.xml"; "$BIN" "$TMP/lpyx" --no-cache --callees=run > "$f" 2>&1
if grep -q '<s [^>]*n="process" p="pkg/x/a.py:2" via="name"' "$f"; then
    cleanArm "(N6) via=name, namesakes of another language/kind" "$TMP/lpyx" "run,target"
else
    no "(N6) premise: run's obj.process() is not via=name to A.process here: $( grep -o '<callees .*' "$f" | head -c 500 )"
fi
f="$TMP/lpyinhelper.xml"; "$BIN" "$TMP/lpyin" --no-cache --callees=helper > "$f" 2>&1; fh_rc=$?
f2="$TMP/lpyinrun.xml"; "$BIN" "$TMP/lpyin" --no-cache --callees=run > "$f2" 2>&1; fr_rc=$?
if [ "$fh_rc" -eq 0 ] && [ "$fr_rc" -eq 0 ] \
   && grep -q '<s [^>]*n="process" p="other/b.py:2" via="name"' "$f" && ! grep -q 'p="pkg/x/a.py:2"' "$f" \
   && grep -q '<s [^>]*n="process" p="pkg/x/a.py:2"' "$f2"; then
    cleanArm "(N7) via=name, the unlisted namesake is in the searched cone" "$TMP/lpyin" "run,target"
else
    no "(N7) premise: helper lists only other/B.process by name and run reaches pkg/x/A.process (rc=$fh_rc/$fr_rc): $( grep -o '<callees .*' "$f" | head -c 300 ) | $( grep -o '<callees .*' "$f2" | head -c 300 )"
fi

echo "(M) MCP path_between carries the same clause"
# Two MCP legend postures (lean-answers): the unchanged assertions run on --mcp-legend=inline, the pre-posture spelling
# where every answer carries its root facts on <path>; a TWIN runs the default session posture, whose answers after the
# first are legend="ref" and carry their root facts on the closing <about …/> instead. Both must match the CLI.
for MPOST in inline session; do
python3 - "$BIN" "$TMP" "$MPOST" <<'PY'
import json, re, subprocess, sys
binp, tmp, posture = sys.argv[1], sys.argv[2], sys.argv[3]
cases = [ ( "decl", "Machine_run", "Process_update", True ), ( "val", "listen", "respond", True ),
          ( "thr", "start", "target", True ), ( "lpy", "run", "target", True ), ( "clean", "a", "d", False ) ]
reqs = [ { "jsonrpc": "2.0", "id": 0, "method": "initialize", "params": { "protocolVersion": "2024-11-05", "capabilities": {}, "clientInfo": { "name": "g", "version": "1" } } } ]
for i, ( d, a, b, _ ) in enumerate( cases ):
    reqs.append( { "jsonrpc": "2.0", "id": i + 1, "method": "tools/call", "params": { "name": "path_between", "arguments": { "path": tmp + "/" + d, "from": a, "to": b } } } )
argv = [ binp, "--mcp" ] + ( [ "--mcp-legend=inline" ] if posture == "inline" else [] )
p = subprocess.run( argv, input = "".join( json.dumps( r ) + "\n" for r in reqs ), capture_output = True, text = True, timeout = 120 )
refs = 0
resp = {}
for line in p.stdout.splitlines():
    try:
        o = json.loads( line )
    except ValueError:
        continue
    if isinstance( o.get( "id" ), int ) and o[ "id" ] > 0:
        resp[ o[ "id" ] ] = "".join( c.get( "text", "" ) for c in o.get( "result", {} ).get( "content", [] ) )
def head( t ):
    m = re.search( r'<path [^>]*>', t )
    return m.group( 0 ) if m else ""
def facts( t ):   # the root's facts: <path …>, plus a legend="ref" answer's closing <about …/> (where they move)
    ab = re.search( r'<about [^>]*legend="ref"[^>]*/>', t )
    return head( t ) + ( ab.group( 0 ) if ab else "" )
def pick( t, name ):
    m = re.search( r'\s' + name + r'="([^"]*)"', facts( t ) )
    return m.group( 1 ) if m else None
bad = 0
for i, ( d, a, b, gap ) in enumerate( cases ):
    mcp = resp.get( i + 1, "" )
    refs += 1 if re.search( r'<about [^>]*legend="ref"', mcp ) else 0
    cli = subprocess.run( [ binp, tmp + "/" + d, "--no-cache", "--path=%s,%s" % ( a, b ) ], capture_output = True, text = True ).stdout
    if not head( mcp ):
        print( "  MCP gave no <path> root for", d, repr( mcp[:300] ), p.stderr[:300] ); bad = 1; continue
    for name in ( "searched", "gaps", "gap_syms", "gap_syms_capped", "next", "reachable" ):
        if pick( mcp, name ) != pick( cli, name ):
            print( "  %s: %s= MCP %r vs CLI %r" % ( d, name, pick( mcp, name ), pick( cli, name ) ) ); bad = 1
    if re.findall( r'<gap [^>]*/>', mcp ) != re.findall( r'<gap [^>]*/>', cli ):
        print( "  %s: gap rows differ" % d ); bad = 1
    if gap and ( "no directed call path" in mcp or "search is incomplete" not in mcp ):
        print( "  %s: MCP hint still claims no path" % d ); bad = 1
    if not gap and "no directed call path" not in mcp:
        print( "  %s: MCP lost the plain no-path hint" % d ); bad = 1
# the posture premise: inline answers never take the ref posture; the session twin's answers after the first all do
if posture == "inline" and refs != 0:
    print( "  inline posture: %d answer(s) came back legend=\"ref\"" % refs ); bad = 1
if posture == "session" and refs != len( cases ) - 1:
    print( "  session posture: %d of the %d later answers are legend=\"ref\" (the twin tests nothing new)" % ( refs, len( cases ) - 1 ) ); bad = 1
sys.exit( bad )
PY
mrc=$?
if [ "$mrc" -eq 0 ]; then
    ok "(M) path_between ($MPOST legend posture): same searched/gaps/gap_syms/rows/next as the CLI on P1-P3 and P7, plain hint on N1"
else
    no "(M) MCP path_between ($MPOST legend posture) disagrees with the CLI or the helper crashed (rc=$mrc, details above)"
fi
done

if [ "$fail" -eq 0 ]; then echo "ALL PASS"; else echo "FAIL"; fi
exit "$fail"
