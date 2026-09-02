#!/usr/bin/env bash
# slicecheck.sh — gate for --slice=SYM[:VAR]: the NAME-BASED intra-procedural def-use slice of one
# variable inside ONE uniquely-resolved definition (motivated by ARISE, arXiv:2605.03117 — statement-
# level def-use edges exposed as a queryable agent primitive). Bare --slice=SYM lists the sliceable
# locals so a caller can pick VAR.
#
# RED-FIRST PROOF SHAPE: every arm below asserts slice-SPECIFIC bytes (an attribute on the <slice>
# element, a row kind, a refusal sentence this verb alone prints) — never a bare exit code. The
# baseline binary refuses `--slice=…` as an unknown flag at exit 1 with NO XML and NONE of these
# sentences, so each arm fails against it; asserting "nonzero exit" alone would be green-while-inert
# against that baseline (the trap CONTRIBUTING §2 names).
#
# Arms:
#   (1)  C++ def/use classification: decl / both (+=) / call-arg / read rows, defs=/uses= counts
#   (1b) C++ direct-initialization ctor args: `Wrap w( seed, … );` — tree-sitter-cpp resolves this to
#        the most-vexing parse (function_declarator + parameter_declarations, each bare argument a
#        type_identifier), so the arguments must still row as call-arg uses
#   (2)  parameter classification: a param occurrence rows t="param" k="def"
#   (3)  Python classification: assign defs + call-arg use
#   (4)  bare --slice=SYM inventory: <v n= l= t=/> rows, vars= count
#   (5)  ambiguity refusal: same-named fn in two files -> exit 1 + file:name spellings; qualified retry works
#   (6)  unknown-var refusal: exit 1, names the sliceable locals
#   (7)  unsupported-language refusal: exit 1, "not served for" (never an empty success)
#   (8)  unknown-symbol refusal: exit 1, the shared not-found message
#   (9)  determinism (x3, byte-identical)
#   (10) xmllint well-formedness (both modes)
#   (11) keyword-local exclusion: a degraded parse must never offer a reserved word as a sliceable
#        local (inventory clean of it, slicing it refuses) — the ugrep matcher.cpp misparse shape
#   (12) C++ condition declaration `if( int k = x )`: tree-sitter-cpp emits a `declaration` whose
#        initializer sits in a `value` field with NO init_declarator, so x must row as a READ of x
#        (and k as its decl) — a false def here is a false binding after scope separation
#
# Usage:  RIPWIRE_BIN=build/ripwire bash test/slicecheck.sh   |   bash test/slicecheck.sh path/to/ripwire

set -u
ROOT="$( cd "$( dirname "$0" )/.." && pwd )"
BIN="${1:-${RIPWIRE_BIN:-$ROOT/build/ripwire}}"
[ "${BIN#/}" = "$BIN" ] && BIN="$ROOT/$BIN"
fail=0
ok(){ printf '  PASS  %s\n' "$*"; }
no(){ printf '  FAIL  %s\n' "$*"; fail=1; }

[ -x "$BIN" ] || { echo "no ripwire binary at $BIN — build first"; exit 2; }

WORK="$( mktemp -d )"; trap 'rm -rf "$WORK"' EXIT
mkdir -p "$WORK/src"

# C++ fixture. accumulate(): count decl'd, compound-assigned (def+use on one line), passed as a call
# arg, and read in the return. limit is a parameter, reassigned once. sink() exists so a call-arg row
# has a callee. shadowed() holds a nested-scope redeclaration of `n` — the disclosed over-include.
cat > "$WORK/src/a.cpp" <<'EOF'
void sink( int v );

int accumulate( int limit )
{
    int count = 0;
    count += limit;
    sink( count );
    return count;
}

int reassign( int limit )
{
    limit = limit + 1;
    return limit;
}

int shadowed( int n )
{
    if( n > 0 )
    {
        int n = 2;
        sink( n );
    }
    return n;
}
EOF

# C++ direct-initialization fixture, mirroring the duckdb Prefix::TransformToDeprecated drop (EVALS
# --slice-flow rung 2, finding D1): `Wrap w( seed, extra, true, true );` is the most-vexing parse —
# tree-sitter-cpp emits declaration → function_declarator → parameter_list, each bare argument a
# parameter_declaration whose TYPE is a type_identifier (even `true`), not an identifier.
cat > "$WORK/src/di.cpp" <<'EOF'
struct Wrap
{
    Wrap( int a, int b, bool c, bool d );
};

