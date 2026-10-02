#!/usr/bin/env bash
# editcheckdeclcheck.sh — --edit-check on C/C++: a declaration and the definition it declares are ONE contract.
#
# The field report: a header declares `int scale( int x, int factor = 2 )`, the .cpp defines it, three callers pass 1, 1
# and 2 arguments, and a trailing `int bias = 0` is added to both. Every call still compiles. The verb answered:
#   R1  --edit-check=scale           refused as "2 distinct contracts" (the prototype and its definition);
#   R2  --edit-check=./lib.cpp:scale incompatible="3" — the defaults live on the HEADER declaration and the arity test
#                                    read the definition's parameter list only;
#   R3  --edit-check=./lib.h:scale   refused again — the handle the refusal itself suggested.
#
# Arms:
#   (A) R1: the bare name answers (exit 0) about the definition, no refusal.
#   (B) R2: the definition's handle reports incompatible="0", flags no caller, and says where the defaults came from
#       (defaults_from="decl", defined in the same document's legend).
#   (C) R3: the header handle answers too, with the same contract as (B).
#   (D) the field-report shape on the MCP twin (edit_check symbol=scale): incompatible="0".
#   (E) CONTROL — defaults never make a wildcard: a call with MORE arguments than the parameter list is still flagged,
#       and only that caller is.
#   (F) E3 decoy — two real overloads, scale(int,int=2,int=3) and scale(double,double,double,double): they stay two
#       definitions (defs="2"), each takes defaults only from ITS declaration (a 1-argument call is accepted by the int
#       overload alone, a 5-argument call by neither).
#   (G) a declaration whose parameter TYPES match no definition is not folded and lends no defaults: the 1-argument
#       call against `scale( double, int )` stays flagged, and the bare name stays refused.
#   (H) E2 — every handle printed after "Qualify one contract:" is accepted on a rerun, on (G) and on a two-platform
#       corpus (one declaration, two .cpp definitions, which is two contracts and must stay refused).
#   (J) M2 — a header that drops a default over two platform definitions: no printed handle is the declaration's,
#       whose own answer has no call edges (callers="0"), and the definitions' handles flag the broken call.
#   (K) M3 — `./lib.cpp` beside `./sub/lib.cpp`, and paths with a space: every printed handle names one contract.
#   (L) M1 — the identity is the FULL scope chain plus the member's cv/ref qualifiers: outer::detail::f vs ::detail::f,
#       outer::a::f vs ::a::f, Outer::S::f vs ::S::f and a const member never share a default; a chain spelled two ways
#       (namespace block vs qualified out-of-line definition) still pairs.
#   (O) a namespace opened by a macro (in-file #define, or QT_BEGIN_NAMESPACE from another header) makes the chain
#       unreadable: never paired, disclosed as defaults_untied=; a qualified definition after `using namespace` likewise.
#   (M) S1 — comments in a parameter list (`/* = 2 */`, trailing `//`) do not block the pairing.
#   (N) S2 — a declaration with matching types and defaults that the include proof cannot reach is disclosed as
#       defaults_untied= beside the flags.
#   (I) an unproven declaration (the definition's file does not include the header) lends no defaults.
#   (P) an attribute group in a class head (`struct alignas( 8 ) S`, `struct __attribute__(( packed )) S`,
#       `class __declspec( dllexport ) S`) is part of the head: the member's chain keeps `S`, so its declaration pairs.
#   (Q) a function-pointer parameter is a list this reader cannot parse: the declaration is Unproven, never Different, so
#       a caller relying on its default is disclosed by defaults_untied=; two overloads that both meet that one
#       declaration count it once.
#
# Operates on private temp git repos. Needs git and python3.
set -u
ROOT="$( cd "$( dirname "$0" )/.." && pwd )"
. "$ROOT/test/lib/clean-env.sh"
BIN="${1:-${RIPWIRE_BIN:-$ROOT/build/ripwire}}"
[ "${BIN#/}" = "$BIN" ] && BIN="$ROOT/$BIN"
fail=0
ok(){ printf '  PASS  %s\n' "$*" || { fail=1; printf '  FAIL  could not write the PASS line for: %s\n' "$*"; }; return 0; }
no(){ printf '  FAIL  %s\n' "$*"; fail=1; }

[ -x "$BIN" ] || { echo "no ripwire binary at $BIN — build first"; exit 2; }
command -v git >/dev/null 2>&1 || { echo "git required"; exit 2; }
command -v python3 >/dev/null 2>&1 || { echo "python3 required"; exit 2; }

TMP="$( mktemp -d )"; trap 'rm -rf "$TMP"' EXIT
echo "editcheckdeclcheck: BIN=$BIN"

commit(){ ( cd "$1" && git init -q && git config user.email t@t && git config user.name t && git add -A && git commit -qm init ) >/dev/null 2>&1 \
              || no "could not commit $1 — every arm on it would read no-baseline"; }
