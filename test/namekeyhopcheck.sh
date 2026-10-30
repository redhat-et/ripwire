#!/usr/bin/env bash
# namekeyhopcheck.sh — STRING-KEYED (src/backhops.h NameKeyHops, src/pathgaps.h BridgeVia::NameKey; issue #375 slice 7a): a
# function that looks a method up by a name built from a template joins the hedged walks to the definitions that name fits.
#
# THE DEFECT. A command shell (cpython cmd.Cmd.onecmd: `func = getattr( self, 'do_' + cmd )`) or an event table
# (`this[ 'on' + e ]()`) has no call edge from the dispatcher to the handlers. IX-3 already lists the template lookup as a
# <pd> row on --callers / --impact of a handler, but the joining answers ignored it: --path=main,list_dir (main -> onecmd ->
# do_ls -> list_dir) printed no bridge, and --impact=do_ls counted nothing behind the dispatcher.
#
# THE CONTRACT. A template lookup site in f (PatternIndex: getattr / hasattr / X.__dict__.get with an f-string or `+` holding a
# literal side of >= 3 identifier characters; JS/TS o[ 'p' + x ] / o[ `p${x}` ]) hops to every definition its template can
# name (prefix and suffix around a non-empty hole; a self/this/cls receiver keeps the site's class family); width = that count.
# Every hop is HEDGED: reaches= / reachable= / hops= / proven= never move. The --path bridge crosses it (`<s … via="name-key"
# cands=K/>`) within 16 candidates; the --impact ring follows it (reaches_hedged=, `<rh … via="name-key"/>` at d=2).
# A plain variable name, a literal name, a too-wide template and a sibling class's same-prefix method are no hop.
#
# ARMS
#   (K1) bridge: --path=main,list_dir crosses onecmd -> do_ls via="name-key" cands="2"; reachable="0" hops="0".
#   (K2) --impact=do_ls: reaches_hedged= counts onecmd and its proven caller main; reaches= unchanged (0).
#   (K3) d=2 ring row: --impact=do_go (do_go <- run_cmd <- route, both name-key hops; route's receiver is not self, so
#        unnarrowed) lists `<rh called_by="route" via="name-key" calls="run_cmd"/>`.
#   (N1) a sibling class with the same prefix (Other.do_rm) is not in cands (self narrows to the class family): cands="2".
#   (N2) a plain variable name (getattr( self, name )) and a literal name (getattr( self, "do_ls" )) record no hop.
#   (N3) a too-wide template (f"_{m}") records no hop.
#   (W1) width: 17 fitting handlers are counted by --impact but the bridge does not cross them (fan-out 16).
#   (T1) a handler that itself dispatches by the same template is not its own way in (self-exclusion; mutant: drop `from != sink`).
#   (J1) JS/TS: this[ 'handle' + e ]() crosses to handleClick via="name-key" ('on' alone is under the 3-character literal floor).
#   (L1) the name-key clause rides only when a name-key row/crossing is present; every answer parses as XML.
#   (M1) MCP path_between twin crosses the same hop.
#   fix round 1 (review rv-string-keyed F1-F6):
#   (N1j) F1: JS `this[ 'handle' + e ]` narrows to the class family too (an unrelated class's handleKey is no candidate: cands="1").
#   (N4) F2: a class of the same NAME in another file is another class (b.py's Shell.do_rm is no candidate of a.py's Shell): cands="1", no bridge to secret.
#   (N4b) a class that DERIVES from the site's class stays a candidate (an ancestor / subclass is the family).
#   (W1b) F3: a 17-wide lookup that the bridge declines is a way in on --path: near_sink says why=declined:1 via=name-key cands=17, never external;
#         a narrow lookup whose dispatcher the forward search never reached is told the same way (W1c).
#   (L2) F4: --impact=do_ls (reaches_hedged= counts d=1 name-key hops only) carries reaches_hedged_via="name-key" and the legend clause,
#        compact and full, CLI and MCP; an answer with no name-key hop carries neither.
#   (T2) F5: the self-exclusion guard: a gap shape beside a self-dispatching handler keeps the root next= --expand (CLI and MCP).
#   (M2) F5: MCP --impact keeps reaches= and reaches_hedged= apart. (N5) F5: a template inside a non-lookup call, log(self, 'do_' + c), is no hop.
#   (N6) F6: a JS subscript STORE and a hasattr-only function make no hop (the <pd> clue stays on --callers).
#
# Usage: test/namekeyhopcheck.sh [BIN]   (BIN defaults to RIPWIRE_BIN, then build/ripwire)
set -u
ROOT="$( cd "$( dirname "$0" )/.." && pwd )"
BIN="${1:-${RIPWIRE_BIN:-$ROOT/build/ripwire}}"
[ "${BIN#/}" = "$BIN" ] && BIN="$ROOT/$BIN"
echo "namekeyhopcheck: BIN=$BIN"
[ -x "$BIN" ] || { echo "  FAIL  no ripwire binary at $BIN — build first"; exit 2; }
command -v python3 >/dev/null 2>&1 || { echo "  FAIL  python3 required"; exit 2; }
TMP="$( mktemp -d )"; trap 'rm -rf "$TMP"' EXIT

