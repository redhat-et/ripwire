#!/usr/bin/env bash
# taskroutecheck.sh — deterministic task -> one safe Ripwire command contract.

set -u
ROOT="$( cd "$( dirname "$0" )/.." && pwd )"
BIN="${RIPWIRE_BIN:-$ROOT/build/ripwire}"
[ "${BIN#/}" = "$BIN" ] && BIN="$ROOT/$BIN"
TMP="$( mktemp -d )"; trap 'rm -rf "$TMP"' EXIT
fail=0
ok(){ printf '  PASS  %s\n' "$*"; }
no(){ printf '  FAIL  %s\n' "$*"; fail=1; }

[ -x "$BIN" ] || { echo "no ripwire binary at $BIN — build first"; exit 2; }
REPO="$TMP/router repo"
mkdir -p "$REPO"
git -C "$REPO" init -q
git -C "$REPO" config user.email ripwire@example.invalid
git -C "$REPO" config user.name ripwire-gate
cat >"$REPO/router.cpp" <<'SRC'
int alphaNode() { return 1; }
int betaNode() { return alphaNode(); }
int gammaNode() { return betaNode(); }
int targetSymbol() { return gammaNode(); }
SRC
git -C "$REPO" add router.cpp
git -C "$REPO" commit -qm base
route(){ "$BIN" "$REPO" --no-cache --help-task="$1" 2>"$TMP/err"; }

"$BIN" --help 2>&1 | grep -q -- '--help-task=' && ok "--help advertises --help-task=" || no "--help does not advertise --help-task="
V="$( route 'calls(betaNode, alphaNode)' )"
case "$V" in *'status="recommend"'*'intent="verify-claim"'*'--verify='*) ok "closed claim -> --verify";; *) no "closed claim route wrong: $V";; esac
C="$( route 'How do alphaNode, betaNode, and gammaNode connect?' )"
case "$C" in *'status="recommend"'*'intent="connect-symbols"'*'--connect='*'alphaNode,betaNode,gammaNode'*) ok "three resolved symbols -> --connect";; *) no "three-symbol route wrong: $C";; esac
U="$( route 'Help me understand the implementation of targetSymbol' )"
case "$U" in *'status="recommend"'*'intent="understand-symbol"'*'--expand='*'targetSymbol'*) ok "one resolved symbol -> --expand";; *) no "one-symbol route wrong: $U";; esac
T="$( route $'AddressSanitizer: heap-use-after-free\n#0 0x123 in targetSymbol router.cpp:4' )"
case "$T" in *'status="recommend"'*'intent="trace-debug"'*'--from-trace=-'*) ok "trace shape -> --from-trace=-";; *) no "trace route wrong: $T";; esac

printf '\n// dirty\n' >>"$REPO/router.cpp"
D="$( route 'Review my current changes before I push' )"
case "$D" in *'status="recommend"'*'intent="review-diff"'*'<run>'*'--situ'*) ok "dirty pre-push review -> --situ";; *) no "dirty diff route wrong: $D";; esac
git -C "$REPO" restore router.cpp
D0="$( route 'Review my current changes before I push' )"
case "$D0" in *'status="recommend"'*'intent="review-diff"'*) no "clean worktree recommended dirty-diff route: $D0";; *) ok "clean worktree rejects dirty-only review route";; esac
P="$( route 'Plan the implementation and scope of a new cache feature' )"
case "$P" in *'status="recommend"'*'intent="plan-feature"'*'--pack-task='*) ok "prospective feature -> --pack-task";; *) no "feature plan route wrong: $P";; esac
E="$( route 'I am about to write one helper function for cache keys' )"
case "$E" in *'status="recommend"'*'intent="reuse-one-symbol"'*'--exemplar='*) ok "one new symbol -> --exemplar";; *) no "reuse route wrong: $E";; esac
F="$( route 'Find the code responsible for this retry timeout bug' )"
case "$F" in *'status="recommend"'*'intent="locate-task"'*'--for='*) ok "locate/debug symptom -> --for";; *) no "locate route wrong: $F";; esac

N="$( route 'Write a cheerful release announcement' )"
case "$N" in *'status="abstain"'*) ok "off-topic prompt abstains";; *) no "off-topic prompt did not abstain: $N";; esac
[ "$( printf '%s' "$N" | grep -o '<run>' | wc -l | tr -d ' ' )" = 0 ] && ok "abstention emits zero commands" || no "abstention emitted a command"
[ "$( printf '%s' "$D" | grep -o '<run>' | wc -l | tr -d ' ' )" = 1 ] && ok "recommendation emits exactly one command" || no "recommendation command cardinality != 1"

Q="Plan feature O'Brien & <friends>; touch $TMP/PWNED"
route "$Q" >"$TMP/q1"; route "$Q" >"$TMP/q2"
diff -q "$TMP/q1" "$TMP/q2" >/dev/null && ok "task routing byte-identical" || no "task routing nondeterministic"
[ ! -e "$TMP/PWNED" ] && ok "task text executes nothing" || no "task text was executed"
grep -Fq 'O&apos;\&apos;&apos;Brien' "$TMP/q1" && ok "single quote receives POSIX shell quoting" || no "recommended argv is not safely shell-quoted"
if command -v xmllint >/dev/null 2>&1; then xmllint --noout "$TMP/q1" 2>/dev/null && ok "task route XML well formed" || no "task route XML malformed"; fi

