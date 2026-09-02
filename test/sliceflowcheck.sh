#!/usr/bin/env bash
# sliceflowcheck.sh — gate for --slice-flow=back|fwd|both (+ --slice-depth=N): the ARISE rung-2
# cross-statement data-flow slice. v1 (--slice=SYM:VAR) emits the flat per-line def-use rows of ONE
# variable; rung 2 follows VALUE FLOW across statements over reaching-definition def-use edges — the
# paper's own slicer semantics (arXiv:2605.03117: seed variable + direction, bounded BFS over
# def-use edges, stops at function boundaries, ordered role-carrying steps).
#
# RED-FIRST PROOF SHAPE: every arm asserts flow-SPECIFIC bytes (a flow=/depth=/steps= attribute, a
# v=/d=/f= row, a refusal sentence only this rung prints) — never a bare exit code. The baseline
# binary refuses --slice-flow= as an unknown flag at exit 1 with NO XML and NONE of these sentences,
# so each arm fails against it (the green-while-inert trap CONTRIBUTING §2 names).
#
# THE SEMANTIC HEART is the stray/dead pair in the C++ fixture:
#     int mid = seed + 1;     int out = mid * 2;     int stray = 7;
#     out += stray;           int dead = seed - 1;   sink( dead );   return out;
#   backward from `out`  MUST include stray (it feeds out via +=) and MUST NOT include dead;
#   forward  from `seed` MUST include dead  (seed feeds it)         and MUST NOT include stray.
# A text-proximity or same-line-join impostor cannot produce that asymmetry; only real def-use
# reachability can.
#
# Arms:
#   (1)  forward slice from a parameter: the transitive chain seed->mid->out with depths/roles/f=
#   (2)  backward slice from a local: stray in, dead out, param reached at d=2
#   (3)  depth bound: --slice-depth=2 cuts the chain and DISCLOSES it (flow_truncated="1")
#   (4)  Python chain (family-independent post-processing over the same classifier)
#   (5)  flow="both" is the union (and dedup keeps the backward rows)
#   (6)  refusals: bad direction value / --slice-flow without --slice / --slice-depth without
#        --slice-flow / flow on the bare inventory (no seed VAR) / depth out of 1..32
#   (7)  v1 shape unchanged without the new flags (no flow= attribute, no v= rows)
#   (8)  determinism (x3, byte-identical)
#   (9)  xmllint well-formedness
#   (10) legend honesty: reaching-definition wording, f=/d=/steps= defined, line-granularity, alias
#        and no-control-dependence limits
#   (27) preprocessor-dead regions (C-family): `#if 0` bodies and the `#else` of `#if 1` are DROPPED
#        (preproc_rows= counts them) so a dead def can never replace the live chain; every other
#        conditional region (`#ifdef`/`#ifndef`/`#if EXPR`) is build-dependent, so its rows are KEPT,
#        flagged pp="1", and a pp def does not kill the reach of the unconditional def before it
#   (28) block-scope separation: a name declared twice in one definition is TWO variables — the flow
#        walk binds each use to the innermost enclosing declaration (never chains into a sibling
#        block's shadow), rows of a shadowed name carry b= (the binding's declaration line), the
#        inventory lists each binding, and the legend states the scope rule per family
#   (29) JS destructuring chains (s <- x,y <- o) and the widened under-count clause: the legend names
#        by-reference/out-parameter/macro writes beside receiver mutation, and defines k=scope
#
# Usage:  RIPWIRE_BIN=build/ripwire bash test/sliceflowcheck.sh   |   bash test/sliceflowcheck.sh path/to/ripwire

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

cat > "$WORK/src/a.cpp" <<'EOF'
void sink( int v );

int pipeline( int seed )
{
    int mid = seed + 1;
    int out = mid * 2;
    int stray = 7;
    out += stray;
    int dead = seed - 1;
    sink( dead );
    return out;
}
EOF

cat > "$WORK/src/calc.py" <<'EOF'
def pyflow(a):
    b = a + 1
    c = b * 2
    z = 9
    return c
EOF

# arm (25)'s fuel: statements spanning several LINES via implicit continuation — the operand lives on
# the CONTINUATION line, so line-keyed chaining alone sees nothing (steps=0, the 2026-08-31 Python
# smoke-pass defect). Appended AFTER pyflow, so every line number the arms above address is untouched:
# wideflow at L7, mid's def statement spans 8-9 (scale on 9), out's spans 10-11 (mid on 11), return 12.
cat >> "$WORK/src/calc.py" <<'EOF'

def wideflow(base, scale):
    mid = combine(base,
                  scale)
    out = (1 +
           mid)
    return out
EOF

# the at-seed arms' fuel: `helper` defined in TWO files (ambiguous by name — the seed must narrow it);
# a.cpp's copy starts at L14, its L16 names two locals (r,q), its L17 names exactly one (r). Appended
# AFTER pipeline, so every line number the arms above address is untouched.
cat >> "$WORK/src/a.cpp" <<'EOF'

int helper( int q )
{
    int r = q + 3;
    return r;
}
EOF

cat > "$WORK/src/b.cpp" <<'EOF'
int helper( int z )
{
    return z * 2;
}
EOF

# arm (25c)'s C-family fuel, appended LAST so nothing above moves: widecalc at L20, gamma's def
# statement spans 22-23 (beta on the continuation line), delta's spans 24-25 (gamma on 25), return 26.
cat >> "$WORK/src/a.cpp" <<'EOF'

int widecalc( int alpha, int beta )
{
    int gamma = alpha +
                beta;
    int delta = ( 1 +
                  gamma );
    return delta;
}
EOF

# arm (26)'s fuel: the RECEIVER-MUTATION shape. Every write to `bag` happens inside a method call, so
# the name-based classifier — which has no types and no callee bodies — sees only reads and the slice
# reports steps="0". Appended LAST; arm (26) asserts NO line numbers, so nothing above can move it.
cat >> "$WORK/src/a.cpp" <<'EOF'

int gather( int seed, int cap )
{
    std::vector<int> bag;
    bag.reserve( cap );
    bag.push_back( seed );
    return bag.size();
}
EOF

# arm (27)'s fuel: PREPROCESSOR-CONDITIONAL regions, in a file of their own so no line above moves.
# if0: the `#if 0` body holds a def of v that no build ever compiles — before the fix it was the
# reaching def of `int w = v;` and the live chain w<-v<-n was REPLACED (not truncated) by `v = 111;`
# (audit 2026-09-02, F-01). ifdef_guard: a build-DEPENDENT region — nobody can decide it without
# the build's macro set, so the honest posture is keep + flag, never drop and never trust.
cat > "$WORK/src/pp.cpp" <<'EOF'
int if0( int n )
{
    int v = n;
#if 0
    v = 111;
#endif
    int w = v;
    return w;
}

int ifdef_guard( int n )
{
    int s = n;
#ifdef NEVER_DEFINED_XYZ
    s = 7;
#endif
    int t = s;
    return t;
}