int directinit( int seed, int extra )
{
    Wrap w( seed, extra, true, true );
    return seed + extra;
}
EOF

# the ambiguity pair: one name, two definition sites in two files
cat > "$WORK/src/dupA.cpp" <<'EOF'
int duplicated( int a )
{
    int total = a;
    return total;
}
EOF
cat > "$WORK/src/dupB.cpp" <<'EOF'
int duplicated( int b )
{
    int total = b + 1;
    return total;
}
EOF

# Python fixture
cat > "$WORK/src/calc.py" <<'EOF'
def calc(n):
    total = 0
    total += n
    print(total)
    return total
EOF

# a degraded-parse C++ fixture: the preprocessor guard swallows the `if`, leaving a bare `else if`
# chain that tree-sitter-cpp error recovery reads as a DECLARATION whose declarator is the identifier
# `if` (the ugrep lib/matcher.cpp shape — EVALS "--slice-flow — ARISE rung 2" finding D2). Without the
# reserved-word exclusion the inventory offers <v n="if" t="decl"/> and --slice=kwprobe:if "succeeds".
cat > "$WORK/src/degraded.cpp" <<'EOF'
void g();

void kwprobe( int n )
{
    int count = 0;
#if defined(FAST_PATH)
    if( n == 1 ) { g(); }
#endif
    else if( n == 2 ) { count += 1; }
    else if( n == 3 ) { count += 2; }
    g();
}
EOF

# an indexed language --slice does NOT serve yet
cat > "$WORK/src/r.rb" <<'EOF'
def rubyfn(x)
  y = x + 1
  y
end
EOF

# arm (12)'s fuel: the C++17-style condition declaration. `if( int k = x )` parses as condition_clause
# -> declaration{ type, declarator: k, value: x } — no init_declarator — and the pre-fix classifier read
# every non-type child of a declaration as a declarator, minting a false def of x (found 2026-09-02
# while separating block scopes: the false def became a bogus binding of x at that line).
cat > "$WORK/src/cond.cpp" <<'EOF'
int condread( int x )
{
    if( int k = x ) { x = k; }
    while( int m = x ) { x = m; }
    return x;
}
EOF

echo "slicecheck: BIN=$BIN  (temp corpus, no git)"

sl(){ ( cd "$WORK" && "$BIN" . --slice="$1" --no-cache 2>/dev/null ); }
slrc(){ ( cd "$WORK" && "$BIN" . --slice="$1" --no-cache >/dev/null 2>&1 ); echo $?; }
slerr(){ ( cd "$WORK" && "$BIN" . --slice="$1" --no-cache 2>&1 >/dev/null ); }
# The leading <!-- … --> legend prose-describes attributes with worked examples in quotes, so a naive
# whole-output grep can false-positive on the LEGEND instead of the real element (the editcheckcheck/
# safedeletecheck rows() trap). Strip up to the element's own opening tag first.
elem(){ printf '%s' "$1" | sed 's/.*--><slice/<slice/'; }
attr(){ printf '%s' "$( elem "$1" )" | grep -oE "^<slice [^>]*" | grep -oE "$2=\"[^\"]*\"" | head -1; }
row(){ printf '%s' "$( elem "$1" )" | grep -oE "<s l=\"$2\"[^>]*>"; }

# ── (1) C++ def/use classification on accumulate:count ──────────────────────────────────────────────
OUT1="$( sl accumulate:count )"
[ "$( attr "$OUT1" var )" = 'var="count"' ] \
    && ok "(1) accumulate:count — <slice var=\"count\"> element present" \
    || { no "(1) expected a <slice var=\"count\"> element"; printf '%s\n' "$OUT1"; }
printf '%s' "$( row "$OUT1" 5 )" | grep -q 'k="def" t="decl"' \
    && ok "(1) line 5 'int count = 0;' rows k=def t=decl" \
    || { no "(1) line 5 should row k=\"def\" t=\"decl\""; printf '%s\n' "$OUT1"; }
printf '%s' "$( row "$OUT1" 6 )" | grep -q 'k="both"' \
    && ok "(1) line 6 'count += limit;' rows k=both (compound assignment reads and writes)" \
    || { no "(1) line 6 should row k=\"both\""; printf '%s\n' "$OUT1"; }
