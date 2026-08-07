#!/usr/bin/env bash
# ppaltcheck.sh — a symbol whose body contains MUTUALLY-EXCLUSIVE preprocessor branches
# (`#if SSE … #else … #endif` implementations of the same function) gets cx/ccx/nest/loc summed over
# code that never coexists at compile time — roughly 2x inflation vs any single build. Found on a
# private validation corpus (bullet's LinearMath/btMatrix3x3.h::getRotation, loc=87 spanning both
# arms of a BT_USE_SSE guard; that tree is validation-only, so this gate reproduces the shape in its
# own throwaway fixture — same policy as test/preproccondcheck.sh, the include-graph sibling of this
# defect family).
#
# ── THE RULE THIS PINS (honesty over guessing) ───────────────────────────────────────────────────────
# ripwire does NOT pick a branch: which arm a build compiles depends on flags ripwire never sees, and
# "measure the first/largest branch" is a quiet guess — exactly the surface the repo doctrine forbids
# (README non-negotiable #3: counts that cannot be totals are labelled, never silently rounded).
# Instead the fused cc_walk DFS counts ALTERNATIVE-INTRODUCING preprocessor nodes (preproc_else /
# preproc_elif / preproc_elifdef, matched by prefix so grammar-internal variants ride along) inside the
# def and the row DISCLOSES them: ppalt="N" on --metrics (XML) / "ppalt":N (JSON), ABSENT when 0 — so a
# metric consumer knows the row's structural metrics are a sum over all branches and can discount.
# A bare #if…#endif with NO #else introduces no mutually-exclusive alternative (nothing is summed
# twice), so it deliberately does NOT raise ppalt.
#
# Grammar facts verified by real parses (--match probes on these very fixture shapes), not assumed:
# C, C++ and C# all spell the alternative nodes preproc_else / preproc_elif (C/C++ additionally
# preproc_elifdef), and all of them nest INSIDE the function's own body node, so the def's cc_walk
# sees them. ObjC/CUDA/Metal share the C/C++ preproc node family (see ingest.cpp
# kPreprocConditionalNodes) and inherit the same counting through the same walk.
#
# ── ARMS ─────────────────────────────────────────────────────────────────────────────────────────────
#   0. PRESENCE   — the fixtures spell every shape the arms below claim to assert (green-while-inert
#                   guard, same discipline as preproccondcheck).
#   1. DISCLOSURE — hand-counted ppalt= per fixture fn: #if/#else → 1; #if/#elif/#else → 2;
#                   #ifdef/#elifdef/#else → 2; nested #if-inside-#if with two #else → 2. A
#                   single-constant stub cannot pass all four.
#   2. ABSENT     — a plain fn and a #if-without-#else fn carry NO ppalt= at all (absent, never a bare
#                   "0"), and a non-fn row (struct) never carries it.
#   3. UNCHANGED SUMS — the #if/#else fn still reports the SUMMED cx/ccx/nest (hand-counted: cx=3 is
#                   1 + one if-decision per arm). Disclosure must not change measurement: option (b)
#                   "measure one branch" is the guess this gate exists to forbid.
#   4. C-FAMILY BREADTH — the same #if/#else shape in a .c file (tree-sitter-c) and a .cs method
#                   (tree-sitter-c-sharp) each disclose ppalt="1".
#   5. JSON PARITY — --json --metrics carries "ppalt":1 on the disclosing fn and omits the key on the
#                   plain fn (absent-unless-measured, mirroring locals/tested).
#   6. LEGEND     — the --metrics legend defines ppalt in-band (a reader met an undefined attribute is
#                   the §B7 defect class).
#   7. HYGIENE    — two cold runs byte-identical (determinism), well-formed XML, and warm == cold (the
#                   extraction change is behind kParserVer, so a stale blob must not survive).
#
# Usage:
#   bash test/ppaltcheck.sh
#   RIPWIRE_BIN=build/ripwire bash test/ppaltcheck.sh
#
# Exits non-zero on any failure.

set -u
ROOT="$( cd "$( dirname "$0" )/.." && pwd )"
BIN="${RIPWIRE_BIN:-$ROOT/build/ripwire}"
[ "${BIN#/}" = "$BIN" ] && BIN="$ROOT/$BIN"
TMP="$( mktemp -d )"; trap 'rm -rf "$TMP"' EXIT
fail=0

