#!/usr/bin/env bash
# receiverevidencecheck.sh — a call matched to a definition by NAME ALONE never presents as a single proven edge.
#
#   test/receiverevidencecheck.sh                          # uses build/ripwire on test/receiverevidencefix
#   RIPWIRE_BIN=asan/ripwire test/receiverevidencecheck.sh
#   test/receiverevidencecheck.sh build_base/ripwire       # the RED run (a pre-change binary)
#
# THE DEFECT. A member call `x.m()` (or, in a language with an implicit receiver, a bare `m()`) was bound to an
# in-repo definition of `m` because the NAME matched, with nothing proving the receiver is that definition's
# class. The answer then showed one confident row — and agents adopt a confident wrong row. Each shape below was
# a graded false row (paraphrased; the code is minimal and never built):
#   (Bm) a dynamic receiver bound to the wrong in-repo class: a request context's `ctx.onerror()` drawn to the
#        Application.onerror its file defines; an item's typed text field `item.text.Get()` drawn to Merger.Get;
#        a stored ASGI callable `self._send()` drawn to another class's nested `_send`; a constructor-assigned
#        field `this.bucket.listSchemas()` drawn to the caller's own class; a loop variable over inner routers
#        drawn to SmartRouter.add; `ctx.req.raw.headers.get()` drawn to Context.get because the file imports
#        Context; a member call `context.handler()` drawn to a same-named FREE function; an object-literal
#        module's `this.ctx.get()` drawn to that module's own `get`; a Go struct field or local named like a
#        package (`s.log.Errorf`) drawn to the in-repo `log.Errorf`.
#   (Bd) a builtin/library object behind a variable, in a file that names the class: WeakMap `.set/.get` → the
#        same file's accessors, Promise `.then` → Reply.prototype.then, a stream's `.on` → a TEST double,
#        `dict.get/keys/items` → StylesBase in a file that imports Styles, `list.append`/`str.split` →
#        Content.append/split, URLSearchParams `.append`, Set `.delete`, an outside router's `.all`, an asyncio
#        handle's `.cancel`, an outside parser's `.write`, an outside tcell screen's `.Size`, the globals
#        `Reflect.get` / `Atomics.add` beside in-repo `get` / `add`, a Python outside from-import
#        (`from json import dumps as stringify`) beside in-repo `stringify` / `dumps`.
#   (Bp) a parameter or local callable bound to a def elsewhere: `done()` (a parameter) → another file's
#        closure `done`; `read = os.read; read( fd )` → Stylesheet.read and `feed = parser.feed` → the base
#        class's feed when the parser is a constructed XTermParser (the rows FE-A's local-Keep rule restored);
#        `add_widget = widgets.append; add_widget( n )` → another class's nested add_widget; a JS alias
#        `const onerror = ctx.onerror` and a destructured `const { onerror } = ctx`, then `onerror( e )`.
#   (Bi) an implicit receiver (Java, Kotlin, C#, C++, Swift, Ruby): a bare `render()` / `flush()` inside a class
#        bound to an UNRELATED class's method, though the language reaches only the class's own members, its
#        superclasses and mixins, a free/top-level function, or an import.
#
# THE CONTRACT. Such a call either (a) RESOLVES WITH EVIDENCE — the receiver is `this`/`self`/`cls` inside the
# class or its cone, a construction in scope (`x = new Cls()`, `x = Cls()`, `m := &Merger{}`), a constructor-
# assigned field, a type annotation or declaration on the parameter/local (Go struct field, embedded field,
# aliased import), an import — and then shows one plain row; or (b) KEEPS ITS ROW WITH AN ON-ROW HEDGE:
# `via="name"` on the row itself (XML) / `"via":"name"` on the entry (MCP JSON), listing the by-name candidates
# — never a legend-only hedge, never a silent drop. Every surface shows the same row with the same hedge:
# --callees, --callers, --impact, --path, --connect, --expand <calls>, --for <calls>, the default map's <c> rows, and
# MCP find_symbol / find_referencing_symbols / analyze. A wrong candidate may also disappear (resolved elsewhere, or counted external/
# unresolved), but a TRUE target must stay visible, hedged or not. A SINGLE by-name candidate is hedged too:
# one candidate is not evidence (ruling D1). An --impact row at d>=2 that no all-proven path reaches inherits
# the hedge; a row with some all-proven path stays plain (ruling D3). Every surface's --legend=full (and the MCP
# tool description or answer) defines via="name" and says what it does NOT mean.
#
# PREDICATES (each over one answer; an answer about no symbol is NOROOT and never a pass; rows compare
# (kind, name, file[:line]) — the line only where a spec carries one):
#   notproven  — the named row is absent, or present WITH the hedge (the positive arms: red when unhedged)
#   proven     — the named row is present WITHOUT the hedge (evidence: a near miss a new rule could kill)
#   exactproven— the set of unhedged rows is exactly the given set (no false candidate rides along unhedged)
#   visible    — the named row is present, hedged or not (a true target is never dropped)
#   marked     — the named row is present WITH the hedge (a name-only true edge is kept and labelled)
#
# ARMS (one fixture root per language under test/receiverevidencefix/; each root is indexed on its own).
#   (J) JS:  Bm ctx.onerror (plain, optional-chained, aliased, destructured), an object-literal module's
#            this.ctx.get, member call → free function; Bd WeakMap/Promise/stream/router/Set/URLSearchParams, the
#            globals Reflect/Atomics; Bp a `done` parameter. Evidence that must RESOLVE: a constructor-assigned field
#            (this.bucket → Schemas.listSchemas). Near misses: this.onerror, same-file bare call, relative module
#            receiver (also one bound to the name `Reflect`), a closure called in its own function, construction
#            in scope (`new Application()` / `new Schemas()` decide between same-named methods), super.m(), a
#            class-name (static) receiver; the name-only `reply.send()` / `reply.code()` on a parameter are kept
#            and marked.
#   (T) TS:  Bm a loop variable over Router<T>[] → SmartRouter.add; WHATWG Headers.get → Context.get/Cache.get;
#            the global Atomics.add. Near misses: an annotated parameter, construction through an import alias, a
#            constructed local.
#   (P) Python: Bd dict/set/list/str in a file that imports the class; an argument's .animate; asyncio handle;
#            an outside package's parser; an outside from-import (plain and aliased); Bm self._send → a nested
#            _send, a non-self receiver in the class's own file (mode_screen.refresh, the property self.screen);
#            Bp read = os.read, feed = parser.feed (base class and an unrelated class), add_widget =
#            widgets.append. Near misses: self.update, a constructor-assigned field (+ cone), a typed parameter
#            (+ cone), construction, an import alias, an imported function beside same-named methods,
#            cls.method(), a class-name receiver (Styles.copy), the XTermParser.feed the alias really reaches, a
#            proven and a name-only site to the same method (the merged row stays plain); a name-only parameter
#            call kept and marked.
#   (G) Go:  evidence that must RESOLVE (ruling D4): a typed struct field, a typed parameter, a typed local
#            through an aliased import, an embedded field's promoted method — each exactly the util.Chars row, never
#            Merger.Get/Length; Bd an outside screen's Size, an outside value's Runes, a field or local named `log`
#            of an outside type beside the in-repo log.Errorf. Near misses: a pointer-literal local, the method
#            receiver itself, a real import of the in-repo log package.
#   (G2) Go module aliases (gomod/, one tree per directory): an import path proves a package EXACTLY — the nearest
#            go.mod's module path plus the directory below it, or the path a local `replace L => ./D` gives D. Bm:
#            `replace github.com/up/lib => ./third/lib` beside an in-repo lib/ drew lib.Mark() to lib/ (a directory
#            that merely ends the path); `example.com/t/pkg/lib` proved both pkg/lib and lib/ (declined). Near misses:
#            a replace onto lib/ itself, a replaced legacy/ with and without its own go.mod, a nested module,
#            example.com/a vs example.com/ab, a vendored copy (never the in-repo lib/), a dot import (never the decoy),
#            and a path-less root lib/ beside a nested module that carries the path.
#   (T) Java/C#/Kotlin/Swift (review B3): a typed parameter, a typed / constructed / Java `var` local, a typed or
#            constructed field or property — read bare (implicit this) or through this/self — and a Kotlin `val`
#            constructor property RESOLVE to the declared class's member (Pump.*: Tank and Barrel both define spill).
#            Near misses stay hedged: an untyped local (a lower-case factory), a local that hides the field, an
#            interface/protocol-typed receiver with two implementors (both still listed). Every other binding form: (B).
#   (B) binding scope (review B4; scope/*: Tank and Barrel both define spill, the class's field / the outer binding is a
#            Tank). (a) A binding that HIDES the field or an outer typed local never lets the call prove the field's
#            class: Java for/lambda/catch/resource/instanceof/case/record-pattern variables, C# foreach/lambda/is/out
#            var/case/deconstruction/catch/LINQ, Kotlin for/destructuring/lambda/let/when/catch, Swift for-in/case let/
#            tuple/closure/if-guard-while let/catch, and the same shapes where FE-B reads TS/JS/Python/Go evidence
#            (arrow and catch parameters, for-of, a block const, a destructuring, a JS reassignment; a Python for/lambda/comprehension/
#            with/except/walrus/match/reassignment; a Go range/if/type-switch variable). Outside its block a local never
#            lends its class (a nested block, a lambda's typed parameter), and the field (or outer local) proves again.
#            (b) A generic's type parameter spelled like a class (`<Tank>`, `Box<Tank>`, `[Tank Spiller]`, `def f[Tank]`)
#            never proves that class. Kept: the field itself, a typed local, a typed loop / lambda variable's own class.
#   (I) implicit receiver: Java, Kotlin, C#, C++, Swift, Ruby — a bare call inside a class whose base is OUTSIDE
#            the tree (or that imports the name from outside) never proves an unrelated class's method. Near
#            misses: own members (private too), an in-repo superclass's member (the cone, and Java super.m()),
#            a free / top-level function and a Ruby top-level def; a Ruby included module is contract-only (resolved
#            or hedged, never a false proven row): Ruby's own lookup is separate work.
#   (S) the two sides of a class lookup: a JS/TS call on the CLASS object (`Gauge.read()`, `this` in a static member)
#            resolves to the static member only and an instance call never to it; a Kotlin companion member likewise;
#            a class-name call naming an instance-only member is never proven. A Python `__getattr__` changes nothing
#            for a member the class defines, and a name its lookup misses is never proven onto another class.
#   (H) propagation and parity: the name-only witness `respondWith → reply.send()` is marked in --callees,
#            --callers, --impact (d=1), --path, --connect, --expand <calls>, --for <calls>, the map's <c> rows, MCP
#            find_symbol, find_referencing_symbols and analyze; the false witness `respond → ctx.onerror()` is absent-or-marked on every
#            one of them; the --for HOP blocks (<h n=…><calls>) never prove encode → Response.append,
#            respond → Application.onerror, pipePayload → the test double's on, back → its own module's get;
#            --impact at d>=2 inherits the hedge (viaModule through respondWith → send; serve through
#            respond → onerror) unless some all-proven path reaches the row (both: direct → new Reply().send);
#            the legend of every surface defines via="name" with a NOT sentence; and the hedge bit is
#            VALUE-EQUAL between CLI --callees and MCP calls, CLI --callers and MCP calledBy, and --callees and
#            --expand <calls>, over a set of selectors.
#   (O) graded false callees seen on an earlier binary, as minimal repros: Go exec Cmd.Output → an in-repo
#            Output method (fmt.Errorf / strings.Split pinned clean), TS Date#getTime → an in-repo getTime (the
#            global Response pinned clean), Python list.append on a list literal → Content.append; each on
#            --callees and its --for hop block, with constructed-local near misses.
#   (R) the base-class receiver (CR 5469474915): C# `base` and `super` where it is a keyword (Java/Kotlin/Swift/JS/TS),
#            and Python's super() call, walk the bases only; a LOCAL spelled `base` (Python/JS/TS/Go/Java/Kotlin/Swift/C++/
#            Ruby) or `super` (Go, C#, a Python name shadowing the builtin) never proves the base class's method — a typed
#            one resolves to its own class, an untyped one is hedged. Twins: the keyword calls still prove the base.
#   (C) conservation: each root's census dispositions still sum to calls= with unaccounted=0 (no silent drop).
#   (K) the predicates can fail: a planted unhedged false row fails notproven, a planted hedged row passes it and
#            fails proven, marked rejects an unhedged row, a rootless or not-found answer is NOROOT, the MCP reader
#            reads the hedge, a non-zero or missing exit status fails the arm, a parser crash (a malformed defs=)
#            fails the arm, and a hop reader never reads another hop's <calls>.
#   GUARDS: arms marked `# guard` were already green on the pre-change binary; they pin a shape the change must
#            not break and are not evidence of the fix.
#
# FLOORS — named, not gated here:
#   * Objective-C (a method is only ever sent `[recv msg]`; a bare call is a C function — FE-A's ladder), PHP, Lua,
#     Zig, Dart, Elixir: no arm.
#   * a computed member `ctx['onerror']()` records no call at all (pinned notproven, trivially).
#   * return-type inference (`mode_screen = self.get_screen(); mode_screen.refresh()` → Screen.refresh, or a
#     property's return) is not required: only the false single row is gated.
#   * --uses / --dead-code / --safe-delete, and --for hop blocks of symbols other than the four named in (H): not
#     gated here.
#   * a Python `cls()` construction inside a classmethod is polymorphic (a subclass's override is a legitimate
#     candidate): no arm.
#
# Exits non-zero on any failure.