mkdir -p "$TMP/sh" "$TMP/neg" "$TMP/w17" "$TMP/self" "$TMP/js" "$TMP/d2" "$TMP/js2" "$TMP/two" "$TMP/self2" "$TMP/hasattr" "$TMP/strcall" "$TMP/jwrite" "$TMP/inh"
cat > "$TMP/sh/shell.py" <<'EOF'
def list_dir(a):
    return a


class Shell:
    def onecmd(self, line):
        cmd = line.split()[0]
        func = getattr(self, 'do_' + cmd)
        return func(line)

    def do_ls(self, a):
        return list_dir(a)

    def do_cd(self, a):
        return a


class Other:
    def do_rm(self, a):
        return list_dir(a)


def main():
    Shell().onecmd("ls x")
EOF
cat > "$TMP/neg/shell.py" <<'EOF'
def list_dir(a):
    return a


class Shell:
    def by_var(self, name):
        return getattr(self, name)()

    def by_literal(self):
        return getattr(self, "do_ls")()

    def too_wide(self, m):
        return getattr(self, f"_{m}")()

    def do_ls(self, a):
        return list_dir(a)


def main():
    s = Shell()
    s.by_var("do_ls")
    s.by_literal()
    s.too_wide("x")
EOF
{
    printf 'def leaf(a):\n    return a\n\n\nclass Wide:\n    def run(self, c):\n        return getattr(self, "do_" + c)(1)\n'
    for i in $( seq 1 17 ); do printf '\n    def do_h%s(self, a):\n        return leaf(a)\n' "$i"; done
    printf '\n\ndef main():\n    Wide().run("h1")\n'
} > "$TMP/w17/wide.py"
cat > "$TMP/self/m.py" <<'EOF'
def sink(a):
    return a


class Rec:
    def do_again(self, c):
        return getattr(self, 'do_' + c)(c)

    def do_end(self, c):
        return sink(c)
EOF
cat > "$TMP/js/ev.js" <<'EOF'
function paint(e) {
  return e;
}

class Button {
  fire(e) {
    return this['handle' + e](e);
  }
  handleClick(e) {
    return paint(e);
  }
}

function main() {
  new Button().fire('Click');
}
module.exports = { main };
EOF
cat > "$TMP/d2/m.py" <<'EOF'
class Shell:
    def run_cmd(self, c):
        return getattr(self, 'do_' + c)(c)

    def do_go(self, c):
        return c


class Front:
    def route(self, k, c):
        return getattr(Shell(), 'run_' + k)(c)


def top():
    return Front().route("cmd", "go")
EOF

cat > "$TMP/js2/ev.js" <<'EOF'
function paint(e) {
  return e;
}

class Btn {
  fire(e) {
    return this['handle' + e](e);
  }
  handleClick(e) {
    return paint(e);
  }
}

class Other {
  handleKey(e) {
    return paint(e);
  }
}

function main() {
  new Btn().fire('Click');
}
module.exports = { main };
EOF
cat > "$TMP/two/a.py" <<'EOF'
def leaf_a(a):
    return a


class Shell:
    def onecmd(self, c):
        return getattr(self, 'do_' + c)(1)

    def do_ls(self, a):
        return leaf_a(a)