int if1else( int n )
{
    int a = n;
#if 1
    a = a + 1;
#else
    a = 999;
#endif
    return a;
}
EOF

# arm (28)'s fuel: BLOCK-SCOPED SHADOWING, in a file of its own. Before the fix the backward walk from
# r chained into the inner block's `v` (l5/l6) and never reached `int v = n;` (l3) or the param — the
# answer was a chain through a variable r does not read (audit 2026-09-02, F-02). Go and JS shapes
# pin the rule outside C: an occurrence binds to the innermost enclosing block whose declaration
# precedes it; Go's `v := v + 1` reads the OUTER v in its own initializer; JS `var` is function-scoped.
cat > "$WORK/src/scope.cpp" <<'EOF'
int shadowing( int n )
{
    int v = n;
    {
        int v = 7;
        v = v + 1;
    }
    int r = v;
    return r;
}
EOF
cat > "$WORK/src/scope.go" <<'EOF'
package main

func goshadow(n int) int {
	v := n
	if v > 0 {
		v := v + 1
		_ = v
	}
	r := v
	return r
}
EOF
cat > "$WORK/src/scope.js" <<'EOF'
function jsshadow( n ) {
  let v = n;
  {
    let v = 7;
    v = v + 1;
  }
  if ( n ) { var hoisted = n; }
  let r = v + hoisted;
  return r;
}
EOF

# arm (29)'s fuel: the audit's own JS shape — before the fix `--slice=destructure:s --slice-flow=back`
# returned steps="0"; the whole chain s <- x,y <- o was lost (F-08).
cat > "$WORK/src/d.js" <<'EOF'
function destructure( o ) {
  const { x, y } = o;
  let s = x + y;
  return s;
}
EOF

echo "sliceflowcheck: BIN=$BIN  (temp corpus, no git)"

run(){ ( cd "$WORK" && "$BIN" . "$@" --no-cache 2>/dev/null ); }
rc(){ ( cd "$WORK" && "$BIN" . "$@" --no-cache >/dev/null 2>&1 ); echo $?; }
err(){ ( cd "$WORK" && "$BIN" . "$@" --no-cache 2>&1 >/dev/null ); }
# strip the leading legend comment(s) so grep hits the element, not the prose (the slicecheck trap)
elem(){ printf '%s' "$1" | sed 's/.*--><slice/<slice/'; }
attr(){ printf '%s' "$( elem "$1" )" | grep -oE "^<slice [^>]*" | grep -oE "$2=\"[^\"]*\"" | head -1; }
# flow rows carry v= — match one by var+line
frow(){ printf '%s' "$( elem "$1" )" | grep -oE "<s l=\"$3\"[^>]*v=\"$2\"[^>]*>"; }

# ── (1) forward slice from the parameter seed ───────────────────────────────────────────────────────
F="$( run --slice=pipeline:seed --slice-flow=fwd )"
[ "$( attr "$F" flow )" = 'flow="fwd"' ] && [ "$( attr "$F" depth )" = 'depth="8"' ] \
    && ok "(1) root carries flow=\"fwd\" and the disclosed default depth=\"8\"" \
    || { no "(1) expected flow=\"fwd\" depth=\"8\" on the root"; printf '%s\n' "$F"; }
[ "$( attr "$F" steps )" = 'steps="4"' ] \
    && ok "(1) steps=\"4\" — exactly the four flow rows the chain reaches" \
    || { no "(1) expected steps=\"4\""; printf '%s\n' "$F"; }
printf '%s' "$( frow "$F" mid 6 )" | grep -q 'd="2" f="5"' \
    && ok "(1) seed->mid: mid's reached use at l=6 rows d=2 f=5" \
    || { no "(1) expected <s l=\"6\" ... v=\"mid\" d=\"2\" f=\"5\">"; printf '%s\n' "$F"; }
printf '%s' "$( frow "$F" dead 10 )" | grep -q 't="call-arg"' \
    && ok "(1) seed->dead: the call-arg use at l=10 is in the forward slice" \
    || { no "(1) expected a v=\"dead\" l=\"10\" t=\"call-arg\" row"; printf '%s\n' "$F"; }
printf '%s' "$( frow "$F" out 8 )" | grep -q 'k="both"' && printf '%s' "$( frow "$F" out 11 )" | grep -q 'd="4"' \
    && ok "(1) seed->mid->out: the += line (k=both, d=3) and the return read (d=4) both reached" \
    || { no "(1) expected v=\"out\" rows at l=8 (k=both) and l=11 (d=4)"; printf '%s\n' "$F"; }
printf '%s' "$( elem "$F" )" | grep -q 'v="stray"' \
    && { no "(1) v=\"stray\" must NOT be in the forward slice from seed (stray does not receive seed's value)"; printf '%s\n' "$F"; } \
    || ok "(1) stray is absent forward — the slice is reachability, not proximity"

# ── (2) backward slice from out ─────────────────────────────────────────────────────────────────────
B="$( run --slice=pipeline:out --slice-flow=back )"
[ "$( attr "$B" flow )" = 'flow="back"' ] && [ "$( attr "$B" steps )" = 'steps="3"' ] \
    && ok "(2) root carries flow=\"back\" steps=\"3\"" \
    || { no "(2) expected flow=\"back\" steps=\"3\""; printf '%s\n' "$B"; }
printf '%s' "$( frow "$B" mid 5 )" | grep -q 'k="def" t="decl" v="mid" d="1" f="6"' \
    && ok "(2) out<-mid: mid's reaching def at l=5 rows d=1 f=6" \
    || { no "(2) expected <s l=\"5\" k=\"def\" t=\"decl\" v=\"mid\" d=\"1\" f=\"6\">"; printf '%s\n' "$B"; }
printf '%s' "$( frow "$B" stray 7 )" | grep -q 'd="1" f="8"' \
    && ok "(2) out<-stray: the += line pulls stray's def in at d=1" \
    || { no "(2) expected v=\"stray\" l=\"7\" d=\"1\" f=\"8\""; printf '%s\n' "$B"; }
printf '%s' "$( frow "$B" seed 3 )" | grep -q 't="param" v="seed" d="2"' \
    && ok "(2) out<-mid<-seed: the parameter reached at d=2" \
    || { no "(2) expected v=\"seed\" l=\"3\" t=\"param\" d=\"2\""; printf '%s\n' "$B"; }
printf '%s' "$( elem "$B" )" | grep -q 'v="dead"' \
    && { no "(2) v=\"dead\" must NOT be in the backward slice of out (dead never feeds out)"; printf '%s\n' "$B"; } \
    || ok "(2) dead is absent backward — the stray/dead asymmetry holds"

