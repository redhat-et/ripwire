#!/usr/bin/env bash
# falseedgecheck.sh — a call never binds by name alone to an in-repo definition the language says it cannot reach.
#
#   test/falseedgecheck.sh                          # uses build/ripwire on test/falseedgefix
#   RIPWIRE_BIN=asan/ripwire test/falseedgecheck.sh
#   test/falseedgecheck.sh build_base/ripwire       # the RED run (a pre-change binary)
#
# THE DEFECT. The name ladder in buildGraph binds a call to the lone in-repo definition of its spelling. Three call
# shapes have no in-repo target by the language's own rules, and still got one:
#   (1) a call with NO receiver bound to something such a call cannot reach: a Go/Python/JS method (none of the three
#       has an implicit `this`), a JS accessor (`new URL( u )` → a `get URL ()` getter), a C struct or enum (C has no
#       constructor call). Go `append( xs, x )` became a caller of `func ( h *History ) append`, and a C call of the
#       function opts_parse() was drawn to `struct opts_parse` instead of the function.
#   (2) a call to a language builtin or a global object: Go `append max copy delete len close`, JS/TS `JSON.*`,
#       `Buffer.*`, `Math.*`, `Object.*`, `Array.*`, `Promise.*`, `console.*`, `crypto.*`, the global `fetch`, bound
#       to a same-named in-repo function, method or object property that the calling file never imports.
#   (3) a call through a binding to a package OUTSIDE the tree: a CommonJS `require( 'pkg' )` (default, destructured,
#       or used as a receiver), an ES namespace import of a bare specifier, a Go import of a path outside the module.
# Each was a confident false row in a graded answer; this fixture holds a paraphrased minimal repro of each.
#
# THE CONTRACT. Such a call loses its in-repo edge and is counted EXTERNAL — one `C external` census row with no
# target, and in the external= gauge of the map header (arm G checks both, and that they agree with the census
# `# dispositions external=`) — never declined and never silently dropped. When the language makes exactly one in-repo
# FUNCTION reachable, that one is the edge (Python's imported or star-imported `match`, C's function opts_parse). A name
# the calling scope defines, imports from inside the tree, or shadows keeps its edge: the near-miss arms are true edges
# the pre-change binary keeps and a new rule could kill, pinned with `exactly`.
#
# ARMS (one fixture root per language under test/falseedgefix/; each root is indexed on its own).
#   (A) Go:  builtin append/max/copy/delete/len/close never reach a method, a function-local var or another
#            package's function; qualified calls into an outside package (plain and aliased import) and the standard
#            library never reach a same-named in-repo function. Near misses keep: same-package `min` (shadows the
#            builtin) and `score`/`hook`, also from ANOTHER file of the package; same-package `copy`; `h.append()`; a
#            package-level func VARIABLE called bare; in-module `own.Pick()`; a dot-import's bare `Pick()`; a NESTED
#            module's `lib.Helper()` (sub/go.mod); a module a LOCAL go.mod `replace` maps into the tree
#            (`lib.Shape()` via example.com/vendored); a function passed as a value. Root gonomod/ has NO go.mod: its
#            full-path import of an in-tree package keeps its edge (an unknown module path proves nothing outside).
#            Root gomodcomment/: a `module x // c` line and a nested `module "y" // c` are x and y (near miss: cmx is
#            not under cm); root goreplace/: a module only a local `replace` names (its directory has no go.mod), also
#            spelled quoted (goreplace/quoted/: `"x" => "./x"`, a raw-string path; near miss: a quoted module replaced by
#            another quoted MODULE stays outside).
#   (B) JS:  JSON.stringify, `const { stringify } = JSON`, `new URL()`, Buffer.from, `globalThis.fetch`, console/Math/
#            Object/Array/Promise members, require('destroy'), require('supertest'), a receiver from require('qs')
#            and a name destructured from require('cookie') never reach an in-repo function, getter, method or object
#            property. Near misses keep: a destructured relative require, a relative-module receiver, relative ES
#            namespace and default imports (esm/), a file-local `const JSON` shadow, a same-file `function fetch`, a
#            const arrow function, `ContentType.from` on the in-repo class, `this.set`/`this.get`, and an object's METHOD
#            destructured from a relative require (`const { tidy } = require( './methods' ); tidy( s )`), and a
#            declaration named like the global object (`var self = this`, `const window`, a parameter `global`); the
#            undeclared `self.process()` beside them is external (also in TS: src/selfalias.ts).
#   (C) TS:  the global fetch never reaches a class FIELD named fetch, JSON.parse never reaches an exported `parse`,
#            crypto.subtle.verify never reaches an exported `verify`, `import * as qs from 'qs'` never reaches an
#            in-repo `stringify`; a file that imports nothing does not reach another file's exported `fetch` (root
#            tsimport/). Near misses keep: named and relative namespace imports of in-repo `parse`/`stringify`/
#            `verify`/`fetch`, `new App()` + `app.dispatch()`, an ambient `declare function track` (globals.d.ts)
#            called from a file that imports nothing; ESM default/named imports of outside packages stay unbound (pin).
#   (D) Python (src/ layout): an imported or STAR-imported module function `match` is the edge — not the two
#            same-named methods; a bare `process()` that only a METHOD defines has no edge, and neither has a method's
#            bare `helper()` beside its own class's and a sibling class's `helper` (siblings.py — the shape the S6-C
#            locality fixtures used before FE-A; they moved to Kotlin, where a bare call IS a `this` call). Near misses keep: imported
#            in-repo `append` and `format`, a same-module helper, a module-level callable VARIABLE, a bare class
#            construction `Worker()`, a class-body call, a bound-method alias (`write = self.write; write( b )`
#            reaches its own class's `write`, never another class's), and the same alias or a parameter of an ENCLOSING
#            function captured by a nested def (closure.py: the call keeps its previous resolution). Pins: bare builtins `open`/`format` reach neither the method
#            nor the unimported module function.
#   (E) C:   `opts_parse( … )` and `region( … )` reach the FUNCTION, not the same-named struct; `find_type( … )` never
#            reaches `enum find_type` and, with no function anywhere and no library table naming it, is unresolved= (no
#            census row), while `clock()` beside `struct clock` is external= (the C library table proves it); window_count() and the function-like macro CLAMP keep their edges. C++ (root
#            cpp/): `Point( v )` is a constructor call and keeps both rows it had (the struct rule is C's alone).
#   (R) Rust (no implicit receiver either): a bare call imported from an outside crate never reaches a same-named
#            METHOD; a same-module function, `h.render()`, `History::new()`, `History::render( &h )` and
#            `Self::width()` and the fully qualified `<History as Render>::render_all( h )` keep their edges.
#   (S) JS/TS REBIND (FC3, T1 class 14 alias-through-assignment; root jsrebind/): a binding WRITTEN after its
#            declaration — `let { Eng, Foo } = require( … ); Eng = Foo; new Eng()` builds a Foo — binds nothing: the
#            call is unresolved=, never its declared target nor a same-spelled class. Shapes: destructured and plain
#            require, a conditional write, `[Eng] = [Foo]`, `({ Eng } = o)`, `(Eng) = Foo`, `+=`, `++`, `for ( Eng of xs )`,
#            a second `var Eng = Foo`, a write inside a nested function (the whole declaring scope: h() too), a write
#            AFTER the call in a loop or after a closure that calls it (byte order is not run order), a redefined
#            `function Eng`, an undeclared global, a written bare function `leaf`. Near misses keep: no write; a
#            write to ANOTHER binding of the name (a parameter, a function's own `let`, another file's); `o.Eng =`;
#            `{ Eng }` as a value; `var Eng;` without an initializer; `const` and ES import bindings (a write throws);
#            a named class expression's own name; TS rows the base already left unresolved stay so; a write whose value
#            KEEPS the name (`Eng = require( … ).Eng` in both branches of an if, `({ Eng } = mod)`) over a declaration
#            WITHOUT an initializer (`var Eng;` / `let Eng;`) — the declare-then-assign test idiom (over `let { Eng } =
#            require( 'a' )` or `class Eng` the write replaces a pinned definition: withheld) — while a default (`({ Eng = mod.Foo } = mod)`) does not keep it; `reply.run()` beside
#            a written local `run` (a member call is not the bare name); a MEMBER call through a written ROOT name
#            (`Eng = Foo; Eng.run()`, `m = require( b ); m.Eng()`, `let tank = new Tank(); tank = b; tank.drip()`) keeps only the
#            by-name hedge (via="name", every candidate) — never a pinned row, never the class its SPELLING names, with or
#            without a declaration (FIX2 C1/C2); patterns nested 20000 deep.
#            FLOOR (FC3 delta2 C3, card FC6, pre-existing at 320f8d8f): a member `.limit()` site rides UNHEDGED in a caller row merged
#            with a bare imported `limit(...)` call (kysely clear.test.ts / insert.test.ts `.$call( limit( 1, dialect ) )`).
#   (J) Kotlin (#155): a call with a TRAILING lambda to let/run/with/apply/also is the stdlib scope function: its Java
#            candidates are dropped, and an emptied set is external= (kt/: `s.run { }`, `with( sb ) { }`, `s?.let { }`,
#            `xs.also { }`, `apply { }`). The same Java names with no lambda (`block.run()`), and Kotlin's own definition of
#            `run` (ktown/: `go` binds Task.run; build's `s.run { length }` is pinned there, the receiver gap), keep their edges.
#   (F) propagation: --callers and --impact of the in-repo decoys no longer list the false callers.
#   (G) disclosure: every call the arms above unbind is a `C external` census row (empty targets) — except a Python bare
#            name nothing binds and no builtin table holds (run_all's `process`, siblings.py's `helper`), which has no
#            in-repo target and no proof of an outside one: it is unresolved=, no census row at all, and the py and c
#            roots pin their census unresolved= to exactly the sites named (an omitted call cannot pass); each root's map
#            header external= equals its census `# dispositions external=` and is at least the number of expected
#            external rows; every root's dispositions still sum to calls= with unaccounted=0.
#   (H) MCP twins (fresh TMPDIR cache): find_referencing_symbols / find_symbol name exactly the rows the CLI's
#            --callers / --callees answer names for the same selector (name@file), and that set is the expected one.
#   (K) the predicates can fail: a document carrying the false row is caught; an empty or not-found document is not
#            a pass; the census predicate rejects a bound row. Every binary run (CLI and MCP) must exit 0.
#
# FLOORS — named, not gated here:
#   * implicit-receiver languages (Java, C#, C++, Kotlin, Swift, Ruby, ObjC): a bare call legitimately reaches the
#     enclosing class's methods, so rule (1) cannot apply; a bare call into an UNRELATED class still binds (Java
#     probed). The precise rule needs the caller's class cone — a later lane.
#   * no-implicit-receiver languages without an arm here: PHP, Lua, Zig.
#   * dynamic receivers (`promise.then`, `map.set`, `dict.get`, a parameter called as a function) — a later lane.
#   * Python `max = mymax; max( a, b )`: no edge before or after (the builtin veto wins over the rebinding).
#   * JS `const f = make(); f()` and a Go method value `f := h.append; f()`: no edge before or after.
#   * JS/TS `let { Eng } = require( 'a' ); Eng = require( 'a' ).Eng; new Eng()`: the SAME module's member written over a
#     declaration that already pinned it is withheld too (the spelling is not the proof) — honest over-withholding.
#   * rows() compares (kind, name, file) without the line: two same-named definitions in one file read as one row.
#
# Exits non-zero on any failure.