# ec <corpus> <selector> → the document on stdout (full legend), stderr to $TMP/err, exit code to $TMP/rc
ec(){ ( cd "$1" && "$BIN" . --no-cache --edit-check="$2" --legend=full 2>"$TMP/err"; echo $? >"$TMP/rc" ); }
rc(){ cat "$TMP/rc"; }
# the <edit-check …> root element, and one attribute off it (empty when absent)
root(){ printf '%s' "$1" | grep -oE '<edit-check [^>]*>' | head -1; }
attr(){ printf '%s' "$1" | python3 -c 'import re,sys; m=re.search(r"(?<![A-Za-z0-9_])"+re.escape(sys.argv[1])+r"=\"([^\"]*)\"",sys.stdin.read()); sys.stdout.write(m.group(1) if m else "")' "$2"; }
# the caller names flagged incompatible="1", comma-joined in document order
flagged(){ printf '%s' "$1" | python3 -c 'import re,sys; print(",".join(re.findall(r"<c n=\"([^\"]*)\"[^>]*incompatible=\"1\"",sys.stdin.read())))'; }
legend(){ printf '%s' "$1" | python3 -c 'import re,sys; m=re.match(r"\A(?:\s*<!--.*?-->)+",sys.stdin.read(),re.S); sys.stdout.write(m.group(0) if m else "")'; }

# ── the field-report corpus ───────────────────────────────────────────────────────────────────────────────
F="$TMP/field"; mkdir -p "$F"
printf 'int scale( int x, int factor = 2 );\n' >"$F/lib.h"
printf '#include "lib.h"\nint scale( int x, int factor )\n{\n    return x * factor;\n}\n' >"$F/lib.cpp"
printf '#include "lib.h"\nint a() { return scale( 1 ); }\nint b() { return scale( 2 ); }\nint c() { return scale( 3, 4 ); }\n' >"$F/use.cpp"
commit "$F"
printf 'int scale( int x, int factor = 2, int bias = 0 );\n' >"$F/lib.h"
printf '#include "lib.h"\nint scale( int x, int factor, int bias )\n{\n    return x * factor + bias;\n}\n' >"$F/lib.cpp"

echo "=== (A) R1: the bare name is one contract, not two ==="
OA="$( ec "$F" scale )"; RCA="$( rc )"; RA="$( root "$OA" )"
if [ "$RCA" = 0 ] && [ -n "$RA" ]; then
    ok "(A) --edit-check=scale answers (exit 0) instead of refusing a prototype and its definition as two contracts"
    case "$( attr "$RA" p )" in
        lib.cpp:2) ok "(A) the answer is about the definition (p=\"lib.cpp:2\")" ;;
        *)         no "(A) p=\"$( attr "$RA" p )\", expected the definition lib.cpp:2" ;;
    esac
    [ "$( attr "$RA" incompatible )" = 0 ] \
        && ok "(A) incompatible=\"0\": every call still binds through the header's defaults" \
        || no "(A) incompatible=\"$( attr "$RA" incompatible )\", expected 0 — flags: $( flagged "$OA" )"
else
    no "(A) --edit-check=scale exited $RCA: $( cat "$TMP/err" )"
fi

echo "=== (B) R2: the definition's handle reads the defaults off its declaration ==="
OB="$( ec "$F" ./lib.cpp:scale )"; RB="$( root "$OB" )"
if [ "$( rc )" = 0 ] && [ -n "$RB" ]; then
    [ "$( attr "$RB" incompatible )" = 0 ] && [ -z "$( flagged "$OB" )" ] \
        && ok "(B) incompatible=\"0\" and no caller row flagged (callers=\"$( attr "$RB" callers )\")" \
        || no "(B) incompatible=\"$( attr "$RB" incompatible )\" flags=[$( flagged "$OB" )] — the defaults on lib.h admit all three calls"
    [ "$( attr "$RB" callers )" = 3 ] && ok "(B) premise: callers=\"3\" (the arm is about three real call sites)" \
                                       || no "(B) premise broken: callers=\"$( attr "$RB" callers )\", expected 3"
    [ "$( attr "$RB" status )" = contract-change ] && [ "$( attr "$RB" params_now )" = 3 ] \
        && ok "(B) the edit is still reported: status=\"contract-change\" params_was=\"$( attr "$RB" params_was )\" params_now=\"3\"" \
        || no "(B) status=\"$( attr "$RB" status )\" params_now=\"$( attr "$RB" params_now )\" — the widened list must still read as a contract change"
    [ "$( attr "$RB" defaults_from )" = decl ] \
        && ok "(B) defaults_from=\"decl\" names where the arity range came from" \
        || no "(B) defaults_from=\"$( attr "$RB" defaults_from )\", expected decl"
    case "$( legend "$OB" )" in
        *'defaults_from='*) ok "(B) the legend defines defaults_from=" ;;
        *)                  no "(B) defaults_from= is emitted but not defined in the document's legend" ;;
    esac
else
    no "(B) --edit-check=./lib.cpp:scale exited $( rc ): $( cat "$TMP/err" )"
fi