set -u
export PYTHONDONTWRITEBYTECODE=1
ROOT="$( cd "$( dirname "$0" )/.." && pwd )"
. "$ROOT/test/lib/clean-env.sh"   # a gate that indexes a repo must not inherit GIT_DIR/GIT_WORK_TREE (gitenvhermeticcheck D)
BIN="${1:-${RIPWIRE_BIN:-$ROOT/build/ripwire}}"
[ "${BIN#/}" = "$BIN" ] && BIN="$ROOT/$BIN"          # allow a repo-relative binary
CORPUS="$ROOT/test/receiverevidencefix"
TMP="$( mktemp -d )"; trap 'rm -rf "$TMP"' EXIT
fail=0
ok(){ printf '  PASS  %s\n' "$*" || { fail=1; printf '  FAIL  could not write the PASS line for: %s\n' "$*"; }; return 0; }
no(){ printf '  FAIL  %s\n' "$*"; fail=1; }

[ -x "$BIN" ] || { echo "no ripwire binary at $BIN — build first (cmake --build build -j)"; exit 2; }
[ -d "$CORPUS" ] || { echo "fixture missing: $CORPUS"; exit 2; }
command -v python3 >/dev/null 2>&1 || { echo "python3 required"; exit 2; }
echo "receiverevidencecheck: BIN=$BIN  CORPUS=$CORPUS"

# rw ROOT ARGS… — run against one fixture root (every selector below is relative to that root's `.`)
rw(){ local r="$1"; shift; ( cd "$CORPUS/$r" && "$BIN" . --no-cache "$@" 2>/dev/null ); }

# ── the one reader every predicate shares ─────────────────────────────────────────────────────────────────────
# parse.py MODE FILE [ARGS] — prints one line per row; NOROOT when the document has no answer about a symbol.
# It EXITS NON-ZERO on malformed input (a non-numeric defs=/to_defs=/reachable=) or on any crash, and every call
# site goes through P, which FAILs the arm on a non-zero exit (a crash never reads as "no rows").
#   rows    <s> rows of a callees/callers/impact/path answer: "t n path line H d" (H = name | -, d = depth or -)
#   ecalls  <c> rows inside <calls> (all of them, or only those inside the <b> body named ARG): "n line H"
#           (a joined row `l="4,8"` prints one line per line number)
#   hcalls  <c> rows inside the --for HOP block <h n=ARG>: "n line H" (NOROOT when that hop is not shown)
#   edges   <e> rows of a connect answer: "f t H"
#   mcp     the entries of one array (ARG) of an MCP tools/call result: "name file line H"
#   map     <c> rows of the default MAP: "caller file callee H" (NOROOT without an <r> map root)
#   mcpmap  the same over the map an MCP tools/call (analyze) returned
#   legend  DEFINED when the answer's legend comments define via="name" — the mechanism ("name alone") and a
#           NOT sentence ("does NOT mean") within the definition — else UNDEFINED
#   mcplegend  the same over an MCP stream: the tools/list description of tool ARG, or the tools/call answer
cat >"$TMP/parse.py" <<'PY'
import json, re, sys
mode, path = sys.argv[ 1 ], sys.argv[ 2 ]
arg = sys.argv[ 3 ] if len( sys.argv ) > 3 else ""
doc = open( path, encoding="utf-8", errors="replace" ).read()
def attr( tag, name ):
    m = re.search( r'\s' + name + r'="([^"]*)"', tag )
    return m.group( 1 ) if m else None
def num( v, what ):
    if v is None:
        return None
    if not re.fullmatch( r"[0-9]+", v ):
        sys.stderr.write( "non-numeric %s=%r\n" % ( what, v ) )
        sys.exit( 3 )
    return int( v )
def hedge( tag ):
    return "name" if attr( tag, "via" ) == "name" else "-"
def crows( scope ):
    blocks = re.findall( r"<calls[ >].*?</calls>", scope, re.S )
    if not blocks:
        print( "NOROOT" ); sys.exit( 0 )
    for b in blocks:
        for c in re.findall( r"<c [^>]*>", b ):
            for l in ( attr( c, "l" ) or "-" ).split( "," ):
                print( attr( c, "n" ), l, hedge( c ) )
DEF = re.compile( r'via="name".{0,700}?name alone.{0,700}?does NOT mean', re.S )
if mode == "rows":
    root = re.search( r"<(callees|callers|impact|path) [^>]*>", doc )
    if not root:
        print( "NOROOT" ); sys.exit( 0 )
    head = root.group( 0 )
    found = num( attr( head, "defs" ), "defs" )
    if found is None:
        found = num( attr( head, "to_defs" ), "to_defs" )
    if root.group( 1 ) != "path" and ( found is None or found < 1 ):
        print( "NOROOT" ); sys.exit( 0 )
    depth = "-"
    for s in re.findall( r"<s [^>]*/>", doc[ root.start(): ] ):
        t, n, p = attr( s, "t" ), attr( s, "n" ), attr( s, "p" )
        if not ( t and n and p ):
            continue
        if attr( s, "d" ):
            depth = str( num( attr( s, "d" ), "d" ) )
        f, _, l = p.rpartition( ":" )
        print( t, n, f, l, hedge( s ), depth )
elif mode == "ecalls":
    scope = doc
    if arg:
        m = re.search( r'<b\b[^>]*\sn="' + re.escape( arg ) + r'"[^>]*>(.*?)</b>', doc, re.S )
        if not m:
            print( "NOROOT" ); sys.exit( 0 )
        scope = m.group( 1 )
    crows( scope )
elif mode == "hcalls":
    m = re.search( r'<h\b[^>]*\sn="' + re.escape( arg ) + r'"[^>]*>(.*?)</h>', doc, re.S )
    if not arg or not m:
        print( "NOROOT" ); sys.exit( 0 )
    crows( m.group( 1 ) )
elif mode == "edges":
    root = re.search( r"<connect [^>]*>", doc )
    if not root:
        print( "NOROOT" ); sys.exit( 0 )
    for e in re.findall( r"<e [^>]*/>", doc[ root.start(): ] ):
        print( attr( e, "f" ), attr( e, "t" ), hedge( e ) )
elif mode == "mcp":
    try:
        r = json.loads( doc.strip().splitlines()[ -1 ] )
        d = json.loads( r[ "result" ][ "content" ][ 0 ][ "text" ] )
    except Exception:
        print( "NOROOT" ); sys.exit( 0 )
    if d.get( arg ) is None:
        print( "NOROOT" ); sys.exit( 0 )
    for e in d[ arg ]:
        print( e.get( "name" ), e.get( "file" ), e.get( "line" ), "name" if e.get( "via" ) == "name" else "-" )
elif mode in ( "map", "mcpmap" ):
    if mode == "mcpmap":
        try:
            r = json.loads( doc.strip().splitlines()[ -1 ] )
            doc = r[ "result" ][ "content" ][ 0 ][ "text" ]
        except Exception:
            print( "NOROOT" ); sys.exit( 0 )
    if not re.search( r"<r[ >]", doc ):
        print( "NOROOT" ); sys.exit( 0 )
    for f in re.finditer( r'<f [^>]*>(.*?)</f>', doc, re.S ):
        fp = attr( f.group( 0 )[ :f.group( 0 ).index( ">" ) + 1 ], "p" )
        for s in re.finditer( r'<s ([^>]*?)(?:/>|>(.*?)</s>)', f.group( 1 ), re.S ):
            for c in re.findall( r"<c [^>]*>", s.group( 2 ) or "" ):
                print( attr( "<s " + s.group( 1 ) + ">", "n" ), fp, attr( c, "n" ), hedge( c ) )
elif mode == "legend":
    text = " ".join( re.findall( r"<!--(.*?)-->", doc, re.S ) )
    print( "DEFINED" if DEF.search( text ) else "UNDEFINED" )
elif mode == "mcplegend":
    texts = []
    for line in doc.splitlines():
        try:
            r = json.loads( line )
        except Exception:
            continue
        res = r.get( "result" ) or {}
        for t in res.get( "tools" ) or []:
            if t.get( "name" ) == arg:
                texts.append( t.get( "description" ) or "" )
        for c in res.get( "content" ) or []:
            texts.append( c.get( "text" ) or "" )
    if not texts:
        print( "NOROOT" ); sys.exit( 0 )
    norm = " ".join( texts ).replace( '"via":"name"', 'via="name"' )
    print( "DEFINED" if DEF.search( norm ) else "UNDEFINED" )
else:
    sys.stderr.write( "unknown mode %s\n" % mode ); sys.exit( 2 )
PY
# P MODE FILE [ARG] — the reader's output into $PARSED; a non-zero exit (crash, malformed input) FAILs the arm
P(){
    PARSED="$( python3 "$TMP/parse.py" "$@" 2>"$TMP/parse.err" )"
    local rc=$?
    if [ "$rc" -ne 0 ]; then no "the reader exited rc=$rc on [$*]: $( head -c 300 "$TMP/parse.err" | tr '\n' ' ' )"; return 1; fi
    return 0
}

# answer ROOT VERB SEL [EXTRA…] — write the verb's answer to a per-call file, its exit status beside it (FILE.rc)
answer(){
    local r="$1" v="$2" s="$3"; shift 3
    local f; f="$TMP/$( printf '%s' "$r" | tr '/' '_' ).$v.$( printf '%s' "$s$*" | tr '/:.,= ' '______' ).xml"
    rw "$r" "--$v=$s" "$@" >"$f"; printf '%s' "$?" >"$f.rc"
    printf '%s' "$f"
}
# ran_ok LABEL FILE — the run behind FILE exited 0 (a non-zero or missing exit status FAILs the arm)
ran_ok(){
    local rc; rc="$( cat "$2.rc" 2>/dev/null )"
    if [ "$rc" = "0" ]; then return 0; fi
    no "$1 exited rc=${rc:-unknown}"; return 1
}
# rowsof LABEL FILE — the rows of FILE into $GOT; a reader failure or an answer about no symbol FAILs (returns 1)
rowsof(){
    GOT=""
    P rows "$2" || return 1
    GOT="$PARSED"
    if [ "$GOT" = "NOROOT" ]; then no "$1 produced no answer about a symbol"; return 1; fi
    return 0
}
# getrows ROOT VERB SEL — rows of the verb's answer into $GOT ("" on a failed run or reader, FAIL already printed)
getrows(){
    local f; f="$( answer "$1" "$2" "$3" )"; GOT=""
    ran_ok "($1) --$2=$3" "$f" || return 1
    rowsof "($1) --$2=$3" "$f"
}
# match SPEC — the awk condition for "n path[:line]" over a rows line "t n path line H d"
specmatch(){   # prints the matching rows of $GOT for SPEC
    local n="${1%% *}" p="${1#* }" l=""
    case "$p" in *:[0-9]*) l="${p##*:}"; p="${p%:*}";; esac
    printf '%s\n' "$GOT" | awk -v n="$n" -v p="$p" -v l="$l" 'NF >= 5 && $2 == n && $3 == p && ( l == "" || $4 == l )'
}
show(){ printf '%s' "$GOT" | awk 'NF >= 5 { printf "%s %s %s:%s%s; ", $1, $2, $3, $4, ( $5 == "name" ? " via=name" : "" ) }'; }