ok(){   printf '  PASS  %s\n' "$*"; }
no(){   printf '  FAIL  %s\n' "$*"; fail=1; }

[ -x "$BIN" ] || { echo "no ripwire binary at $BIN — build first (cmake --build build -j)"; exit 2; }
command -v xmllint >/dev/null 2>&1 || { echo "xmllint required"; exit 2; }
echo "ppaltcheck: BIN=$BIN  TMP=$TMP"

# ── fixtures ─────────────────────────────────────────────────────────────────────────────────────────
FIX="$TMP/fix"; mkdir -p "$FIX"
cat > "$FIX/pp.cpp" <<'EOF'
int withElse( int a )
{
#if FOO
    if( a ) { return 1; }
    return 2;
#else
    if( a ) { return 4; }
    return 5;
#endif
}
int withElifElse( int a )
{
#if FOO
    return 1;
#elif BAR
    return 2;
#else
    return 3;
#endif
}
int withElifdef( int a )
{
#ifdef FOO
    return 1;
#elifdef BAR
    return 2;
#else
    return 3;
#endif
}
int nestedGuards( int a )
{
#if OUTER
#if INNER
    if( a ) { return 1; }
#else
    return 2;
#endif
#else
    return 3;
#endif
}
int guardOnly( int a )
{
#ifdef FOO
    if( a ) { return 6; }
#endif
    return 0;
}
int plain( int a )
{
    if( a ) { return 7; }
    return 8;
}
struct PlainStruct
{
    int field;
};
EOF
cat > "$FIX/pp.c" <<'EOF'
int c_withElse( int a )
{
#if FOO
    return 1;
#else
    return 2;
#endif
}
EOF
cat > "$FIX/Cond.cs" <<'EOF'
class CondHolder
{
    int WithElse( int a )
    {
#if FOO
        if( a > 0 ) { return 1; }
        return 2;
#else
        if( a > 0 ) { return 4; }
        return 5;
#endif
    }
}
EOF

# ══ 0. PRESENCE — the fixtures spell what the arms below assert ══════════════════════════════════════
presence(){ # presence <file> <literal> <label>
    if grep -qF -- "$2" "$FIX/$1"; then ok "presence: $3"; else no "presence: $3 — fixture drifted, arms below cannot assert"; fi
}
presence pp.cpp '#else'          'C++ #else arm present'
presence pp.cpp '#elif BAR'      'C++ #elif arm present'
presence pp.cpp '#elifdef BAR'   'C++ #elifdef arm present'
presence pp.cpp '#if INNER'      'nested #if-inside-#if present'
presence pp.cpp '#ifdef FOO'     '#ifdef-without-#else control present'
presence pp.cpp 'struct PlainStruct' 'non-fn control row present'
presence pp.c   '#else'          'C #else arm present'
presence Cond.cs '#else'         'C# #else arm present'

# ══ 1+2+3+4. one --metrics run, per-row assertions ═══════════════════════════════════════════════════
"$BIN" "$FIX" --metrics --no-cache >"$TMP/map.xml" 2>"$TMP/map.err"
rc=$?
[ "$rc" -eq 0 ] && ok "--metrics exits 0" || { no "--metrics exits $rc"; head -3 "$TMP/map.err"; }
[ -s "$TMP/map.xml" ] || { echo "ppaltcheck: empty --metrics output, cannot proceed"; exit 2; }

row(){ # row <name> — the one <s …n="name"…> opening tag
    tr '<' '\n' < "$TMP/map.xml" | grep -F "n=\"$1\"" | head -1
}
wants(){ # wants <name> <attr-literal> <label>
    if row "$1" | grep -qF "$2"; then ok "$3"; else no "$3 — row: $( row "$1" )"; fi
}
lacks(){ # lacks <name> <attr-prefix> <label>
    if row "$1" | grep -qF "$2"; then no "$3 — row: $( row "$1" )"; else ok "$3"; fi
}