# ── (3) the depth bound cuts AND discloses ──────────────────────────────────────────────────────────
D="$( run --slice=pipeline:seed --slice-flow=fwd --slice-depth=2 )"
[ "$( attr "$D" depth )" = 'depth="2"' ] && [ "$( attr "$D" flow_truncated )" = 'flow_truncated="1"' ] \
    && ok "(3) --slice-depth=2: depth=\"2\" echoed and flow_truncated=\"1\" disclosed" \
    || { no "(3) expected depth=\"2\" flow_truncated=\"1\""; printf '%s\n' "$D"; }
printf '%s' "$( elem "$D" )" | grep -q 'v="out"' \
    && { no "(3) d=3+ rows (v=\"out\") must be cut by --slice-depth=2"; printf '%s\n' "$D"; } \
    || ok "(3) the d=3 continuation is cut by the bound"

# ── (4) Python chain ────────────────────────────────────────────────────────────────────────────────
P="$( run --slice=pyflow:a --slice-flow=fwd )"
printf '%s' "$( frow "$P" b 3 )" | grep -q 'd="2"' && printf '%s' "$( frow "$P" c 5 )" | grep -q 'd="3"' \
    && ok "(4) python a->b->c: b's use at l=3 (d=2) and c's return read at l=5 (d=3)" \
    || { no "(4) expected v=\"b\" l=\"3\" d=\"2\" and v=\"c\" l=\"5\" d=\"3\""; printf '%s\n' "$P"; }
printf '%s' "$( elem "$P" )" | grep -q 'v="z"' \
    && { no "(4) v=\"z\" must NOT appear (z never receives a's value)"; printf '%s\n' "$P"; } \
    || ok "(4) the unrelated python local stays out"

# ── (5) both = union, deduped ───────────────────────────────────────────────────────────────────────
U="$( run --slice=pipeline:out --slice-flow=both )"
[ "$( attr "$U" flow )" = 'flow="both"' ] && [ "$( attr "$U" steps )" = 'steps="3"' ] \
    && ok "(5) flow=\"both\" on out: the union dedups to the same three rows" \
    || { no "(5) expected flow=\"both\" steps=\"3\""; printf '%s\n' "$U"; }

# ── (6) refusals — each fuses exit code AND the rung-specific sentence ──────────────────────────────
E1="$( err --slice=pipeline:seed --slice-flow=diagonal )"
[ "$( rc --slice=pipeline:seed --slice-flow=diagonal )" != 0 ] && printf '%s' "$E1" | grep -q 'back|fwd|both' \
    && ok "(6) unknown direction refused, values named (back|fwd|both)" \
    || { no "(6) --slice-flow=diagonal should refuse naming back|fwd|both"; printf '%s\n' "$E1"; }
E2="$( err --slice-flow=back )"
[ "$( rc --slice-flow=back )" != 0 ] && printf '%s' "$E2" | grep -q -- '--slice-flow.*--slice=' \
    && ok "(6) --slice-flow without --slice refused loudly" \
    || { no "(6) --slice-flow alone should refuse and name --slice="; printf '%s\n' "$E2"; }
E3="$( err --slice-depth=3 )"
[ "$( rc --slice-depth=3 )" != 0 ] && printf '%s' "$E3" | grep -q -- '--slice-depth.*--slice-flow' \
    && ok "(6) --slice-depth without --slice-flow refused loudly" \
    || { no "(6) --slice-depth alone should refuse and name --slice-flow"; printf '%s\n' "$E3"; }
E4="$( err --slice=pipeline --slice-flow=back )"
[ "$( rc --slice=pipeline --slice-flow=back )" != 0 ] && printf '%s' "$E4" | grep -q 'seed variable' \
    && ok "(6) flow on the bare inventory refused — a flow needs a seed variable" \
    || { no "(6) --slice=SYM --slice-flow should refuse asking for a seed variable"; printf '%s\n' "$E4"; }
[ "$( rc --slice=pipeline:seed --slice-flow=fwd --slice-depth=33 )" != 0 ] \
    && [ "$( rc --slice=pipeline:seed --slice-flow=fwd --slice-depth=0 )" != 0 ] \
    && ok "(6) depth outside 1..32 refused (0 and 33)" \
    || no "(6) --slice-depth=0 / 33 should both refuse"

# ── (7) v1 shape unchanged without the new flags ────────────────────────────────────────────────────
V="$( run --slice=pipeline:out )"
if printf '%s' "$( elem "$V" )" | grep -qE 'flow=|v="|d="|steps='; then
    no "(7) plain --slice must not grow flow attributes (purely additive contract)"
else
    printf '%s' "$( elem "$V" )" | grep -q '<s l="6" k="def" t="decl">' \
        && ok "(7) plain --slice=pipeline:out keeps the v1 row shape exactly" \
        || { no "(7) v1 rows missing from plain --slice"; printf '%s\n' "$V"; }
fi

# ── (8) determinism (x3) ────────────────────────────────────────────────────────────────────────────
X1="$( run --slice=pipeline:seed --slice-flow=fwd )"; X2="$( run --slice=pipeline:seed --slice-flow=fwd )"; X3="$( run --slice=pipeline:seed --slice-flow=fwd )"
Y1="$( run --slice=pipeline:out --slice-flow=both )"; Y2="$( run --slice=pipeline:out --slice-flow=both )"
[ -n "$X1" ] && [ "$X1" = "$X2" ] && [ "$X2" = "$X3" ] && [ -n "$Y1" ] && [ "$Y1" = "$Y2" ] \
    && ok "(8) determinism: repeated flow runs byte-identical (fwd + both)" \
    || no "(8) determinism: flow runs differ or emitted nothing"

# ── (9) well-formed XML ─────────────────────────────────────────────────────────────────────────────
if command -v xmllint >/dev/null 2>&1; then
    ( cd "$WORK" && "$BIN" . --slice=pipeline:seed --slice-flow=fwd --no-cache 2>/dev/null | xmllint --noout - ) \
        && ok "(9) xmllint: flow output is well-formed XML" \
        || no "(9) xmllint: flow output is NOT well-formed XML"
else
    echo "  SKIP  (9) xmllint not installed — well-formedness not checked"
fi

# ── (10) legend honesty ─────────────────────────────────────────────────────────────────────────────
if printf '%s' "$F" | grep -q 'reaching-definition' \
   && printf '%s' "$F" | grep -q 'd=' && printf '%s' "$F" | grep -q 'f=' && printf '%s' "$F" | grep -q 'steps=' \
   && printf '%s' "$F" | grep -qi 'line-granular' && printf '%s' "$F" | grep -q 'no alias analysis' \
   && printf '%s' "$F" | grep -qi 'no control dependence' && printf '%s' "$F" | grep -qi 'guard'; then
    ok "(10) legend defines the flow vocabulary (reaching-definition, d=, f=, steps=, line-granular + alias + control-dependence limits)"
else
    no "(10) flow legend must define d=/f=/steps= and state the reaching-definition + line-granularity + alias + control-dependence limits"
fi