notproven(){
    local r="$1" v="$2" s="$3"; shift 3
    getrows "$r" "$v" "$s" || return
    local spec hits
    for spec in "$@"; do
        hits="$( specmatch "$spec" | awk '$5 != "name"' )"
        if [ -n "$hits" ]; then no "($r) --$v=$s shows [$spec] as a PROVEN edge (no receiver evidence, no via=\"name\"): $( show )"
        else ok "($r) --$v=$s never proves [$spec] (absent or hedged)"; fi
    done
}
proven(){
    local r="$1" v="$2" s="$3"; shift 3
    getrows "$r" "$v" "$s" || return
    local spec t hits
    for spec in "$@"; do
        t="${spec%% *}"; hits="$( specmatch "${spec#* }" | awk -v t="$t" '$1 == t && $5 != "name"' )"
        if [ -n "$hits" ]; then ok "($r) --$v=$s keeps the proven row [$spec]"
        else no "($r) --$v=$s lost or hedged the proven row [$spec]: $( show )"; fi
    done
}
exactproven(){
    local r="$1" v="$2" s="$3" want="$4" got
    getrows "$r" "$v" "$s" || return
    got="$( printf '%s\n' "$GOT" | awk 'NF >= 5 && $5 != "name" { print $1 " " $2 " " $3 }' | sort -u | tr '\n' ';' | sed 's/;$//' )"
    want="$( printf '%s' "$want" | tr ';' '\n' | sort -u | tr '\n' ';' | sed 's/;$//' )"
    if [ "$got" = "$want" ]; then ok "($r) --$v=$s unhedged rows are exactly [${want:-none}]"
    else no "($r) --$v=$s unhedged rows are [${got:-none}], want [${want:-none}]"; fi
}
visible(){
    local r="$1" v="$2" s="$3"; shift 3
    getrows "$r" "$v" "$s" || return
    local spec
    for spec in "$@"; do
        if [ -n "$( specmatch "$spec" )" ]; then ok "($r) --$v=$s shows the true target [$spec] (hedged or not)"
        else no "($r) --$v=$s does not show the true target [$spec]: $( show )"; fi
    done
}
marked(){
    local r="$1" v="$2" s="$3"; shift 3
    getrows "$r" "$v" "$s" || return
    local spec
    for spec in "$@"; do
        if [ -n "$( specmatch "$spec" | awk '$5 == "name"' )" ]; then ok "($r) --$v=$s keeps [$spec] marked via=\"name\""
        elif [ -n "$( specmatch "$spec" )" ]; then no "($r) --$v=$s shows the name-only [$spec] with no via=\"name\": $( show )"
        else no "($r) --$v=$s dropped the name-only true edge [$spec]: $( show )"; fi
    done
}
# hopnotproven ROOT QUERY HOP NAME LINE — the --for answer shows the hop block <h n=HOP>, and that hop's <calls> row
# NAME at l=LINE is absent or via="name". A hop with no block is read through the HOP-SLOT RULE (test/forsigspancheck.sh
# (H)): a hop candidate whose every callee edge is name-only gets no <h> row and counts in noedge=. Then the arm reads
# the same fact off --callees instead, and every premise is checked, so an absent hop is never an empty pass: HOP's <d>
# row is in the answer with r= within <hops total=> (it was a hop candidate), noedge= >= 1, and --callees=FILE:HOP lists
# NAME and proves no row at all (else the hop was dropped for another reason: FAIL).
hopnotproven(){
    local r="$1" q="$2" h="$3" n="$4" l="$5" f
    f="$( answer "$r" for "$q" )"
    ran_ok "($r) --for=\"$q\"" "$f" || return
    P hcalls "$f" "$h" || return
    if [ "$PARSED" = "NOROOT" ]; then
        local drow hp hr htot hne
        drow="$( grep -o "<d [^>]*n=\"$h\"[^>]*>" "$f" | head -1 )"
        hp="$( printf '%s' "$drow" | sed -n 's/.* p="\([^"]*\)".*/\1/p' )"
        hr="$( printf '%s' "$drow" | sed -n 's/.* r="\([0-9][0-9]*\)".*/\1/p' )"
        htot="$( grep -o '<hops [^>]*>' "$f" | head -1 | sed -n 's/.* total="\([0-9][0-9]*\)".*/\1/p' )"
        hne="$( grep -o '<hops [^>]*>' "$f" | head -1 | sed -n 's/.* noedge="\([0-9][0-9]*\)".*/\1/p' )"
        case "$hp|$hr|$htot|$hne" in
            *'||'*|'|'*|*'|') no "($r) --for=\"$q\" shows no hop <h n=\"$h\">, and the hop-slot premises are unreadable (d p=/r=: '$hp'/'$hr', hops total=/noedge=: '$htot'/'$hne')"; return ;;
        esac
        if [ "$hr" -gt "$htot" ] || [ "$hne" -lt 1 ]; then
            no "($r) --for=\"$q\" shows no hop <h n=\"$h\">, and it was no dropped hop candidate (r=$hr, hops total=$htot, noedge=$hne)"; return
        fi
        getrows "$r" callees "$hp:$h" || return
        if [ -z "$( printf '%s\n' "$GOT" | awk -v n="$n" 'NF >= 5 && $2 == n' )" ]; then
            no "($r) --for=\"$q\" dropped hop $h, and --callees=$hp:$h does not list $n either: $( show )"
        elif [ -n "$( printf '%s\n' "$GOT" | awk 'NF >= 5 && $5 != "name"' )" ]; then
            no "($r) --for=\"$q\" dropped hop $h, yet --callees=$hp:$h proves a row (the hop-slot rule does not explain the drop): $( show )"
        else
            ok "($r) --for=\"$q\": hop $h takes no slot (every callee name-only: --callees=$hp:$h, noedge=$hne), so it never proves <c n=\"$n\">"
        fi
        return
    fi
    if [ -n "$( printf '%s\n' "$PARSED" | awk -v n="$n" -v l="$l" '$1 == n && $2 == l && $3 != "name"' )" ]; then
        no "($r) --for=\"$q\": hop $h proves <c n=\"$n\" l=\"$l\"> (no via=\"name\"): $( printf '%s' "$PARSED" | tr '\n' ';' )"
    else ok "($r) --for=\"$q\": hop $h never proves <c n=\"$n\" l=\"$l\"> (absent or hedged)"; fi
}

echo "=== (J) JS: receivers with no evidence never prove a same-named method ==="
notproven js callees lib/application.js:respond "onerror lib/application.js"
visible   js callees lib/application.js:respond "onerror lib/context.js"
notproven js callees lib/application.js:respondSafely "onerror lib/application.js"
notproven js callees lib/application.js:respondComputed "onerror lib/application.js"   # guard: no call recorded today
notproven js callees lib/application.js:respondAlias "onerror lib/application.js"     # guard
notproven js callees lib/application.js:respondDestructured "onerror lib/application.js"   # guard
notproven js callees lib/delegate/response.js:back "get lib/delegate/response.js"
visible   js callees lib/delegate/response.js:back "get lib/delegate/request.js"
notproven js callees lib/handle.js:run "handler lib/handle.js"
notproven js callees lib/request.js:compile "get lib/request.js" "set lib/request.js"
notproven js callees lib/reply.js:awaitResult "then lib/reply.js"
notproven js callees lib/reply.js:pipePayload "on test/server.test.js"
notproven js callees lib/routes.js:fallback "all lib/routes.js"
notproven js callees lib/routes.js:forget "delete lib/routes.js"
notproven js callees lib/search.js:encode "append lib/response.js"
notproven js callees lib/reply.js:writePayload "done lib/parser.js"
notproven js callees lib/meta.js:peek "get lib/meta.js" "get lib/reflect.js"   # guard
notproven js callees lib/meta.js:bump "add lib/meta.js"   # guard
echo "--- (J) evidence decides between same-named methods, and a constructor-assigned field RESOLVES"
exactproven js callees lib/uses.js:build "cls Application lib/application.js;method onerror lib/application.js;cls Schemas lib/schemas.js;method listSchemas lib/schemas.js"
notproven js callees lib/application.js:schemas "listSchemas lib/application.js"
exactproven js callees lib/application.js:schemas "method listSchemas lib/schemas.js"
echo "--- (J) near misses: true edges kept"
exactproven js callees lib/application.js:handle "method onerror lib/application.js;fn respond lib/application.js"
exactproven js callees lib/handle.js:wrapped "fn handler lib/handle.js"
exactproven js callees lib/uses.js:viaModule "fn respondWith lib/reply.js"
exactproven js callees lib/uses.js:make "method create lib/application.js"   # guard: a class-name (static) receiver
exactproven js callees lib/listing.js:list "method listSchemas lib/schemas.js"   # guard: super.listSchemas()
exactproven js callees lib/mirror.js:look "method get lib/reflect.js"   # guard: a relative module bound to `Reflect`
exactproven js callees lib/trailer.js:sendTrailer "fn send lib/trailer.js"
exactproven js callees lib/reply.js:direct "fn Reply lib/reply.js;method send lib/reply.js"
notproven js callees lib/reply.js:notFound "send lib/trailer.js"
marked    js callees lib/reply.js:notFound "code lib/reply.js" "send lib/reply.js"
marked    js callees lib/reply.js:respondWith "send lib/reply.js"

echo "=== (T) TS ==="
notproven ts callees src/router/smart.ts:match "add src/router/smart.ts"
notproven ts callees src/middleware/auth.ts:bearer "get src/context.ts" "get src/cache.ts"   # cache.ts: guard
notproven ts callees src/atomics.ts:bump "add src/atomics.ts" "add src/router/smart.ts" "add src/router/trie.ts"   # guard
echo "--- (T) near misses: annotation, alias construction, constructed local"
exactproven ts callees src/middleware/auth.ts:readUser "method get src/context.ts"
exactproven ts callees src/middleware/alias.ts:remember "cls Context src/context.ts;method set src/context.ts"
exactproven ts callees src/middleware/alias.ts:single "cls TrieRouter src/router/trie.ts;method add src/router/trie.ts;method match src/router/trie.ts"

echo "=== (P) Python ==="
notproven py callees src/tui/css/stylesheet.py:reparse "get src/tui/css/styles.py" "keys src/tui/css/styles.py" "items src/tui/css/styles.py" "update src/tui/css/stylesheet.py"   # update: guard
notproven py callees src/tui/css/stylesheet.py:refresh_rules "animate src/tui/css/styles.py"
notproven py callees src/tui/reactive.py:watch "append src/tui/content.py"
notproven py callees src/tui/reactive.py:toggle "split src/tui/content.py" "split src/tui/geometry.py"   # geometry.py: guard
notproven py callees src/tui/callback.py:invoke "call_later src/tui/message_pump.py" "cancel src/tui/worker.py"
notproven py callees src/web/formparsers.py:parse_form "write src/web/datastructures.py"
notproven py callees src/web/requests.py:send_json "_send src/web/errors.py"
notproven py callees src/web/render.py:render "stringify src/web/jsonutil.py" "dumps src/web/jsonutil.py"   # guard: outside from-import
notproven py callees src/tui/app.py:switch_mode "refresh src/tui/app.py"
notproven py callees src/tui/app.py:repaint_screen "refresh src/tui/app.py"
visible   py callees src/tui/app.py:repaint_screen "refresh src/tui/screen.py"
notproven py callees src/tui/drivers/linux.py:process_events "read src/tui/css/stylesheet.py" "feed src/tui/xterm_parser.py:2" "feed src/tui/byte_stream.py"
notproven py callees src/tui/screen.py:collect "add_widget src/tui/compositor.py"
echo "--- (P) near misses: self, constructor-assigned field, typed parameter, construction, alias, import, cls"
proven    py callees src/tui/drivers/linux.py:process_events "fn feed src/tui/xterm_parser.py:7"
exactproven py callees src/tui/css/stylesheet.py:own "fn update src/tui/css/stylesheet.py;fn get src/tui/css/styles.py"
# repaint: self.refresh() (proven) and self.screen.refresh() (a property: name-only) reach the same App.refresh;
# the merged row stays plain, and Screen.refresh may only ride along hedged
exactproven py callees src/tui/app.py:repaint "fn refresh src/tui/app.py"
exactproven py callees src/tui/uses.py:sync "fn update src/tui/css/stylesheet.py"
exactproven py callees src/tui/uses.py:apply "fn animate src/tui/css/styles.py"
exactproven py callees src/tui/uses.py:build "cls Stylesheet src/tui/css/stylesheet.py;fn update src/tui/css/stylesheet.py;fn read src/tui/css/stylesheet.py"
exactproven py callees src/tui/uses.py:clone "fn copy src/tui/css/styles.py"   # guard: a class-name receiver
exactproven py callees src/tui/css/stylesheet.py:parse_rules "fn parse src/tui/css/parse.py"
exactproven py callees src/tui/css/stylesheet.py:blank "fn default_rules src/tui/css/stylesheet.py"
marked    py callees src/tui/callback.py:schedule "call_later src/tui/message_pump.py"

echo "=== (G) Go: declared types RESOLVE (D4) ==="
notproven go callees src/result.go:buildResult "Get src/merger.go" "Length src/merger.go"
exactproven go callees src/result.go:buildResult "method Get src/util/chars.go;method Length src/util/chars.go"
exactproven go callees src/result.go:fromValue "method Get src/util/chars.go"
exactproven go callees src/embed.go:aliased "method Length src/util/chars.go"
notproven go callees src/embed.go:firstRune "Get src/merger.go"
exactproven go callees src/embed.go:firstRune "method Get src/util/chars.go"
notproven go callees src/tui/tcell.go:MaxY "Size src/tui/tcell.go"
notproven go callees src/tui/tcell.go:Graphemes "Runes src/tui/tcell.go"
notproven go callees src/service.go:Fail "Errorf src/internal/log/log.go"
notproven go callees src/service.go:Report "Errorf src/internal/log/log.go"
echo "--- (G) near misses: a pointer-literal local, the method receiver itself, a real package import"
exactproven go callees src/result.go:merged "method Length src/merger.go"
exactproven go callees src/merger.go:First "method Get src/merger.go"
exactproven go callees src/tui/tcell.go:Lines "method Size src/tui/tcell.go"
exactproven go callees src/cmd/run.go:Run "fn Errorf src/internal/log/log.go"   # guard

echo "=== (G2) Go module aliases: an import path proves a package exactly ==="
mkdir -p "$TMP/gomod"
exactproven gomod/fork2 callees app/app.go:Use "fn Mark third/lib/l.go"   # Bm: lib/ merely ends github.com/up/lib
notproven   gomod/fork2 callees app/app.go:Use "Mark lib/l.go"
exactproven gomod/tail  callees app/app.go:Use "fn Mark pkg/lib/l.go"     # Bm: lib/ ends example.com/t/pkg/lib too
exactproven gomod/tail  callees app/near.go:Near "fn Mark lib/l.go"
exactproven gomod/fork  callees app/app.go:Use "fn Mark lib/l.go"         # near miss: the replace names lib/ itself
exactproven gomod/rep   callees app/app.go:Use "fn Mark legacy/lib/l.go"  # near miss: replaced, with its own go.mod
exactproven gomod/rep   callees app/near.go:Near "fn Mark lib/l.go"
exactproven gomod/rep2  callees app/app.go:Use "fn Mark legacy/lib/l.go"  # near miss: replaced, under the root go.mod only
exactproven gomod/rep2  callees app/near.go:Near "fn Mark lib/l.go"
exactproven gomod/nest  callees app/app.go:Use "fn Mark other/util/u.go"  # near miss: a nested module
exactproven gomod/pfx   callees app/app.go:Use "fn Mark ab/lib/l.go"      # near miss: example.com/a vs example.com/ab
exactproven gomod/pfx   callees app/near.go:Near "fn Mark lib/l.go"
notproven   gomod/vend  callees app/app.go:Use "Mark lib/l.go"            # near miss: the vendored copy is the package
notproven   gomod/dot   callees app/app.go:Use "Mark decoy/d.go"          # near miss: a dot import (lib/ unresolved: a floor)
exactproven gomod/mixed callees m/app/app.go:Use "fn Mark m/lib/l.go"     # near miss: a path-less lib/ never takes a carried path

echo "=== (T) Java/C#/Kotlin/Swift: declared receivers RESOLVE (review B3) ==="
exactproven java  callees src/main/java/app/Pump.java:param "method spill src/main/java/app/Pump.java"
exactproven java  callees src/main/java/app/Pump.java:typedLocal "method spill src/main/java/app/Pump.java;method makeTank src/main/java/app/Pump.java"
exactproven java  callees src/main/java/app/Pump.java:ctorLocal "cls Tank src/main/java/app/Pump.java;method spill src/main/java/app/Pump.java"
exactproven java  callees src/main/java/app/Pump.java:varLocal "cls Tank src/main/java/app/Pump.java;method spill src/main/java/app/Pump.java"
exactproven java  callees src/main/java/app/Pump.java:implicitField "method spill src/main/java/app/Pump.java"
exactproven java  callees src/main/java/app/Pump.java:thisField "method spill src/main/java/app/Pump.java"
proven      java  callees src/main/java/app/Pump.java:param "method spill src/main/java/app/Pump.java:7"
notproven   java  callees src/main/java/app/Pump.java:untyped "spill src/main/java/app/Pump.java:7" "spill src/main/java/app/Pump.java:8"       # near miss: an untyped local
notproven   java  callees src/main/java/app/Pump.java:shadow "spill src/main/java/app/Pump.java:7" "spill src/main/java/app/Pump.java:8"        # near miss: a local hides the field
notproven   java  callees src/main/java/app/Pump.java:viaIface "spill src/main/java/app/Pump.java:7" "spill src/main/java/app/Pump.java:8"      # near miss: an interface, two implementors
visible     java  callees src/main/java/app/Pump.java:viaIface "spill src/main/java/app/Pump.java:7" "spill src/main/java/app/Pump.java:8"
exactproven cs    callees App/Pump.cs:Param "method Spill App/Pump.cs"
exactproven cs    callees App/Pump.cs:TypedLocal "method Spill App/Pump.cs;method MakeTank App/Pump.cs"
exactproven cs    callees App/Pump.cs:CtorLocal "method Spill App/Pump.cs;cls Tank App/Pump.cs"
exactproven cs    callees App/Pump.cs:ImplicitField "method Spill App/Pump.cs"
exactproven cs    callees App/Pump.cs:ThisField "method Spill App/Pump.cs"
proven      cs    callees App/Pump.cs:ViaProperty "method Spill App/Pump.cs:8"
notproven   cs    callees App/Pump.cs:Untyped "Spill App/Pump.cs:7" "Spill App/Pump.cs:8"
notproven   cs    callees App/Pump.cs:Shadow "Spill App/Pump.cs:7" "Spill App/Pump.cs:8"
notproven   cs    callees App/Pump.cs:ViaIface "Spill App/Pump.cs:7" "Spill App/Pump.cs:8"
visible     cs    callees App/Pump.cs:ViaIface "Spill App/Pump.cs:7" "Spill App/Pump.cs:8"
exactproven kt    callees src/app/Pump.kt:param "fn spill src/app/Pump.kt"
exactproven kt    callees src/app/Pump.kt:typedLocal "fn spill src/app/Pump.kt;fn makeTank src/app/Pump.kt"
exactproven kt    callees src/app/Pump.kt:ctorLocal "cls Tank src/app/Pump.kt;fn spill src/app/Pump.kt"
exactproven kt    callees src/app/Pump.kt:implicitField "fn spill src/app/Pump.kt"
exactproven kt    callees src/app/Pump.kt:thisField "fn spill src/app/Pump.kt"
proven      kt    callees src/app/Pump.kt:ctorProperty "fn spill src/app/Pump.kt:8"
proven      kt    callees src/app/Pump.kt:constructedProperty "fn spill src/app/Pump.kt:7"
notproven   kt    callees src/app/Pump.kt:untyped "spill src/app/Pump.kt:7" "spill src/app/Pump.kt:8"
notproven   kt    callees src/app/Pump.kt:shadow "spill src/app/Pump.kt:7" "spill src/app/Pump.kt:8"
notproven   kt    callees src/app/Pump.kt:viaIface "spill src/app/Pump.kt:7" "spill src/app/Pump.kt:8"
visible     kt    callees src/app/Pump.kt:viaIface "spill src/app/Pump.kt:7" "spill src/app/Pump.kt:8"
exactproven swift callees Sources/App/Pump.swift:param "fn spill Sources/App/Pump.swift"
exactproven swift callees Sources/App/Pump.swift:typedLocal "fn spill Sources/App/Pump.swift;fn makeTank Sources/App/Pump.swift"
exactproven swift callees Sources/App/Pump.swift:ctorLocal "cls Tank Sources/App/Pump.swift;fn spill Sources/App/Pump.swift"
exactproven swift callees Sources/App/Pump.swift:implicitField "fn spill Sources/App/Pump.swift"
exactproven swift callees Sources/App/Pump.swift:selfField "fn spill Sources/App/Pump.swift"
proven      swift callees Sources/App/Pump.swift:constructedProperty "fn spill Sources/App/Pump.swift:6"
notproven   swift callees Sources/App/Pump.swift:untyped "spill Sources/App/Pump.swift:5" "spill Sources/App/Pump.swift:6"
notproven   swift callees Sources/App/Pump.swift:shadow "spill Sources/App/Pump.swift:5" "spill Sources/App/Pump.swift:6"
notproven   swift callees Sources/App/Pump.swift:viaIface "spill Sources/App/Pump.swift:5" "spill Sources/App/Pump.swift:6"
visible     swift callees Sources/App/Pump.swift:viaIface "spill Sources/App/Pump.swift:5" "spill Sources/App/Pump.swift:6"

echo "=== (B) binding scope (review B4): a binding that hides a field or an outer local, and a type parameter ==="
# hides ROOT FILE NAME OUTER BOUND FN… — at each FN's call, a binding of the receiver's name hides the field (or outer local)
# whose class defines NAME at line OUTER: that edge is never PROVEN, and the candidate at line BOUND (the binding's own
# class) stays visible, hedged or proven. Outside a binding's scope the roles swap (OUTER = the binding's class).
hides(){
    local r="$1" f="$2" n="$3" outer="$4" bound="$5" fn; shift 5
    for fn in "$@"; do
        notproven "$r" callees "$f:$fn" "$n $f:$outer"
        visible   "$r" callees "$f:$fn" "$n $f:$bound"
    done
}
J=src/app/Scope.java; C=App/Scope.cs; K=src/app/Scope.kt; W=Sources/App/Scope.swift
hides scope/java  $J spill 7 8 forEachLoop lambdaParam typedLambda catchUse tryRes patternVar negatedPattern switchPattern recordPattern
hides scope/java  $J spill 8 7 nestedBlock lambdaOutside                       # outside its block: never the binding's Barrel
hides scope/java  $J spill 7 7 methodTypeParam classTypeParam typeParamField   # <Tank>: any Spiller, never class Tank proven
proven scope/java callees $J:fieldUse "method spill $J:7"
proven scope/java callees $J:typedLocal "method spill $J:8"
hides scope/cs    $C Spill 7 8 ForEachLoop ForEachVar LambdaParam PatternVar OutVar SwitchCase Deconstruct CatchUse Linq
hides scope/cs    $C Spill 8 7 NestedBlock LambdaOutside
hides scope/cs    $C Spill 7 7 MethodTypeParam ClassTypeParam TypeParamField
proven scope/cs   callees $C:FieldUse "method Spill $C:7"
proven scope/cs   callees $C:NestedBlock "method Spill $C:7"                     # the field, past the block that hid it
proven scope/cs   callees $C:TypedLocal "method Spill $C:8"
proven scope/cs   callees $C:ForEachLoop "method Spill $C:8"                     # the loop variable's own declared class
hides scope/kt    $K spill 5 6 forLoop forDestructure lambdaParam letParam typedLambda destructure whenSubject catchUse
hides scope/kt    $K spill 6 5 nestedBlock lambdaOutside
hides scope/kt    $K spill 5 5 classTypeParam typeParamField
proven scope/kt   callees $K:fieldUse "fn spill $K:5"
proven scope/kt   callees $K:typedLocal "fn spill $K:6"
proven scope/kt   callees $K:typedLambda "fn spill $K:6"
hides scope/swift $W spill 3 4 forLoop forCaseLet forTuple closureParam typedClosure ifLet guardLet whileLet caseLet ifCaseLet catchLet
hides scope/swift $W spill 4 3 nestedBlock
hides scope/swift $W spill 3 3 classTypeParam typeParamField
proven scope/swift callees $W:fieldUse "fn spill $W:3"
proven scope/swift callees $W:typedLocal "fn spill $W:4"
echo "--- (B) the same shapes where FE-B reads TS / JS / Python / Go evidence (an outer typed or constructed binding hidden)"
hides scope/ts    scope.ts spill 4 5 arrowParam forOf blockLocal catchParam destructure
hides scope/ts    scope.ts spill 4 4 typeParam classTypeParam typeParamField
proven scope/ts   callees scope.ts:typedParam "method spill scope.ts:4"
hides scope/js    scope.js spill 2 3 arrowParam forOf catchParam reassign
proven scope/js   callees scope.js:blockOutside "method spill scope.js:2"         # the outer local, past the block that hid it
proven scope/js   callees scope.js:constructed "method spill scope.js:2"
hides scope/py    scope.py spill 3 6 for_loop lambda_param comprehension with_as except_as walrus reassign match_capture match_as
hides scope/py    scope.py spill 3 3 type_param
proven scope/py   callees scope.py:typed_param "fn spill scope.py:3"
hides scope/go    scope.go Spill 8 12 RangeLoop ShortIf TypeSwitch
hides scope/go    scope.go Spill 8 8 TypeParam TypeParamField
proven scope/go   callees scope.go:BlockOutside "method Spill scope.go:8"
proven scope/go   callees scope.go:TypedParam "method Spill scope.go:8"

echo "=== (I) implicit receiver: a bare call never proves an unrelated class's method ==="
notproven java callees src/main/java/app/Logger.java:line "render src/main/java/app/Exporter.java"
notproven java callees src/main/java/app/Logger.java:close "flush src/main/java/app/Buffer.java" "flush src/main/java/app/Exporter.java"
notproven java callees src/main/java/app/FileBuffer.java:sync "flush src/main/java/app/Exporter.java"
notproven kt callees src/app/Plain.kt:finish "flush src/app/Exporter.kt" "flush src/app/Logger.kt"
notproven cs callees App/Logger.cs:Line "Render App/Exporter.cs"
notproven cs callees App/Logger.cs:Finish "Flush App/Logger.cs" "Flush App/Exporter.cs"   # Exporter.cs: guard
notproven cpp callees src/plain.cpp:finish "flush src/exporter.cpp" "flush src/logger.cpp"
notproven swift callees Sources/App/Plain.swift:finish "flush Sources/App/Exporter.swift" "flush Sources/App/Logger.swift"
notproven rb callees lib/app/plain.rb:finish "render lib/app/exporter.rb" "flush lib/app/logger.rb"
echo "--- (I) near misses: own members, the in-repo superclass (cone, super.m()), free/top-level functions, mixins"
proven    java callees src/main/java/app/Logger.java:close "method reset src/main/java/app/Logger.java"
proven    java callees src/main/java/app/FileBuffer.java:sync "method flush src/main/java/app/Buffer.java"
exactproven java callees src/main/java/app/FileBuffer.java:drain "method flush src/main/java/app/Buffer.java"
exactproven java callees src/main/java/app/Buffer.java:write "method flush src/main/java/app/Buffer.java"
exactproven kt callees src/app/Logger.kt:line "fn render src/app/Logger.kt"
exactproven kt callees src/app/Logger.kt:close "fn flush src/app/Logger.kt;fn reset src/app/Logger.kt"
exactproven cs callees App/Logger.cs:Close "method Flush App/Logger.cs;method Reset App/Logger.cs"
exactproven cpp callees src/logger.cpp:line "fn render src/logger.cpp"
exactproven cpp callees src/logger.cpp:close "method flush src/logger.cpp;method reset src/logger.cpp"
exactproven swift callees Sources/App/Logger.swift:line "fn render Sources/App/Logger.swift"
exactproven swift callees Sources/App/Logger.swift:close "fn flush Sources/App/Logger.swift;fn reset Sources/App/Logger.swift"
# Ruby's own method lookup (mixins, typed and class receivers) is another lane's: these two arms state only the
# contract — a mixin's method is RESOLVED or HEDGED, never dropped and never beside a false proven row — so they hold
# whichever lands first
visible   rb callees lib/app/logger.rb:line "stamp lib/app/helpers.rb"
notproven rb callees lib/app/logger.rb:line "render lib/app/exporter.rb"
# Ruby's own lookup (RubySelfReach, PR #373) is PROOF: what it proves comes out resolved, never via="name" — a mixin's
# method, a concern's call to its includer's method, a template method's call to a subclass's hook
exactproven rb callees lib/app/logger.rb:line "method stamp lib/app/helpers.rb"
exactproven rb callees lib/app/auditable.rb:log_audit "method audit_target lib/app/order.rb"
exactproven rb callees lib/app/order.rb:render_report "method header_line lib/app/order.rb"
exactproven rb callees lib/app/logger.rb:close "method flush lib/app/logger.rb;method reset lib/app/logger.rb;method top_level_note lib/app/notes.rb"

echo "=== (O) graded false callees from an earlier binary (Go, TS, Python repros): red where still present, pinned clean otherwise ==="
notproven go callees src/gotool.go:runGo "Output src/gotool.go"
notproven go callees src/gotool.go:runGo "Errorf src/internal/log/log.go" "Split src/gotool.go"   # guard: fmt.Errorf, strings.Split
exactproven go callees src/gotool.go:runTool "method Output src/gotool.go;method Split src/gotool.go"   # guard
notproven ts callees src/http.ts:reply "getTime src/http.ts"
notproven ts callees src/http.ts:reply "Response src/response.ts"   # guard: the global Response
notproven ts callees src/http.ts:stamped "getTime src/http.ts"
exactproven ts callees src/http.ts:local "cls Clock src/http.ts;method getTime src/http.ts"
exactproven ts callees src/http.ts:wrap "cls Response src/response.ts"   # guard
notproven py callees src/tui/listing.py:gather "append src/tui/content.py"
exactproven py callees src/tui/listing.py:grow "cls Content src/tui/content.py;fn append src/tui/content.py"
hopnotproven go "how does runGo run the go command" runGo Output 14
hopnotproven ts "how does reply build a Response" reply getTime 5
hopnotproven ts "how does stamped get the time" stamped getTime 5
hopnotproven py "how does gather append nodes" gather append 5

echo "=== (S) the two SIDES of a class lookup, and a fallback hook only after a miss (#373's Ruby class-object rule) ==="
# JS: Gauge.read() is the static (line 3) and never the instance read (line 4); new Gauge().read() the reverse; `this` inside
# a static member is the class. Plain.read() names an instance-only member on the CLASS: never proven (hedged or absent).
proven    js callees lib/sides.js:onClass "method read lib/sides.js:3"
notproven js callees lib/sides.js:onClass "read lib/sides.js:4"
proven    js callees lib/sides.js:onInstance "method read lib/sides.js:4"
notproven js callees lib/sides.js:onInstance "read lib/sides.js:3"
proven    js callees lib/sides.js:make "method read lib/sides.js:3"
notproven js callees lib/sides.js:make "read lib/sides.js:4"
notproven js callees lib/sides.js:wrongSide "read lib/sides.js:8" "read lib/sides.js:4"
# TS: the same through a class-name receiver and a typed parameter
proven    ts callees src/sides.ts:onClass "method read src/sides.ts:3"
notproven ts callees src/sides.ts:onClass "read src/sides.ts:4"
proven    ts callees src/sides.ts:onTyped "method read src/sides.ts:4"
notproven ts callees src/sides.ts:onTyped "read src/sides.ts:3"
# Kotlin: Dial.read() is the companion's; Knob().read() never the companion's
exactproven kt callees src/app/Sides.kt:onClass "fn read src/app/Sides.kt"
notproven kt callees src/app/Sides.kt:onInstance "read src/app/Sides.kt:6"
# Python __getattr__ runs only after a miss: run()'s self.real() resolves to Proxyish.real (the hook changes nothing for a
# member the class defines); self.ghost() — a name the lookup misses — is never proven onto another class's ghost
proven    py callees src/tui/ghost.py:run "fn real src/tui/ghost.py:7"
notproven py callees src/tui/ghost.py:run "real src/tui/ghost.py:19" "ghost src/tui/ghost.py:16"
echo "=== (H) propagation: one hedge, every surface ==="
# the name-only TRUE witness respondWith → reply.send(): kept and marked everywhere
marked js callers lib/reply.js:send "respondWith lib/reply.js"
# impact_d3 — the d=1 row respondWith is marked; viaModule (d=2, reached ONLY through respondWith → send) inherits
# the hedge; both (d=2, also reached through direct → new Reply().send, all proven) and direct (d=1) stay plain
impact_send(){
    local f; f="$( answer js impact lib/reply.js:send )"
    ran_ok "(js) --impact=lib/reply.js:send" "$f" || return
    rowsof "(H) --impact=lib/reply.js:send" "$f" || return
    local d1 vm bo di
    d1="$( printf '%s\n' "$GOT" | awk '$2 == "respondWith" && $6 == "1" { print $5 }' )"
    if [ "$d1" = "name" ]; then ok "(H) --impact=lib/reply.js:send: the d=1 row respondWith is marked via=\"name\""
    else no "(H) --impact=lib/reply.js:send: the d=1 row respondWith is [${d1:-absent}], want via=\"name\": $( show )"; fi
    vm="$( printf '%s\n' "$GOT" | awk '$2 == "viaModule" && $6 == "2" { print $5 }' )"
    if [ "$vm" = "name" ]; then ok "(H) --impact=lib/reply.js:send: viaModule (d=2, only through the hedged edge) inherits via=\"name\""
    else no "(H) --impact=lib/reply.js:send: viaModule at d=2 is [${vm:-absent}], want via=\"name\" (D3): $( show )"; fi
    bo="$( printf '%s\n' "$GOT" | awk '$2 == "both" && $6 == "2" { print $5 }' )"
    if [ "$bo" = "-" ]; then ok "(H) --impact=lib/reply.js:send: both (d=2, an all-proven path through direct) stays plain"
    else no "(H) --impact=lib/reply.js:send: both at d=2 is [${bo:-absent}], want plain (an all-proven path reaches it): $( show )"; fi
    di="$( printf '%s\n' "$GOT" | awk '$2 == "direct" && $6 == "1" { print $5 }' )"
    if [ "$di" = "-" ]; then ok "(H) --impact=lib/reply.js:send: direct (d=1, new Reply().send) stays plain"
    else no "(H) --impact=lib/reply.js:send: direct at d=1 is [${di:-absent}], want plain: $( show )"; fi
}
impact_send
path_send(){
    local f last; f="$( answer js path lib/uses.js:viaModule,lib/reply.js:send )"
    ran_ok "(js) --path=viaModule,send" "$f" || return
    P rows "$f" || return
    GOT="$PARSED"
    last="$( printf '%s\n' "$GOT" | awk 'NF >= 5' | tail -1 )"
    case "$last" in
        "method send lib/reply.js 7 name"*) ok "(H) --path=viaModule,send: the hop into Reply.prototype.send is marked via=\"name\"";;
        *) no "(H) --path=viaModule,send: last hop is [${last:-none}], want Reply.prototype.send marked via=\"name\": $( show )";;
    esac
}
path_send
connect_send(){
    local f e; f="$( answer js connect lib/reply.js:respondWith,lib/reply.js:send )"
    ran_ok "(js) --connect=respondWith,send" "$f" || return
    P edges "$f" || return
    e="$( printf '%s\n' "$PARSED" | awk '$1 == "respondWith" && $2 == "send" { print $3 }' )"
    if [ "$e" = "name" ]; then ok "(H) --connect: the edge respondWith → send is marked via=\"name\""
    else no "(H) --connect: the edge respondWith → send is [${e:-absent}], want via=\"name\": $( printf '%s' "$PARSED" | tr '\n' ';' )"; fi
}
connect_send
expand_send(){
    local f c; f="$( answer js expand lib/reply.js:respondWith --top-k=0 --legend=full )"
    ran_ok "(js) --expand=respondWith" "$f" || return
    P ecalls "$f" || return
    c="$( printf '%s\n' "$PARSED" | awk '$1 == "send" { print $3 }' | sort -u )"
    if [ "$c" = "name" ]; then ok "(H) --expand=respondWith: <calls> row send is marked via=\"name\""
    else no "(H) --expand=respondWith: <calls> row send is [${c:-absent}], want via=\"name\": $( printf '%s' "$PARSED" | tr '\n' ';' )"; fi
}
expand_send
for_send(){
    local f c; f="$( answer js for "how does respondWith send the reply" --legend=full )"
    ran_ok "(js) --for=respondWith" "$f" || return
    P ecalls "$f" respondWith || return
    if [ "$PARSED" = "NOROOT" ]; then no "(H) --for: no respondWith body with <calls> (the arm needs it)"; return; fi
    c="$( printf '%s\n' "$PARSED" | awk '$1 == "send" { print $3 }' | sort -u )"
    if [ "$c" = "name" ]; then ok "(H) --for: respondWith's body <calls> row send is marked via=\"name\""
    else no "(H) --for: respondWith's body <calls> row send is [${c:-absent}], want via=\"name\": $( printf '%s' "$PARSED" | tr '\n' ';' )"; fi
}
for_send
# the FALSE witness respond → ctx.onerror(): absent or marked on every surface
notproven js callers lib/application.js:onerror "respond lib/application.js" "respondSafely lib/application.js"
impact_onerror(){
    local f se rs; f="$( answer js impact lib/application.js:onerror )"
    ran_ok "(js) --impact=lib/application.js:onerror" "$f" || return
    rowsof "(H) --impact=lib/application.js:onerror" "$f" || return
    if [ -n "$( printf '%s\n' "$GOT" | awk '$2 == "respond" && $6 == "1" && $5 != "name"' )" ]; then
        no "(H) --impact=lib/application.js:onerror proves respond at d=1: $( show )"
    else ok "(H) --impact=lib/application.js:onerror never proves respond at d=1"; fi
    # serve reaches onerror only through respond: when respond is shown (hedged), serve is shown at d=2 marked
    rs="$( printf '%s\n' "$GOT" | awk '$2 == "respond" { print $5 }' )"
    se="$( printf '%s\n' "$GOT" | awk '$2 == "serve" { print $5 "@" $6 }' )"
    if [ -n "$rs" ]; then
        if [ "$se" = "name@2" ]; then ok "(H) --impact=lib/application.js:onerror: serve (d=2, only through respond's name-only call) inherits via=\"name\""
        else no "(H) --impact=lib/application.js:onerror: serve is [${se:-absent}], want via=\"name\" at d=2 (D3): $( show )"; fi
    else
        case "$se" in ""|name@*) ok "(H) --impact=lib/application.js:onerror: respond is gone, serve is absent or marked";;
                       *) no "(H) --impact=lib/application.js:onerror: serve is PROVEN [$se] with respond gone: $( show )";; esac
    fi
}
impact_onerror
path_onerror(){
    local f last reach top; f="$( answer js path lib/application.js:respond,lib/application.js:onerror )"
    ran_ok "(js) --path=respond,onerror" "$f" || return
    P rows "$f" || return
    GOT="$PARSED"
    last="$( printf '%s\n' "$GOT" | awk 'NF >= 5' | tail -1 )"
    top="$( grep -oE '<path [^>]*>' "$f" | grep -oE ' to_p="[^"]*"' )"
    if [ "$top" != ' to_p="lib/application.js:12"' ]; then no "(H) --path=respond,onerror bound the target to [${top:-nothing}], want to_p=\"lib/application.js:12\""; return; fi
    reach="$( grep -oE '<path [^>]*>' "$f" | grep -oE ' reachable="[^"]*"' | sed 's/.*="//; s/"$//' )"
    case "$reach" in ''|*[!0-9]*) no "(H) --path=respond,onerror carries no numeric reachable= ([$reach])"; return;; esac
    if [ "$reach" = "0" ]; then ok "(H) --path=respond,onerror: unreachable (the false edge is gone)"
    else case "$last" in
        *" name "*|*" name") ok "(H) --path=respond,onerror: the hop into Application.onerror is marked via=\"name\"";;
        *) no "(H) --path=respond,onerror proves the hop into Application.onerror: [$last]";;
    esac; fi
}
path_onerror
expand_onerror(){
    local f; f="$( answer js expand lib/application.js:respond --top-k=0 --legend=full )"
    ran_ok "(js) --expand=respond" "$f" || return
    P ecalls "$f" || return
    if [ "$PARSED" = "NOROOT" ]; then no "(H) --expand=respond emitted no <calls> block"
    elif [ -n "$( printf '%s\n' "$PARSED" | awk '$1 == "onerror" && $2 == "12" && $3 != "name"' )" ]; then
        no "(H) --expand=respond: <calls> proves onerror at application.js:12: $( printf '%s' "$PARSED" | tr '\n' ';' )"
    else ok "(H) --expand=respond: <calls> never proves Application.onerror"; fi
}
expand_onerror