# 1. DISCLOSURE — four distinct hand-counted values.
wants withElse     'ppalt="1"' 'disclosure: #if/#else fn → ppalt="1"'
wants withElifElse 'ppalt="2"' 'disclosure: #if/#elif/#else fn → ppalt="2"'
wants withElifdef  'ppalt="2"' 'disclosure: #ifdef/#elifdef/#else fn → ppalt="2"'
wants nestedGuards 'ppalt="2"' 'disclosure: nested guards, one #else each level → ppalt="2"'

# 2. ABSENT — never a bare 0, and never on a non-fn row.
lacks plain     'ppalt=' 'absent: plain fn carries no ppalt='
lacks guardOnly 'ppalt=' 'absent: #if-without-#else introduces no alternative — no ppalt='
lacks PlainStruct 'ppalt=' 'absent: a struct row never carries ppalt='

# 3. UNCHANGED SUMS — disclosure, not branch-guessing: the summed measurement is pinned.
wants withElse 'cx="3"'   'unchanged sums: #if/#else fn still reports cx=3 (1 + one if per arm)'
wants withElse 'ccx="2"'  'unchanged sums: ccx=2 (one +1 if per arm)'
wants withElse 'nest="1"' 'unchanged sums: nest=1'

# 4. C-FAMILY BREADTH — the C and C# grammars disclose through the same walk.
wants c_withElse 'ppalt="1"' 'breadth: C (.c, tree-sitter-c) #if/#else fn → ppalt="1"'
wants WithElse   'ppalt="1"' 'breadth: C# (.cs) #if/#else method → ppalt="1"'

# ══ 5. JSON PARITY ═══════════════════════════════════════════════════════════════════════════════════
"$BIN" "$FIX" --json --metrics --no-cache >"$TMP/map.json" 2>/dev/null
jrow(){ tr '{' '\n' < "$TMP/map.json" | grep -F "\"$1\"" | head -1; }
if jrow withElse | grep -qF '"ppalt":1'; then ok "json: withElse carries \"ppalt\":1"; else no "json: withElse missing \"ppalt\":1 — row: $( jrow withElse )"; fi
if jrow plain | grep -qF '"ppalt"'; then no "json: plain fn must OMIT the ppalt key — row: $( jrow plain )"; else ok "json: plain fn omits the ppalt key"; fi

# ══ 6. LEGEND — the attribute is defined in-band on the map that carries it ══════════════════════════
if grep -qF 'ppalt=' "$TMP/map.xml" && head -c 2000 "$TMP/map.xml" | grep -qF 'ppalt'; then
    ok "legend: the metrics legend defines ppalt"
else
    no "legend: ppalt emitted but not defined in the metrics legend header"
fi

# ══ 7. HYGIENE — determinism, well-formedness, warm == cold ══════════════════════════════════════════
"$BIN" "$FIX" --metrics --no-cache >"$TMP/cold2.xml" 2>/dev/null
if diff -q "$TMP/map.xml" "$TMP/cold2.xml" >/dev/null 2>&1; then
    ok "hygiene: two cold runs are byte-identical (determinism)"
else
    no "hygiene: two cold runs DIFFER"
fi
if xmllint --noout "$TMP/map.xml" >/dev/null 2>&1; then
    ok "hygiene: --metrics map is well-formed XML"
else
    no "hygiene: --metrics map failed xmllint"
fi
CACHE="$TMP/blob.bin"
"$BIN" "$FIX" --metrics --cache="$CACHE" >"$TMP/warm0.xml" 2>/dev/null   # builds the blob
"$BIN" "$FIX" --metrics --cache="$CACHE" >"$TMP/warm1.xml" 2>/dev/null   # reads it back
if diff -q "$TMP/map.xml" "$TMP/warm1.xml" >/dev/null 2>&1; then
    ok "hygiene: warm run == cold run (ppalt survives the def cache round-trip)"
else
    no "hygiene: warm run DIFFERS from cold — ppalt not round-tripped through the cache"
    diff "$TMP/map.xml" "$TMP/warm1.xml" | head -5
fi

echo
if [ "$fail" -eq 0 ]; then echo "ppaltcheck: ALL PASS"; exit 0; else echo "ppaltcheck: FAILURES"; exit 1; fi