echo "=== (C) R3: the header's handle is accepted and answers the same contract ==="
OC="$( ec "$F" ./lib.h:scale )"; RC3="$( root "$OC" )"
if [ "$( rc )" = 0 ] && [ -n "$RC3" ]; then
    ok "(C) --edit-check=./lib.h:scale answers (exit 0)"
    for k in p status incompatible callers defs; do
        [ "$( attr "$RC3" "$k" )" = "$( attr "$RB" "$k" )" ] \
            || no "(C) $k=\"$( attr "$RC3" "$k" )\" differs from the definition handle's \"$( attr "$RB" "$k" )\""
    done
    ok "(C) p/status/incompatible/callers/defs agree with --edit-check=./lib.cpp:scale"
else
    no "(C) --edit-check=./lib.h:scale exited $( rc ): $( cat "$TMP/err" )"
fi

echo "=== (D) the MCP twin answers the field-report shape the same way ==="
python3 - "$F" <<'PY' | "$BIN" --mcp >"$TMP/mcp.rpc" 2>/dev/null
import json, sys
print( json.dumps( { "jsonrpc": "2.0", "id": 1, "method": "initialize" } ) )
print( json.dumps( { "jsonrpc": "2.0", "id": 2, "method": "tools/call", "params": { "name": "edit_check", "arguments": { "path": sys.argv[1], "symbol": "scale", "legend": "full" } } } ) )
PY
OD="$( python3 -c '
import json,sys
lines=[l for l in open(sys.argv[1]).read().splitlines() if l.strip()]
r=json.loads(lines[-1]) if lines else {}
sys.stdout.write("__ERROR__:"+str(r.get("error",{}).get("message","no response")) if "result" not in r else r["result"]["content"][0]["text"])' "$TMP/mcp.rpc" 2>/dev/null )"
RD="$( root "$OD" )"
[ -n "$RD" ] && [ "$( attr "$RD" incompatible )" = 0 ] && [ "$( attr "$RD" defaults_from )" = decl ] \
    && ok "(D) MCP edit_check symbol=scale: incompatible=\"0\" defaults_from=\"decl\"" \
    || no "(D) MCP edit_check symbol=scale: ${OD:0:300}"

echo "=== (E) CONTROL: defaults never make a wildcard ==="
E="$TMP/over"; mkdir -p "$E"; cp "$F"/lib.h "$F"/lib.cpp "$F"/use.cpp "$E/"
printf 'int d() { return scale( 1, 2, 3, 4 ); }\n' >>"$E/use.cpp"
commit "$E"
OE="$( ec "$E" ./lib.cpp:scale )"; RE="$( root "$OE" )"
[ "$( attr "$RE" incompatible )" = 1 ] && [ "$( flagged "$OE" )" = d ] \
    && ok "(E) the 4-argument call to a 3-parameter scale is flagged, and only it (incompatible=\"1\", d)" \
    || no "(E) incompatible=\"$( attr "$RE" incompatible )\" flags=[$( flagged "$OE" )], expected 1 and [d]"

echo "=== (F) E3 decoy: real overloads stay two definitions, each with its own declaration's defaults ==="
D="$TMP/decoy"; mkdir -p "$D"
printf 'int scale( int x, int f = 2, int g = 3 );\ndouble scale( double x, double y, double z, double w );\n' >"$D/lib.h"
printf '#include "lib.h"\nint scale( int x, int f, int g ) { return x + f + g; }\ndouble scale( double x, double y, double z, double w ) { return x + y + z + w; }\n' >"$D/lib.cpp"
printf '#include "lib.h"\nint a1() { return scale( 1 ); }\nint a3() { return scale( 1, 2, 3 ); }\ndouble a4() { return scale( 1.0, 2.0, 3.0, 4.0 ); }\nint a5() { return scale( 1, 2, 3, 4, 5 ); }\n' >"$D/use.cpp"
commit "$D"
OF="$( ec "$D" scale )"; RF="$( root "$OF" )"
if [ "$( rc )" = 0 ] && [ -n "$RF" ]; then
    [ "$( attr "$RF" defs )" = 2 ] && [ "$( printf '%s' "$OF" | grep -oE '<def [^>]*params="[0-9]+"' | grep -oE 'params="[0-9]+"' | tr '\n' ' ' )" = 'params="3" params="4" ' ] \
        && ok "(F) defs=\"2\": the two overloads stay two definitions (params 3 and 4), the declarations fold beside them" \
        || no "(F) defs=\"$( attr "$RF" defs )\" def rows: $( printf '%s' "$OF" | grep -oE '<def [^>]*>' | tr '\n' ' ' )"
    [ "$( flagged "$OF" )" = a5 ] \
        && ok "(F) only the 5-argument call is flagged; the 1-argument call binds the int overload through ITS defaults" \
        || no "(F) flags=[$( flagged "$OF" )], expected [a5] — a1 flagged means the int overload's defaults went to the double one"
else
    no "(F) --edit-check=scale on two overloads exited $( rc ): $( cat "$TMP/err" )"
fi