def main():
    Shell().onecmd("ls")
EOF
cat > "$TMP/two/b.py" <<'EOF'
def secret(a):
    return a


class Shell:
    def do_rm(self, a):
        return secret(a)
EOF
cat > "$TMP/inh/m.py" <<'EOF'
def leaf_base(a):
    return a


def leaf_sub(a):
    return a


class Base:
    def run(self, c):
        return getattr(self, 'do_' + c)(1)

    def do_base(self, a):
        return leaf_base(a)


class Sub(Base):
    def do_sub(self, a):
        return leaf_sub(a)


def main():
    Sub().run("x")
EOF
cat > "$TMP/self2/m.py" <<'EOF'
def sink(a):
    return a


class Rec:
    def do_again(self, c):
        return getattr(self, 'do_' + c)(c)

    def do_end(self, c):
        return sink(c)


class P:
    def go(self):
        return 1


class Q:
    def go(self):
        return 2


def main(cb, x):
    cb(1)
    return x.go()
EOF
cat > "$TMP/hasattr/m.py" <<'EOF'
def leaf(a):
    return a


class S:
    def has(self, c):
        return hasattr(self, 'do_' + c)

    def do_x(self, a):
        return leaf(a)


def main():
    S().has("x")
EOF
cat > "$TMP/strcall/m.py" <<'EOF'
def leaf(a):
    return a


def log(obj, msg):
    return msg


class S:
    def show(self, c):
        return log(self, 'do_' + c)

    def do_x(self, a):
        return leaf(a)


def main():
    S().show("x")
EOF
cat > "$TMP/jwrite/ev.js" <<'EOF'
function paint(e) {
  return e;
}

class Btn {
  bind(e, fn) {
    this['handle' + e] = fn;
    return 0;
  }
  handleClick(e) {
    return paint(e);
  }
}

function main() {
  new Btn().bind('Click', null);
}
module.exports = { main };
EOF
cat >> "$TMP/sh/shell.py" <<'EOF'


def orphan():
    return 0
EOF

python3 - "$BIN" "$TMP" <<'PY'
import json, re, shutil, subprocess, sys
binp, tmp = sys.argv[1], sys.argv[2]
fail = 0
def ok( m ): print( "  PASS  " + m )
def no( m ):
    global fail
    fail = 1
    print( "  FAIL  " + m )
def check( c, m ): ( ok if c else no )( m )
def run( d, *args ):
    """One answer, read only off a run that succeeded and printed a root (checklist 14)."""
    p = subprocess.run( [ binp, d, "--no-cache", *args ], cwd = d, capture_output = True, text = True, timeout = 120 )
    if p.returncode != 0 or not re.search( r'<(path|impact) ', p.stdout ):
        return None
    return p.stdout
def body( t ):
    return re.sub( r'<!--.*?-->', '', t or "", flags = re.S )
def root( t, tag ):
    m = re.search( r'<' + tag + r' [^>]*>', body( t ) )
    return m.group( 0 ) if m else ""
def attr( el, a ):
    m = re.search( r'\b' + a + r'="([^"]*)"', el )
    return m.group( 1 ) if m else None
def bridge( t ):
    m = re.search( r'<bridge .*?</bridge>', body( t ) )
    return m.group( 0 ) if m else ""
def xmlok( t ):
    if shutil.which( "xmllint" ) is None:
        return True
    return subprocess.run( [ "xmllint", "--noout", "-" ], input = t, text = True, capture_output = True ).returncode == 0

sh = f"{tmp}/sh"
t = run( sh, "--path=main,list_dir", "--legend=full" )
if t is None:
    no( "K1 --path=main,list_dir answered" )
else:
    r, b = root( t, "path" ), bridge( t )
    check( attr( r, "reachable" ) == "0" and attr( r, "hops" ) == "0", "K1 reachable=0 hops=0 (a name-key hop is no proven edge)" )
    check( re.search( r'<s [^>]*n="do_ls"[^>]*via="name-key" cands="2"', b ) is not None, "K1 bridge crosses onecmd -> do_ls via=name-key cands=2 (N1: Other.do_rm not a candidate)" )
    check( re.search( r'n="onecmd".*n="do_ls".*n="list_dir"', b ) is not None, "K1 bridge order main..onecmd -> do_ls -> list_dir" )
    check( "a NAME-KEYED lookup, not a call" in t, "L1 the name-key clause rides with a name-key crossing" )
    check( xmlok( t ), "L1 the --path answer parses as XML" )