# ═══ the at-seed arms (lane/tc-sliceat): --slice takes the FILE:LINE seed — ARISE's (file, line[, var]) ═══
#
# RED-FIRST PROOF SHAPE: the baseline binary DROPS --at when --slice is given ("takes precedence …
# IGNORED this run") and serves the @-selector as a plain inventory — so every arm here asserts
# seed-SPECIFIC bytes (a seed=/var_from=/seed_vars= attribute, a refusal sentence only the composition
# prints, the ABSENCE of the IGNORED warning) that the baseline cannot produce.

# ── (11) --slice + --at compose: no IGNORED warning, and the seed line's ONE local is pre-picked ────
S11="$( run --slice=pipeline --at=src/a.cpp:7 )"
E11="$( err --slice=pipeline --at=src/a.cpp:7 )"
if printf '%s' "$E11" | grep -q 'IGNORED this run'; then
    no "(11) --at beside --slice must SEED the slice, not be dropped with the precedence warning"
else
    [ "$( attr "$S11" var )" = 'var="stray"' ] \
        && ok "(11) --slice=pipeline --at=src/a.cpp:7: L7 names exactly one sliceable local — var=\"stray\" pre-picked" \
        || { no "(11) expected var=\"stray\" pre-picked from the seed line"; printf '%s\n' "$S11"; }
fi

# ── (12) the pre-pick DISCLOSES how the seed resolved ───────────────────────────────────────────────
[ "$( attr "$S11" seed )" = 'seed="src/a.cpp:7"' ] && [ "$( attr "$S11" var_from )" = 'var_from="seed"' ] \
    && [ "$( attr "$S11" sym )" = 'sym="pipeline"' ] \
    && ok "(12) seed=\"src/a.cpp:7\" var_from=\"seed\" sym=\"pipeline\" — the resolution is disclosed, not implied" \
    || { no "(12) expected seed=/var_from=/sym= disclosure on the pre-picked slice"; printf '%s\n' "$S11"; }
printf '%s' "$( elem "$S11" )" | grep -q '<s l="7" k="def"' && printf '%s' "$( elem "$S11" )" | grep -q '<s l="8" k="use"' \
    && ok "(12) the pre-picked slice serves stray's v1 rows (def l=7, use l=8)" \
    || { no "(12) expected stray's def/use rows"; printf '%s\n' "$S11"; }

# ── (13) seed line naming TWO locals: inventory with the candidates marked, never a guess ───────────
S13="$( run --slice=pipeline --at=src/a.cpp:5 )"
[ "$( attr "$S13" seed_vars )" = 'seed_vars="2"' ] && [ -z "$( attr "$S13" var )" ] \
    && ok "(13) L5 names mid+seed: no var pre-picked, seed_vars=\"2\" disclosed" \
    || { no "(13) expected the inventory with seed_vars=\"2\" and no var="; printf '%s\n' "$S13"; }
printf '%s' "$( elem "$S13" )" | grep -q '<v n="mid"[^>]*seed="1"' && printf '%s' "$( elem "$S13" )" | grep -q '<v n="seed"[^>]*seed="1"' \
    && ok "(13) the two candidates carry seed=\"1\" in the inventory" \
    || { no "(13) expected seed=\"1\" on the mid and seed rows"; printf '%s\n' "$S13"; }
printf '%s' "$( elem "$S13" )" | grep -q '<v n="stray"[^>]*seed="1"' \
    && { no "(13) stray is NOT on the seed line — it must not carry seed=\"1\""; printf '%s\n' "$S13"; } \
    || ok "(13) off-line locals stay unmarked"

# ── (14) seed line naming NO local: the plain inventory, count disclosed as zero ────────────────────
S14="$( run --slice=pipeline --at=src/a.cpp:4 )"
[ "$( attr "$S14" seed_vars )" = 'seed_vars="0"' ] && [ "$( attr "$S14" vars )" = 'vars="5"' ] \
    && ok "(14) a brace-only seed line: seed_vars=\"0\", the full inventory still served" \
    || { no "(14) expected seed_vars=\"0\" vars=\"5\""; printf '%s\n' "$S14"; }

# ── (15) explicit VAR + seed + flow: v2 semantics unchanged under the seed ──────────────────────────
S15="$( run --slice=pipeline:out --at=src/a.cpp:6 --slice-flow=back )"
[ "$( attr "$S15" flow )" = 'flow="back"' ] && [ "$( attr "$S15" seed )" = 'seed="src/a.cpp:6"' ] \
    && [ "$( attr "$S15" var )" = 'var="out"' ] && [ -z "$( attr "$S15" var_from )" ] \
    && ok "(15) explicit :out + seed + flow compose; var_from absent (the spec picked the var, not the seed)" \
    || { no "(15) expected flow=\"back\" seed=\"src/a.cpp:6\" var=\"out\" without var_from"; printf '%s\n' "$S15"; }
printf '%s' "$( frow "$S15" stray 7 )" | grep -q 'd="1"' \
    && { printf '%s' "$( elem "$S15" )" | grep -q 'v="dead"' \
         && { no "(15) dead must stay out of the backward flow under a seed"; printf '%s\n' "$S15"; } \
         || ok "(15) the stray/dead asymmetry holds under the seed (v2 semantics unchanged)"; } \
    || { no "(15) expected stray's backward row under the seed"; printf '%s\n' "$S15"; }

# ── (16) the seed NARROWS an ambiguous selector instead of refusing it ──────────────────────────────
[ "$( rc --slice=helper )" != 0 ] \
    && ok "(16) --slice=helper alone still refuses (2 definitions)" \
    || no "(16) --slice=helper should be ambiguous without a seed"
S16="$( run --slice=helper --at=src/a.cpp:17 )"
[ "$( attr "$S16" sym )" = 'sym="helper"' ] && [ "$( attr "$S16" var )" = 'var="r"' ] \
    && printf '%s' "$( attr "$S16" p )" | grep -q 'src/a.cpp' \
    && ok "(16) --at=src/a.cpp:17 narrows to a.cpp's helper and pre-picks r" \
    || { no "(16) expected the seed to narrow the 2-def selector to src/a.cpp's helper"; printf '%s\n' "$S16"; }

# ── (17) seed and spec DISAGREE: loud refusal naming both, never a silent pick ──────────────────────
E17a="$( err --slice=helper --at=src/a.cpp:7 )"
[ "$( rc --slice=helper --at=src/a.cpp:7 )" != 0 ] \
    && printf '%s' "$E17a" | grep -q 'pipeline' && printf '%s' "$E17a" | grep -q 'helper' \
    && ok "(17) seed inside pipeline vs --slice=helper: refused naming both" \
    || { no "(17) expected a disagreement refusal naming pipeline and helper"; printf '%s\n' "$E17a"; }