printf '%s' "$( row "$OUT1" 7 )" | grep -q 'k="use" t="call-arg"' \
    && ok "(1) line 7 'sink( count );' rows k=use t=call-arg" \
    || { no "(1) line 7 should row k=\"use\" t=\"call-arg\""; printf '%s\n' "$OUT1"; }
printf '%s' "$( row "$OUT1" 8 )" | grep -q 'k="use" t="read"' \
    && ok "(1) line 8 'return count;' rows k=use t=read" \
    || { no "(1) line 8 should row k=\"use\" t=\"read\""; printf '%s\n' "$OUT1"; }
[ "$( attr "$OUT1" defs )" = 'defs="2"' ] && [ "$( attr "$OUT1" uses )" = 'uses="3"' ] \
    && ok "(1) occurrence counts: defs=2 (decl, +=) uses=3 (+=, call-arg, return)" \
    || { no "(1) expected defs=\"2\" uses=\"3\""; printf '%s\n' "$OUT1"; }
printf '%s' "$OUT1" | grep -q 'int count = 0;' \
    && ok "(1) the def row carries the trimmed statement line in CDATA" \
    || { no "(1) expected the CDATA payload 'int count = 0;'"; printf '%s\n' "$OUT1"; }
printf '%s' "$OUT1" | grep -q 'no alias analysis' \
    && ok "(1) the legend states the name-based limits (no alias analysis)" \
    || { no "(1) legend should disclose 'no alias analysis'"; printf '%s\n' "$OUT1"; }

# ── (1b) direct-initialization ctor args survive the most-vexing parse ──────────────────────────────
OUT1B="$( sl directinit:seed )"
printf '%s' "$( row "$OUT1B" 8 )" | grep -q 'k="use" t="call-arg"' \
    && ok "(1b) directinit:seed — 'Wrap w( seed, … );' rows k=use t=call-arg despite the most-vexing parse" \
    || { no "(1b) line 8 'Wrap w( seed, … );' should row k=\"use\" t=\"call-arg\""; printf '%s\n' "$OUT1B"; }
[ "$( attr "$OUT1B" defs )" = 'defs="1"' ] && [ "$( attr "$OUT1B" uses )" = 'uses="2"' ] \
    && ok "(1b) occurrence counts: defs=1 (param) uses=2 (ctor-arg, return)" \
    || { no "(1b) expected defs=\"1\" uses=\"2\""; printf '%s\n' "$OUT1B"; }
OUT1C="$( sl directinit:extra )"
printf '%s' "$( row "$OUT1C" 8 )" | grep -q 'k="use" t="call-arg"' \
    && ok "(1b) directinit:extra — the second ctor argument rows k=use t=call-arg too (systematic, not positional)" \
    || { no "(1b) line 8 should row k=\"use\" t=\"call-arg\" for extra as well"; printf '%s\n' "$OUT1C"; }

# ── (2) parameter classification ────────────────────────────────────────────────────────────────────
OUT2="$( sl reassign:limit )"
printf '%s' "$( elem "$OUT2" )" | grep -q 'k="def" t="param"' \
    && ok "(2) reassign:limit — the parameter occurrence rows k=def t=param" \
    || { no "(2) expected a k=\"def\" t=\"param\" row"; printf '%s\n' "$OUT2"; }
printf '%s' "$( row "$OUT2" 13 )" | grep -q 'k="both" t="assign"' \
    && ok "(2) 'limit = limit + 1;' rows k=both t=assign (write left, read right, one line)" \
    || { no "(2) line 13 should row k=\"both\" t=\"assign\""; printf '%s\n' "$OUT2"; }

# ── (3) Python classification ───────────────────────────────────────────────────────────────────────
OUT3="$( sl calc:total )"
printf '%s' "$( row "$OUT3" 2 )" | grep -q 'k="def" t="assign"' \
    && ok "(3) calc:total — 'total = 0' rows k=def t=assign" \
    || { no "(3) python line 2 should row k=\"def\" t=\"assign\""; printf '%s\n' "$OUT3"; }
printf '%s' "$( row "$OUT3" 3 )" | grep -q 'k="both"' \
    && ok "(3) 'total += n' rows k=both" \
    || { no "(3) python line 3 should row k=\"both\""; printf '%s\n' "$OUT3"; }
