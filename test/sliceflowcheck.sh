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
#       and the root carries counts_floor="1" like the five graph verbs that are floors for the same
#       name-based reason.
# RED against the pre-fix binary on (b) and (c): the legend has no such clause and <slice> has no
# counts_floor= attribute. Arm (a) is GREEN before and after, deliberately — it is the control.
R="$( run --slice=gather:bag )"
RF="$( run --slice=gather:bag --slice-flow=back )"
[ "$( attr "$R" defs )" = 'defs="1"' ] && [ "$( attr "$RF" steps )" = 'steps="0"' ] \
    && ok "(26a) CONTROL: receiver mutation stays a read — defs=\"1\", steps=\"0\" (semantics unchanged)" \
    || { no "(26a) expected the declined semantics: defs=\"1\" and steps=\"0\""; printf '%s\n' "$R"; printf '%s\n' "$RF"; }
# the v1 rows must still SHOW the mutating lines — the slice is under-classified, never empty
printf '%s' "$( elem "$R" )" | grep -q 'push_back' \
    && ok "(26a) the push_back line is still emitted as a row — under-classified, not omitted" \
    || { no "(26a) the receiver-mutation line must still appear as a row"; printf '%s\n' "$R"; }
for lit in 'receiver' 'counts_floor='; do
    printf '%s' "$( legend "$R" )" | grep -q -- "$lit" \
        && ok "(26b) v1 legend carries \"$lit\"" \
        || { no "(26b) the v1 legend must define/name \"$lit\""; }
done
printf '%s' "$( legend "$RF" )" | grep -q 'receiver' \
    && ok "(26b) the FLOW legend also names the receiver-mutation limit where steps= is defined" \
    || no "(26b) the flow legend must name receiver mutation beside its steps= definition"
printf '%s' "$( elem "$R" )" | grep -q '^<slice [^>]*counts_floor="1"' \
    && printf '%s' "$( elem "$RF" )" | grep -q '^<slice [^>]*counts_floor="1"' \
    && ok "(26c) <slice> carries counts_floor=\"1\" — defs=/uses=/steps= are floors, seeded or not" \
    || { no "(26c) <slice> must carry counts_floor=\"1\" on both the v1 and the flow form"; printf '%s\n' "$( elem "$R" )"; }
# the inventory form is a count too (vars=), so it carries the marker as well
RI="$( run --slice=gather )"
printf '%s' "$( elem "$RI" )" | grep -q 'counts_floor="1"' \
    && ok "(26c) the bare-inventory form carries the marker too (vars= is a floor)" \
    || { no "(26c) --slice=SYM inventory must carry counts_floor=\"1\""; printf '%s\n' "$( elem "$RI" )"; }

[ "$fail" = 0 ] && printf 'ALL PASS\n' || printf 'FAILURES ABOVE\n'
exit "$fail"