E17b="$( err --slice=pipeline --at=src/b.cpp:3 )"
[ "$( rc --slice=pipeline --at=src/b.cpp:3 )" != 0 ] \
    && printf '%s' "$E17b" | grep -q 'helper' \
    && ok "(17) unique spec + seed in a different definition: refused, seed's definition named" \
    || { no "(17) expected a disagreement refusal naming helper (the seed's definition)"; printf '%s\n' "$E17b"; }

# ── (18) a plain-identifier spec beside a seed is the ARISE (file, line, VARIABLE) form ─────────────
S18="$( run --slice=dead --at=src/a.cpp:4 )"
[ "$( attr "$S18" sym )" = 'sym="pipeline"' ] && [ "$( attr "$S18" var )" = 'var="dead"' ] \
    && printf '%s' "$( elem "$S18" )" | grep -q '<s l="9" k="def"' \
    && ok "(18) --slice=dead --at=src/a.cpp:4: no symbol 'dead' exists, so the spec is the seed's VARIABLE" \
    || { no "(18) expected sym=\"pipeline\" var=\"dead\" via the spec-as-variable reading"; printf '%s\n' "$S18"; }

# ── (19) unknown variable beside a seed: the locals-listing refusal, not a silent inventory ─────────
E19="$( err --slice=nosuchvar --at=src/a.cpp:4 )"
[ "$( rc --slice=nosuchvar --at=src/a.cpp:4 )" != 0 ] && printf '%s' "$E19" | grep -q 'stray' \
    && ok "(19) --slice=nosuchvar + seed: refused, sliceable locals listed" \
    || { no "(19) expected the unknown-var refusal listing pipeline's locals"; printf '%s\n' "$E19"; }

# ── (20) a faulted seed refuses through --slice with the shared at-diagnosis ────────────────────────
E20a="$( err --slice=pipeline --at=src/a.cpp:999 )"
[ "$( rc --slice=pipeline --at=src/a.cpp:999 )" != 0 ] && printf '%s' "$E20a" | grep -q 'has only' \
    && ok "(20) seed past EOF: the LineOutOfRange diagnosis speaks through --slice" \
    || { no "(20) expected the shared line-out-of-range clause"; printf '%s\n' "$E20a"; }
E20b="$( err --slice=pipeline --at=nosuch.cpp:3 )"
[ "$( rc --slice=pipeline --at=nosuch.cpp:3 )" != 0 ] && printf '%s' "$E20b" | grep -q 'no indexed file' \
    && ok "(20) unmatched seed file: the FileUnmatched diagnosis speaks through --slice" \
    || { no "(20) expected the shared no-indexed-file clause"; printf '%s\n' "$E20b"; }

# ── (21) the @-selector spelling pre-picks identically (one seed grammar, two spellings) ────────────
S21="$( run --slice=@src/a.cpp:7 )"
[ "$( attr "$S21" var )" = 'var="stray"' ] && [ "$( attr "$S21" var_from )" = 'var_from="seed"' ] \
    && [ "$( attr "$S21" seed )" = 'seed="src/a.cpp:7"' ] \
    && ok "(21) --slice=@src/a.cpp:7 pre-picks stray with the same disclosure as the --at form" \
    || { no "(21) expected the @-selector to pre-pick var=\"stray\" var_from=\"seed\""; printf '%s\n' "$S21"; }
E21="$( err --slice=@src/a.cpp:7 --at=src/a.cpp:5 )"
[ "$( rc --slice=@src/a.cpp:7 --at=src/a.cpp:5 )" != 0 ] && printf '%s' "$E21" | grep -qi 'one seed' \
    && ok "(21) an @-selector beside --at is TWO seeds: refused loudly" \
    || { no "(21) expected the two-seeds refusal"; printf '%s\n' "$E21"; }

# ── (22) unseeded runs carry NONE of the seed vocabulary (purely additive) ──────────────────────────
S22="$( run --slice=pipeline:out )"; S22b="$( run --slice=pipeline )"
if printf '%s' "$( elem "$S22" )$( elem "$S22b" )" | grep -qE 'seed=|seed_vars=|var_from='; then
    no "(22) plain --slice must not grow seed attributes (purely additive contract)"
else
    ok "(22) unseeded --slice output carries no seed vocabulary"
fi

# ── (23) determinism (x2) + well-formedness on seeded output ────────────────────────────────────────
T1="$( run --slice=pipeline --at=src/a.cpp:7 )"; T2="$( run --slice=pipeline --at=src/a.cpp:7 )"
[ -n "$T1" ] && [ "$T1" = "$T2" ] \
    && ok "(23) determinism: seeded runs byte-identical" \
    || no "(23) determinism: seeded runs differ or emitted nothing"
if command -v xmllint >/dev/null 2>&1; then
    ( cd "$WORK" && "$BIN" . --slice=pipeline --at=src/a.cpp:7 --no-cache 2>/dev/null | xmllint --noout - ) \
        && ( cd "$WORK" && "$BIN" . --slice=pipeline --at=src/a.cpp:5 --no-cache 2>/dev/null | xmllint --noout - ) \
        && ok "(23) xmllint: seeded outputs are well-formed XML" \
        || no "(23) xmllint: seeded output is NOT well-formed XML"
else
    echo "  SKIP  (23) xmllint not installed — well-formedness not checked"
fi

# ── (24) legend honesty: the seed vocabulary is defined exactly when it is armed ────────────────────
legend(){ printf '%s' "$1" | sed 's/--><slice.*//'; }
if printf '%s' "$( legend "$S11" )" | grep -q 'seed=' && printf '%s' "$( legend "$S11" )" | grep -q 'var_from=' \
   && printf '%s' "$( legend "$S13" )" | grep -q 'seed_vars='; then
    ok "(24) seeded legends define seed=/var_from=/seed_vars= where the reader meets them"
else
    no "(24) seeded output must define its seed vocabulary in the legend"
fi
if printf '%s' "$( legend "$S22" )" | grep -qE 'seed=|seed_vars=|var_from='; then
    no "(24) the unseeded legend must NOT carry the seed vocabulary (G4 density)"
else
    ok "(24) unseeded legend stays free of the seed vocabulary"
fi

# ── (25) multi-line statements chain as ONE statement (the 2026-08-31 Python smoke-pass defect) ─────
# A def whose statement spans several lines must chain through operands on its CONTINUATION lines —
# statement-anchored chaining, not line-keyed. Red against the pre-fix binary: steps="0" on all three.
W="$( run --slice=calc.py:wideflow:out --slice-flow=back )"
[ "$( attr "$W" steps )" = 'steps="3"' ] \
    && ok "(25a) py back through continuations: steps=\"3\" (mid, then base+scale)" \
    || { no "(25a) expected steps=\"3\" — a continuation-line operand must chain"; printf '%s\n' "$W"; }
printf '%s' "$( frow "$W" mid 8 )" | grep -q 'd="1" f="10"' \
    && ok "(25a) out<-mid: mid's def at l=8 reached d=1 from out's ANCHOR line f=10" \
    || { no "(25a) expected <s l=\"8\" ... v=\"mid\" d=\"1\" f=\"10\">"; printf '%s\n' "$W"; }
