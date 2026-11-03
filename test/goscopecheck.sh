#!/usr/bin/env bash
# goscopecheck.sh — a Go method's receiver type, and an interface member's interface, are the symbol's scope (#403).
#
# THE DEFECT. enclosingScopeOf (src/ingest_names.h) knew C++ and Python owners only, and Go definitions never reached
# it, so every Go method was indexed without an owner: `--whereis=Loop` listed Matcher.Loop and Terminal.Loop as two
# bare rows, and a `Type::method` / `Type.method` selector was refused ("symbol not found") on every verb that takes one.
#
# THE CONTRACT (src/ingest_names.h kScopeOwners, slice 9a's table rows):
#   method_declaration → the receiver parameter's type, `*` and type arguments stripped (`*Stack[T]` → Stack), for the
#   method's OWN name only — a def in the method body (a local var, a func literal bound to one) is a local, no scope;
#   type_spec → its name, for the definitions INSIDE it (an interface's members) — never the type's own name.
#   C++ and Python rows are unchanged (a class still carries itself as sc=, arm F).
#
# ARMS (fixture test/goscopefix: iface.go, deb.go, other.go)
#   (A) map: Deb's methods sc="Deb", Packager's members sc="Packager", Matcher.Loop sc="Matcher", Terminal.Loop sc="Terminal".
#   (B) selectors: --callers=Deb::Package and Deb.Package resolve to ONE def and list Run; Packager::Package one def;
#       Matcher::Loop one def and lists Terminal.Loop; the bare --callers=Package keeps defs="3", bare Loop defs="2".
#   (C) near misses: a generic receiver (`*Stack[T]`, and the unnamed value receiver `Stack[T]`) scopes to Stack; a func
#       literal bound inside a method (`step`) and a local var have no scope; the types Deb / Packager / Stack / closer and
#       the free function Package carry no sc=; an interface declared inside a function body scopes its member to itself
#       (Close sc="closer"), not to the function.
#   (D) the cache round-trips the scope: a warm run equals the --no-cache run byte for byte.
#   (E) the multi-definition table: --callers=Loop labels its two <def> rows sc="Matcher" and sc="Terminal".
#   (F) unchanged rows: a Python class keeps sc= on itself, its method and a nested function (the SelfAndInside row).
#   (G) entity identity: Matcher.Loop and Terminal.Loop (one file, two receiver types) are two map rows, never one
#       overloads="2" row (Go has no overloading; the owner-less ids used to fold them).
#   (H) --uses names a call's enclosing method by its scoped id (deb.go::Deb::Package); a free function keeps its name.
#   (I) a comment inside the receiver list keeps the receiver scope (Body sc="Note"); members of an alias to an
#       interface literal (`type Sink = interface{…}`) scope to the alias (Flush sc="Sink").
#
# Go struct fields are not indexed as definitions (queries/go/tags.scm captures none), so "a struct field scopes to its
# struct" has no row to check; the nearest-type_spec rule is pinned by the interface-in-function arm instead.
#
# Usage: test/goscopecheck.sh [BIN]   (BIN defaults to RIPWIRE_BIN, then build/ripwire)

set -u
ROOT="$( cd "$( dirname "$0" )/.." && pwd )"
BIN="${1:-${RIPWIRE_BIN:-$ROOT/build/ripwire}}"
[ "${BIN#/}" = "$BIN" ] && BIN="$PWD/$BIN"
FIX="$ROOT/test/goscopefix"
TMP="$( mktemp -d )"; trap 'rm -rf "$TMP"' EXIT
fail=0
ok(){ printf '  PASS  %s\n' "$*" || { fail=1; printf '  FAIL  could not write the PASS line for: %s\n' "$*"; }; return 0; }
no(){ printf '  FAIL  %s\n' "$*"; fail=1; }

echo "goscopecheck: BIN=$BIN  FIX=$FIX"
[ -x "$BIN" ] || { echo "no ripwire binary at $BIN — build first"; exit 2; }
[ -d "$FIX" ] || { echo "no fixture at $FIX"; exit 2; }

# run ARGS... → stdout in $TMP/out, rc in $rc; an answer that did not run (rc != 0, empty) fails the arm that reads it
run(){ "$BIN" "$FIX" --no-cache "$@" >"$TMP/out" 2>"$TMP/err"; rc=$?; }

run
map_rc=$rc
cp "$TMP/out" "$TMP/map.xml"
rows="$( grep -o "<s t=\"" "$TMP/map.xml" | wc -l | tr -d " " )"
if [ "$map_rc" -eq 0 ] && [ "${rows:-0}" -ge 15 ]; then ok "(A0) map ran: rc=0, $rows rows"; else no "(A0) map rc=$map_rc rows=${rows:-0}: $( head -c 300 "$TMP/err" )"; fi