echo "=== (G) a declaration whose parameter TYPES match no definition lends nothing ==="
G="$TMP/mismatch"; mkdir -p "$G"
printf 'int scale( int x, int f = 2 );\n' >"$G/lib.h"
printf '#include "lib.h"\nint scale( double x, int f ) { return int( x ) * f; }\n' >"$G/lib.cpp"
printf '#include "lib.h"\nint a1() { return scale( 1 ); }\n' >"$G/use.cpp"
commit "$G"
OG="$( ec "$G" ./lib.cpp:scale )"; RG="$( root "$OG" )"
[ "$( flagged "$OG" )" = a1 ] && [ -z "$( attr "$RG" defaults_from )" ] \
    && ok "(G) scale( double, int ) takes no defaults from scale( int, int = 2 ): a1 stays flagged, no defaults_from=" \
    || no "(G) flags=[$( flagged "$OG" )] defaults_from=\"$( attr "$RG" defaults_from )\" — a different parameter-type list is a different contract"
ec "$G" scale >/dev/null
[ "$( rc )" = 1 ] && grep -q 'Qualify one contract' "$TMP/err" \
    && ok "(G) the bare name stays refused: the declaration and the definition are two contracts here" \
    || no "(G) --edit-check=scale exited $( rc ), expected the ambiguity refusal: $( cat "$TMP/err" )"

echo "=== (H) E2: every handle the refusal prints is accepted on a rerun ==="
P="$TMP/platform"; mkdir -p "$P"
printf 'int scale( int x, int f = 2 );\n' >"$P/lib.h"
printf '#include "lib.h"\nint scale( int x, int f ) { return x * f; }\n' >"$P/posix.cpp"
printf '#include "lib.h"\nint scale( int x, int f ) { return x + f; }\n' >"$P/win.cpp"
printf '#include "lib.h"\nint a1() { return scale( 1 ); }\n' >"$P/use.cpp"
commit "$P"
# The handles a refusal lists, one per line: split on ", " (a quoted handle may hold a space), quotes removed.
handles(){ sed -n 's/.*Qualify one contract: \(.*\) — e\.g\..*/\1/p' "$TMP/err" | sed 's/ (+[^)]*)//g' | awk 'BEGIN{RS=", "} {sub(/\n$/,""); gsub(/^'"'"'|'"'"'$/,""); if (length) print}'; }
example(){ sed -n "s/.* — e\.g\. --edit-check=\(.*\)$/\1/p" "$TMP/err" | sed "s/^'//; s/'\$//"; }
roundTrip(){ # roundTrip <label> <corpus> <selector> <min callers every pasted handle must answer>
    ec "$2" "$3" >/dev/null
    if [ "$( rc )" != 1 ]; then no "$1: --edit-check=$3 exited $( rc ), expected the ambiguity refusal"; return; fi
    cp "$TMP/err" "$TMP/refusal"   # the reruns below overwrite $TMP/err; an arm that inspects the refusal reads this copy
    handles >"$TMP/handles"
    [ -s "$TMP/handles" ] || { no "$1: no handle list in the refusal: $( cat "$TMP/err" )"; return; }
    _ex="$( example )"
    grep -qxF -- "$_ex" "$TMP/handles" && ok "$1: the e.g. handle '$_ex' is one of the listed handles" \
                                       || no "$1: the e.g. handle '$_ex' is not among the listed handles: $( cat "$TMP/err" )"
    while IFS= read -r _h; do
        _o="$( ec "$2" "$_h" )"
        _c="$( attr "$( root "$_o" )" callers )"
        if [ "$( rc )" != 0 ] || [ -z "$( root "$_o" )" ]; then
            no "$1: suggested handle '$_h' is refused on rerun (exit $( rc )): $( cat "$TMP/err" )"
        elif ! [[ "$_c" =~ ^[0-9]+$ ]]; then
            no "$1: suggested handle '$_h' answers with no numeric callers= (\"$_c\"): a malformed answer"
        elif [ "$_c" -lt "$4" ]; then
            no "$1: suggested handle '$_h' answers callers=\"$( attr "$( root "$_o" )" callers )\" (want >= $4): a handle whose answer is not the definition's"
        else
            ok "$1: suggested handle '$_h' is accepted and answers callers=\"$( attr "$( root "$_o" )" callers )\""
        fi
    done <"$TMP/handles"
}
roundTrip "(H) mismatched types" "$G" scale 1
roundTrip "(H) two platform definitions" "$P" scale 1
# the pre-apply preview keeps one contract per file, so it still refuses the field corpus — and must not steer the reader to
# the declaration, whose own answer has no call edges (M2)
printf 'int scale( int x, int factor, int bias )\n{\n    return x;\n}\n' >"$TMP/payload.txt"
( cd "$F" && "$BIN" . --no-cache --edit-check=scale --edit-payload="$TMP/payload.txt" --dry-run >/dev/null 2>"$TMP/err" )
case "$( cat "$TMP/err" )" in
    *'lib.h'*'— e.g.'*) no "(H) the --dry-run refusal lists a handle for the declaration in lib.h: $( cat "$TMP/err" )" ;;
    *'Qualify one contract: ./lib.cpp:scale'*'declaration-only'*) ok "(H) the --dry-run refusal lists only the definition and counts the declaration-only contract" ;;
    *) no "(H) unexpected --dry-run answer: $( cat "$TMP/err" )" ;;