t = run( sh, "--impact=do_ls" )
if t is None:
    no( "K2 --impact=do_ls answered" )
else:
    r = root( t, "impact" )
    check( attr( r, "reaches_hedged" ) == "2", f"K2 reaches_hedged=2 (onecmd + main) got {attr( r, 'reaches_hedged' )}" )
    check( attr( r, "reaches" ) in ( None, "0" ), f"K2 reaches= unchanged ({attr( r, 'reaches' )})" )
    check( xmlok( t ), "L1 the --impact answer parses as XML" )
t = run( f"{tmp}/d2", "--impact=do_go", "--legend=full" )
if t is None:
    no( "K3 --impact=do_go answered" )
else:
    check( re.search( r'<rh [^>]*called_by="route"[^>]*via="name-key"[^>]*calls="run_cmd"', body( t ) ) is not None, "K3 d=2 ring row route -> run_cmd via=name-key" )
    check( attr( root( t, "impact" ), "reaches_hedged" ) == "3", f"K3 reaches_hedged=3 (run_cmd, route, top) got {attr( root( t, 'impact' ), 'reaches_hedged' )}" )
    check( "a NAME-KEYED lookup, not a call" in t and xmlok( t ), "L1 ring clause rides with a name-key <rh> row; XML parses" )
t = run( f"{tmp}/neg", "--path=main,list_dir", "--legend=full" )
if t is None:
    no( "N2 --path answered" )
else:
    check( 'via="name-key"' not in t and "NAME-KEYED" not in t, "N2/N3 a variable name, a literal name and a too-wide template are no name-key hop (and no clause)" )
t = run( f"{tmp}/neg", "--impact=do_ls" )
check( t is not None and attr( root( t, "impact" ), "reaches_hedged" ) is None, "N2/N3 --impact=do_ls has no reaches_hedged" )
t = run( f"{tmp}/w17", "--path=main,leaf" )
check( t is not None and 'via="name-key"' not in bridge( t ), "W1 17 candidates: the bridge does not cross (fan-out 16)" )
t = run( f"{tmp}/w17", "--impact=do_h1" )
check( t is not None and attr( root( t, "impact" ), "reaches_hedged" ) == "1", f"W1 --impact counts the wide hop itself (run), composes nothing: {attr( root( t or '', 'impact' ), 'reaches_hedged' )}" )
t = run( f"{tmp}/self", "--impact=do_again" )
check( t is not None and attr( root( t, "impact" ), "reaches_hedged" ) is None, "T1 a dispatcher is not its own way in" )
t = run( f"{tmp}/self", "--impact=sink" )
check( t is not None, "T1 the self-dispatching shape terminates" )
t = run( f"{tmp}/js", "--path=main,paint" )
if t is None:
    no( "J1 --path=main,paint answered" )
else:
    check( re.search( r'<s [^>]*n="handleClick"[^>]*via="name-key"', bridge( t ) ) is not None, "J1 JS this['handle' + e] crosses fire -> handleClick via=name-key" )
