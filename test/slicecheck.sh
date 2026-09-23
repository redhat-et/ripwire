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
#   (10) xmllint well-formedness (both modes); (10d) the FULL tier specifically, plain and
#        --slice-flow=both — the tier the default-tier-only arms above never exercise
#   (11) keyword-local exclusion: a degraded parse must never offer a reserved word as a sliceable
#        local (inventory clean of it, slicing it refuses) — the ugrep matcher.cpp misparse shape
#   (12) C++ condition declaration `if( int k = x )`: tree-sitter-cpp emits a `declaration` whose
#        initializer sits in a `value` field with NO init_declarator, so x must row as a READ of x
#        (and k as its decl) — a false def here is a false binding after scope separation
#   (13) JS/TS destructuring binders are sliceable locals whose def is the pattern line: object,
#        array, renamed (`y: yy`), defaulted (`z = 3`, its right side a read), rest, a destructured
#        parameter, `for (const { k } of xs)`, and `({ x } = o)` as an assign
#   (order) VAR-mode rows emit in the declared order (def-use coverage desc, then line) and the root says
#        order="defuse" — the legend (both tiers) and --help define it; a flow run's seed rows keep that order
#   (14) Python `global X` / `nonlocal X` row k="scope" t="global"|"nonlocal" — a scope declaration,
#        neither read nor write — and introduce the name in the inventory with that role
#   (rank) the pre-registered ARISE line-ranking attempt (docs/research/arise-line-ranking-prereg.md):
#        the unit driver test/slicerank_unit.cpp, on synthetic fixtures — kSliceLineRankVerdict is
#        Pending (unwired from the CLI), so this proves the new paths compile/run/behave as registered
#        without changing anything the (order) arms above already pin
#
# Usage:  RIPWIRE_BIN=build/ripwire bash test/slicecheck.sh   |   bash test/slicecheck.sh path/to/ripwire

set -u
ROOT="$( cd "$( dirname "$0" )/.." && pwd )"
BIN="${1:-${RIPWIRE_BIN:-$ROOT/build/ripwire}}"
[ "${BIN#/}" = "$BIN" ] && BIN="$ROOT/$BIN"
fail=0
ok(){ printf '  PASS  %s\n' "$*" || { fail=1; printf '  FAIL  could not write the PASS line for: %s\n' "$*"; }; return 0; }
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

# arm (13)'s fuel: JS/TS destructuring — before the fix `const { x, y } = o` minted NO local and NO def
# (audit 2026-09-02, F-08: vars="2" listing only o and s; --slice=destructure:x -> defs="0").
cat > "$WORK/src/d.js" <<'EOF'
function destructure( o, { p, q }, [ r ] ) {
  const { x, y: yy, z = 3, ...rest } = o;
  const [ a, b ] = o;
  let s = x + yy + z + a + b + p + q + r;
  ({ x } = o);
  for (const { k } of o) { s += k; }
  return s + rest.length;
}
EOF
cat > "$WORK/src/d.ts" <<'EOF'
function tsdestructure( o: any, { p, q }: { p: number; q: number } ): number {
  const { x, y: yy } = o;
  let s: number = x + yy + p + q;
  return s;
}
EOF
# arm (14)'s fuel: Python scope statements
cat > "$WORK/src/g.py" <<'EOF'
COUNTER = 0

def bump(n):
    global COUNTER
    COUNTER = COUNTER + n
    return COUNTER

def outer():
    acc = 0
    def inner(k):
        nonlocal acc
        acc += k
        return acc
    return inner
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
# L1 (2026-09-19): the CLI default legend is compact; (1) reads the FULL legend's prose off $OUT1, so this run asks for it
# (the sl helper's exact invocation, plus --legend=full).
OUT1="$( cd "$WORK" && "$BIN" . --slice=accumulate:count --no-cache --legend=full 2>/dev/null )"
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
    # (10d) the full-tier legend is its own XML comment (never the compact dictionary's shorter one);
    # an inline flag mention with its dashes ("--at=") is a double-hyphen INSIDE that comment, which
    # xmllint --noout rejects outright — a pre-existing G4 violation on origin/main 15a20855 too, not
    # caught before because every other well-formedness arm here and in sliceflowcheck.sh/
    # sliceflowsenscheck.sh only lints the DEFAULT (compact) tier.
    ( cd "$WORK" && "$BIN" . --slice=accumulate:count --legend=full --no-cache 2>/dev/null | xmllint --noout - ) \
        && ok "(10d) xmllint: --slice=accumulate:count --legend=full output is well-formed XML" \
        || no "(10d) xmllint: --slice=accumulate:count --legend=full output is NOT well-formed XML (a '--' inside the legend comment?)"
    ( cd "$WORK" && "$BIN" . --slice=accumulate:count --slice-flow=both --legend=full --no-cache 2>/dev/null | xmllint --noout - ) \
        && ok "(10d) xmllint: --slice=accumulate:count --slice-flow=both --legend=full output is well-formed XML" \
        || no "(10d) xmllint: --slice=accumulate:count --slice-flow=both --legend=full output is NOT well-formed XML (a '--' inside the legend comment?)"
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