printf '%s' "$( row "$OUT3" 4 )" | grep -q 'k="use" t="call-arg"' \
    && ok "(3) 'print(total)' rows k=use t=call-arg" \
    || { no "(3) python line 4 should row k=\"use\" t=\"call-arg\""; printf '%s\n' "$OUT3"; }
[ "$( attr "$OUT3" lang )" = 'lang="py"' ] \
    && ok "(3) the element carries lang=\"py\"" \
    || { no "(3) expected lang=\"py\""; printf '%s\n' "$OUT3"; }

# ── (4) bare --slice=SYM: the sliceable-locals inventory ────────────────────────────────────────────
OUT4="$( sl accumulate )"
[ "$( attr "$OUT4" vars )" = 'vars="2"' ] \
    && ok "(4) accumulate inventory: vars=2 (limit, count)" \
    || { no "(4) expected vars=\"2\""; printf '%s\n' "$OUT4"; }
printf '%s' "$( elem "$OUT4" )" | grep -q '<v n="count" l="5" t="decl"/>' \
    && ok "(4) inventory rows count at its first-def line 5" \
    || { no "(4) expected <v n=\"count\" l=\"5\" t=\"decl\"/>"; printf '%s\n' "$OUT4"; }
printf '%s' "$( elem "$OUT4" )" | grep -q '<v n="limit" l="3" t="param"/>' \
    && ok "(4) inventory rows the parameter limit at line 3" \
    || { no "(4) expected <v n=\"limit\" l=\"3\" t=\"param\"/>"; printf '%s\n' "$OUT4"; }

# ── (5) ambiguity refusal: two definition sites, spellings offered, qualified retry works ───────────
# Each refusal arm below fuses the exit code AND the slice-specific sentence into ONE assertion: the
# baseline refuses every spelling at exit 1 too ("unknown flag"), so a bare exit-code check would be
# green-while-inert against it.
ERR5="$( slerr duplicated:total )"
[ "$( slrc duplicated:total )" != 0 ] \
    && printf '%s' "$ERR5" | grep -q 'dupA.cpp:duplicated' && printf '%s' "$ERR5" | grep -q 'dupB.cpp:duplicated' \
    && ok "(5) duplicated:total (two definition sites): nonzero exit + both file:name spellings listed" \
    || { no "(5) an ambiguous SYM should refuse and list dupA.cpp:duplicated / dupB.cpp:duplicated"; printf '%s\n' "$ERR5"; }
OUT5="$( sl dupA.cpp:duplicated:total )"
[ "$( attr "$OUT5" var )" = 'var="total"' ] \
    && ok "(5) the file-qualified retry (dupA.cpp:duplicated:total) resolves" \
    || { no "(5) file-qualified retry should emit <slice var=\"total\">"; printf '%s\n' "$OUT5"; }

# ── (6) unknown-var refusal names the sliceable locals ──────────────────────────────────────────────
ERR6="$( slerr accumulate:nonesuchvar )"
[ "$( slrc accumulate:nonesuchvar )" != 0 ] \
    && printf '%s' "$ERR6" | grep -q 'sliceable locals' && printf '%s' "$ERR6" | grep -q 'count' \
    && ok "(6) accumulate:nonesuchvar — nonzero exit + the sliceable locals offered (count)" \
    || { no "(6) an unknown VAR should refuse and offer the sliceable locals incl. count"; printf '%s\n' "$ERR6"; }

# ── (7) unsupported-language refusal — honest, never an empty success ───────────────────────────────
ERR7="$( slerr rubyfn:y )"
[ "$( slrc rubyfn:y )" != 0 ] \
    && printf '%s' "$ERR7" | grep -q 'not served for' \
    && ok "(7) rubyfn:y (Ruby): nonzero exit + a 'not served for' refusal" \
    || { no "(7) an unserved language should refuse with 'not served for', never empty-succeed"; printf '%s\n' "$ERR7"; }

# ── (8) unknown symbol: the shared selector not-found refusal ───────────────────────────────────────
ERR8="$( slerr totallyMadeUpSymXYZ )"
[ "$( slrc totallyMadeUpSymXYZ )" != 0 ] \
    && printf '%s' "$ERR8" | grep -q 'matched no symbol' \
    && ok "(8) unknown symbol: nonzero exit + the shared not-found refusal" \
    || { no "(8) unknown symbol should refuse with 'matched no symbol'"; printf '%s\n' "$ERR8"; }