printf '%s' "$( frow "$W" base 7 )" | grep -q 'd="2"' && printf '%s' "$( frow "$W" scale 7 )" | grep -q 'd="2" f="8"' \
    && ok "(25a) mid<-base+scale: BOTH params reached d=2 — scale sits on mid's continuation line" \
    || { no "(25a) expected v=\"base\" and v=\"scale\" param rows at l=7 d=2"; printf '%s\n' "$W"; }
WF="$( run --slice=calc.py:wideflow:scale --slice-flow=fwd )"
[ "$( attr "$WF" steps )" = 'steps="2"' ] \
    && printf '%s' "$( frow "$WF" mid 11 )" | grep -q 'd="2" f="8"' \
    && printf '%s' "$( frow "$WF" out 12 )" | grep -q 'd="3" f="10"' \
    && ok "(25b) py fwd through continuations: scale->mid (use on out's continuation) ->out (return)" \
    || { no "(25b) expected steps=\"2\" with v=\"mid\" l=11 d=2 and v=\"out\" l=12 d=3"; printf '%s\n' "$WF"; }
WC="$( run --slice=widecalc:delta --slice-flow=back )"
[ "$( attr "$WC" steps )" = 'steps="3"' ] \
    && printf '%s' "$( frow "$WC" gamma 22 )" | grep -q 'd="1" f="24"' \
    && printf '%s' "$( frow "$WC" alpha 20 )" | grep -q 'd="2"' \
    && printf '%s' "$( frow "$WC" beta 20 )" | grep -q 'd="2" f="22"' \
    && ok "(25c) C-family back through continuations: gamma d=1, alpha+beta params d=2" \
    || { no "(25c) expected steps=\"3\" with gamma l=22 d=1, alpha/beta l=20 d=2"; printf '%s\n' "$WC"; }

# ── (26) receiver mutation is DECLINED as a def, and the decline is DISCLOSED ───────────────────────
# `bag.push_back( seed )` writes bag. The classifier cannot know that: proving it needs the callee's
# body and the receiver's type, neither of which a name-based slicer has. Guessing from a curated
# method-name list is what this arm refuses on the tool's behalf — measured 2026-08-31, the same
# populations that would gain a def are dominated by names that must NOT become one (`reserve`, 150
# receiver-only sites in src/, changes capacity and never the value; `clear`/`pop_back`, 114 more,
# carry no incoming value), and sliceFlowExpandFwd's `if( r.hasDef ) break;` means a wrong def does
# not merely add a row — it KILLS the reach of the correct def before it.
#
# So the ANSWER stays steps="0" and the FIX is the disclosure. This arm pins both halves:
#   (a) the semantics are unchanged — a future round that quietly promotes receiver calls to defs
#       reds this arm and has to argue for it,
#   (b) the zero is no longer bare — the legend names receiver mutation as a limit in its own words,
#       and the root carries counts="as-classified": NOT the graph verbs' counts_floor= — a slice count
#       over-includes as well as under-includes (audit 2026-09-02, F-03: defs="3" where the variable has
#       one def), so "floor" was a false claim and the marker now says what the numbers ARE — exact
#       counts of what the name-based classifier rowed, neither floors nor totals of the program's truth.
# RED against the pre-fix binary on (b) and (c): the legend has no such clause and <slice> carried the
# counts_floor= marker it could not honour. Arm (a) is GREEN before and after, deliberately — the control.
R="$( run --slice=gather:bag )"
RF="$( run --slice=gather:bag --slice-flow=back )"
[ "$( attr "$R" defs )" = 'defs="1"' ] && [ "$( attr "$RF" steps )" = 'steps="0"' ] \
    && ok "(26a) CONTROL: receiver mutation stays a read — defs=\"1\", steps=\"0\" (semantics unchanged)" \
    || { no "(26a) expected the declined semantics: defs=\"1\" and steps=\"0\""; printf '%s\n' "$R"; printf '%s\n' "$RF"; }
# the v1 rows must still SHOW the mutating lines — the slice is under-classified, never empty
printf '%s' "$( elem "$R" )" | grep -q 'push_back' \
    && ok "(26a) the push_back line is still emitted as a row — under-classified, not omitted" \
    || { no "(26a) the receiver-mutation line must still appear as a row"; printf '%s\n' "$R"; }
for lit in 'receiver' 'counts="as-classified"' 'neither floors nor totals'; do
    printf '%s' "$( legend "$R" )" | grep -qi -- "$lit" \
        && ok "(26b) v1 legend carries \"$lit\"" \
        || { no "(26b) the v1 legend must define/name \"$lit\""; }
done
# the legend may NAME counts_floor= (to say why it is absent) but must never CLAIM it
printf '%s' "$( legend "$R" )" | grep -qE 'counts_floor="1"|are FLOORS' \
    && no "(26b) the v1 legend must not claim a floor — a slice count over-includes too" \
    || ok "(26b) the v1 legend makes no floor claim"
printf '%s' "$( legend "$RF" )" | grep -q 'receiver' \
    && ok "(26b) the FLOW legend also names the receiver-mutation limit where steps= is defined" \
    || no "(26b) the flow legend must name receiver mutation beside its steps= definition"
printf '%s' "$( elem "$R" )" | grep -q '^<slice [^>]*counts="as-classified"' \
    && printf '%s' "$( elem "$RF" )" | grep -q '^<slice [^>]*counts="as-classified"' \
    && ! printf '%s' "$( elem "$R" )$( elem "$RF" )" | grep -q 'counts_floor=' \
    && ok "(26c) <slice> carries counts=\"as-classified\" and NOT counts_floor= — defs=/uses=/steps= are what the classifier rowed, seeded or not" \
    || { no "(26c) <slice> must carry counts=\"as-classified\" (never counts_floor=) on both the v1 and the flow form"; printf '%s\n' "$( elem "$R" )"; }
# the inventory form is a count too (vars=), so it carries the marker as well
RI="$( run --slice=gather )"
printf '%s' "$( elem "$RI" )" | grep -q 'counts="as-classified"' && ! printf '%s' "$( elem "$RI" )" | grep -q 'counts_floor=' \
    && ok "(26c) the bare-inventory form carries the marker too (vars= is as-classified)" \
    || { no "(26c) --slice=SYM inventory must carry counts=\"as-classified\""; printf '%s\n' "$( elem "$RI" )"; }