# ── (13) JS/TS destructuring binders are locals with the pattern line as their def ──────────────────
OUT13="$( sl d.js:destructure )"
if [ "$( attr "$OUT13" vars )" = 'vars="12"' ] \
   && printf '%s' "$( elem "$OUT13" )" | grep -q '<v n="x" l="2" t="decl"/>' && printf '%s' "$( elem "$OUT13" )" | grep -q '<v n="yy" l="2" t="decl"/>' \
   && printf '%s' "$( elem "$OUT13" )" | grep -q '<v n="z" l="2" t="decl"/>' && printf '%s' "$( elem "$OUT13" )" | grep -q '<v n="rest" l="2" t="decl"/>' \
   && printf '%s' "$( elem "$OUT13" )" | grep -q '<v n="a" l="3" t="decl"/>' && printf '%s' "$( elem "$OUT13" )" | grep -q '<v n="b" l="3" t="decl"/>' \
   && printf '%s' "$( elem "$OUT13" )" | grep -q '<v n="p" l="1" t="param"/>' && printf '%s' "$( elem "$OUT13" )" | grep -q '<v n="r" l="1" t="param"/>' \
   && printf '%s' "$( elem "$OUT13" )" | grep -q '<v n="k" l="6" t="decl"/>' \
   && ! printf '%s' "$( elem "$OUT13" )" | grep -q '<v n="y"'; then
    ok "(13) destructure inventory: vars=12 — o/p/q/r params, x/yy/z/rest (object), a/b (array), s, k (for-of); the KEY y is not a local"
else
    no "(13) expected vars=\"12\" with x/yy/z/rest@2, a/b@3, p/q/r@1 params, k@6 and no <v n=\"y\">"; printf '%s\n' "$OUT13"
fi
OUT13X="$( sl d.js:destructure:x )"
[ "$( attr "$OUT13X" defs )" = 'defs="2"' ] && printf '%s' "$( row "$OUT13X" 2 )" | grep -q 'k="def" t="decl"' \
    && printf '%s' "$( row "$OUT13X" 5 )" | grep -q 'k="def" t="assign"' \
    && ok "(13) destructure:x — the pattern line rows k=def t=decl, '({ x } = o)' rows k=def t=assign: defs=2" \
    || { no "(13) expected defs=\"2\": l=2 k=def t=decl and l=5 k=def t=assign"; printf '%s\n' "$OUT13X"; }
OUT13Z="$( sl d.js:destructure:z )"
[ "$( attr "$OUT13Z" defs )" = 'defs="1"' ] && printf '%s' "$( row "$OUT13Z" 2 )" | grep -q 'k="def" t="decl"' \
    && ok "(13) destructure:z — a defaulted binder is a decl (its default's right side is not a write of z)" \
    || { no "(13) expected defs=\"1\" with l=2 k=def t=decl for the defaulted binder"; printf '%s\n' "$OUT13Z"; }
OUT13T="$( sl tsdestructure )"
printf '%s' "$( elem "$OUT13T" )" | grep -q '<v n="x" l="2" t="decl"/>' && printf '%s' "$( elem "$OUT13T" )" | grep -q '<v n="p" l="1" t="param"/>' \
    && ok "(13) TS: the typed destructured parameter and the object pattern are binders too" \
    || { no "(13) expected TS binders x@2 (decl) and p@1 (param)"; printf '%s\n' "$OUT13T"; }