set -u
export PYTHONDONTWRITEBYTECODE=1
ROOT="$( cd "$( dirname "$0" )/.." && pwd )"
. "$ROOT/test/lib/clean-env.sh"   # a gate that indexes a repo must not inherit GIT_DIR/GIT_WORK_TREE (gitenvhermeticcheck D)
BIN="${1:-${RIPWIRE_BIN:-$ROOT/build/ripwire}}"
[ "${BIN#/}" = "$BIN" ] && BIN="$ROOT/$BIN"          # allow a repo-relative binary
CORPUS="$ROOT/test/falseedgefix"
TMP="$( mktemp -d )"; trap 'rm -rf "$TMP"' EXIT
fail=0
ok(){ printf '  PASS  %s\n' "$*" || { fail=1; printf '  FAIL  could not write the PASS line for: %s\n' "$*"; }; return 0; }
no(){ printf '  FAIL  %s\n' "$*"; fail=1; }

[ -x "$BIN" ] || { echo "no ripwire binary at $BIN — build first (cmake --build build -j)"; exit 2; }
[ -d "$CORPUS" ] || { echo "fixture missing: $CORPUS"; exit 2; }
command -v python3 >/dev/null 2>&1 || { echo "python3 required"; exit 2; }
echo "falseedgecheck: BIN=$BIN  CORPUS=$CORPUS"

# rw ROOT ARGS… — run against one fixture root (every selector below is relative to that root's `.`)
rw(){ local r="$1"; shift; ( cd "$CORPUS/$r" && "$BIN" . --no-cache "$@" 2>/dev/null ); }