echo "--- (H) --for HOP blocks: the graded false rows were hop <calls>, not only body <calls>"
hopnotproven js "how does handle report an error" encode append 3
hopnotproven js "how does respond report an error on ctx" respond onerror 12
hopnotproven js "how does pipePayload handle payload end" pipePayload on 4
hopnotproven js "how does the response go back to the referrer" back get 4

echo "--- (H) the legend defines via=\"name\" and says what it does NOT mean, on every surface"
legend_arm(){
    local label="$1" f="$2"
    ran_ok "(H) legend $label" "$f" || return
    P legend "$f" || return
    if [ "$PARSED" = "DEFINED" ]; then ok "(H) legend $label defines via=\"name\" (by name alone) with a NOT sentence"
    else no "(H) legend $label: no definition of via=\"name\" naming the mechanism (\"name alone\") and a \"does NOT mean\" sentence"; fi
}
legend_arm "--callees" "$( answer js callees lib/reply.js:respondWith --legend=full )"
legend_arm "--callers" "$( answer js callers lib/reply.js:send --legend=full )"
legend_arm "--impact"  "$( answer js impact lib/reply.js:send --legend=full )"
legend_arm "--path"    "$( answer js path lib/uses.js:viaModule,lib/reply.js:send --legend=full )"
legend_arm "--connect" "$( answer js connect lib/reply.js:respondWith,lib/reply.js:send --legend=full )"
legend_arm "--expand"  "$( answer js expand lib/reply.js:respondWith --top-k=0 --legend=full )"
legend_arm "--for"     "$( answer js for "how does respondWith send the reply" --legend=full )"