# ── (14) Python global/nonlocal: a scope declaration is neither a read nor a write ──────────────────
OUT14="$( sl bump:COUNTER )"
printf '%s' "$( row "$OUT14" 4 )" | grep -q 'k="scope" t="global"' \
    && [ "$( attr "$OUT14" defs )" = 'defs="1"' ] && [ "$( attr "$OUT14" uses )" = 'uses="2"' ] \
    && ok "(14) bump:COUNTER — 'global COUNTER' rows k=scope t=global and counts as neither def nor use (defs=1 uses=2)" \
    || { no "(14) expected l=4 k=\"scope\" t=\"global\", defs=\"1\" uses=\"2\""; printf '%s\n' "$OUT14"; }
OUT14I="$( sl bump )"
printf '%s' "$( elem "$OUT14I" )" | grep -q '<v n="COUNTER" l="4" t="global"/>' \
    && ok "(14) bump inventory lists COUNTER at its global statement with t=global — a global, not a local, and it says so" \
    || { no "(14) expected <v n=\"COUNTER\" l=\"4\" t=\"global\"/>"; printf '%s\n' "$OUT14I"; }
OUT14N="$( sl inner:acc )"
printf '%s' "$( row "$OUT14N" 11 )" | grep -q 'k="scope" t="nonlocal"' && printf '%s' "$( row "$OUT14N" 12 )" | grep -q 'k="both"' \
    && ok "(14) inner:acc — 'nonlocal acc' rows k=scope t=nonlocal, 'acc += k' rows k=both" \
    || { no "(14) expected l=11 k=\"scope\" t=\"nonlocal\" and l=12 k=\"both\""; printf '%s\n' "$OUT14N"; }

# ── (15) deep nesting: answered in linear time up to the guard, refused by name past it ──────────────────────────
#    The walk used to climb to each occurrence's statement anchor through ts_node_parent, which descends from the root
#    every time, so its cost grew with the cube of the nesting: 2,000 chained `if (x)` took 48 s and 4,000 did not
#    finish in two minutes (an MCP `slice` call on such a file wedged the server). It now reads parents from a table
#    built in one cursor pass and memoizes the anchor, so the occurrence scan is linear. lane/slice-iterative then made
#    both walks run on an explicit heap work stack instead of recursing, so the 2,048-level bound is a TIME/MEMORY
#    guard now, not a stack one: the reaching-definitions fixpoint is inherently super-linear in nesting (measured:
#    8,192 nested `for` loops, 48 s), and that cost — not any stack frame — is what the guard protects against.
#    (a) 2,000 nested ifs are ANSWERED inside a 30 s bound (base: killed).
#    (b) 2,040 nested `for` loops — the shape whose fixpoint redo costs the most per level — are ANSWERED just under
#        the guard. This arm now passes even with the caller's stack held to 1 MB (`ulimit -s 1024`: the walk no
#        longer needs any stack margin, only time), where the pre-fix binary SIGSEGV'd here (rc 139), un-sanitized —
#        run this gate with RIPWIRE_BIN=asan/ripwire too, which no longer needs the wider sanitizer frame margin either.
#    (c) a CPython-shaped chained assignment ~808 levels deep — Lib/test/test_traceback.py:3256, the deepest function in
#        47,795 parsed files — is ANSWERED: a real file must never meet the guard.
#    (d) 6,000 nested blocks are REFUSED by name, in bounded time, before any walk.
DEEPDIR="$( mktemp -d )"
python3 - "$DEEPDIR" <<'PYDEEP'
import sys
d = sys.argv[1]
open(d + "/deep.c", "w").write("int deep( int x )\n{\n    int y = 0;\n    " + "if (x) " * 2000 + "y = x;\n    return y;\n}\n"
                                "int loops( int x )\n{\n    int y = 0;\n    " + "for (;;) " * 2040 + "y = x;\n    return y;\n}\n"
                                "int blocks( int x )\n{\n    int y = 0;\n    " + "{ " * 6000 + "y = x;" + " }" * 6000 + "\n    return y;\n}\n")
