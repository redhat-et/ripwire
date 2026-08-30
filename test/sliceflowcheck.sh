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
#   (10) legend honesty: reaching-definition wording, f=/d=/steps= defined, line-granularity limit
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
   && printf '%s' "$F" | grep -qi 'line-granular' && printf '%s' "$F" | grep -q 'no alias analysis'; then
    ok "(10) legend defines the flow vocabulary (reaching-definition, d=, f=, steps=, line-granular + alias limits)"
else
    no "(10) flow legend must define d=/f=/steps= and state the reaching-definition + line-granularity + alias limits"
fi

[ "$fail" = 0 ] && printf 'ALL PASS\n' || printf 'FAILURES ABOVE\n'
exit "$fail"