echo "--- (H) the MAP's <c> rows carry the same bit (the orient map is a surface too)"
# map_c FILE CALLER FILE CALLEE — the hedge column of that map <c> row ("" when absent; NOROOT FAILs the arm)
map_c(){
    P map "$1" || return 1
    if [ "$PARSED" = "NOROOT" ]; then no "(H) map: no <r> map document to read"; return 1; fi
    MAPC="$( printf '%s\n' "$PARSED" | awk -v n="$2" -v f="$3" -v c="$4" '$1 == n && $2 == f && $3 == c { print $4 }' | sort -u | tr '\n' ' ' | sed 's/ $//' )"
}
map_arms(){
    local f="$TMP/js.map.xml"
    rw js --top-k=500 --legend=full >"$f"; printf '%s' "$?" >"$f.rc"
    ran_ok "(js) the default map" "$f" || return
    map_c "$f" respondWith lib/reply.js send || return
    if [ "$MAPC" = "name" ]; then ok "(H) map: respondWith's <c n=\"send\"> is marked via=\"name\""
    else no "(H) map: respondWith's <c n=\"send\"> is [${MAPC:-absent}], want via=\"name\""; fi
    map_c "$f" direct lib/reply.js send || return
    if [ "$MAPC" = "-" ]; then ok "(H) map: near miss — direct's <c n=\"send\"> (new Reply().send) stays plain"
    else no "(H) map: direct's <c n=\"send\"> is [${MAPC:-absent}], want plain (a constructed receiver proves it)"; fi
    map_c "$f" respond lib/application.js onerror || return
    case "$MAPC" in *-*) no "(H) map: respond's <c n=\"onerror\"> is PROVEN (the false witness ctx.onerror())";;
                   *) ok "(H) map: respond's <c n=\"onerror\"> is absent or marked";; esac
    legend_arm "map" "$f"
    # near miss for the legend: a map whose rows carry no name-only <c> pays nothing for it — a bare call to a function
    # its own file defines is proven by scope, so its <c> is plain and the comment must not ride
    local g="$TMP/plainmap" gf="$TMP/plainmap.xml"
    mkdir -p "$g" && printf 'function a() { return b(); }\nfunction b() { return 1; }\nmodule.exports = { a };\n' >"$g/m.js"
    ( cd "$g" && "$BIN" . --no-cache --top-k=500 --legend=full >"$gf" 2>/dev/null ); printf '%s' "$?" >"$gf.rc"
    ran_ok "(H) the plain-call map" "$gf" || return
    map_c "$gf" a m.js b || return
    if [ "$MAPC" != "-" ]; then no "(H) map near miss: a's <c n=\"b\"> is [${MAPC:-absent}], want a plain row (the premise of this arm)"; return; fi
    P legend "$gf" || return
    if [ "$PARSED" = "UNDEFINED" ]; then ok "(H) map near miss: a scope-proven <c n=\"b\"> stays plain and the via legend does not ride"
    else no "(H) map near miss: the via legend rides a map whose rows carry no via=\"name\""; fi
}
map_arms