# has_row KIND NAME SC (has_row_in FILE KIND NAME SC) → the map holds that row with exactly that sc= (SC empty = the row has NO sc= attribute)
has_row(){ has_row_in "$TMP/map.xml" "$@"; }
has_any_row(){ grep -qE "<s t=\"$1\" n=\"$2\"[ >/]" "$TMP/map.xml"; }   # any row of that kind and name, scoped or not
has_row_in(){
    python3 -I - "$1" "$2" "$3" "$4" <<'PY'
import re, sys
xml, kind, name, sc = sys.argv[1:5]
rows = re.findall(r'<s t="([^"]*)" n="([^"]*)"((?: [a-z_]+="[^"]*")*)', open(xml).read())
hits = [attrs for t, n, attrs in rows if t == kind and n == name]
want = [a for a in hits if (re.search(r' sc="([^"]*)"', a) or [None, None])[1] == (sc or None)]
sys.exit(0 if want else 1)
PY
}

echo "=== (A) methods and interface members carry their owner ==="
for spec in "method Package Deb" "method ConventionalFileName Deb" "method Package Packager" "method ConventionalFileName Packager" \
            "method Loop Matcher" "method Loop Terminal"; do
    set -- $spec
    if has_row "$1" "$2" "$3"; then ok "(A) t=$1 $2 sc=\"$3\""; else no "(A) no t=$1 $2 row with sc=\"$3\""; fi
done

echo "=== (B) qualified selectors resolve; bare names keep every def ==="
# callers_of SEL DEFS [CALLER] → --callers=SEL answers defs="DEFS" (and lists CALLER when given)
callers_of(){
    run --callers="$1"
    local root; root="$( grep -o '<callers [^>]*>' "$TMP/out" | head -1 )"
    if [ "$rc" -ne 0 ] || [ -z "$root" ]; then no "(B) --callers=$1: rc=$rc, no <callers> root: $( head -c 200 "$TMP/err" )"; return; fi
    case "$root" in *" defs=\"$2\""*) ok "(B) --callers=$1 defs=\"$2\"" ;; *) no "(B) --callers=$1 wanted defs=\"$2\": $root" ;; esac
    if [ -n "${3:-}" ]; then
        if grep -q "<s t=\"[a-z]*\" n=\"$3\"" "$TMP/out"; then ok "(B) --callers=$1 lists $3"; else no "(B) --callers=$1 does not list $3"; fi
    fi
}
callers_of "Deb::Package" 1 Run
callers_of "Deb.Package" 1 Run
callers_of "Packager::Package" 1
callers_of "Matcher::Loop" 1 Terminal.Loop
# twin (QUALNAME-1): a Go method caller prints Owner.name, so the bare spelling is NOT a row; the positive above
# can only pass on the qualified row, and this proves the row probe fails on a spelling that is not printed
if grep -q '<s t="[a-z]*" n="Loop"' "$TMP/out"; then no "(B) --callers=Matcher::Loop still prints a bare n=\"Loop\" row"; else ok "(B) --callers=Matcher::Loop prints no bare n=\"Loop\" row (Terminal.Loop is Owner-qualified)"; fi
callers_of "Package" 3
callers_of "Loop" 2

echo "=== (C) near misses ==="
for spec in "method Push Stack" "method Size Stack" "method Close closer" \
            "struct Deb -" "iface Packager -" "struct Stack -" "iface closer -" "fn Package -" "fn Build -" "fn Run -"; do
    set -- $spec
    sc="$3"; [ "$sc" = "-" ] && sc=""
    want="no sc="; [ -n "$sc" ] && want="sc=\"$sc\""
    if has_row "$1" "$2" "$sc"; then ok "(C) t=$1 $2 $want"; else no "(C) t=$1 $2 wanted $want"; fi
done

# train 30 (go-scope x go-local-var): a func literal bound inside a method (`var step = func…`) and a local `var c closer` are
# function-local declarations, which are no longer indexed symbols at all (test/localdeclcheck.sh) — so no row of either
# exists, scoped or not (on main before go-local-var both were rows with no sc=; read off the map checked non-empty above).
for spec in "var step" "var c"; do
    set -- $spec
    if [ "$rows" -gt 0 ] && ! has_any_row "$1" "$2"; then ok "(C) t=$1 $2 is no symbol (function-local, so never scoped to the method)"
    else no "(C) t=$1 $2: a function-local declaration is a map row again (rows=$rows)"; fi
done