esac

echo "=== (J) M2: a header that drops a default, two platform definitions — no handle answers callers=\"0\" ==="
W="$TMP/pwbreak"; mkdir -p "$W"
printf 'int f( int x, int y = 0 );\n' >"$W/h.h"
printf '#include "h.h"\nint f( int x, int y ) { return x * y; }\n' >"$W/posix.cpp"
printf '#include "h.h"\nint f( int x, int y ) { return x + y; }\n' >"$W/win.cpp"
printf '#include "h.h"\nint a() { return f( 1 ); }\n' >"$W/use.cpp"
commit "$W"
printf 'int f( int x, int y );\n' >"$W/h.h"
roundTrip "(J) dropped default" "$W" f 1
case "$( cat "$TMP/refusal" )" in
    *'Qualify one contract:'*'h.h'*) no "(J) the refusal still lists a handle for h.h's declaration: $( cat "$TMP/refusal" )" ;;
    *'Qualify one contract:'*) ok "(J) no handle for the declaration-only contract" ;;
    *) no "(J) the saved refusal holds no handle list: $( cat "$TMP/refusal" )" ;;
esac
OW="$( ec "$W" ./posix.cpp:f )"
[ "$( flagged "$OW" )" = a ] && ok "(J) the definition's handle flags the call the dropped default broke" \
                               || no "(J) ./posix.cpp:f flags=[$( flagged "$OW" )], expected [a]"

echo "=== (K) M3: a path that is a suffix of another, and a path with a space — every handle is unique ==="
X="$TMP/suffix"; mkdir -p "$X/sub" "$X/my dir" "$X/other dir/my dir"
printf 'int sc( int x ) { return x; }\n' >"$X/lib.cpp"
printf 'int sc( int x, int y ) { return x + y; }\n' >"$X/sub/lib.cpp"
printf 'int sp( int x ) { return x; }\n' >"$X/my dir/a b.cpp"
printf 'int sp( int x, int y ) { return x - y; }\n' >"$X/other dir/my dir/a b.cpp"
printf 'int sc( int x );\nint sp( int x );\nint u() { return sc( 1 ) + sp( 1 ); }\n' >"$X/use.cpp"
commit "$X"
roundTrip "(K) suffix-overlapping paths" "$X" sc 0
roundTrip "(K) paths with a space" "$X" sp 0
OK1="$( ec "$X" ./lib.cpp:sc )"
[ "$( attr "$( root "$OK1" )" p )" = lib.cpp:1 ] && ok "(K) ./lib.cpp:sc answers lib.cpp, not sub/lib.cpp" \
                                                 || no "(K) ./lib.cpp:sc answered p=\"$( attr "$( root "$OK1" )" p )\" (exit $( rc ))"

OP="$( ec "$P" ./posix.cpp:scale )"
[ "$( attr "$( root "$OP" )" defaults_from )" = decl ] && [ -z "$( flagged "$OP" )" ] \
    && ok "(H) each platform definition still takes the shared header's defaults (posix.cpp: defaults_from=\"decl\", nothing flagged)" \
    || no "(H) ./posix.cpp:scale: flags=[$( flagged "$OP" )] defaults_from=\"$( attr "$( root "$OP" )" defaults_from )\""

echo "=== (L) M1: the FULL scope chain is the identity — a same-named innermost scope is a different function ==="
# lone <label> <corpus> <selector> <want flagged> — the definition takes no default from a declaration in another scope chain
lone(){
    _o="$( ec "$2" "$3" )"; _r="$( root "$_o" )"
    if [ -n "$_r" ] && [ "$( flagged "$_o" )" = "$4" ] && [ -z "$( attr "$_r" defaults_from )" ]; then
        ok "$1: $3 flags [$4] and borrows no default (no defaults_from=)"
    elif [ -z "$_r" ] && [ "$( rc )" = 1 ] && grep -q 'is ambiguous' "$TMP/err"; then
        ok "$1: $3 is refused as more than one contract (no answer, so no false zero)"
    else
        no "$1: $3 flags=[$( flagged "$_o" )] defaults_from=\"$( attr "$_r" defaults_from )\" (exit $( rc )) — a declaration in another scope chain lent its default"
    fi
}
N1="$TMP/detail"; mkdir -p "$N1"
printf 'namespace outer { namespace detail { int f( int x, int y, int z = 0 ); } }\n' >"$N1/outer.h"
printf '#include "outer.h"\nnamespace detail { int f( int x, int y ) { return x + y; } }\n' >"$N1/impl.cpp"
printf '#include "outer.h"\nint a() { return detail::f( 1, 2 ); }\n' >"$N1/use.cpp"
commit "$N1"
printf '#include "outer.h"\nnamespace detail { int f( int x, int y, int z ) { return x + y + z; } }\n' >"$N1/impl.cpp"
lone "(L) DETAIL outer::detail::f vs ::detail::f" "$N1" ./impl.cpp:f a
ec "$N1" f >/dev/null
[ "$( rc )" = 1 ] && ok "(L) DETAIL: the bare name stays refused — two functions, two contracts" \
                   || no "(L) DETAIL: --edit-check=f exited $( rc ) — outer::detail::f was folded into ::detail::f"