# (H) the map's MERGED hedged rows (fix round 1): N byte-identical via="name" rows of one symbol print ONCE with x="N"; the
# full legend and the compact legend define x=; --callees on the caller lists every candidate (the cut is recoverable).
# Near misses: a lone hedged candidate carries no x=, a PROVEN row is never merged into a hedged one, and two different
# names stay two rows.
merge_arms(){
    local g="$TMP/mergemap"
    mkdir -p "$g"
    { printf 'class A { get() { return 1; } put() { return 1; } }\nclass B { get() { return 2; } }\nclass C { get() { return 3; } }\n'
      printf 'function use(o) { return o.get() + o.put(); }\nfunction proven() { return new A().get(); }\nmodule.exports = { A, B, C, use, proven };\n'; } >"$g/u.js"
    local full="$TMP/mergemap.full.xml" comp="$TMP/mergemap.compact.xml" cal="$TMP/mergemap.callees.xml"
    ( cd "$g" && "$BIN" . --no-cache --top-k=500 --legend=full >"$full" 2>/dev/null ); printf '%s' "$?" >"$full.rc"
    ( cd "$g" && "$BIN" . --no-cache --top-k=500 --legend=compact >"$comp" 2>/dev/null ); printf '%s' "$?" >"$comp.rc"
    ( cd "$g" && "$BIN" . --no-cache --callees=u.js:use >"$cal" 2>/dev/null ); printf '%s' "$?" >"$cal.rc"
    ran_ok "(H) merge: the full-legend map" "$full" || return
    ran_ok "(H) merge: the compact-legend map" "$comp" || return
    ran_ok "(H) merge: --callees=u.js:use" "$cal" || return
    local use proven
    use="$( sed 's/<s /\n<s /g' "$full" | grep -m1 '<s t="fn" n="use"' )"
    proven="$( sed 's/<s /\n<s /g' "$full" | grep -m1 '<s t="fn" n="proven"' )"
    if [ -z "$use" ] || [ -z "$proven" ]; then no "(H) merge: the map has no row for use/proven (the premise): $( head -c 400 "$full" )"; return; fi
    [ "$( printf '%s' "$use" | grep -o '<c n="get"[^>]*>' | wc -l | tr -d ' ' )" = 1 ] && printf '%s' "$use" | grep -qE '<c n="get"( prov="split")? via="name" x="3"/>' \
        && ok "(H) merge: use's three same-named hedged get candidates print ONE row <c n=\"get\" via=\"name\" x=\"3\"/>" \
        || no "(H) merge: use's get rows are not one x=\"3\" row: $use"
    printf '%s' "$use" | grep -q '<c n="put"[^>]* x="' \
        && no "(H) merge near miss: use's lone put candidate carries x=: $use" \
        || ok "(H) merge near miss: a lone hedged candidate (put) carries no x="
    printf '%s' "$proven" | grep -q 'x="' \
        && no "(H) merge near miss: proven's evidence-bound get row was merged: $proven" \
        || ok "(H) merge near miss: a proven row is never merged (proven's get carries no x=)"
    [ "$( grep -o '<s [^>]*n="get"' "$cal" | wc -l | tr -d ' ' )" = 3 ] \
        && ok "(H) merge: --callees=u.js:use lists all three get candidates (the merged row is recoverable)" \
        || no "(H) merge: --callees=u.js:use does not list three get candidates: $( head -c 600 "$cal" )"
    grep -q 'x=N' "$full" && P legend "$full" && [ "$PARSED" = "DEFINED" ] \
        && ok "(H) merge: the full map legend defines via=\"name\" and x=" \
        || no "(H) merge: the full map legend does not define via=\"name\" (name alone + does NOT mean) and x="
    grep -q '<c x=N>' "$comp" && grep -qE '<c n="get"( prov="split")? via="name" x="3"/>' "$comp" \
        && ok "(H) merge: the compact map defines <c x=N> and keeps the merged row" \
        || no "(H) merge: the compact map does not define <c x=N> beside the merged row"
}
merge_arms