open(d + "/chain.py", "w").write("def chained():\n    " + " = ".join("a%d" % i for i in range(1, 807)) + " = 1\n    return a1\n")
PYDEEP
bounded(){ if command -v timeout >/dev/null 2>&1; then timeout 60 "$@"; else perl -e 'alarm 60; exec @ARGV' "$@"; fi; }
( cd "$DEEPDIR" && bounded "$BIN" . --slice=deep:y --no-cache >"$DEEPDIR/deep.out" 2>"$DEEPDIR/deep.err" ); rc15=$?
[ "$rc15" -eq 0 ] && grep -q '<s l="4"' "$DEEPDIR/deep.out" \
    && ok "(15a) deep:y — 2,000 nested ifs slice in bounded time (exit 0, the assignment row at l=4)" \
    || no "(15a) deep:y exit $rc15 (expected 0 with the l=4 row; 124/142 is the cubic walk, 1 a guard set below real depth): $( head -c 200 "$DEEPDIR/deep.err" )"
( cd "$DEEPDIR" && bounded "$BIN" . --slice=loops:y --no-cache >"$DEEPDIR/loops.out" 2>"$DEEPDIR/loops.err" ); rc15l=$?
[ "$rc15l" -eq 0 ] && grep -q '<s l="10"' "$DEEPDIR/loops.out" \
    && ok "(15b) loops:y — 2,040 nested for loops (the fixpoint's costliest shape per level) slice just under the guard (exit 0, the assignment row at l=10)" \
    || no "(15b) loops:y exit $rc15l (expected 0; 139/138 below the guard would mean the walk is recursing again — it should not be): $( head -c 200 "$DEEPDIR/loops.err" )"
( cd "$DEEPDIR" && bounded "$BIN" . --slice=chained:a1 --no-cache >"$DEEPDIR/chain.out" 2>"$DEEPDIR/chain.err" ); rc15b=$?
[ "$rc15b" -eq 0 ] && grep -q '<s l="2"' "$DEEPDIR/chain.out" \
    && ok "(15c) chained:a1 — an 806-name, ~808-level chained assignment (CPython test_traceback.py's shape) is answered" \
    || no "(15c) chained:a1 exit $rc15b — a real-world depth must be answered: $( head -c 200 "$DEEPDIR/chain.err" )"
( cd "$DEEPDIR" && bounded "$BIN" . --slice=blocks:y --no-cache >"$DEEPDIR/blocks.out" 2>"$DEEPDIR/blocks.err" ); rc15c=$?
[ "$rc15c" -eq 1 ] && grep -q 'nests deeper than 2048 syntax levels' "$DEEPDIR/blocks.err" \
    && ok "(15d) blocks:y — 6,000 nested blocks refuse by name at the 2,048-level guard" \
    || no "(15d) blocks:y exit $rc15c (expected 1 with the stack-guard refusal): $( head -c 200 "$DEEPDIR/blocks.err" )"
rm -rf "$DEEPDIR"

# ── (rd-bound) an UNSETTLED reaching-definition fixpoint is disclosed on the root, in every build flavour ─────────
# The loop fixpoint stops at kSliceRdMaxIter; no input reaches it (it settles in one round on every measured corpus),
# so the arm LOWERS the bound with RIPWIRE_TEST_SLICE_RD_MAXITERS — pagerank's RIPWIRE_TEST_PR_MAXITERS pattern, honoured
# in every flavour. The walk used to keep reach="cfg" and a one-argument DISCLOSE (a debug trace, nothing in Release);
# the scan's DISCLOSE sink now puts reach_converged="0" on the root, defined in the same header.
RD="$WORK/rdbound"; mkdir -p "$RD"
printf 'int loopy( int n )\n{\n    int x = 0;\n    while( n > 0 )\n    {\n        n = n - x;\n        x = x + 1;\n    }\n    return x;\n}\n' >"$RD/a.c"
"$BIN" "$RD" --slice=loopy:x --no-cache >"$RD/ctl.xml" 2>/dev/null
RIPWIRE_TEST_SLICE_RD_MAXITERS=1 "$BIN" "$RD" --slice=loopy:x --no-cache >"$RD/hit.xml" 2>/dev/null
RDCTL="$( grep -o '<slice [^>]*>' "$RD/ctl.xml" )"; RDHIT="$( grep -o '<slice [^>]*>' "$RD/hit.xml" )"
{ printf '%s' "$RDCTL" | grep -q ' reach="cfg"' && ! grep -q 'reach_converged' "$RD/ctl.xml"; } \
    && ok "(rd-bound) control: the settled slice reads reach=\"cfg\" with no reach_converged=" \
    || no "(rd-bound) control: the unhooked slice is not the settled cfg shape: $RDCTL"
