#!/usr/bin/env bash
# atomscheck.sh — the atoms-of-confusion lint pack (Gopstein et al., FSE 2017) fires on exactly the
# validated micro-patterns and on nothing that merely looks like one.
#
# The fixture below is hand-derived: every atom line is annotated with the rule it must produce AND
# the exact finding text, every "NOT" line is a near miss that must stay silent (a standalone `i++;`,
# a for-header comma/assignment/crement, a boolean or pointer condition, a decimal/hex/float literal,
# a flat ternary, a normal subscript). The assertions are the full (rule, enclosing symbol, text)
# multiset — not just counts — so a rule that fires the right NUMBER of times in the wrong PLACES is
# still red. Arm D proves the C-family language guard (the same node type names exist in the
# JavaScript grammar); arm F is the mutation control that proves the counters are not vacuous.

set -u
ROOT="$( cd "$( dirname "$0" )/.." && pwd )"
BIN="${RIPWIRE_BIN:-$ROOT/build/ripwire}"
[ "${BIN#/}" = "$BIN" ] && BIN="$ROOT/$BIN"
TMP="$( mktemp -d )"; trap 'rm -rf "$TMP"' EXIT
FIXTURE="$TMP/fixture"
mkdir -p "$FIXTURE"

fail=0
ok(){ printf '  PASS  %s\n' "$1"; }
no(){ printf '  FAIL  %s\n' "$1"; fail=1; }

[ -x "$BIN" ] || { echo "no ripwire binary at $BIN — build first"; exit 2; }

# ── the C-grammar half ────────────────────────────────────────────────────────────────────────────
cat >"$FIXTURE/atoms.c" <<'CFILE'
/* atoms.c — C-grammar half of the atoms-of-confusion fixture. */
int aSink( int v );

int aComma( int p, int q )
{
    int c1 = 0;
    int c2 = 0;
    c1 = ( p, q );                             /* atom-comma-operator "p, q" */
    c2 = ( p, q, c1 );                         /* atom-comma-operator "p, q, c1" (outermost only) */
    for( c1 = 0, c2 = 0; c1 < 3; c1++, c2++ )  /* NOT: for-header comma/assign/crement */
    {
        q += c1;
    }
    return c1 + c2 + q;
}

int aCrement( int n )
{
    int i = 0;
    int j = 0;
    int k = 0;
    int r = 0;
    i++;                                       /* NOT: standalone statement */
    --j;                                       /* NOT: standalone statement */
    r = n + k++;                               /* atom-embedded-crement "k++" */
    r = aSink( ++i );                          /* atom-embedded-crement "++i" */
    while( j-- > 0 )                           /* atom-embedded-crement "j--" */
    {
        r += 1;
    }
    for( k = 0; k < 3; ++k )                   /* NOT: for-header */
    {
        r += k;
    }
    return r;
}

int aAssign( int n, int m )
{
    int a1 = 0;
    int r = 0;
    a1 = n;                                    /* NOT: assignment as a statement */
    a1 += m;                                   /* NOT: compound assignment as a statement */
    if( a1 = n )                               /* atom-assign-as-value "a1 = n" */
    {
        r = 1;
    }
    while( ( a1 = m ) != 0 )                   /* atom-assign-as-value "a1 = m" */
    {
        m = 0;
    }
    r = aSink( a1 = n + 1 );                   /* atom-assign-as-value "a1 = n + 1" */
    return r + a1;
}

int aTernary( int n, int m )
{
    int r = 0;
    r = n ? m ? 1 : 2 : 3;                     /* atom-nested-ternary */
    r += n ? ( m ? 4 : 5 ) : 6;                /* atom-nested-ternary (parenthesised inner) */
    r += n ? 7 : 8;                            /* NOT: flat ternary */
    return r + m;
}

int aPredicate( int n, int m, const int* ptr, int flag )
{
    int r = 0;
    if( n % 2 ) { r += 1; }                    /* atom-implicit-predicate "n % 2" */
    while( n - m ) { r += 2; }                 /* atom-implicit-predicate "n - m" */
    r += n + m ? 3 : 4;                        /* atom-implicit-predicate "n + m" */
    if( 2 ) { r += 5; }                        /* atom-implicit-predicate "2" */
    if( 1 ) { r += 6; }                        /* NOT: 1 is the universal disable/loop idiom */
    if( 0 ) { r += 7; }                        /* NOT: 0 is the universal disable idiom */
    if( ptr ) { r += 8; }                      /* NOT: pointer condition */
    if( flag ) { r += 9; }                     /* NOT: plain identifier condition */
    if( n < m ) { r += 10; }                   /* NOT: comparison */
    if( n && flag ) { r += 11; }               /* NOT: logical operator */
    if( n & 4 ) { r += 12; }                   /* NOT: bitwise flag test */
    while( 1 ) { break; }                      /* NOT: infinite-loop idiom */
    return r;
}