echo "--- (H) MCP twins (fresh TMPDIR: the MCP cache lives there)"
mkdir -p "$TMP/mcp"
# mcp ROOT TOOL SELECTOR OUT — one tools/call (then tools/list); the raw stream into OUT, the exit status into OUT.rc
mcp(){
    printf '%s\n' '{"jsonrpc":"2.0","id":1,"method":"initialize"}' \
        "$( printf '{"jsonrpc":"2.0","id":2,"method":"tools/call","params":{"name":"%s","arguments":{"path":"%s","symbol":"%s"}}}' "$2" "$CORPUS/$1" "$3" )" \
        | TMPDIR="$TMP/mcp" "$BIN" --mcp >"$4" 2>/dev/null
    printf '%s' "$?" >"$4.rc"
}
# mcp_hedge ROOT TOOL SEL FIELD NAME FILE WANT — WANT = name (marked) | notproven (absent or marked)
mcp_hedge(){
    local r="$1" tool="$2" sel="$3" field="$4" n="$5" file="$6" want="$7" out h
    out="$TMP/mcp.$r.$tool.$( printf '%s' "$sel" | tr '/:.' '___' )"
    mcp "$r" "$tool" "$sel" "$out"
    ran_ok "(H) MCP $tool $sel" "$out" || return
    P mcp "$out" "$field" || return
    if [ "$PARSED" = "NOROOT" ]; then no "(H) MCP $tool $sel: no JSON answer with $field"; return; fi
    h="$( printf '%s\n' "$PARSED" | awk -v n="$n" -v f="$file" '$1 == n && $2 == f { print $4 }' | sort -u | tr '\n' ' ' | sed 's/ $//' )"
    if [ "$want" = "name" ]; then
        if [ "$h" = "name" ]; then ok "(H) MCP $tool $sel: $field entry $n@$file is marked via=name"
        else no "(H) MCP $tool $sel: $field entry $n@$file is [${h:-absent}], want via=name"; fi
    else
        case " $h " in *" - "*) no "(H) MCP $tool $sel: $field entry $n@$file is PROVEN (no via=name)";;
                       *) ok "(H) MCP $tool $sel: $field entry $n@$file is absent or marked";; esac
    fi
}
mcp_hedge js find_symbol lib/reply.js:respondWith calls send lib/reply.js name
mcp_hedge js find_referencing_symbols lib/reply.js:send calledBy respondWith lib/reply.js name
mcp_hedge js find_symbol lib/application.js:respond calls onerror lib/application.js notproven
mcp_hedge js find_referencing_symbols lib/application.js:onerror calledBy respond lib/application.js notproven
mcp_hedge py find_symbol src/tui/callback.py:schedule calls call_later src/tui/message_pump.py name
# mcp_legend TOOL SEL — tools/call then tools/list: the tool's description or its answer defines "via":"name"
mcp_legend(){
    local tool="$1" sel="$2" out="$TMP/mcplegend.$1"
    printf '%s\n' '{"jsonrpc":"2.0","id":1,"method":"initialize"}' \
        "$( printf '{"jsonrpc":"2.0","id":2,"method":"tools/call","params":{"name":"%s","arguments":{"path":"%s","symbol":"%s"}}}' "$tool" "$CORPUS/js" "$sel" )" \
        '{"jsonrpc":"2.0","id":3,"method":"tools/list"}' \
        | TMPDIR="$TMP/mcp" "$BIN" --mcp >"$out" 2>/dev/null
    printf '%s' "$?" >"$out.rc"
    ran_ok "(H) MCP legend $tool" "$out" || return
    P mcplegend "$out" "$tool" || return
    if [ "$PARSED" = "DEFINED" ]; then ok "(H) MCP $tool: the tool description or answer defines \"via\":\"name\" with a NOT sentence"
    elif [ "$PARSED" = "NOROOT" ]; then no "(H) MCP $tool: no tools/list or tools/call answer to read"
    else no "(H) MCP $tool: neither the tool description nor the answer defines \"via\":\"name\" (\"name alone\" + \"does NOT mean\")"; fi
}
mcp_legend find_symbol lib/reply.js:respondWith
mcp_legend find_referencing_symbols lib/reply.js:send
# the MAP's MCP twin (analyze): the same <c> rows, the same bit, the same legend
mcp_map(){
    local out="$TMP/mcp.js.analyze" c d
    printf '%s\n' '{"jsonrpc":"2.0","id":1,"method":"initialize"}' \
        "$( printf '{"jsonrpc":"2.0","id":2,"method":"tools/call","params":{"name":"analyze","arguments":{"path":"%s"}}}' "$CORPUS/js" )" \
        | TMPDIR="$TMP/mcp" "$BIN" --mcp >"$out" 2>/dev/null
    printf '%s' "$?" >"$out.rc"
    ran_ok "(H) MCP analyze" "$out" || return
    P mcpmap "$out" || return
    if [ "$PARSED" = "NOROOT" ]; then no "(H) MCP analyze: no map in the answer"; return; fi
    c="$( printf '%s\n' "$PARSED" | awk '$1 == "respondWith" && $2 == "lib/reply.js" && $3 == "send" { print $4 }' | sort -u )"
    d="$( printf '%s\n' "$PARSED" | awk '$1 == "direct" && $2 == "lib/reply.js" && $3 == "send" { print $4 }' | sort -u )"
    if [ "$c" = "name" ]; then ok "(H) MCP analyze: respondWith's <c n=\"send\"> is marked via=\"name\" (the CLI map's bit)"
    else no "(H) MCP analyze: respondWith's <c n=\"send\"> is [${c:-absent}], want via=\"name\""; fi
    if [ "$d" = "-" ]; then ok "(H) MCP analyze: near miss — direct's <c n=\"send\"> stays plain"
    else no "(H) MCP analyze: direct's <c n=\"send\"> is [${d:-absent}], want plain"; fi
    P mcplegend "$out" analyze || return
    if [ "$PARSED" = "DEFINED" ]; then ok "(H) MCP analyze: the answer defines via=\"name\" with a NOT sentence"
    else no "(H) MCP analyze: the answer does not define via=\"name\" (\"name alone\" + \"does NOT mean\")"; fi
}
mcp_map

echo "--- (H) parity: the hedge bit is value-equal across CLI and MCP, and across --callees and --expand"
# cli_set ROOT VERB SEL — "name@file#H" lines of the CLI answer; mcp_set ROOT TOOL SEL FIELD — the same from MCP
# (a run or reader failure prints RUNFAIL, which parity FAILs)
cli_set(){ local f rc rows; f="$( answer "$1" "$2" "$3" )"; rc="$( cat "$f.rc" 2>/dev/null )"
           if [ "$rc" != "0" ]; then echo "RUNFAIL --$2=$3 rc=${rc:-unknown}"; return; fi
           rows="$( python3 "$TMP/parse.py" rows "$f" 2>/dev/null )" || { echo "RUNFAIL reader on --$2=$3"; return; }
           printf '%s\n' "$rows" | awk 'NF >= 5 { print $2 "@" $3 "#" $5 } $0 == "NOROOT" { print }' | sort -u; }
mcp_set(){ local out rc rows; out="$TMP/mcpset.$1.$2.$( printf '%s' "$3" | tr '/:.' '___' )"; mcp "$1" "$2" "$3" "$out"
           rc="$( cat "$out.rc" 2>/dev/null )"
           if [ "$rc" != "0" ]; then echo "RUNFAIL MCP $2 $3 rc=${rc:-unknown}"; return; fi
           rows="$( python3 "$TMP/parse.py" mcp "$out" "$4" 2>/dev/null )" || { echo "RUNFAIL reader on MCP $2 $3"; return; }
           printf '%s\n' "$rows" | awk 'NF >= 4 { print $1 "@" $2 "#" $4 } $0 == "NOROOT" { print }' | sort -u; }
parity(){
    local label="$1" a="$2" b="$3"
    case "$a$b" in *RUNFAIL*) no "(H) parity $label: a run or reader failed ([$a] [$b])"; return;; esac
    if [ -z "$a" ] || [ "$a" = "NOROOT" ] || [ "$b" = "NOROOT" ]; then no "(H) parity $label: an empty or rootless side ([$a] vs [$b])"; return; fi
    if [ "$a" = "$b" ]; then ok "(H) parity $label: $( printf '%s' "$a" | tr '\n' ' ' )"
    else no "(H) parity $label: CLI [$( printf '%s' "$a" | tr '\n' ' ' )] vs [$( printf '%s' "$b" | tr '\n' ' ' )]"; fi
}
for sel in lib/application.js:respond lib/reply.js:respondWith lib/reply.js:notFound lib/request.js:compile lib/uses.js:build lib/application.js:handle lib/delegate/response.js:back; do
    parity "callees/find_symbol.calls $sel" "$( cli_set js callees "$sel" )" "$( mcp_set js find_symbol "$sel" calls )"
done
for sel in lib/reply.js:send lib/application.js:onerror lib/schemas.js:listSchemas; do
    parity "callers/find_referencing_symbols.calledBy $sel" "$( cli_set js callers "$sel" )" "$( mcp_set js find_referencing_symbols "$sel" calledBy )"
done
# --callees vs --expand <calls>: compared by name + hedge (a <c> row names no file)
for sel in lib/reply.js:respondWith lib/reply.js:notFound lib/request.js:compile lib/delegate/response.js:back; do
    fc="$( answer js callees "$sel" )"; fe="$( answer js expand "$sel" --top-k=0 --legend=full )"
    if ran_ok "(H) --callees=$sel" "$fc" && ran_ok "(H) --expand=$sel" "$fe"; then
        if ra="$( python3 "$TMP/parse.py" rows "$fc" 2>/dev/null )" && rb="$( python3 "$TMP/parse.py" ecalls "$fe" 2>/dev/null )"; then
            a="$( printf '%s\n' "$ra" | awk 'NF >= 5 { print $2 "#" $5 }' | sort -u )"
            b="$( printf '%s\n' "$rb" | awk 'NF >= 3 { print $1 "#" $3 }' | sort -u )"
            parity "callees/expand-calls $sel" "$a" "$b"
        else no "(H) parity callees/expand-calls $sel: the reader failed"; fi
    fi
done

echo "=== (R) the base-class receiver is a KEYWORD, never a local spelled like one (CR 5469474915, receiverevidence.h:124) ==="
# superroot/<lang>: Panel extends Base; Base and Widget both define render. A local `base` (C#/Go: `super`) holding a
# Widget, or an untyped value, never proves Base's render through the bases-only lookup: the typed local resolves to its
# own class, the untyped one is hedged. The keyword twins (`super.render()`, Python `super().render()`, Go's promoted
# p.Render()) still prove Base's render. C# `base.Render()` is pinned as visible only: no C# tree reaches the base-class
# receiver today (the grammar's `base` node is not read as a receiver root — a disclosed floor, never a false row).
SR=superroot
notproven $SR/py callees pkg/panel.py:untyped "render pkg/shapes.py:2"
notproven $SR/py callees pkg/panel.py:shadowed "render pkg/shapes.py:2"
visible   $SR/py callees pkg/panel.py:untyped "render pkg/shapes.py:2" "render pkg/shapes.py:7"
exactproven $SR/py callees pkg/panel.py:typed "cls Widget pkg/shapes.py;fn render pkg/shapes.py"   # guard: Rule 2 types it first
proven    $SR/py callees pkg/panel.py:typed "fn render pkg/shapes.py:7"   # guard
proven    $SR/py callees pkg/panel.py:real_super "fn render pkg/shapes.py:2"   # guard: super() walks the bases
for l in js ts; do
    f="$( [ "$l" = js ] && echo lib/panel.js || echo src/panel.ts )"; d="$( [ "$l" = js ] && echo lib/shapes.js || echo src/shapes.ts )"
    notproven $SR/$l callees "$f:typed" "render $d:2"
    proven    $SR/$l callees "$f:typed" "method render $d:6"
    notproven $SR/$l callees "$f:untyped" "render $d:2"
    visible   $SR/$l callees "$f:untyped" "render $d:2" "render $d:6"
    proven    $SR/$l callees "$f:realSuper" "method render $d:2"   # guard: super.render()