printf '%s' "$RDHIT" | grep -q ' reach="cfg" reach_converged="0"' \
    && ok "(rd-bound) a fixpoint stopped at its bound says so on the root: reach_converged=\"0\" (every build flavour)" \
    || no "(rd-bound) a fixpoint stopped at its bound still reads as a finished flow analysis: $RDHIT"
grep -q 'reach_converged="0": ' "$RD/hit.xml" \
    && ok "(rd-bound) reach_converged= is defined in the same document" || no "(rd-bound) reach_converged= rides with no definition"
command -v xmllint >/dev/null 2>&1 && { xmllint --noout "$RD/hit.xml" 2>/dev/null \
    && ok "(rd-bound) the disclosing document is well-formed" || no "(rd-bound) the disclosing document fails xmllint"; }
rdbad=0
for v in 64 65 1000 1x '' 0 ' 1'; do
    RIPWIRE_TEST_SLICE_RD_MAXITERS="$v" "$BIN" "$RD" --slice=loopy:x --no-cache >"$RD/v.xml" 2>/dev/null
    cmp -s "$RD/v.xml" "$RD/ctl.xml" || { no "(rd-bound) RIPWIRE_TEST_SLICE_RD_MAXITERS='$v' changed the document — the hook is not lower-only/strict"; rdbad=1; }
done
[ "$rdbad" = 0 ] && ok "(rd-bound) the hook cannot raise the bound and parses strictly: 7 non-lowering values are byte-identical to unset"
"$BIN" --help=all 2>&1 | grep -q 'RIPWIRE_TEST_SLICE_RD_MAXITERS' \
    && no "(rd-bound) the arming hook is advertised in --help — it is a gate's hook, not a user surface (G5)" \
    || ok "(rd-bound) the arming hook appears in no --help text (G5)"

# ── (order) --slice=SYM:VAR rows emit in the DECLARED order, and the root states it ─────────────────────────────
# Measured (LocBench py, 478 (instance, variable) pairs): source order pinpoints a gold line WORSE than a random
# shuffle of the same rows (MRR 0.525 vs 0.602), def-use coverage beats it (0.628). So the rows rank by coverage —
# how many distinct sliceable locals share the line — descending, then line, then binding line, and the root says
# order="defuse" so the reader never mistakes a ranking for source order (or the reverse). Fixture: l=4 names FOUR
# locals, l=2 and l=5 name one each; source order is 2,4,5, the declared order is 4,2,5. A flow run keeps the same
# seed rows in the same order (the flow rows keep their own stated (d=, l=, v=) order).
ORD="$WORK/order"; mkdir -p "$ORD"
printf 'def mix(a):\n    x = 1\n    y = 2\n    z = x + y + a\n    return x\n' >"$ORD/m.py"
"$BIN" "$ORD" --slice=mix:x --no-cache >"$ORD/o.xml" 2>/dev/null
"$BIN" "$ORD" --slice=mix:x --slice-flow=back --no-cache >"$ORD/f.xml" 2>/dev/null
OROOT="$( grep -o '<slice [^>]*>' "$ORD/o.xml" )"
OLINES="$( grep -o '<s l="[0-9]*"' "$ORD/o.xml" | tr -dc '0-9\n' | tr '\n' ',' )"
FLINES="$( grep -o '<s l="[0-9]*" k="[a-z]*" t="[a-z-]*"[ a-z="0-9,-]*><' "$ORD/f.xml" | grep -v ' v="' | grep -o 'l="[0-9]*"' | tr -dc '0-9\n' | tr '\n' ',' )"
[ "$OLINES" = "4,2,5," ] \
    && ok "(order) mix:x rows emit 4,2,5 — coverage descending (l=4 names four locals), then line" \
    || { no "(order) mix:x rows emit '$OLINES', expected 4,2,5 (coverage desc, then line)"; printf '%s\n' "$OROOT"; }
printf '%s' "$OROOT" | grep -q ' order="defuse"' \
    && ok "(order) the root states the row order: order=\"defuse\"" \
    || no "(order) the root does not state the row order (expected order=\"defuse\"): $OROOT"