# rows DOC — the answer's <s> rows as sorted "t n file" lines (p= without its line number), or the single line
# NOROOT when the document carries no callees/callers/impact root element, or one whose defs= is absent or 0 (the
# selector matched nothing) — so an empty answer, or one about no symbol, is never a pass
rows(){ python3 - "$1" <<'PY'
import re, sys
doc = open( sys.argv[ 1 ], encoding="utf-8", errors="replace" ).read()
root = re.search( r"<(callees|callers|impact) [^>]*>", doc )
defs = re.search( r' defs="([0-9]+)"', root.group( 0 ) ) if root else None
if not defs or int( defs.group( 1 ) ) < 1:
    print( "NOROOT" ); sys.exit( 0 )
out = set()
for s in re.findall( r"<s [^>]*/>", doc ):
    t = re.search( r' t="([^"]*)"', s ); n = re.search( r' n="([^"]*)"', s ); p = re.search( r' p="([^"]*)"', s )
    if t and n and p:
        out.add( "%s %s %s" % ( t.group( 1 ), n.group( 1 ), p.group( 1 ).rsplit( ":", 1 )[ 0 ] ) )
for line in sorted( out ):
    print( line )
PY
}
# answer ROOT VERB SEL — write the verb's answer to a per-call file, its exit status beside it (FILE.rc), echo the path
answer(){
    local f; f="$TMP/$1.$2.$( printf '%s' "$3" | tr '/:.' '___' ).xml"
    rw "$1" "--$2=$3" >"$f"; printf '%s' "$?" >"$f.rc"
    printf '%s' "$f"
}
# ran_ok ROOT VERB SEL FILE — the run behind FILE exited 0 (a non-zero exit FAILs the arm, whatever it printed)
ran_ok(){
    local rc; rc="$( cat "$4.rc" 2>/dev/null )"
    if [ "$rc" = "0" ]; then return 0; fi
    no "($1) --$2=$3 exited rc=${rc:-unknown}"; return 1
}
# lacks ROOT VERB SEL "N FILE" … — no row names N at FILE (any kind), spelled bare OR owner-qualified (Owner::N, Owner.N,
# Owner#N — the member-owner vocabulary), so a wrong edge to a method cannot hide behind its qualified spelling;
# the root element must be present
lacks(){
    local r="$1" v="$2" s="$3"; shift 3
    local f got; f="$( answer "$r" "$v" "$s" )"; ran_ok "$r" "$v" "$s" "$f" || return; got="$( rows "$f" )"
    if [ "$got" = "NOROOT" ]; then no "($r) --$v=$s produced no <$v> answer about a symbol"; return; fi
    local nf
    for nf in "$@"; do
        if printf '%s\n' "$got" | grep -qE "^[^ ]+ ([^ ]*(::|\.|#))?${nf% *} ${nf#* }\$"; then
            no "($r) --$v=$s still lists ${nf% *} at ${nf#* } — a false edge: $( printf '%s' "$got" | tr '\n' ';' )"
        else
            ok "($r) --$v=$s does not list ${nf% *} at ${nf#* }"
        fi
    done
}
# has ROOT VERB SEL "t n file" … — each named row is present (the near-miss form where other rows are not pinned)
has(){
    local r="$1" v="$2" s="$3"; shift 3
    local f got; f="$( answer "$r" "$v" "$s" )"; ran_ok "$r" "$v" "$s" "$f" || return; got="$( rows "$f" )"
    if [ "$got" = "NOROOT" ]; then no "($r) --$v=$s produced no <$v> answer about a symbol"; return; fi
    local row
    for row in "$@"; do
        if printf '%s\n' "$got" | grep -qxF "$row"; then ok "($r) --$v=$s keeps the pinned row [$row]"
        else no "($r) --$v=$s lost the pinned row [$row]: $( printf '%s' "$got" | tr '\n' ';' )"; fi
    done
}
# hedged ROOT VERB SEL "n file" — the row for symbol n at file is present and carries via="name" (the name ladder's HEDGED
# reading, never a pinned binding); absent, or a pinned row (no via=), fails
hedged(){
    local r="$1" v="$2" s="$3" want="$4"
    local f; f="$( answer "$r" "$v" "$s" )"; ran_ok "$r" "$v" "$s" "$f" || return
    if python3 - "$f" "${want% *}" "${want#* }" <<'PY'
import re, sys
doc, name, path = sys.argv[ 1: ]
for s in re.findall( r"<s [^>]*/>", open( doc, encoding="utf-8", errors="replace" ).read() ):
    n = re.search( r' n="([^"]*)"', s ); p = re.search( r' p="([^"]*)"', s )
    if n and p and n.group( 1 ) == name and p.group( 1 ).rsplit( ":", 1 )[ 0 ] == path and ' via="name"' in s: sys.exit( 0 )
sys.exit( 1 )
PY
    then ok "($r) --$v=$s lists [$want] as a hedged via=name row"
    else no "($r) --$v=$s has no hedged via=name row [$want]"; fi
}
# unpinned ROOT VERB SEL "n file" … — each named row is absent or carries via="name": never a confident (pinned) row
unpinned(){
    local r="$1" v="$2" s="$3"; shift 3
    local f; f="$( answer "$r" "$v" "$s" )"; ran_ok "$r" "$v" "$s" "$f" || return
    local want
    for want in "$@"; do
        if python3 - "$f" "${want% *}" "${want#* }" <<'PY'
import re, sys
doc, name, path = sys.argv[ 1: ]
for s in re.findall( r"<s [^>]*/>", open( doc, encoding="utf-8", errors="replace" ).read() ):
    n = re.search( r' n="([^"]*)"', s ); p = re.search( r' p="([^"]*)"', s )
    if n and p and n.group( 1 ) == name and p.group( 1 ).rsplit( ":", 1 )[ 0 ] == path and ' via="name"' not in s: sys.exit( 1 )
sys.exit( 0 )
PY
        then ok "($r) --$v=$s has no confident row [$want]"
        else no "($r) --$v=$s lists [$want] as a confident (pinned) row"; fi
    done
}
# exactly ROOT VERB SEL "t n file;t n file" — the exact row set (";"-separated, sorted); "" = no rows at all
exactly(){
    local r="$1" v="$2" s="$3" want="$4"
    local f got; f="$( answer "$r" "$v" "$s" )"; ran_ok "$r" "$v" "$s" "$f" || return; got="$( rows "$f" )"
    if [ "$got" = "NOROOT" ]; then no "($r) --$v=$s produced no <$v> answer about a symbol"; return; fi
    got="$( printf '%s' "$got" | tr '\n' ';' | sed 's/;$//' )"
    if [ "$got" = "$want" ]; then ok "($r) --$v=$s rows are exactly [${want:-none}]"
    else no "($r) --$v=$s rows are [${got:-none}], want [${want:-none}]"; fi
}
# reaches_fn ROOT SEL NAME FILE_ERE — the callees name the FUNCTION NAME (at a file matching FILE_ERE) and no
# struct/class/enum/typedef of that name
reaches_fn(){
    local r="$1" s="$2" n="$3" fre="$4"
    local f got; f="$( answer "$r" callees "$s" )"; ran_ok "$r" callees "$s" "$f" || return; got="$( rows "$f" )"
    if [ "$got" = "NOROOT" ]; then no "($r) --callees=$s produced no <callees> answer about a symbol"; return; fi
    if printf '%s\n' "$got" | grep -qE "^fn $n ($fre)\$"; then ok "($r) $s → the FUNCTION $n"
    else no "($r) $s does not reach the function $n: $( printf '%s' "$got" | tr '\n' ';' )"; fi
    if printf '%s\n' "$got" | grep -qE "^(cls|struct|enum|union|type|typedef) $n "; then
        no "($r) $s still lists the type $n: $( printf '%s' "$got" | tr '\n' ';' )"
    else
        ok "($r) $s does not list a struct/enum/typedef $n"
    fi
}