N2="$TMP/nsnest"; mkdir -p "$N2"
printf 'namespace outer { namespace a { int f( int x, int y = 0 ); } }\nnamespace a { int f( int x, int y ); }\n' >"$N2/h.h"
printf '#include "h.h"\nnamespace a { int f( int x, int y ) { return x + y; } }\n' >"$N2/a.cpp"
printf '#include "h.h"\nint u() { return a::f( 1 ); }\n' >"$N2/use.cpp"
commit "$N2"
lone "(L) NSNEST outer::a::f vs ::a::f" "$N2" ./a.cpp:f u
lone "(L) NSNEST, through the header's handle" "$N2" ./h.h:f u
N3="$TMP/nest2"; mkdir -p "$N3"
printf 'struct Outer { struct S { int f( int x, int y, int z = 0 ); }; };\nstruct S { int f( int x, int y, int z ); };\n' >"$N3/s.h"
printf '#include "s.h"\nint S::f( int x, int y, int z ) { return x + y + z; }\n' >"$N3/n.cpp"
printf '#include "s.h"\nint u( S& s ) { return s.f( 1, 2 ); }\n' >"$N3/use.cpp"
commit "$N3"
lone "(L) NEST2 Outer::S::f vs ::S::f" "$N3" ./n.cpp:f u
N4="$TMP/constq"; mkdir -p "$N4"
printf 'struct S\n{\n    int f( int x, int y, int z = 0 );\n    int f( int x, int y, int z ) const;\n};\n' >"$N4/s.h"
printf '#include "s.h"\nint S::f( int x, int y, int z ) const { return x + y + z; }\n' >"$N4/s.cpp"
printf '#include "s.h"\nint u( const S& s ) { return s.f( 1, 2 ); }\n' >"$N4/use.cpp"
commit "$N4"
lone "(L) CONSTQ: the const member takes no default from the non-const declaration" "$N4" ./s.cpp:f u
# CONTROL: the same chain spelled two ways still pairs — namespace block in the header, qualified out-of-line definition
N5="$TMP/nsok"; mkdir -p "$N5"
printf 'namespace outer { namespace detail { int f( int x, int y, int z = 0 ); } }\n' >"$N5/outer.h"
printf '#include "outer.h"\nint outer::detail::f( int x, int y, int z ) { return x + y + z; }\n' >"$N5/impl.cpp"
printf '#include "outer.h"\nint a() { return outer::detail::f( 1, 2 ); }\n' >"$N5/use.cpp"
commit "$N5"
ON5="$( ec "$N5" ./impl.cpp:f )"
[ "$( attr "$( root "$ON5" )" defaults_from )" = decl ] && [ -z "$( flagged "$ON5" )" ] \
    && ok "(L) CONTROL: outer::detail::f declared in a namespace block and defined qualified out of line still pairs" \
    || no "(L) CONTROL: ./impl.cpp:f flags=[$( flagged "$ON5" )] defaults_from=\"$( attr "$( root "$ON5" )" defaults_from )\""

echo "=== (O) a namespace opened by a MACRO: the chain is unreadable, never paired, and disclosed ==="
MA="$TMP/macrons"; mkdir -p "$MA"
printf '#define NS_BEGIN namespace outer {\n#define NS_END }\nNS_BEGIN\nint f( int x, int y, int z = 0 );\nNS_END\n' >"$MA/h.h"
printf '#include "h.h"\nint f( int x, int y ) { return x + y; }\n' >"$MA/impl.cpp"
printf '#include "h.h"\nint a() { return f( 1, 2 ); }\n' >"$MA/use.cpp"
commit "$MA"
printf '#include "h.h"\nint f( int x, int y, int z ) { return x + y + z; }\n' >"$MA/impl.cpp"
OMA="$( ec "$MA" ./impl.cpp:f )"; RMA="$( root "$OMA" )"
if [ "$( flagged "$OMA" )" = a ] && [ -z "$( attr "$RMA" defaults_from )" ] && [ "$( attr "$RMA" defaults_untied )" = 1 ]; then
    ok "(O) MACRO: outer::f behind NS_BEGIN lends nothing to ::f (a flagged, defaults_untied=\"1\")"
else
    no "(O) MACRO: flags=[$( flagged "$OMA" )] defaults_from=\"$( attr "$RMA" defaults_from )\" defaults_untied=\"$( attr "$RMA" defaults_untied )\""
fi
ec "$MA" f >/dev/null
[ "$( rc )" = 1 ] && ok "(O) MACRO: the bare name stays refused — not silently merged" \
                   || no "(O) MACRO: --edit-check=f exited $( rc ) — the macro-opened declaration was folded into ::f"