"$BIN" "$REPO" --help-task= >/dev/null 2>"$TMP/empty.err"; rc=$?
[ "$rc" -ne 0 ] && grep -q 'needs' "$TMP/empty.err" && ok "empty task refuses" || no "empty task did not refuse clearly"
"$BIN" "$REPO" --help-task='plan a feature' --json >/dev/null 2>"$TMP/json.err"; rc=$?
[ "$rc" -ne 0 ] && grep -qi 'json' "$TMP/json.err" && ok "unsupported --json combination refuses" || no "--json combination did not refuse"
"$BIN" "$REPO" "$ROOT/test/fixture" --help-task='plan a feature' >/dev/null 2>"$TMP/multi.err"; rc=$?
[ "$rc" -ne 0 ] && grep -qi 'single-root' "$TMP/multi.err" && ok "multi-root routing refuses" || no "multi-root routing did not refuse"
for f in --verify --connect --expand --from-trace --situ --pack-task --exemplar --for; do "$BIN" --help 2>&1 | grep -q -- "$f" || no "recommended flag absent from --help: $f"; done

# ── byte-compat: the verify-claim template must emit the SHIPPED --verify grammar byte-exactly ─────────
# (PLAN 2026-08-13 addendum: gate against the real verb's PARSER, never a copy of its syntax.)
# Route a claim through --help-task, unquote the recommended argv robustly (a real XML parse + a real
# POSIX tokenizer, not a regex over quotes), then EXECUTE the real verb. Acceptance = exit 0 plus a
# well-formed <verify> root carrying a three-valued verdict (any of the three counts); a refusal
# (non-zero, no root) on an emitted claim is exactly the drift this arm exists to catch. Byte-exactness
# is asserted twice: the unquoted --verify= argument must equal the task's claim text, and the parser's
# own claim= echo on the root must equal it again after XML decoding.
claim_from_route(){ python3 - "$1" <<'PY'
import sys, shlex, xml.etree.ElementTree as ET
run = ET.parse( sys.argv[1] ).getroot().find( './/run' )
if run is None or not run.text: sys.exit( 3 )
for tok in shlex.split( run.text ):
    if tok.startswith( '--verify=' ):
        sys.stdout.write( tok[ len( '--verify=' ): ] ); sys.exit( 0 )
sys.exit( 4 )
PY
}
claim_echo_of(){ python3 - "$1" <<'PY'
import sys, xml.etree.ElementTree as ET
sys.stdout.write( ET.parse( sys.argv[1] ).getroot().get( 'claim', '' ) )
PY
}
for CLAIM in 'calls(betaNode, alphaNode)' 'uses(targetSymbol)' 'reaches(alphaNode, "router.cpp")'; do
    shape="${CLAIM%%(*}"
    route "$CLAIM" >"$TMP/bc.$shape.route.xml"
    grep -q 'intent="verify-claim"' "$TMP/bc.$shape.route.xml" \
        && ok "byte-compat $shape: the claim routes to verify-claim" \
        || { no "byte-compat $shape: claim did not route to verify-claim: $( cat "$TMP/bc.$shape.route.xml" )"; continue; }
    GOT="$( claim_from_route "$TMP/bc.$shape.route.xml" )" \
        || { no "byte-compat $shape: no --verify= argument recoverable from <run>"; continue; }
    [ "$GOT" = "$CLAIM" ] \
        && ok "byte-compat $shape: the emitted --verify= argument round-trips byte-identical" \
        || no "byte-compat $shape: emitted claim diverges after unquoting: [$GOT] != [$CLAIM]"
    "$BIN" "$REPO" --no-cache --verify="$GOT" >"$TMP/bc.$shape.out.xml" 2>"$TMP/bc.$shape.err"; rc=$?
    RV="$( grep -o '<verify [^>]*>' "$TMP/bc.$shape.out.xml" | head -1 )"
    { [ $rc -eq 0 ] && printf '%s' "$RV" | grep -Eq 'verdict="(confirmed|refuted|not-established)"'; } \
        && ok "byte-compat $shape: the shipped parser ACCEPTED the emitted claim with a verdict" \
        || { no "byte-compat $shape: the real parser refused the emitted claim (rc=$rc)"; head -2 "$TMP/bc.$shape.err"; continue; }
    printf '%s' "$RV" | grep -q "shape=\"$shape\"" \
        && ok "byte-compat $shape: the verdict root names the claimed shape" \
        || no "byte-compat $shape: shape= on the verify root disagrees with the claim"
    ECHOED="$( claim_echo_of "$TMP/bc.$shape.out.xml" )"
    [ "$ECHOED" = "$CLAIM" ] \
        && ok "byte-compat $shape: the parser's claim= echo is byte-identical to the task's claim" \
        || no "byte-compat $shape: parser echoed a different claim: [$ECHOED] != [$CLAIM]"
    if command -v xmllint >/dev/null 2>&1; then
        xmllint --noout "$TMP/bc.$shape.out.xml" 2>/dev/null \
            && ok "byte-compat $shape: verdict XML well formed" \
            || no "byte-compat $shape: verdict XML malformed"
    fi
done

# A reaches claim whose unquoted second argument is NOT a built-in layer word is a claim the shipped
# parser refuses — recommending --verify for it would be a prerequisite-violating route. The router
# must treat it as not-a-closed-claim (here: no stronger evidence remains, so it abstains).
RB="$( route 'reaches(alphaNode, gammaNode)' )"
case "$RB" in
    *'--verify='*) no "reaches(SYM,SYM) recommended the parser-refused --verify form: $RB";;
    *) ok "reaches(SYM,SYM) never routes to a command the --verify parser refuses";;
esac

EVAL="$( python3 "$ROOT/bench/taskroute_eval.py" --bin "$BIN" --corpus "$ROOT/test/taskroutefix/prompts.tsv" --split test 2>&1 )"; rc=$?
[ "$rc" -eq 0 ] && ok "held-out command-routing floors ($EVAL)" || no "held-out command-routing floors failed: $EVAL"

[ "$fail" = 0 ] && echo "ALL PASS" || echo "FAILURES ABOVE"
exit "$fail"