# ── census: one per root, written FIRST so no arm reads a missing file ─────────────────────────────────────────
ROOTS="go gonomod gomodcomment goreplace js ts tsimport py c cpp rs jsrebind kt ktown"
for r in $ROOTS; do
    if ! rw "$r" --pin-census="$TMP/$r.tsv" >"$TMP/$r.map.xml"; then no "($r) the census run exited non-zero"; fi
    if [ ! -s "$TMP/$r.tsv" ]; then no "($r) the census run wrote no census — every census arm for this root would be vacuous"; fi
done
# ext_row ROOT FILE CALLER CALLEE — the census holds a `C external` row for that caller and callee with no target
ext_row(){
    python3 - "$TMP/$1.tsv" "$2" "$3" "$4" <<'PY'
import sys
census, path, caller, callee = sys.argv[ 1: ]
for line in open( census, encoding="utf-8", errors="replace" ):
    f = line.rstrip( "\n" ).split( "\t" )
    if len( f ) < 9 or f[ 0 ] != "C" or f[ 1 ] != "external":
        continue
    cid = f[ 5 ]
    head, _, tail = cid.partition( "::" )
    if head == path and tail.rsplit( "#", 1 )[ 0 ].split( "::" )[ -1 ] == caller and f[ 6 ] == callee and f[ 7 ] == "":
        sys.exit( 0 )
sys.exit( 1 )
PY
}
externals(){
    local r="$1" file="$2" caller="$3"; shift 3
    local c
    for c in "$@"; do
        printf '%s\n' "$caller:$c" >>"$TMP/$r.nexp"
        if ext_row "$r" "$file" "$caller" "$c"; then ok "(G) ($r) census: $caller → $c is a C external row"
        else no "(G) ($r) census: no C external row for $file $caller → $c (bound, declined or dropped instead)"; fi
    done
}

echo "=== (A) Go: builtins, outside packages, and receiverless calls to methods ==="
lacks go callees algo/algo.go:Collect "append hist/history.go" "max term/terminal.go" "copy util/copy.go" "len hist/cache.go"
lacks go callees algo/drain.go:Drain "delete hist/cache.go" "len hist/cache.go" "close hist/cache.go"
lacks go callees tui/screen.go:Open "NewScreen tui/screen.go" "Split tui/screen.go" "len hist/cache.go"
lacks go callees tui/paint.go:Paint "NewScreen tui/screen.go"
lacks go callees own/extra.go:Twice "len hist/cache.go"
echo "--- (A) near misses: true edges kept"
exactly go callees own/own.go:Pick "fn min own/own.go;fn score own/own.go"
has go callees util/copy.go:Dup "fn copy util/copy.go"
lacks go callees util/copy.go:Dup "len hist/cache.go"
exactly go callees hist/history.go:Remember "method History.append hist/history.go"
exactly go callees own/hook.go:Fire "var hook own/hook.go"
exactly go callees algo/route.go:Route "fn Pick own/own.go"
has go callees own/extra.go:Twice "fn min own/own.go" "fn score own/own.go" "var hook own/hook.go"
exactly go callees dot/dot.go:UseDot "fn Pick own/own.go"
exactly go callees algo/usesub.go:UseSub "fn Helper sub/lib/lib.go"
exactly go callees algo/fnval.go:UseFnVal "fn apply algo/fnval.go"
exactly gonomod callees app/app.go:Run "fn Pick own/own.go"
exactly go callees algo/vendored.go:UseVendored "fn Shape vendored/lib/lib.go"
echo "--- (A2) go.mod spellings: a trailing comment on the module line, a quoted path, a replace-only module"
# A `module x // c` line is x (the comment goes before the trim and the unquote): the in-module call keeps its edge,
# also for a nested `module "y" // c`. Near miss: a path that only STARTS with the module path (cmx, not cm/) is still
# outside — a cut that over-trims the module path (at the first '/') would put it in the tree and fail this arm.
exactly gomodcomment callees app/app.go:Run "fn Shape lib/lib.go"
exactly gomodcomment callees quoted/app/app.go:Use "fn Mark quoted/lib/lib.go"
lacks gomodcomment callees app/near.go:Near "Shape lib/lib.go"
# goreplace/ keeps the replace-only shape the go/ root had before it became buildable Go: legacy/ has no go.mod, so
# the replace line is the only source of example.com/legacy (twin of the old UseVendored arm)
exactly goreplace callees app/app.go:UseLegacy "fn Shape legacy/lib/lib.go"
# goreplace/quoted/: the go.mod grammar lets either side of a replace be quoted — an interpreted string or a raw
# (backquoted) one, single-line or grouped. Each is the same local replace as the bare spelling. Near miss: a quoted
# module replaced by another quoted MODULE (not a directory) stays outside the tree — reading the quote itself as the
# start of a local path would put it in.
exactly goreplace callees quoted/app/app.go:UseQuoted "fn Quote quoted/qlegacy/lib/lib.go"
exactly goreplace callees quoted/app/raw.go:UseRaw "fn Raw quoted/qraw/lib/lib.go"
lacks goreplace callees quoted/app/remote.go:UseRemote "Quote quoted/qlegacy/lib/lib.go"
# goworkspace/: two roots indexed together; a's go.mod replaces example.com/wb by the SIBLING root ../b, quoted. The
# cross-root alias (resolve.h parseGoModReplaces) reads the path with the same goModToken, so the call keeps its edge.
wsf="$TMP/goworkspace.callees.xml"
( cd "$CORPUS/goworkspace" && "$BIN" a b --no-cache --callees=app/app.go:Use >"$wsf" 2>/dev/null ); wsrc=$?
wsgot="$( rows "$wsf" | tr '\n' ';' | sed 's/;$//' )"
if [ "$wsrc" -ne 0 ]; then no "(goworkspace) --callees=app/app.go:Use over roots a b exited rc=$wsrc"
elif [ "$wsgot" = "fn Far b/lib/lib.go" ]; then ok "(goworkspace) a quoted replace into a sibling root keeps the cross-root edge [fn Far b/lib/lib.go]"
else no "(goworkspace) --callees=app/app.go:Use over roots a b: rows [${wsgot:-none}], want [fn Far b/lib/lib.go]"; fi