MB="$TMP/macroext"; mkdir -p "$MB"
printf 'QT_BEGIN_NAMESPACE\nint f( int x, int y, int z = 0 );\nQT_END_NAMESPACE\n' >"$MB/h.h"
cp "$MA/use.cpp" "$MB/use.cpp"; printf '#include "h.h"\nint f( int x, int y, int z ) { return x + y + z; }\n' >"$MB/impl.cpp"
commit "$MB"
OMB="$( ec "$MB" ./impl.cpp:f )"
[ "$( flagged "$OMB" )" = a ] && [ -z "$( attr "$( root "$OMB" )" defaults_from )" ] \
    && ok "(O) a scope macro defined in ANOTHER header (QT_BEGIN_NAMESPACE) is unreadable too" \
    || no "(O) QT_BEGIN_NAMESPACE: flags=[$( flagged "$OMB" )] defaults_from=\"$( attr "$( root "$OMB" )" defaults_from )\""
US="$TMP/usingns"; mkdir -p "$US"
printf 'namespace outer { struct S { int f( int x, int y, int z = 0 ); }; }\n' >"$US/s.h"
printf '#include "s.h"\nusing namespace outer;\nint S::f( int x, int y, int z ) { return x + y + z; }\n' >"$US/s.cpp"
printf '#include "s.h"\nint u( outer::S& s ) { return s.f( 1, 2 ); }\n' >"$US/use.cpp"
commit "$US"
OUS="$( ec "$US" ./s.cpp:f )"; RUS="$( root "$OUS" )"
if [ -z "$( flagged "$OUS" )" ] || [ "$( attr "$RUS" defaults_untied )" = 1 ]; then
    ok "(O) USING: S::f after using namespace outer is never a silent false flag (flags=[$( flagged "$OUS" )] defaults_untied=\"$( attr "$RUS" defaults_untied )\")"
else
    no "(O) USING: flags=[$( flagged "$OUS" )] with no defaults_untied= — the using-directive reading is silent"
fi

echo "=== (M) S1: comments inside a parameter list do not block the pairing ==="
C1="$TMP/cmt"; mkdir -p "$C1"
printf 'int scale( int x, int factor = 2 );\n' >"$C1/lib.h"
printf '#include "lib.h"\nint scale( int x, int factor /* = 2 */ ) { return x * factor; }\n' >"$C1/lib.cpp"
printf '#include "lib.h"\nint a() { return scale( 1 ); }\n' >"$C1/use.cpp"
commit "$C1"
OC1="$( ec "$C1" ./lib.cpp:scale )"
[ "$( attr "$( root "$OC1" )" defaults_from )" = decl ] && [ -z "$( flagged "$OC1" )" ] \
    && ok "(M) a /* = 2 */ reminder on the definition: paired, nothing flagged" \
    || no "(M) CMT: flags=[$( flagged "$OC1" )] defaults_from=\"$( attr "$( root "$OC1" )" defaults_from )\""
C2="$TMP/cmtml"; mkdir -p "$C2"
printf 'int scale( int x,      // the value\n           int factor = 2 // the multiplier, (a, b)\n         );\n' >"$C2/lib.h"
printf '#include "lib.h"\nint scale( int x, int factor ) { return x * factor; }\n' >"$C2/lib.cpp"
printf '#include "lib.h"\nint a() { return scale( 1 ); }\n' >"$C2/use.cpp"
commit "$C2"
OC2="$( ec "$C2" ./lib.cpp:scale )"
[ "$( attr "$( root "$OC2" )" defaults_from )" = decl ] && [ -z "$( flagged "$OC2" )" ] \
    && ok "(M) a multi-line declaration with trailing // comments: paired, nothing flagged" \
    || no "(M) CMTML: flags=[$( flagged "$OC2" )] defaults_from=\"$( attr "$( root "$OC2" )" defaults_from )\""

echo "=== (N) S2: a declaration the include proof cannot reach is disclosed beside the flags it might admit ==="
T1="$TMP/trans"; mkdir -p "$T1"
printf 'int scale( int x, int factor = 2 );\n' >"$T1/lib.h"
printf '#include "lib.h"\n' >"$T1/mid.h"
printf '#include "mid.h"\nint scale( int x, int factor ) { return x * factor; }\n' >"$T1/lib.cpp"
printf '#include "lib.h"\nint a() { return scale( 1 ); }\n' >"$T1/use.cpp"
commit "$T1"
OT1="$( ec "$T1" ./lib.cpp:scale )"; RT1="$( root "$OT1" )"
if [ "$( flagged "$OT1" )" = a ] && [ "$( attr "$RT1" defaults_untied )" = 1 ] && [ -z "$( attr "$RT1" defaults_from )" ]; then
    ok "(N) TRANS: the transitive include is not proven (a stays flagged) and defaults_untied=\"1\" says a default may admit it"
else
    no "(N) TRANS: flags=[$( flagged "$OT1" )] defaults_untied=\"$( attr "$RT1" defaults_untied )\" defaults_from=\"$( attr "$RT1" defaults_from )\""
fi
case "$( legend "$OT1" )" in *'defaults_untied='*) ok "(N) the legend defines defaults_untied=" ;; *) no "(N) defaults_untied= is not defined in the legend" ;; esac
[ -z "$( attr "$( root "$OB" )" defaults_untied )" ] && ok "(N) absent where every declaration was tied (the field corpus)" \
                                                    || no "(N) the field corpus carries defaults_untied="