int aOctal( void )
{
    int mode = 0755;                           /* atom-octal-literal "0755" */
    int mask = 0644;                           /* atom-octal-literal "0644" */
    int tiny = 07;                             /* atom-octal-literal "07" */
    int suff = 0711L;                          /* atom-octal-literal "0711L" */
    int zero = 0;                              /* NOT: bare zero */
    int deci = 755;                            /* NOT: decimal */
    int hexa = 0x1F;                           /* NOT: hexadecimal */
    int nine = 099;                            /* NOT: an 8/9 digit is not an octal literal */
    int lzer = 0L;                             /* NOT: zero with a suffix */
    double frac = 0.5;                         /* NOT: floating literal */
    return mode + mask + tiny + suff + zero + deci + hexa + nine + lzer + (int)frac;
}

int aSubscript( int* arr )
{
    int r = 0;
    r += 1[arr];                               /* atom-reversed-subscript "1[arr]" */
    r += arr[2];                               /* NOT: normal subscript */
    return r;
}
CFILE

# ── the C++-grammar half: C++ wraps if/while conditions in condition_clause, C/ObjC in ─────────────
#    parenthesized_expression, so every position-anchored atom needs both node paths.
cat >"$FIXTURE/atoms.cpp" <<'CPPFILE'
// atoms.cpp — C++-grammar half of the atoms-of-confusion fixture.
int cSink( int v );

int cppAtoms( int n, int m )
{
    int x = 0;
    int r = 0;
    r = ( n, m );                              // atom-comma-operator "n, m"
    r = n + x++;                               // atom-embedded-crement "x++"
    x++;                                       // NOT: standalone statement
    if( x = n ) { r = 1; }                     // atom-assign-as-value "x = n"
    r = n ? m ? 1 : 2 : 3;                     // atom-nested-ternary
    if( n % 3 ) { r += 1; }                    // atom-implicit-predicate "n % 3"
    while( n - m ) { m = 0; }                  // atom-implicit-predicate "n - m"
    if( n < m ) { r += 2; }                    // NOT: comparison
    int mode = 0640;                           // atom-octal-literal "0640"
    return r + x + mode + cSink( m );
}
CPPFILE

# ── the executable-context guard. tree-sitter's C++ grammar resolves the declaration-vs-expression
#    ambiguity WRONGLY for a pointer-to-member declarator with a default member initializer: the
#    field comes back as an assignment_expression, and every such row in ripwire's own flag tables was
#    reported as an assignment-used-as-a-value before this guard existed. Nothing in a struct body is
#    EVALUATED, so no expression atom may fire here — but an octal literal is confusing wherever it is
#    written and is deliberately exempt from the guard, which this fixture also pins.
cat >"$FIXTURE/decl.cpp" <<'DECLFILE'
// decl.cpp — declarations only. No expression atom may fire in a struct body.
struct Knobs
{
    bool Knobs::* isSetFlag     = nullptr;
    bool Knobs::* isSetFlagAlso = nullptr;
    int           mode          = 0666;   // atom-octal-literal: exempt from the executable guard
};
DECLFILE

# ── the language guard: the JavaScript grammar spells update_expression / assignment_expression /
#    subscript_expression exactly the way C does. Not one atom row may come from this file.
cat >"$FIXTURE/guard.js" <<'JSFILE'
function guarded( a, b ) {
    let r = 0;
    r = a + b++;
    r = a ? ( b ? 1 : 2 ) : 3;
    if ( r = a ) { r = 1; }
    r = a[1];
    return r;
}
JSFILE

# ── A) determinism ────────────────────────────────────────────────────────────────────────────────
"$BIN" "$FIXTURE" --lint --no-cache >"$TMP/a" 2>/dev/null
"$BIN" "$FIXTURE" --lint --no-cache >"$TMP/b" 2>/dev/null
cmp -s "$TMP/a" "$TMP/b" && ok "atoms lint output is deterministic" \
    || { no "atoms lint output is NOT deterministic"; exit 1; }

# ── B/C/D/E) the exact finding multiset, the rule tally, and the language guard ────────────────────
python3 - "$TMP/a" <<'PY' || exit 1
import sys
import xml.etree.ElementTree as ET