t = run( sh, "--path=main,list_dir" )
check( t is not None and "s via=name-key cands=K:" in t, "L1 the default (compact) legend reads s via=name-key (present-only)" )
t = run( f"{tmp}/neg", "--path=main,list_dir" )
check( t is not None and "via=name-key" not in t, "L1 the compact name-key reading is absent with no name-key row" )
# F1: the JS `this` receiver keeps the class family (Symbol::scope is empty for a JS method: the owner is the enclosing class definition)
t = run( f"{tmp}/js2", "--path=main,paint" )
check( t is not None and re.search( r'<s [^>]*n="handleClick"[^>]*via="name-key" cands="1"', bridge( t ) ) is not None, "N1j JS this[...]: Other.handleKey is no candidate (cands=1)" )
# F2: a class named like the site's class in another file is another class
t = run( f"{tmp}/two", "--path=main,leaf_a" )
check( t is not None and re.search( r'<s [^>]*n="do_ls"[^>]*via="name-key" cands="1"', bridge( t ) ) is not None, "N4 the same-named class in b.py is no candidate of a.py's Shell (cands=1)" )
t = run( f"{tmp}/two", "--path=main,secret" )
check( t is not None and 'via="name-key"' not in t and attr( root( t, "path" ), "reachable" ) == "0", "N4 no bridge from a.py's Shell to b.py's do_rm -> secret" )
# the family is still the ancestors and subclasses
t = run( f"{tmp}/inh", "--path=main,leaf_sub" )
check( t is not None and re.search( r'<s [^>]*n="do_sub"[^>]*via="name-key" cands="2"', bridge( t ) ) is not None, "N4b a base's dispatcher still names its subclass's handler (cands=2: do_base, do_sub)" )
# F3: the declined lookup is a way in, in the near_sink vocabulary of a declined call
t = run( f"{tmp}/w17", "--path=main,leaf" )
ns = re.search( r'<near_sink .*?</near_sink>', body( t or "" ), flags = re.S )
nsb = ns.group( 0 ) if ns else ""
check( t is not None and nsb != "" and 'why="external"' not in nsb and re.search( r'<ns [^>]*why="declined:1"[^>]*in="run"[^>]*via="name-key" cands="17"', nsb ) is not None,
       "W1b a 17-wide lookup the bridge declines: near_sink why=declined:1 via=name-key cands=17, never external" )
t = run( sh, "--path=orphan,list_dir", "--legend=full" )
ns = re.search( r'<near_sink .*?</near_sink>', body( t or "" ), flags = re.S )
nsb = ns.group( 0 ) if ns else ""
check( t is not None and re.search( r'<ns [^>]*n="do_ls"[^>]*why="declined:1"[^>]*in="onecmd"[^>]*via="name-key" cands="2"', nsb ) is not None and re.search( r'<ns [^>]*n="do_ls"[^>]*why="external"', nsb ) is None,
       "W1c a narrow lookup whose dispatcher the search never reached is told as a way in too (cands=2)" )