# ── (9) determinism (x3, byte-identical, both modes) ────────────────────────────────────────────────
D1="$( sl accumulate:count )"; D2="$( sl accumulate:count )"; D3="$( sl accumulate:count )"
I1="$( sl accumulate )"; I2="$( sl accumulate )"
[ -n "$D1" ] && [ "$D1" = "$D2" ] && [ "$D2" = "$D3" ] && [ -n "$I1" ] && [ "$I1" = "$I2" ] \
    && ok "(9) determinism: repeated runs byte-identical (var + inventory modes)" \
    || no "(9) determinism: runs differ or emitted nothing"

# ── (10) well-formed XML (xmllint, when available) ──────────────────────────────────────────────────
if command -v xmllint >/dev/null 2>&1; then
    ( cd "$WORK" && "$BIN" . --slice=accumulate:count --no-cache 2>/dev/null | xmllint --noout - ) \
        && ok "(10) xmllint: --slice=accumulate:count output is well-formed XML" \
        || no "(10) xmllint: --slice=accumulate:count output is NOT well-formed XML"
    ( cd "$WORK" && "$BIN" . --slice=accumulate --no-cache 2>/dev/null | xmllint --noout - ) \
        && ok "(10) xmllint: --slice=accumulate inventory output is well-formed XML" \
        || no "(10) xmllint: --slice=accumulate inventory output is NOT well-formed XML"
else
    echo "  SKIP  (10) xmllint not installed — well-formedness not checked"
fi

# ── (11) keyword-local exclusion on a degraded parse ────────────────────────────────────────────────
# Both assertions fuse a positive slice-specific byte with the exclusion, so each is red against the
# no---slice baseline AND against the pre-fix binary (which offered <v n="if" l=… t="decl"/> here).
OUT11="$( sl kwprobe )"
if printf '%s' "$( elem "$OUT11" )" | grep -q '<v n="count"' && [ "$( attr "$OUT11" vars )" = 'vars="2"' ] \
    && ! printf '%s' "$( elem "$OUT11" )" | grep -q '<v n="if"'; then
    ok "(11) kwprobe inventory: the real locals row (n, count → vars=2), the misparsed keyword 'if' does not"
else
    no "(11) a reserved word must never be a sliceable local (expected vars=\"2\" with count, no <v n=\"if\"…>)"; printf '%s\n' "$OUT11"
fi
ERR11="$( slerr kwprobe:if )"
[ "$( slrc kwprobe:if )" != 0 ] \
    && printf '%s' "$ERR11" | grep -q 'sliceable locals' && printf '%s' "$ERR11" | grep -q 'count' \
    && ok "(11) kwprobe:if — nonzero exit + the sliceable-locals refusal (a keyword is never a variable)" \
    || { no "(11) slicing a keyword should refuse like any unknown VAR and offer the real locals"; printf '%s\n' "$ERR11"; }

# ── (12) a condition declaration's initializer is a READ, never a def ───────────────────────────────
# RED against the pre-fix binary: defs="5" (param + two false decls + two assigns) and <v n="x" l="3">.
OUT12="$( sl condread:x )"
[ "$( attr "$OUT12" defs )" = 'defs="3"' ] && [ "$( attr "$OUT12" uses )" = 'uses="3"' ] \
    && printf '%s' "$( row "$OUT12" 3 )" | grep -q 'k="both" t="assign"' \
    && ok "(12) condread:x — 'if( int k = x ) { x = k; }' rows k=both t=assign (read in the condition, write in the body): defs=3 uses=3" \
    || { no "(12) expected defs=\"3\" uses=\"3\" and l=3 k=\"both\" t=\"assign\" — the initializer x must not be a decl"; printf '%s\n' "$OUT12"; }
OUT12I="$( sl condread )"
[ "$( attr "$OUT12I" vars )" = 'vars="3"' ] && printf '%s' "$( elem "$OUT12I" )" | grep -q '<v n="k" l="3" t="decl"/>' \
    && ! printf '%s' "$( elem "$OUT12I" )" | grep -q '<v n="x" l="3"' \
    && ok "(12) inventory: x, k, m — k IS the decl at l3, x is not re-declared there" \
    || { no "(12) expected vars=\"3\" with <v n=\"k\" l=\"3\"/> and no <v n=\"x\" l=\"3\"/>"; printf '%s\n' "$OUT12I"; }

[ "$fail" = 0 ] && printf 'ALL PASS\n' || printf 'FAILURES ABOVE\n'
exit "$fail"