# ── (27) preprocessor-dead regions never replace the live chain; build-dependent ones are flagged ───
# RED against the pre-fix binary: if0:w back returned steps="1" whose only row was `v = 111;` from
# inside `#if 0` — the real chain w<-v<-n ABSENT, no disclosure. A wrong chain is worse than a refusal.
P0="$( run --slice=if0:w --slice-flow=back )"
[ "$( attr "$P0" steps )" = 'steps="2"' ] \
    && printf '%s' "$( frow "$P0" v 3 )" | grep -q 'k="def" t="decl" v="v" d="1" f="7"' \
    && printf '%s' "$( frow "$P0" n 1 )" | grep -q 't="param" v="n" d="2" f="3"' \
    && ok "(27a) if0:w back: the LIVE chain w<-v(l3)<-n(l1), steps=\"2\"" \
    || { no "(27a) expected steps=\"2\" with v's live def at l=3 (d=1) and the param at l=1 (d=2)"; printf '%s\n' "$P0"; }
printf '%s' "$( elem "$P0" )" | grep -q 'v = 111' \
    && { no "(27a) the #if 0 def 'v = 111;' must NOT be a row — it is preprocessor-dead"; printf '%s\n' "$P0"; } \
    || ok "(27a) the #if 0 def is absent from the flow"
P0V="$( run --slice=if0:v )"
[ "$( attr "$P0V" defs )" = 'defs="1"' ] && [ "$( attr "$P0V" preproc_rows )" = 'preproc_rows="1"' ] \
    && ! printf '%s' "$( elem "$P0V" )" | grep -q '<s l="5"' \
    && ok "(27a) if0:v flat: defs=\"1\", the dropped row DISCLOSED as preproc_rows=\"1\", no l=5 row" \
    || { no "(27a) expected defs=\"1\" preproc_rows=\"1\" and no l=5 row"; printf '%s\n' "$P0V"; }
# build-dependent: kept, flagged, and NOT allowed to kill the reach of the unconditional def before it
P1="$( run --slice=ifdef_guard:t --slice-flow=back )"
printf '%s' "$( frow "$P1" s 15 )" | grep -q 'd="1" f="17" pp="1"' \
    && ok "(27b) ifdef_guard:t back: the #ifdef def 's = 7;' (l15) is a row AND carries pp=\"1\"" \
    || { no "(27b) expected <s l=\"15\" … v=\"s\" d=\"1\" f=\"17\" pp=\"1\">"; printf '%s\n' "$P1"; }
printf '%s' "$( frow "$P1" s 13 )" | grep -q 'k="def" t="decl" v="s" d="1" f="17"' \
    && printf '%s' "$( frow "$P1" n 11 )" | grep -q 'd="2"' \
    && ok "(27b) …and the unconditional def 'int s = n;' (l13) is STILL reached (d=1) with n behind it (d=2) — a pp def does not kill the reach" \
    || { no "(27b) the unconditional def at l=13 and the param at l=11 must both be reached past the pp def"; printf '%s\n' "$P1"; }
[ -z "$( attr "$P1" preproc_rows )" ] \
    && ok "(27b) nothing dropped ⇒ no preproc_rows= (absent means zero, the skipped convention)" \
    || { no "(27b) a kept region must not count as dropped"; printf '%s\n' "$P1"; }
P1F="$( run --slice=ifdef_guard:s --slice-flow=fwd )"
# (s's own l17 use is a d=0 seed row, so the reach shows as t's return read at l18: d=2, from 17)
printf '%s' "$( frow "$P1F" t 18 )" | grep -q 'd="2" f="17"' \
    && ok "(27b) fwd from s: the l13 def reaches the l17 use THROUGH the pp def (no kill) — t's read at l18 rows d=2 f=17" \
    || { no "(27b) expected v=\"t\" l=\"18\" d=\"2\" f=\"17\" — the pp def must not stop the forward reach"; printf '%s\n' "$P1F"; }
# #if 1: the body is live and unflagged, the #else is dead and dropped
P2="$( run --slice=if1else:a )"
printf '%s' "$( elem "$P2" )" | grep -q '<s l="25" k="both" t="assign">' \
    && ! printf '%s' "$( elem "$P2" )" | grep -q 'a = 999' \
    && [ "$( attr "$P2" preproc_rows )" = 'preproc_rows="1"' ] \
    && ok "(27c) if1else:a: the #if 1 body rows unflagged (k=both), the #else body dropped, preproc_rows=\"1\"" \
    || { no "(27c) expected l=25 k=both unflagged, no 'a = 999', preproc_rows=\"1\""; printf '%s\n' "$P2"; }
# the rule is stated, exactly, where the reader meets pp= and preproc_rows=
if printf '%s' "$( legend "$P0V" )" | grep -q 'preproc_rows=' && printf '%s' "$( legend "$P0V" )" | grep -q 'pp=' \
   && printf '%s' "$( legend "$P0V" )" | grep -q '#if 0' && printf '%s' "$( legend "$P0V" )" | grep -qi 'ifdef'; then
    ok "(27d) the legend states the preprocessor rule (#if 0 dropped, #ifdef kept+flagged) and defines pp=/preproc_rows="
else
    no "(27d) the legend must name #if 0, ifdef, pp= and preproc_rows="
fi

# ── (28) block scopes are separated: a shadow in a sibling block is not a reaching def ─────────────
# RED against the pre-fix binary: shadowing:r back chained l6 -> l5 (the inner v) and stopped there.
SC="$( run --slice=scope.cpp:shadowing:r --slice-flow=back )"
[ "$( attr "$SC" steps )" = 'steps="2"' ] \
    && printf '%s' "$( frow "$SC" v 3 )" | grep -q 'k="def" t="decl" v="v" d="1" f="8"' \
    && printf '%s' "$( frow "$SC" n 1 )" | grep -q 't="param" v="n" d="2" f="3"' \
    && ok "(28a) shadowing:r back: r<-v(l3, the OUTER v)<-n — steps=\"2\"" \
    || { no "(28a) expected steps=\"2\": the outer v's def at l=3 (d=1 f=8) and the param at l=1 (d=2)"; printf '%s\n' "$SC"; }
printf '%s' "$( elem "$SC" )" | grep -qE '<s l="(5|6)"' \
    && { no "(28a) the inner block's v (l5/l6) must NOT be in r's backward slice — r never reads it"; printf '%s\n' "$SC"; } \
    || ok "(28a) the inner shadow is absent — scope-separated, not name-matched"
# the flat rows of a shadowed name are LABELLED per binding, never merged
SV="$( run --slice=scope.cpp:shadowing:v )"
[ "$( attr "$SV" bindings )" = 'bindings="2"' ] \
    && printf '%s' "$( elem "$SV" )" | grep -q '<s l="3" k="def" t="decl" b="3">' \
    && printf '%s' "$( elem "$SV" )" | grep -q '<s l="5" k="def" t="decl" b="5">' \
    && printf '%s' "$( elem "$SV" )" | grep -q '<s l="6" k="both" t="assign" b="5">' \
    && printf '%s' "$( elem "$SV" )" | grep -q '<s l="8" k="use" t="read" b="3">' \
    && ok "(28b) shadowing:v: bindings=\"2\" and every row carries b= (l3/l8 -> b=3, l5/l6 -> b=5)" \
    || { no "(28b) expected bindings=\"2\" with b=\"3\" on l3/l8 and b=\"5\" on l5/l6"; printf '%s\n' "$SV"; }