done
notproven $SR/go callees src/panel.go:Typed "Render src/shapes.go:5"
proven    $SR/go callees src/panel.go:Typed "method Render src/shapes.go:9"
notproven $SR/go callees src/panel.go:Untyped "Render src/shapes.go:5"
notproven $SR/go callees src/panel.go:Super "Render src/shapes.go:5"
visible   $SR/go callees src/panel.go:Super "Render src/shapes.go:5" "Render src/shapes.go:9"
proven    $SR/go callees src/panel.go:Promoted "method Render src/shapes.go:5"   # guard: the embedded Base's promoted method
notproven $SR/java callees src/app/Panel.java:typed "render src/app/Base.java"
proven    $SR/java callees src/app/Panel.java:typed "method render src/app/Widget.java"
notproven $SR/java callees src/app/Panel.java:untyped "render src/app/Base.java"
proven    $SR/java callees src/app/Panel.java:realSuper "method render src/app/Base.java"   # guard
notproven $SR/kt callees src/app/Panel.kt:typed "render src/app/Shapes.kt:4"
proven    $SR/kt callees src/app/Panel.kt:typed "fn render src/app/Shapes.kt:8"
notproven $SR/kt callees src/app/Panel.kt:untyped "render src/app/Shapes.kt:4"
proven    $SR/kt callees src/app/Panel.kt:realSuper "fn render src/app/Shapes.kt:4"   # guard
notproven $SR/swift callees Sources/App/Panel.swift:typed "render Sources/App/Shapes.swift:2"
proven    $SR/swift callees Sources/App/Panel.swift:typed "fn render Sources/App/Shapes.swift:6"
notproven $SR/swift callees Sources/App/Panel.swift:untyped "render Sources/App/Shapes.swift:2"
proven    $SR/swift callees Sources/App/Panel.swift:realSuper "fn render Sources/App/Shapes.swift:2"   # guard
notproven $SR/cs callees App/Panel.cs:Typed "Render App/Shapes.cs:5"
proven    $SR/cs callees App/Panel.cs:Typed "method Render App/Shapes.cs:10"
notproven $SR/cs callees App/Panel.cs:Untyped "Render App/Shapes.cs:5"
visible   $SR/cs callees App/Panel.cs:RealBase "Render App/Shapes.cs:5"   # guard (floor above)
notproven $SR/cpp callees src/panel.cpp:untyped "render src/shapes.h:6"
proven    $SR/cpp callees src/panel.cpp:typed "method render src/shapes.h:11"   # guard: Rule 2 types it first
notproven $SR/rb callees lib/panel.rb:untyped "render lib/shapes.rb:2"
proven    $SR/rb callees lib/panel.rb:typed "method render lib/shapes.rb:8"   # guard

echo "=== (C) conservation: no call silently disappears ==="
ROOTS="js ts py go java kt cs cpp swift rb"
for r in $ROOTS; do
    if ! rw "$r" --pin-census="$TMP/$r.tsv" >"$TMP/$r.map.xml"; then no "(C) ($r) the census run exited non-zero"; continue; fi
    DL="$( grep -m1 '^# dispositions ' "$TMP/$r.tsv" 2>/dev/null )"
    if [ -z "$DL" ]; then no "(C) ($r) the census carries no '# dispositions' line"; continue; fi
    if python3 - "$DL" <<'PY'
import re, sys
kv = dict( ( k, int( v ) ) for k, v in re.findall( r"(\w+)=(\d+)", sys.argv[ 1 ] ) )
if "calls" not in kv or "unaccounted" not in kv or kv[ "calls" ] < 1:
    sys.exit( 1 )
total = kv.pop( "calls" )
sys.exit( 0 if kv[ "unaccounted" ] == 0 and sum( kv.values() ) == total else 1 )
PY
    then ok "(C) ($r) dispositions sum to calls= with unaccounted=0"
    else no "(C) ($r) conservation broken: $DL"; fi
done

echo "=== (K) the predicates can fail ==="
kread(){ P rows "$1" && GOT="$PARSED"; }
printf '<callees of="x" defs="1"><s t="method" n="onerror" p="lib/application.js:12"/></callees>' >"$TMP/k1.xml"; kread "$TMP/k1.xml"
if [ -n "$( specmatch "onerror lib/application.js" | awk '$5 != "name"' )" ]; then ok "(K) an unhedged planted row reads as PROVEN (notproven would fail it)"
else no "(K) the reader missed an unhedged planted row: [$GOT]"; fi
printf '<callees of="x" defs="1"><s t="method" n="onerror" p="lib/application.js:12" via="name"/></callees>' >"$TMP/k2.xml"; kread "$TMP/k2.xml"
if [ -n "$( specmatch "onerror lib/application.js" | awk '$5 == "name"' )" ] && [ -z "$( specmatch "onerror lib/application.js" | awk '$5 != "name"' )" ]; then
    ok "(K) a hedged planted row reads as marked (notproven passes it, proven fails it)"
else no "(K) the reader did not read via=\"name\": [$GOT]"; fi
printf '<callees of="x" defs="1"><s t="method" n="onerror" p="lib/application.js:12" via="import"/></callees>' >"$TMP/k3.xml"; kread "$TMP/k3.xml"
if [ -n "$( specmatch "onerror lib/application.js" | awk '$5 != "name"' )" ]; then ok "(K) via=\"import\" is not the hedge"
else no "(K) the reader took via=\"import\" for the hedge: [$GOT]"; fi
printf 'nothing here' >"$TMP/k4.xml"
if P rows "$TMP/k4.xml" && [ "$PARSED" = "NOROOT" ]; then ok "(K) an answer with no root element is NOROOT"
else no "(K) a rootless document read as an answer"; fi
printf '<callers of="x" found="0"/>' >"$TMP/k5.xml"
if P rows "$TMP/k5.xml" && [ "$PARSED" = "NOROOT" ]; then ok "(K) an answer about no symbol (no defs=) is NOROOT"
else no "(K) a not-found answer read as an empty answer"; fi
printf '<ctx><b n="other"><calls total="1"><c n="send" l="7">sig</c></calls></b></ctx>' >"$TMP/k6.xml"
if P ecalls "$TMP/k6.xml" respondWith && [ "$PARSED" = "NOROOT" ]; then ok "(K) a --for answer without the named body is NOROOT, never an empty pass"
else no "(K) ecalls read another body's <calls> as respondWith's"; fi
printf '<ctx><b n="respondWith"><calls total="1"><c n="send" l="7" via="name">sig</c></calls></b></ctx>' >"$TMP/k7.xml"
if P ecalls "$TMP/k7.xml" respondWith && [ "$PARSED" = "send 7 name" ]; then ok "(K) ecalls reads a marked <c> row"
else no "(K) ecalls missed a marked <c> row: [$PARSED]"; fi
printf '%s\n' '{"jsonrpc":"2.0","id":2,"result":{"content":[{"type":"text","text":"{\"calls\":[{\"name\":\"send\",\"file\":\"lib/reply.js\",\"line\":7,\"via\":\"name\"},{\"name\":\"code\",\"file\":\"lib/reply.js\",\"line\":12}]}"}]}}' >"$TMP/k8.json"
if P mcp "$TMP/k8.json" calls && [ "$( printf '%s' "$PARSED" | tr '\n' ';' )" = "send lib/reply.js 7 name;code lib/reply.js 12 -" ]; then ok "(K) the MCP reader reads the hedge bit per entry"
else no "(K) the MCP reader misread: [$( printf '%s' "$PARSED" | tr '\n' ';' )]"; fi
if P mcp "$TMP/k8.json" calledBy && [ "$PARSED" = "NOROOT" ]; then ok "(K) an MCP answer without the field is NOROOT"
else no "(K) the MCP reader invented a missing field"; fi
printf '1' >"$TMP/k9.rc"
if ( ran_ok k "$TMP/k9" ) >/dev/null; then no "(K) ran_ok accepted a run that exited 1"
else ok "(K) ran_ok fails a run that exited non-zero"; fi
rm -f "$TMP/k10.rc"
if ( ran_ok k "$TMP/k10" ) >/dev/null; then no "(K) ran_ok accepted a run with no recorded exit status"
else ok "(K) ran_ok fails a run with no recorded exit status"; fi
if ( parity k "a#-" "a#name" ) | grep -q FAIL; then ok "(K) parity fails when the hedge bit differs"
else no "(K) parity accepted differing hedge bits"; fi
if ( parity k "" "" ) | grep -q FAIL; then ok "(K) parity fails on two empty sides (never a vacuous pass)"
else no "(K) parity accepted two empty sides"; fi
if ( parity k "RUNFAIL --callees=x rc=1" "RUNFAIL --callees=x rc=1" ) | grep -q FAIL; then ok "(K) parity fails when a run exited non-zero"
else no "(K) parity accepted a failed run"; fi
# change 1: a reader crash or malformed defs= FAILs the arm; it never reads as "no rows" (the old fall-through)
printf '<callees of="x" defs="x"><s t="method" n="onerror" p="lib/application.js:12"/></callees>' >"$TMP/k11.xml"
if python3 "$TMP/parse.py" rows "$TMP/k11.xml" >/dev/null 2>&1; then no "(K) the reader accepted a non-numeric defs="
else ok "(K) the reader exits non-zero on a non-numeric defs="; fi
if ( rowsof k "$TMP/k11.xml" ) | grep -q FAIL; then ok "(K) a reader failure FAILs the arm (never an empty pass)"
else no "(K) a reader failure fell through to PASS"; fi
if ( fail=0; rowsof k "$TMP/k11.xml" >/dev/null; [ "$fail" -eq 1 ] ); then ok "(K) a reader failure sets the gate's failure flag"
else no "(K) a reader failure left the failure flag clear"; fi
printf '<ctx><hops><h n="encode"><calls total="1"><c n="append" l="3" via="name"/></calls></h><h n="respond"><calls total="1"><c n="onerror" l="12"/></calls></h></hops></ctx>' >"$TMP/k12.xml"
if P hcalls "$TMP/k12.xml" encode && [ "$PARSED" = "append 3 name" ] && P hcalls "$TMP/k12.xml" respond && [ "$PARSED" = "onerror 12 -" ]; then
    ok "(K) a hop reader reads only its own hop's <calls>"
else no "(K) the hop reader crossed hops: [$PARSED]"; fi
if P hcalls "$TMP/k12.xml" pipePayload && [ "$PARSED" = "NOROOT" ]; then ok "(K) a hop that is not shown is NOROOT, never an empty pass"
else no "(K) the hop reader invented a hop: [$PARSED]"; fi
printf '<ctx><calls total="1"><c n="get" l="4,8"/></calls></ctx>' >"$TMP/k13.xml"
if P ecalls "$TMP/k13.xml" && [ "$( printf '%s' "$PARSED" | tr '\n' ';' )" = "get 4 -;get 8 -" ]; then ok "(K) a joined <c l=\"4,8\"> row reads as one row per line"
else no "(K) a joined <c> row misread: [$PARSED]"; fi
printf '<impact of="x" defs="1"><!-- via="name": a row matched by name alone. It does NOT mean the edge is false. --></impact>' >"$TMP/k14.xml"
printf '<impact of="x" defs="1"><!-- via="import" by name alone; it does NOT mean much. via="name" is a hedge. --></impact>' >"$TMP/k15.xml"
if P legend "$TMP/k14.xml" && [ "$PARSED" = "DEFINED" ] && P legend "$TMP/k15.xml" && [ "$PARSED" = "UNDEFINED" ]; then
    ok "(K) the legend reader needs the mechanism and the NOT sentence AFTER via=\"name\""
else no "(K) the legend reader misread a planted legend"; fi

if [ "$fail" -eq 0 ]; then echo "ALL PASS"; else echo "FAILURES ABOVE"; exit 1; fi