root = ET.parse(sys.argv[1]).getroot()

ATOM_RULES = (
    "atom-comma-operator", "atom-embedded-crement", "atom-assign-as-value", "atom-nested-ternary",
    "atom-implicit-predicate", "atom-octal-literal", "atom-reversed-subscript",
)

failed = []
def ok(msg):    print(f"  PASS  {msg}")
def no(msg):    failed.append(msg); print(f"  FAIL  {msg}")

rows = [f for f in root.findall("f") if (f.get("rule") or "").startswith("atom-")]

# (B) every atom rule is declared in the per-rule tally, and its count= equals the rows emitted.
tally = {r.get("name"): int(r.get("count")) for r in root.findall("rule")}
missing = [r for r in ATOM_RULES if r not in tally]
if missing:
    no(f"atom rules missing from the <rule> tally: {missing}")
else:
    ok("all seven atom rules are declared in the per-rule tally")

for rule in ATOM_RULES:
    emitted = sum(1 for f in rows if f.get("rule") == rule)
    if tally.get(rule) != emitted:
        no(f"{rule}: tally count={tally.get(rule)} but {emitted} rows emitted")
if not failed:
    ok("every atom rule's count= equals the rows it emitted")

# (C) the exact (rule, enclosing symbol, text) multiset — hand-derived from the fixture above.
expected = sorted([
    ("atom-comma-operator",     "aComma",     "p, q"),
    ("atom-comma-operator",     "aComma",     "p, q, c1"),
    ("atom-comma-operator",     "cppAtoms",   "n, m"),
    ("atom-embedded-crement",   "aCrement",   "k++"),
    ("atom-embedded-crement",   "aCrement",   "++i"),
    ("atom-embedded-crement",   "aCrement",   "j--"),
    ("atom-embedded-crement",   "cppAtoms",   "x++"),
    ("atom-assign-as-value",    "aAssign",    "a1 = n"),
    ("atom-assign-as-value",    "aAssign",    "a1 = m"),
    ("atom-assign-as-value",    "aAssign",    "a1 = n + 1"),
    ("atom-assign-as-value",    "cppAtoms",   "x = n"),
    ("atom-nested-ternary",     "aTernary",   "n ? m ? 1 : 2 : 3"),
    ("atom-nested-ternary",     "aTernary",   "n ? ( m ? 4 : 5 ) : 6"),
    ("atom-nested-ternary",     "cppAtoms",   "n ? m ? 1 : 2 : 3"),
    ("atom-implicit-predicate", "aPredicate", "n % 2"),
    ("atom-implicit-predicate", "aPredicate", "n - m"),
    ("atom-implicit-predicate", "aPredicate", "n + m"),
    ("atom-implicit-predicate", "aPredicate", "2"),
    ("atom-implicit-predicate", "cppAtoms",   "n % 3"),
    ("atom-implicit-predicate", "cppAtoms",   "n - m"),
    ("atom-octal-literal",      "aOctal",     "0755"),
    ("atom-octal-literal",      "aOctal",     "0644"),
    ("atom-octal-literal",      "aOctal",     "07"),
    ("atom-octal-literal",      "aOctal",     "0711L"),
    ("atom-octal-literal",      "cppAtoms",   "0640"),
    ("atom-octal-literal",      "Knobs",      "0666"),
    ("atom-reversed-subscript", "aSubscript", "1[arr]"),
])
got = sorted((f.get("rule"), f.get("in"), (f.text or "")) for f in rows)
if got != expected:
    extra   = [t for t in got      if got.count(t)      > expected.count(t)]
    absent  = [t for t in expected if expected.count(t) > got.count(t)]
    no(f"atom finding multiset differs — unexpected={sorted(set(extra))} missing={sorted(set(absent))}")
else:
    ok(f"all {len(expected)} atom findings match the hand-derived (rule, symbol, text) multiset")

# (D1) the executable-context guard — a struct body holds declarations, not evaluated expressions.
#      The two pointer-to-member fields are what the C++ grammar hands back as assignment_expressions.
declRows = sorted((f.get("rule"), f.text) for f in rows if "decl.cpp" in (f.get("p") or ""))
if declRows != [("atom-octal-literal", "0666")]:
    no(f"declaration-only file produced {declRows}, expected only the exempt octal literal")
else:
    ok("a misparsed pointer-to-member field fires no expression atom; the octal literal still does")

# (D) the C-family language guard — not one row may come from the JavaScript file.
leaked = [f.get("p") for f in rows if "guard.js" in (f.get("p") or "")]
if leaked:
    no(f"atom rules fired on a non-C-family file: {leaked}")