echo "=== (B) JS: globals, required packages, accessors ==="
lacks js callees lib/response.js:length "stringify lib/query.js"
lacks js callees lib/response.js:redirect "URL lib/request.js"
lacks js callees lib/request.js:host "URL lib/request.js"
lacks js callees lib/response.js:finish "destroy helpers/stream.js"
lacks js callees lib/response.js:encode "from lib/content-type.js"
lacks js callees tests/response.test.js:checkStatus "request helpers/context.js"
exactly js callees lib/globals.js:summarize ""
lacks js callees lib/encode.js:toQuery "stringify lib/query.js"
lacks js callees lib/encode.js:readCookies "parse lib/query.js"
lacks js callees lib/aliases.js:a "stringify lib/query.js"
lacks js callees lib/aliases.js:b "fetch lib/shadow.js"
lacks js callees lib/selfalias.js:onMessage "process lib/selfalias.js"
echo "--- (B) near misses: true edges kept"
exactly js callees tests/context.test.js:makeCtx "fn request helpers/context.js"
exactly js callees tests/context.test.js:encodeQuery "fn stringify lib/query.js"
exactly js callees lib/shadow.js:emit "fn stringify lib/query.js"
exactly js callees lib/shadow.js:load "fn fetch lib/shadow.js"
exactly js callees lib/arrow.js:clean "fn normalize lib/arrow.js"
exactly js callees lib/response.js:parseType "method ContentType.from lib/content-type.js"   # js-def-naming: a JS method row names its class
has js callees lib/response.js:redirect "method set lib/response.js"
has js callees lib/request.js:host "method get lib/request.js"
exactly js callees esm/ns.mjs:nsUse "fn stringify lib/query.js"
exactly js callees esm/ns.mjs:defUse "fn max lib/util.js"
exactly js callees lib/usemethods.js:cleanAll "method tidy lib/methods.js"
# a declaration named like the global object (`var self = this`, a `const window`, a parameter `global`) is a value:
# the call reaches the in-repo method. The undeclared `self.process` in onMessage is the global object's (lacks above).
exactly js callees lib/selfalias.js:run "method process lib/selfalias.js"
exactly js callees lib/selfalias.js:runWin "method process lib/selfalias.js"
exactly js callees lib/selfalias.js:viaParam "method process lib/selfalias.js"

echo "=== (C) TS: globals and outside packages ==="
lacks ts callees src/utils/token.ts:fetchKeys "fetch src/base.ts"
lacks ts callees src/utils/token.ts:decodePart "parse src/utils/cookie.ts"
lacks ts callees src/utils/sig.ts:checkSig "verify src/utils/token.ts"
lacks ts callees src/client.ts:encode "stringify src/helpers.ts"
lacks tsimport callees src/remote.ts:pull "fetch src/client.ts"
lacks ts callees src/selfalias.ts:onTick "process src/selfalias.ts"
echo "--- (C) near misses: true edges kept, and the outside-package pins"
exactly ts callees src/app.ts:readCookie "fn parse src/utils/cookie.ts"
exactly ts callees src/app.ts:serve "cls App src/base.ts;method App.dispatch src/base.ts"
exactly ts callees src/client.ts:probe ""
exactly ts callees src/client.ts:check ""
exactly tsimport callees src/use.ts:load "fn fetch src/client.ts"
exactly ts callees src/ns.ts:nsUse "fn stringify src/helpers.ts"
exactly ts callees src/ns.ts:nsVerify "fn verify src/utils/token.ts"
exactly ts callees src/script.ts:report "fn track src/globals.d.ts"
exactly ts callees src/selfalias.ts:run "method Pump.process src/selfalias.ts"
exactly ts callees src/selfalias.ts:viaWindow "method Pump.process src/selfalias.ts"

echo "=== (D) Python: an imported function beats same-named methods; a bare call never reaches a method ==="
exactly py callees src/ui/widget.py:prune_children "fn match src/ui/css/match.py"
exactly py callees src/ui/star.py:use_star "fn match src/ui/css/match.py"
lacks py callees src/ui/widget.py:run_all "process src/ui/worker.py"
lacks py callees src/ui/siblings.py:run "helper src/ui/siblings.py"
echo "--- (D) near misses: true edges kept, and the builtin pins"
exactly py callees src/ui/use_lists.py:grow "fn append src/ui/lists.py"
exactly py callees src/ui/use_lists.py:twice "fn helper src/ui/use_lists.py"
exactly py callees src/ui/worker.py:Worker "fn Worker._default src/ui/worker.py"
exactly py callees src/ui/star.py:use_var "var handler src/ui/star.py"
exactly py callees src/ui/star.py:build "cls Worker src/ui/worker.py"
exactly py callees src/ui/star.py:fmt "fn format src/ui/text.py"
exactly py callees src/ui/alias.py:flush "fn Driver.write src/ui/alias.py"
exactly py callees src/ui/closure.py:line_width "fn Tree.label_width src/ui/closure.py"
# a pin, not a claim of truth: a call through a CAPTURED parameter keeps whatever the unchanged ladder decided
has py callees src/ui/closure.py:run "fn Sheet.reparse src/ui/sheet.py"
lacks py callees src/ui/widget.py:read_config "open src/ui/worker.py"
lacks py callees src/ui/report.py:render "format src/ui/text.py"

echo "=== (E) C: a call never reaches a struct or an enum; C++ construction is untouched ==="
reaches_fn c copy.c:copy_command opts_parse 'arguments\.c|mux\.h'
reaches_fn c usemacro.c:clampit region 'region\.c|usemacro\.c'
has c callees usemacro.c:clampit "macro CLAMP macro.h"
exactly c callees copy.c:classify "fn window_count window.c"
exactly c callees window.c:elapsed ""
exactly cpp callees use.cpp:origin "cls Point point.hpp;fn Point::Point point.hpp"

echo "=== (R) Rust: no implicit receiver either — a bare call never reaches a method ==="
lacks rs callees src/lib.rs:draw "render src/history.rs"
exactly rs callees src/lib.rs:paint "fn helper src/lib.rs;method History::render src/history.rs"
exactly rs callees src/assoc.rs:build "method History::new src/assoc.rs;method History::render src/history.rs"
exactly rs callees src/assoc.rs:count "method History::width src/assoc.rs"
exactly rs callees src/ufcs.rs:draw_all "method History::render_all src/ufcs.rs"