SF="$( run --slice=scope.cpp:shadowing:v --slice-flow=fwd )"
printf '%s' "$( frow "$SF" r 9 )" | grep -q 'd="2" f="8"' \
    && ! printf '%s' "$( elem "$SF" )" | grep -q 'v="r"[^>]*f="6"' \
    && ok "(28b) fwd from v: the outer binding reaches r (l9, d=2); the inner one reaches nothing outside its block" \
    || { no "(28b) expected r at l=9 d=2 f=8 and no reach from the inner block"; printf '%s\n' "$SF"; }
# the inventory lists each BINDING, so a caller can see the shadow before slicing
SI="$( run --slice=scope.cpp:shadowing )"
[ "$( attr "$SI" vars )" = 'vars="4"' ] \
    && printf '%s' "$( elem "$SI" )" | grep -q '<v n="v" l="3" t="decl"/>' && printf '%s' "$( elem "$SI" )" | grep -q '<v n="v" l="5" t="decl"/>' \
    && ok "(28c) inventory: vars=\"4\" — n, v@3, v@5, r (two <v n=\"v\"> rows, one per binding)" \
    || { no "(28c) expected vars=\"4\" with <v n=\"v\" l=\"3\"/> and <v n=\"v\" l=\"5\"/>"; printf '%s\n' "$SI"; }
# an unshadowed slice is byte-for-byte free of the b=/bindings= vocabulary (purely additive)
if printf '%s' "$( elem "$( run --slice=pipeline:out --slice-flow=both )" )" | grep -qE ' b="|bindings='; then
    no "(28c) an unshadowed slice must not carry b=/bindings="
else
    ok "(28c) unshadowed output carries no binding vocabulary"
fi
# Go: `v := v + 1` in the inner block reads the OUTER v; r reads the outer v
SG="$( run --slice=goshadow:r --slice-flow=back )"
printf '%s' "$( frow "$SG" v 4 )" | grep -q 'd="1" f="9"' && printf '%s' "$( frow "$SG" n 3 )" | grep -q 'd="2"' \
    && ! printf '%s' "$( elem "$SG" )" | grep -qE '<s l="(6|7)"' \
    && ok "(28d) go: goshadow:r back binds to the outer v (l4) and the param, never the inner := shadow" \
    || { no "(28d) expected v at l=4 d=1 f=9, n at l=3 d=2, no l6/l7 rows"; printf '%s\n' "$SG"; }
# `v := v + 1` (l6) is ONE line touching TWO bindings: the := declares the inner v (b=6), the
# initializer reads the OUTER v (b=4) — two rows, never merged into a lying k="both"
SGI="$( run --slice=goshadow:v )"
printf '%s' "$( elem "$SGI" )" | grep -q '<s l="6" k="def" t="decl" b="6">' && printf '%s' "$( elem "$SGI" )" | grep -q '<s l="6" k="use" t="read" b="4">' \
    && ok "(28d) go: l6 splits into the inner := def (b=6) and the outer read in its own initializer (b=4)" \
    || { no "(28d) expected two l=6 rows: k=def b=6 and k=use b=4"; printf '%s\n' "$SGI"; }
# JS: let is block-scoped, var is function-scoped (hoisting)
SJ="$( run --slice=jsshadow:r --slice-flow=back )"
printf '%s' "$( frow "$SJ" v 2 )" | grep -q 'd="1" f="8"' && ! printf '%s' "$( elem "$SJ" )" | grep -qE '<s l="(4|5)"' \
    && printf '%s' "$( frow "$SJ" hoisted 7 )" | grep -q 'd="1" f="8"' \
    && ok "(28e) js: r<-v binds to the outer let (l2), skips the inner block, and reaches the function-scoped var (l7)" \
    || { no "(28e) expected v at l=2 d=1, no l4/l5 rows, hoisted at l=7 d=1"; printf '%s\n' "$SJ"; }
# the rule is stated where b= and bindings= are met, and the old over-include disclaimer is gone
if printf '%s' "$( legend "$SV" )" | grep -q 'b=' && printf '%s' "$( legend "$SV" )" | grep -q 'bindings=' \
   && printf '%s' "$( legend "$SV" )" | grep -qi 'innermost' && printf '%s' "$( legend "$SV" )" | grep -qi 'function-scoped' \
   && ! printf '%s' "$( legend "$SV" )" | grep -q 'shadowing may over-include' \
   && ! printf '%s' "$( legend "$SV" )" | grep -q 'NOT separated'; then
    ok "(28f) the legend defines b=/bindings=, states the innermost-binding rule and the function-scoped families, and no longer claims shadowing over-includes"
else
    no "(28f) the legend must define b=/bindings=, state the scope rule, and drop the over-include disclaimer"
fi

# ── (29) destructuring chains, and the under-count clause names every hidden-write shape ───────────
DJ="$( run --slice=destructure:s --slice-flow=back )"
[ "$( attr "$DJ" steps )" = 'steps="3"' ] \
    && printf '%s' "$( frow "$DJ" x 2 )" | grep -q 'k="def" t="decl" v="x" d="1" f="3"' \
    && printf '%s' "$( frow "$DJ" y 2 )" | grep -q 'k="def" t="decl" v="y" d="1" f="3"' \
    && printf '%s' "$( frow "$DJ" o 1 )" | grep -q 't="param" v="o" d="2" f="2"' \
    && ok "(29a) js destructure:s back: s <- x,y (the pattern line, d=1) <- o (d=2), steps=\"3\"" \
    || { no "(29a) expected steps=\"3\": x and y at l=2 d=1, o at l=1 d=2"; printf '%s\n' "$DJ"; }
# the under-count clause: receiver mutation was the only named shape; a write through an ARGUMENT
# (by-reference parameter, out-parameter, function-like macro) is the same blind spot (F-12)
L29="$( legend "$DJ" )"
if printf '%s' "$L29" | grep -qi 'by-reference' && printf '%s' "$L29" | grep -qi 'out-param' && printf '%s' "$L29" | grep -qi 'macro' \
   && printf '%s' "$L29" | grep -q 'call-arg'; then
    ok "(29b) the legend's under-count clause names by-reference / out-parameter / macro writes (classified call-arg) beside receiver mutation"
else
    no "(29b) the legend must widen the under-count clause to by-reference, out-parameter and macro writes"
fi
printf '%s' "$L29" | grep -q 'scope' && printf '%s' "$L29" | grep -q 'nonlocal' && printf '%s' "$L29" | grep -qi 'destructur' \
    && ok "(29b) the legend defines k=scope (global/nonlocal) and names destructuring binders" \
    || no "(29b) the legend must define k=scope / t=global|nonlocal and name destructuring"

[ "$fail" = 0 ] && printf 'ALL PASS\n' || printf 'FAILURES ABOVE\n'
exit "$fail"