echo "=== (I) receiver-list comment and interface alias (written to a temp dir) ==="
# I1: `func ( /* c */ n *Note) Body()` — the first named child of the receiver list is the comment, not the parameter.
# I2: `type Sink = interface{ Flush() error }` — a type_alias owns its interface members as a type_spec does.
# Written here, not committed under test/goscopefix: a Go `alias` row in the repo's own map pulls the Go type-kind legend
# clause into every whole-repo map, which moves readmedriftcheck's --max-tokens=3000 head (G4) by two rows.
mkdir -p "$TMP/goi"
printf 'package scope\n\ntype Note struct{}\n\nfunc ( /* the note */ n *Note) Body() string { return "" }\n\ntype Sink = interface {\n\tFlush() error\n}\n' > "$TMP/goi/alias.go"
"$BIN" "$TMP/goi" --no-cache >"$TMP/goi.xml" 2>/dev/null; irc=$?
for spec in "method Body Note" "method Flush Sink" "struct Note -"; do
    set -- $spec
    sc="$3"; [ "$sc" = "-" ] && sc=""
    want="no sc="; [ -n "$sc" ] && want="sc=\"$sc\""
    if [ "$irc" -eq 0 ] && has_row_in "$TMP/goi.xml" "$1" "$2" "$sc"; then ok "(I) t=$1 $2 $want"; else no "(I) rc=$irc: t=$1 $2 wanted $want"; fi
done

echo "=== (D) the cache round-trips the scope ==="
"$BIN" "$FIX" --cache="$TMP/cache" >"$TMP/cold.xml" 2>/dev/null; c1=$?
"$BIN" "$FIX" --cache="$TMP/cache" >"$TMP/warm.xml" 2>/dev/null; c2=$?
if [ "$c1" -eq 0 ] && [ "$c2" -eq 0 ] && cmp -s "$TMP/warm.xml" "$TMP/map.xml" && [ -s "$TMP/warm.xml" ]; then ok "(D) warm cached map == --no-cache map"
else no "(D) cold rc=$c1 warm rc=$c2; warm and --no-cache maps differ or are empty"; fi

echo "=== (E) the two-def answer names each owner ==="
run --callers=Loop
if [ "$rc" -eq 0 ] && grep -q '<def ix="1" t="method" sc="Matcher"' "$TMP/out" && grep -q '<def ix="2" t="method" sc="Terminal"' "$TMP/out"; then
    ok "(E) --callers=Loop def rows carry sc=\"Matcher\" and sc=\"Terminal\""
else no "(E) --callers=Loop (rc=$rc): the <def> rows do not name both owners"; fi

echo "=== (G) two receiver types' same-named methods in one file are two rows, never overloads ==="
loops="$( grep -o '<s t="method" n="Loop"[^>]*>' "$TMP/map.xml" )"
nloops="$( printf '%s\n' "$loops" | grep -c 'n="Loop"' )"
if [ "$nloops" -eq 2 ] && ! printf '%s' "$loops" | grep -q 'overloads='; then ok "(G) Matcher.Loop and Terminal.Loop are 2 map rows, no overloads="
else no "(G) wanted 2 Loop rows without overloads=, got: $loops"; fi

echo "=== (H) --uses names the enclosing method by its scoped id ==="
run --uses=ConventionalFileName
if [ "$rc" -eq 0 ] && grep -q '<u role="call" p="deb.go:11" in_id="deb.go::Deb::Package"/>' "$TMP/out" \
   && grep -q '<u role="call" p="other.go:38" in_id="Run"/>' "$TMP/out"; then
    ok "(H) the call in Deb.Package reads in_id=\"deb.go::Deb::Package\"; the free function Run keeps in_id=\"Run\""
else no "(H) --uses=ConventionalFileName (rc=$rc) lacks the scoped in_id rows"; fi

echo "=== (F) unchanged rows: a Python class's scope ==="
mkdir -p "$TMP/py"
printf 'class Foo:\n    def m(self):\n        def inner():\n            pass\n        return inner\n' > "$TMP/py/a.py"
"$BIN" "$TMP/py" --no-cache >"$TMP/map.xml" 2>/dev/null; prc=$?
for spec in "cls Foo Foo" "fn m Foo" "fn inner Foo"; do
    set -- $spec
    if [ "$prc" -eq 0 ] && has_row "$1" "$2" "$3"; then ok "(F) python t=$1 $2 sc=\"$3\""; else no "(F) python rc=$prc: no t=$1 $2 sc=\"$3\""; fi
done

echo
if [ "$fail" -eq 0 ]; then echo "ALL PASS"; exit 0; else echo "SOME CHECKS FAILED"; exit 1; fi