# the legend is everything before the root (a legend spells <s …> rows, so a [^>]* comment match would stop short)
grep -q 'order="defuse"' "$ORD/o.xml" && sed 's/<slice .*//' "$ORD/o.xml" | grep -q 'order=defuse\|order=\\"defuse\\"\|order="defuse"' \
    && ok "(order) order= is defined in the same document's legend" || no "(order) order= rides with no legend definition"
"$BIN" "$ORD" --slice=mix:x --legend=compact --no-cache 2>/dev/null | sed 's/<slice .*//' | grep -q 'order=defuse' \
    && ok "(order) the compact legend defines order= too" || no "(order) the compact legend does not define order="
"$BIN" "$ORD" --slice=mix:x --legend=full --no-cache 2>/dev/null | sed 's/<slice .*//' | grep -q 'order=\\\?"defuse' \
    && ok "(order) the full legend defines order= too" || no "(order) the full legend does not define order="
[ "$FLINES" = "4,2,5," ] \
    && ok "(order) a flow run's seed rows keep the same declared order" \
    || no "(order) a flow run's seed rows emit '$FLINES', expected 4,2,5"
"$BIN" --help=all 2>&1 | grep -q 'order="defuse"' \
    && ok "(order) --help documents order=\"defuse\"" || no "(order) --help does not document order=\"defuse\""

# ── (rank) the pre-registered ARISE line-ranking attempt — docs/research/arise-line-ranking-prereg.md ──
# kSliceLineRankVerdict is Pending (unwired from the CLI, verdict awaits the real corpus — the (order)
# arms above already prove today's shipped behavior is untouched). The two new paths
# (sliceLineRankAttemptOrder, sliceStatedOrder) and the seed-free sliceRowHasAnyDef substrate are
# exercised directly, on SYNTHETIC fixtures, by test/slicerank_unit.cpp — compiled ad hoc against the
# real CMake flags, the same shape test/macroreparsecheck.sh's (U) arm already uses.
BUILD_DIR="$( cd "$( dirname "$BIN" )" && pwd )"
FLAGS_MK="$BUILD_DIR/CMakeFiles/ripwire.dir/flags.make"
LINK_TXT="$BUILD_DIR/CMakeFiles/ripwire.dir/link.txt"
if [ ! -f "$FLAGS_MK" ] || [ ! -f "$LINK_TXT" ]; then
    no "(rank) cannot find CMake flags under $BUILD_DIR — the unit arm needs a CMake-built binary"
else
    # shellcheck source=test/lib/cxxflags.sh
    . "$ROOT/test/lib/cxxflags.sh"
    if ! cxxflags_load "$FLAGS_MK"; then
        no "(rank) cannot parse $FLAGS_MK without executing it (see the cxxflags: line on stderr)"
    else
        CXX="$( awk 'NR==1{ print $1; exit }' "$LINK_TXT" )"
        [ -n "$CXX" ] && command -v "$CXX" >/dev/null 2>&1 || CXX="$( command -v c++ || command -v clang++ )"
        DIAG_OBJ="$BUILD_DIR/CMakeFiles/ripwire.dir/src/infra/diagnostics.cpp.o"
        DIAG_LINK=(); [ -f "$DIAG_OBJ" ] && DIAG_LINK=( "$DIAG_OBJ" )
        if "$CXX" "${CXX_FLAGS[@]}" "${CXX_DEFINES[@]}" "${CXX_INCLUDES[@]}" -I"$ROOT/src" \
             "$ROOT/test/slicerank_unit.cpp" "${DIAG_LINK[@]}" -o "$WORK/slicerank_unit" >"$WORK/rank_build.log" 2>&1; then
            if "$WORK/slicerank_unit" >"$WORK/rank_run.log" 2>&1; then
                ok "(rank) slicerank_unit: $( grep -c '  PASS' "$WORK/rank_run.log" | tr -d ' ' ) cases hold"
            else
                no "(rank) slicerank_unit failed:"; grep FAIL "$WORK/rank_run.log" | head -12 | sed 's/^/        /'
            fi
        else
            no "(rank) slicerank_unit does not compile:"; grep -m4 -E 'error' "$WORK/rank_build.log" | sed 's/^/        /'
        fi
    fi
fi

[ "$fail" = 0 ] && printf 'ALL PASS\n' || printf 'FAILURES ABOVE\n'
exit "$fail"