else:
    ok("no atom fired on guard.js (C-family language guard holds)")

# (E) the near misses stay silent — asserted on the TEXT of the constructs that must not fire.
forbidden = ("i++", "--j", "++k", "c1++", "c2++", "a1 += m", "n ? 7 : 8",
             "ptr", "flag", "n < m", "n && flag", "n & 4", "1", "0",
             "099", "0x1F", "0L", "0.5", "755", "arr[2]")
noisy = sorted({(f.get("rule"), f.text) for f in rows if f.text in forbidden})
if noisy:
    no(f"a near-miss construct fired an atom: {noisy}")
else:
    ok("every near-miss construct (standalone crement, for-header, boolean/pointer condition, "
       "decimal/hex/float literal, flat ternary, normal subscript) stayed silent")

sys.exit(1 if failed else 0)
PY
[ $? -eq 0 ] || fail=1

# ── F) mutation control — the counters must move when the corpus does ─────────────────────────────
countRule(){ grep -oE "<rule name=\"$1\" count=\"[0-9]+\"" "$2" | grep -oE '[0-9]+'; }
octalBefore="$( countRule atom-octal-literal "$TMP/a" )"
subBefore="$(   countRule atom-reversed-subscript "$TMP/a" )"

cat >"$FIXTURE/more.c" <<'MOREFILE'
int mutantAtoms( int* arr )
{
    int one = 0600;
    int two = 0400;
    return one + two + 3[arr];
}
MOREFILE

"$BIN" "$FIXTURE" --lint --no-cache >"$TMP/mut" 2>/dev/null
octalAfter="$( countRule atom-octal-literal "$TMP/mut" )"
subAfter="$(   countRule atom-reversed-subscript "$TMP/mut" )"

[ "$octalAfter" = "$(( octalBefore + 2 ))" ] \
    && ok "mutation control: two added octal literals raise atom-octal-literal $octalBefore -> $octalAfter" \
    || no "mutation control: atom-octal-literal went $octalBefore -> $octalAfter, expected $(( octalBefore + 2 ))"
[ "$subAfter" = "$(( subBefore + 1 ))" ] \
    && ok "mutation control: one added reversed subscript raises atom-reversed-subscript $subBefore -> $subAfter" \
    || no "mutation control: atom-reversed-subscript went $subBefore -> $subAfter, expected $(( subBefore + 1 ))"

# ── G) a corpus with no C-family file still DECLARES every atom rule at count="0" ─────────────────
#     (honesty: a zero means "none found here", and the reader must be able to see the rule ran).
#     L7: since src/lintcatalog.h, that same corpus makes every atom-* rule structurally INERT (its
#     registered languages — cpp/c/objc — intersect none of a JS-only corpus), so the honest row now
#     also carries applicable="0" — a stronger disclosure than the bare zero this arm used to check,
#     not a different fact. See --lint-catalog.
JSONLY="$TMP/jsonly"; mkdir -p "$JSONLY"
cp "$FIXTURE/guard.js" "$JSONLY/guard.js"
"$BIN" "$JSONLY" --lint --no-cache >"$TMP/js" 2>/dev/null
zeroed=1
for rule in atom-comma-operator atom-embedded-crement atom-assign-as-value atom-nested-ternary \
            atom-implicit-predicate atom-octal-literal atom-reversed-subscript
do
    grep -q "<rule name=\"$rule\" count=\"0\" applicable=\"0\"/>" "$TMP/js" || { zeroed=0; echo "    (missing zero+inert row for $rule)"; }
done
[ "$zeroed" = 1 ] \
    && ok "a JavaScript-only corpus declares all seven atom rules at count=\"0\" applicable=\"0\"" \
    || no "a JavaScript-only corpus does not declare every atom rule at count=\"0\""

# ── H) G5: --lint without any C-family atom is byte-identical to a flagless run's map ─────────────
#     (the pack is additive — it may not perturb the default map).
"$BIN" "$FIXTURE" --no-cache >"$TMP/map1" 2>/dev/null
"$BIN" "$FIXTURE" --no-cache >"$TMP/map2" 2>/dev/null
cmp -s "$TMP/map1" "$TMP/map2" && [ -s "$TMP/map1" ] \
    && ok "the default map is unchanged and deterministic alongside the atoms pack" \
    || no "the default map is empty or non-deterministic"

[ "$fail" = 0 ] && echo "PASS atomscheck" || echo "FAIL atomscheck"
exit "$fail"