echo "=== (I) an UNPROVEN declaration (no #include of it) lends no defaults ==="
U="$TMP/unproven"; mkdir -p "$U"
printf 'int scale( int x, int f = 2 );\n' >"$U/lib.h"
printf 'int scale( int x, int f ) { return x * f; }\n' >"$U/lib.cpp"
printf '#include "lib.h"\nint a1() { return scale( 1 ); }\n' >"$U/use.cpp"
commit "$U"
OU="$( ec "$U" ./lib.cpp:scale )"
[ "$( flagged "$OU" )" = a1 ] && [ -z "$( attr "$( root "$OU" )" defaults_from )" ] \
    && ok "(I) lib.cpp does not include lib.h: no defaults are borrowed, a1 stays flagged (the safe direction)" \
    || no "(I) flags=[$( flagged "$OU" )] defaults_from=\"$( attr "$( root "$OU" )" defaults_from )\""

echo "=== (P) an attribute group in a class head is part of the head, not a cancel ==="
attrHead(){ # attrHead <label> <head spelling>
    _d="$TMP/attrhead-$1"; mkdir -p "$_d"
    printf '%s\n{\n    int f( int x, int y = 2 );\n};\n' "$2" >"$_d/lib.h"
    printf '#include "lib.h"\nint S::f( int x, int y )\n{\n    return x + y;\n}\n' >"$_d/lib.cpp"
    printf '#include "lib.h"\nint a() { S s; return s.f( 1 ); }\n' >"$_d/use.cpp"
    commit "$_d"
    _o="$( ec "$_d" ./lib.cpp:f )"; _r="$( root "$_o" )"
    if [ -n "$_r" ] && [ -z "$( flagged "$_o" )" ] && [ "$( attr "$_r" defaults_from )" = decl ]; then
        ok "(P) '$2': the member declaration pairs with S::f (no flag, defaults_from=\"decl\")"
    else
        no "(P) '$2': flags=[$( flagged "$_o" )] defaults_from=\"$( attr "$_r" defaults_from )\" defaults_untied=\"$( attr "$_r" defaults_untied )\""
    fi
}
attrHead alignas 'struct alignas( 8 ) S'
attrHead gnu 'struct __attribute__(( packed )) S'
attrHead declspec 'class __declspec( dllexport ) S'

echo "=== (Q) a function-pointer parameter: Unproven and disclosed, counted once across overloads ==="
Q="$TMP/fnptr"; mkdir -p "$Q"
printf 'void on( int (*)( int ), int n = 0 );\n' >"$Q/lib.h"
printf '#include "lib.h"\nvoid on( int (*cb)( int ), int n )\n{\n    cb( n );\n}\n' >"$Q/lib.cpp"
printf '#include "lib.h"\nint g( int );\nvoid a() { on( g ); }\n' >"$Q/use.cpp"
commit "$Q"
OQ="$( ec "$Q" ./lib.cpp:on )"; RQ="$( root "$OQ" )"
[ "$( attr "$RQ" defaults_untied )" = 1 ] \
    && ok "(Q) the 1-argument call stays flagged and defaults_untied=\"1\" says the unparsed declaration may admit it" \
    || no "(Q) flags=[$( flagged "$OQ" )] defaults_untied=\"$( attr "$RQ" defaults_untied )\" (want 1)"
Q2="$TMP/fnptr2"; mkdir -p "$Q2"
printf 'void on( int (*)( int ), int n = 0 );\n' >"$Q2/lib.h"
printf '#include "lib.h"\nvoid on( int (*cb)( int ), int n )\n{\n    cb( n );\n}\nvoid on( double d, int n )\n{\n}\n' >"$Q2/lib.cpp"
printf '#include "lib.h"\nint g( int );\nvoid a() { on( g ); }\n' >"$Q2/use.cpp"
commit "$Q2"
OQ2="$( ec "$Q2" ./lib.cpp:on )"; RQ2="$( root "$OQ2" )"
[ "$( attr "$RQ2" defs )" = 2 ] && [ "$( attr "$RQ2" defaults_untied )" = 1 ] \
    && ok "(Q) two overloads that both meet the one unparsed declaration count it once (defs=\"2\" defaults_untied=\"1\")" \
    || no "(Q) defs=\"$( attr "$RQ2" defs )\" defaults_untied=\"$( attr "$RQ2" defaults_untied )\" (want 2 and 1: one declaration)"

echo "=== determinism + well-formedness ==="
O2="$( ec "$F" ./lib.cpp:scale )"
if [ "$O2" = "$OB" ]; then ok "GUARD: two runs byte-identical"; else no "GUARD: two runs differ"; fi
if command -v xmllint >/dev/null 2>&1; then
    if printf '%s' "$OB" | xmllint --noout - 2>/dev/null; then ok "GUARD: XML well-formed"; else no "GUARD: XML malformed"; fi
fi

[ "$fail" = 0 ] && echo "ALL PASS" || echo "FAILURES ABOVE"
exit "$fail"