echo "=== (S) JS/TS rebind: a written binding names nothing (FC3) ==="
# the exact row set: every case file whose binding is written is GONE; each near miss keeps its row (nestedP keeps h,
# its g wrote its own `let Eng`; classexprP's m constructs its own class expression)
exactly jsrebind callers Eng "fn h cases/nestedP.js;method Eng.m cases/classexprP.js;modscope &lt;file-scope&gt; cases/constwriteP.js;modscope &lt;file-scope&gt; cases/esimport.js;modscope &lt;file-scope&gt; cases/keepdestrP.js;modscope &lt;file-scope&gt; cases/keepmemberP.js;modscope &lt;file-scope&gt; cases/memberroot.js;modscope &lt;file-scope&gt; cases/memberwriteP.js;modscope &lt;file-scope&gt; cases/norewriteP.js;modscope &lt;file-scope&gt; cases/otherfileP_y.js;modscope &lt;file-scope&gt; cases/paramP.js;modscope &lt;file-scope&gt; cases/redeclnoinitP.js"
lacks jsrebind callers leaf "&lt;file-scope&gt; cases/fncall.js"
has jsrebind callers leaf "method Eng.run src/eng.js"
lacks jsrebind callers Foo "&lt;file-scope&gt; cases/destr.js" "&lt;file-scope&gt; cases/plainreq.js"   # undecided is not Foo either
# a member call spelled like a written LOCAL is not that local: `let run = ''; run += ' '; reply.run( … )` keeps its row
has jsrebind callers run "fn onSendEnd cases/memberwriteP.js"
# FIX1 B3: a MEMBER call is read through its ROOT name — `Eng = Foo; Eng.run()` calls Foo's, a rebound module alias
# `m = require( b ); m.Eng()` whatever b holds (memberroot.js: a hedged row below), and a
# local class `Pack = Crate; Pack.make()` — when the write REPLACES a value the declaration bound. Near misses keep: a
# name nobody writes, and `let rig; … rig = new Rig(); rig.fire()` (the declaration bound nothing: the test-file idiom;
# measured: refusing it dropped 400+ true rows from hono alone)
# FIX2 C1: such a member call is not DROPPED either — a written root is no receiver, so the call keeps the by-name ladder's
# hedge (via="name", every candidate): the true target stays visible, never a pinned row (memberclass, memberlocal, memberroot)
hedged jsrebind callers run "&lt;file-scope&gt; cases/memberclass.js"
hedged jsrebind callers Eng "&lt;file-scope&gt; cases/memberroot.js"
exactly jsrebind callers make "modscope &lt;file-scope&gt; cases/memberlocal.js;modscope &lt;file-scope&gt; cases/membernowriteP.js"
hedged jsrebind callers make "&lt;file-scope&gt; cases/memberlocal.js"
hedged jsrebind callers drip "reassign cases/pinnedhedgeP.js"   # `let tank = new Tank(); tank = b; tank.drip()`
# FIX2 C2: a root ASSIGNED anywhere in its scope never decides by its own SPELLING — `Eng = Foo; Eng.run()` is not the class
# `Eng`, with or without a declaration, nor `Cog = require( … ).Gear; Cog.spin()` the class `Cog`: hedged at best, never pinned
unpinned jsrebind callers spin "&lt;file-scope&gt; cases/spellnodeclP.js" "&lt;file-scope&gt; cases/spellimplicitP.js" "&lt;file-scope&gt; cases/spellvarP.js"
hedged jsrebind callers spin "&lt;file-scope&gt; cases/spellnodeclP.js"   # the by-name hedge keeps both candidates, not a guess at either
has jsrebind callers fire "modscope &lt;file-scope&gt; cases/memberunpinnedP.js"
# FIX1 FC5: `reply.leaf( … )` is a member call: the ES-imported function `leaf` of the same file does not PIN it
hedged jsrebind callers leaf "send cases/esmemberP.js"   # by name at best: not the imported `leaf` as a pinned row
# FIX1 B2: the name-keeping exception is for `var x;` / `let x;` / an undeclared name only. keepotherinit.js / keepclass.js
# (above: absent from the Eng rows) write another module's `Eng` over a declaration that already pinned one. NAMED FLOOR:
# keepsamemod.js re-assigns the SAME module's `Eng` over its destructured require — true, but the spelling is not the proof,
# so it is withheld too (honest over-withholding; the positive reading `x = mod.member` is a later lane)
lacks jsrebind callers Eng "&lt;file-scope&gt; cases/keepsamemod.js"
# FIX1 B1: patterns nest as deep as a file likes — an assignment target / declarator 20000 object patterns deep (a recursive
# walk overflows the stack: rc 138 / SIGBUS / ASan stack-overflow) answers, exits 0, and binds nothing it cannot read
deep="$TMP/jsdeep"; mkdir -p "$deep/src" "$deep/test"
printf 'class Eng { run() { return 1; } }\nmodule.exports = { Eng };\n' >"$deep/src/a.js"
python3 - "$deep/test" <<'PY'
import sys
d, n = sys.argv[ 1 ], 20000
pat = "{a:" * n + "{Eng}" + "}" * n
open( d + "/assign.test.js", "w" ).write( 'let { Eng } = require("../src/a");\n(' + pat + ' = o);\ntest("x", () => { new Eng(); });\n' )
open( d + "/decl.test.js", "w" ).write( 'var ' + pat + ' = o;\nvar Eng = require("../src/a").Eng;\ntest("x", () => { new Eng(); });\n' )
PY
deepf="$TMP/jsdeep.callers.xml"
( cd "$deep" && "$BIN" . --no-cache --callers=Eng >"$deepf" 2>/dev/null ); deeprc=$?
if [ "$deeprc" -ne 0 ]; then no "(jsrebind) --callers=Eng over 20000-deep object patterns exited rc=$deeprc"
elif ! grep -q '<callers [^>]* defs="1"' "$deepf"; then no "(jsrebind) --callers=Eng over 20000-deep object patterns produced no answer about Eng"
elif grep -q 'test/assign.test.js' "$deepf"; then no "(jsrebind) the 20000-deep assignment still binds a row: $( tr '<' '\n' <"$deepf" | grep 'assign.test' | tr '\n' ';' )"
else ok "(jsrebind) 20000-deep object patterns: exit 0, the written \`Eng\` binds no row"; fi

echo "=== (J) Kotlin: a trailing-lambda scope function never binds a Java method (#155) ==="
# A Kotlin call with a trailing lambda to let/run/with/apply/also is the stdlib scope function: its Java candidates are dropped
# and an emptied set is external= (kotlin scope arm of FalseEdgeRules). Kotlin's own candidates are kept, and a call with no
# lambda (`block.run()` on a Runnable) keeps every candidate the ladder had.
exactly kt callers java/jobs/Job.java:run "fn dispatch kt/Dispatch.kt;fn kick kt/Use.kt"
lacks kt callers java/jobs/Job.java:run "build kt/Use.kt"
exactly kt callers java/lib/Builder.java:with "fn realWith kt/Scopes.kt"
exactly kt callers java/lib/Builder.java:apply ""
exactly kt callers java/lib/Builder.java:let ""
exactly kt callers java/lib/Builder.java:also ""
# Kotlin DEFINES run (ktown): own-language-first keeps the Kotlin run for go and build (the receiver gap, pinned); kick's j.run()
# has no lambda and keeps Job.run, as it did before the fix.
exactly ktown callers kt/Task.kt:run "fn build kt/Task.kt;fn go kt/Task.kt"
exactly ktown callers java/jobs/Job.java:run "fn kick kt/Task.kt"