check( t is not None and "ns via=name-key cands=K" in t and xmlok( t ), "W1c the near_sink name-key clause rides with such a row (full legend); XML parses" )
t = run( sh, "--path=orphan,list_dir" )
check( t is not None and "ns via=name-key cands=K" in t, "W1c the compact legend reads ns via=name-key (present-only)" )
t = run( f"{tmp}/neg", "--path=main,list_dir", "--legend=full" )
check( t is not None and "ns via=name-key" not in t, "W1c no name-key row, no near_sink name-key clause" )
# F4: reaches_hedged= counts d=1 name-key hops that have no row: the answer says so
t = run( sh, "--impact=do_ls", "--legend=full" )
check( t is not None and attr( root( t, "impact" ), "reaches_hedged_via" ) == "name-key" and "NAME-KEYED" in t and xmlok( t ), "L2 --impact=do_ls (d=1 hops only) carries reaches_hedged_via=name-key and the full-legend clause" )
t = run( sh, "--impact=do_ls" )
check( t is not None and attr( root( t, "impact" ), "reaches_hedged_via" ) == "name-key" and "reaches_hedged_via=name-key:" in t, "L2 the compact legend reads reaches_hedged_via=name-key" )
p = subprocess.run( [ binp, sh, "--no-cache", "--impact=do_ls", "--json" ], cwd = sh, capture_output = True, text = True, timeout = 120 )
check( p.returncode == 0 and '"reaches_hedged_via":"name-key"' in p.stdout.replace( " ", "" ), "L2 the JSON form carries reaches_hedged_via" )
t = run( f"{tmp}/neg", "--impact=do_ls", "--legend=full" )
check( t is not None and "reaches_hedged_via" not in t and "NAME-KEYED" not in t, "L2 no name-key hop: no reaches_hedged_via, no clause" )
# F5: the self-exclusion guard is live on the --path root next= (a gap shape beside a self-dispatching handler)
t = run( f"{tmp}/self2", "--path=main,do_again" )
check( t is not None and attr( root( t, "path" ), "next" ) == "--expand=m.py:main", f"T2 the root next= stays --expand=m.py:main, not the sink's own lookup ({attr( root( t or '', 'path' ), 'next' )})" )
# F5: the lookup-callee check
t = run( f"{tmp}/strcall", "--path=main,leaf" )
check( t is not None and 'via="name-key"' not in t, "N5 log(self, 'do_' + c) is no name-key hop (the template is not inside getattr/hasattr/__dict__.get)" )
t = run( f"{tmp}/strcall", "--impact=do_x" )
check( t is not None and attr( root( t, "impact" ), "reaches_hedged" ) is None, "N5 --impact=do_x counts no hedged function" )
# F6: a presence test and a store are no lookup
t = run( f"{tmp}/hasattr", "--path=main,leaf" )
check( t is not None and 'via="name-key"' not in t, "N6 a hasattr-only function is no name-key hop" )
t = run( f"{tmp}/hasattr", "--impact=do_x" )
check( t is not None and attr( root( t, "impact" ), "reaches_hedged" ) is None, "N6 --impact=do_x counts nothing behind hasattr" )
t = run( f"{tmp}/jwrite", "--path=main,paint" )
check( t is not None and 'via="name-key"' not in t, "N6 a JS subscript store this['handle' + e] = fn is no name-key hop" )
p = subprocess.run( [ binp, f"{tmp}/hasattr", "--no-cache", "--callers=do_x" ], cwd = f"{tmp}/hasattr", capture_output = True, text = True, timeout = 120 )
check( p.returncode == 0 and '<pd in="has"' in p.stdout, "N6 the <pd> clue of the hasattr test stays on --callers" )
# M1: the MCP path_between twin crosses the same hop
req = '{"jsonrpc":"2.0","id":1,"method":"initialize","params":{}}\n{"jsonrpc":"2.0","id":2,"method":"tools/call","params":{"name":"path_between","arguments":{"from":"main","to":"list_dir"}}}\n'
p = subprocess.run( [ binp, "--mcp", sh, "--no-cache" ], cwd = sh, input = req, capture_output = True, text = True, timeout = 120 )
check( 'via=\\"name-key\\"' in p.stdout, "M1 MCP path_between crosses via=name-key" )
# M2 / T2 / L2 on the MCP twins
def mcp( d, name, **args ):
    req = '{"jsonrpc":"2.0","id":1,"method":"initialize","params":{}}\n' + json.dumps( { "jsonrpc": "2.0", "id": 2, "method": "tools/call", "params": { "name": name, "arguments": args } } ) + "\n"
    q = subprocess.run( [ binp, "--mcp", d, "--no-cache" ], cwd = d, input = req, capture_output = True, text = True, timeout = 120 )
    last = [ ln for ln in q.stdout.splitlines() if ln.strip() ][-1]
    try:
        return json.loads( last )["result"]["content"][0]["text"]
    except Exception:
        return ""
mt = mcp( sh, "impact", symbol = "do_ls" )
mr = root( mt, "impact" )
check( attr( mr, "reaches" ) == "0" and attr( mr, "reaches_hedged" ) == "2", f"M2 MCP impact keeps reaches=0 apart from reaches_hedged=2 ({mr[:160]})" )
check( attr( mr, "reaches_hedged_via" ) == "name-key", "L2 MCP impact carries reaches_hedged_via=name-key" )
mt = mcp( f"{tmp}/self2", "path_between", **{ "from": "main", "to": "do_again" } )
check( attr( root( mt, "path" ), "next" ) == "--expand=m.py:main", f"T2 MCP path_between root next= stays --expand ({attr( root( mt, 'path' ), 'next' )})" )
sys.exit( fail )
PY
rc=$?   # the harness's own status, read immediately (checklist 14): 0 every arm passed, 1 an arm failed, anything else a crash
fail=0
if [ "$rc" -ne 0 ]; then
    printf '  FAIL  the arm harness exited %s (an arm failed above, or the harness crashed)\n' "$rc"
    fail=1
fi
[ "$fail" = 0 ] && echo "ALL PASS" || echo "FAILURES ABOVE"
exit "$fail"