externals kt kt/Use.kt build run
externals kt kt/Scopes.kt useWith with
externals kt kt/Scopes.kt useApply apply
externals kt kt/Scopes.kt useLet let
externals kt kt/Scopes.kt useAlso also
echo "=== (F) propagation: the decoys' callers and impact ==="
exactly go callers hist/history.go:append "fn Remember hist/history.go"
lacks go impact hist/history.go:append "Collect algo/algo.go"
lacks go impact hist/cache.go:len "Collect algo/algo.go" "Drain algo/drain.go" "Open tui/screen.go" "Dup util/copy.go"
exactly go callers util/copy.go:copy "fn Dup util/copy.go"
exactly js callers lib/query.js:stringify "fn emit lib/shadow.js;fn encodeQuery tests/context.test.js;fn nsUse esm/ns.mjs"
exactly js callers helpers/stream.js:destroy ""
exactly ts callers src/base.ts:fetch ""
exactly py callers src/ui/fuzzy.py:match ""

echo "=== (G) disclosure: each unbound call is a C external census row; conservation per root ==="
externals go algo/algo.go Collect append max copy len
externals go util/copy.go Dup len
externals go algo/drain.go Drain delete len close
externals go tui/screen.go Open NewScreen Split len
externals go tui/paint.go Paint NewScreen
externals go own/extra.go Twice len
externals js lib/response.js length stringify
externals js lib/response.js redirect URL
externals js lib/request.js host URL
externals js lib/response.js finish destroy
externals js lib/response.js encode from
externals js tests/response.test.js checkStatus request
externals js lib/globals.js summarize log keys max from resolve
externals js lib/encode.js toQuery stringify
externals js lib/encode.js readCookies parse
externals js lib/aliases.js a stringify
externals js lib/aliases.js b fetch
externals ts src/utils/token.ts fetchKeys fetch
externals ts src/utils/token.ts decodePart parse
externals ts src/utils/sig.ts checkSig verify
externals ts src/client.ts encode stringify
externals tsimport src/remote.ts pull fetch
externals js lib/selfalias.js onMessage process
externals ts src/selfalias.ts onTick process
externals gomodcomment app/near.go Near Shape
externals goreplace quoted/app/remote.go UseRemote Quote
# a Python name no import, local or module def binds and that is no builtin: no in-repo target, but nothing proves it is
# outside the tree either (a closure variable, a star import of an unresolved module) — so it is no census row at all
# (counted unresolved=), never a C external row and never a bound one
unresolved_site(){
    local r="$1" file="$2" caller="$3" callee="$4"
    printf '%s %s %s\n' "$file" "$caller" "$callee" >>"$TMP/$r.nunres"   # the pin below counts the sites named per root
    if python3 - "$TMP/$r.tsv" "$file" "$caller" "$callee" <<'PY'
import sys
census, path, caller, callee = sys.argv[ 1: ]
for line in open( census, encoding="utf-8", errors="replace" ):
    f = line.rstrip( "\n" ).split( "\t" )
    if len( f ) >= 9 and f[ 0 ] == "C" and f[ 6 ] == callee:
        head, _, tail = f[ 5 ].partition( "::" )
        if head == path and tail.rsplit( "#", 1 )[ 0 ].split( "::" )[ -1 ] == caller:
            sys.exit( 1 )
sys.exit( 0 )
PY
    then ok "(G) ($r) census: $caller → $callee has no row (unresolved — neither bound nor claimed external)"
    else no "(G) ($r) census: $file $caller → $callee has a C row (bound or claimed external)"; fi
}
unresolved_site py src/ui/widget.py run_all process
unresolved_site py src/ui/siblings.py run helper
externals py src/ui/widget.py read_config open
unresolved_site c copy.c classify find_type
# unresolved_site reads an ABSENT census row, so a call extraction dropped would pass it too (CodeRabbit on #372). Each
# root that names unresolved sites therefore pins its census `unresolved=` to exactly the number it names: a dropped call
# lowers the count (red), and a new unresolved call in the fixture raises it (red until an arm names that site too).
unresolved_pinned(){
    local r="$1" want got
    want="$( sort -u "$TMP/$r.nunres" 2>/dev/null | wc -l | tr -d ' ' )"
    got="$( grep -m1 '^# dispositions ' "$TMP/$r.tsv" 2>/dev/null | grep -oE ' unresolved=[0-9]+' | grep -oE '[0-9]+$' )"
    if [ -z "$got" ]; then no "(G) ($r) the census dispositions carry no unresolved= count — the pin cannot be read"
    elif [ "$want" -lt 1 ]; then no "(G) ($r) no unresolved site is named for this root — the pin would be vacuous"
    elif [ "$got" -ne "$want" ]; then no "(G) ($r) census unresolved=$got, but this gate names $want unresolved site(s): $( tr '\n' ';' <"$TMP/$r.nunres" )"
    else ok "(G) ($r) census unresolved=$got == the $want site(s) named above: each was extracted and left unresolved"; fi
}
unresolved_pinned py
unresolved_pinned c
externals c window.c elapsed clock
externals rs src/lib.rs draw render
for r in $ROOTS; do
    hdr="$( grep -oE '<!-- files=[^>]*-->' "$TMP/$r.map.xml" | head -1 )"
    if [ -z "$hdr" ]; then no "(G) ($r) the census run printed no map header"; continue; fi
    hx="$( printf '%s' "$hdr" | grep -oE ' external=[0-9]+' | grep -oE '[0-9]+$' )"; hx="${hx:-0}"   # absent = 0
    cx="$( grep -m1 '^# dispositions ' "$TMP/$r.tsv" | grep -oE ' external=[0-9]+' | grep -oE '[0-9]+$' )"
    nx="$( sort -u "$TMP/$r.nexp" 2>/dev/null | wc -l | tr -d ' ' )"
    if [ -z "$cx" ]; then no "(G) ($r) the census dispositions carry no external= count"
    elif [ "$hx" != "$cx" ]; then no "(G) ($r) header external=$hx but census external=$cx — two derivations disagree"
    elif [ "$hx" -lt "$nx" ]; then no "(G) ($r) header external=$hx is below the $nx external call(s) this gate expects"
    else ok "(G) ($r) header external=$hx == census external=$cx >= $nx expected"; fi
    DL="$( grep -m1 '^# dispositions ' "$TMP/$r.tsv" 2>/dev/null )"
    if [ -z "$DL" ]; then no "(G) ($r) the census carries no '# dispositions' line"; continue; fi
    if python3 - "$DL" <<'PY'
import re, sys
kv = dict( ( k, int( v ) ) for k, v in re.findall( r"(\w+)=(\d+)", sys.argv[ 1 ] ) )
if "calls" not in kv or "unaccounted" not in kv:
    sys.exit( 1 )
total = kv.pop( "calls" )
sys.exit( 0 if kv[ "unaccounted" ] == 0 and sum( kv.values() ) == total else 1 )
PY
    then
        ok "(G) ($r) dispositions sum to calls= with unaccounted=0"
    else
        no "(G) ($r) conservation broken: $DL"
    fi
done

echo "=== (H) MCP twins (fresh TMPDIR: the MCP cache lives there) ==="
mkdir -p "$TMP/mcp"
# mcp_names TOOL ARGS FIELD OUT — the de-duplicated "name@file" entries of one array of the answer, sorted and
# ";"-joined, into OUT; the server's exit status into OUT.rc; NOJSON when there is no such array
mcp_names(){
    printf '%s\n' '{"jsonrpc":"2.0","id":1,"method":"initialize"}' \
        "{\"jsonrpc\":\"2.0\",\"id\":2,\"method\":\"tools/call\",\"params\":{\"name\":\"$1\",\"arguments\":$2}}" \
        | TMPDIR="$TMP/mcp" "$BIN" --mcp >"$4.raw" 2>/dev/null
    printf '%s' "$?" >"$4.rc"
    tail -1 "$4.raw" | python3 -c '
import json, sys
try:
    r = json.load( sys.stdin ); d = json.loads( r[ "result" ][ "content" ][ 0 ][ "text" ] )
except Exception:
    print( "NOJSON" ); sys.exit( 0 )
arr = d.get( sys.argv[ 1 ] )
if arr is None:
    print( "NOJSON" ); sys.exit( 0 )
print( ";".join( sorted( { "%s@%s" % ( e.get( "name" ), e.get( "file" ) ) for e in arr } ) ) )' "$3" >"$4"
}
# margs ROOT SELECTOR — the tool arguments (built by printf: no brace expansion can split them)
margs(){ printf '{"path":"%s","symbol":"%s"}' "$CORPUS/$1" "$2"; }
# mcp_twin ROOT CLI_VERB SEL TOOL FIELD WANT — CLI rows (as name@file) == WANT, and the MCP array == the CLI rows
mcp_twin(){
    local r="$1" v="$2" sel="$3" tool="$4" field="$5" want="$6"
    local f got cli out mrc mcp
    f="$( answer "$r" "$v" "$sel" )"; ran_ok "$r" "$v" "$sel" "$f" || return; got="$( rows "$f" )"
    if [ "$got" = "NOROOT" ]; then no "(H) ($r) --$v=$sel produced no answer about a symbol"; return; fi
    cli="$( printf '%s\n' "$got" | awk 'NF == 3 { print $2 "@" $3 }' | sort -u | tr '\n' ';' | sed 's/;$//' )"
    out="$TMP/mcp.$r.$tool.$( printf '%s' "$sel" | tr '/:.' '___' )"
    mcp_names "$tool" "$( margs "$r" "$sel" )" "$field" "$out"
    mrc="$( cat "$out.rc" 2>/dev/null )"; mcp="$( cat "$out" 2>/dev/null )"
    if [ "$mrc" != "0" ]; then no "(H) ($r) MCP $tool $sel: the server exited rc=${mrc:-unknown}"; return; fi
    if [ "$mcp" = "NOJSON" ]; then no "(H) ($r) MCP $tool $sel: no JSON answer with $field"; return; fi
    if [ "$cli" != "$want" ]; then no "(H) ($r) CLI --$v=$sel names [${cli:-none}], want [${want:-none}]"
    elif [ "$mcp" != "$cli" ]; then no "(H) ($r) MCP $tool $sel $field = [${mcp:-none}] but the CLI names [${cli:-none}]"
    else ok "(H) ($r) MCP $tool $sel $field == CLI --$v == [${want:-none}]"; fi
}
mcp_twin go callers hist/history.go:append find_referencing_symbols calledBy "Remember@hist/history.go"
mcp_twin go callees algo/algo.go:Collect find_symbol calls ""
mcp_twin go callees own/own.go:Pick find_symbol calls "min@own/own.go;score@own/own.go"
mcp_twin py callees src/ui/widget.py:prune_children find_symbol calls "match@src/ui/css/match.py"
mcp_twin ts callees src/utils/token.ts:fetchKeys find_symbol calls ""

echo "=== (K) the predicates can fail ==="
printf '<callees of="x" defs="1"><s t="method" n="append" p="hist/history.go:6"/></callees>' >"$TMP/k1.xml"
got="$( rows "$TMP/k1.xml" )"
if [ "$got" = "method append hist/history.go" ]; then ok "(K) rows() reads a false row back"
else no "(K) rows() missed a planted row: [$got]"; fi
printf 'nothing here' >"$TMP/k2.xml"
if [ "$( rows "$TMP/k2.xml" )" = "NOROOT" ]; then ok "(K) an answer with no root element is NOROOT, never an empty pass"
else no "(K) rows() treated a rootless document as an answer"; fi
printf '<callers of="x" found="0"/>' >"$TMP/k3.xml"
if [ "$( rows "$TMP/k3.xml" )" = "NOROOT" ]; then ok "(K) an answer about no symbol (no defs=) is NOROOT, never an empty pass"
else no "(K) rows() treated a not-found answer as an empty answer"; fi
printf 'C\tunique\t1\t1\t-\talgo/algo.go::Collect#1\tappend\thist/history.go::append#3\t10\n' >"$TMP/k.tsv"
if ext_row k algo/algo.go Collect append; then no "(K) ext_row accepted a BOUND census row as external"
else ok "(K) ext_row rejects a bound census row"; fi
printf 'C\texternal\t1\t0\t-\talgo/algo.go::Collect#1\tappend\t\t10\n' >"$TMP/k.tsv"
if ext_row k algo/algo.go Collect append; then ok "(K) ext_row reads a planted external row back"
else no "(K) ext_row missed a planted external row"; fi
printf '1' >"$TMP/k4.rc"
if ( ran_ok k callees x "$TMP/k4" ) >/dev/null; then no "(K) ran_ok accepted a run that exited 1"
else ok "(K) ran_ok fails a run that exited non-zero"; fi
rm -f "$TMP/k5.rc"
if ( ran_ok k callees x "$TMP/k5" ) >/dev/null; then no "(K) ran_ok accepted a run with no recorded exit status"
else ok "(K) ran_ok fails a run with no recorded exit status"; fi

if [ "$fail" -eq 0 ]; then echo "ALL PASS"; else echo "FAILURES ABOVE"; exit 1; fi
