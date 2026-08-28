#!/usr/bin/env bash
# taskroutecheck.sh — deterministic task -> one safe Ripwire command contract.

set -u
ROOT="$( cd "$( dirname "$0" )/.." && pwd )"
BIN="${1:-${RIPWIRE_BIN:-$ROOT/build/ripwire}}"
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
int classify() { return targetSymbol(); }
int report() { return classify(); }
int summary() { return report(); }
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
XG="$( route 'Find every exact occurrence of "return alphaNode()" with nearby context' )"
case "$XG" in *'status="recommend"'*'intent="exact-grep"'*'--grep='*'--grep-context=2'*) ok "quoted exact literal -> context-aware --grep";; *) no "exact grep route wrong: $XG";; esac
# Prose apostrophes are NOT quotes: possessives must never mint a grep literal out of the words between
# them ("s config and the team" was the pre-fix extraction here), while a REAL quoted literal in the same
# apostrophe-laden sentence still routes. The mangled-literal assertion is the red-first arm vs a pre-fix binary.
AP="$( route "Search for the user's config and the team's settings for the flag" )"
case "$AP" in *'--grep='*'s config'*) no "possessive apostrophes minted a bogus grep literal: $AP";; *) ok "possessive apostrophes mint no grep literal";; esac
AQ="$( route "Search for the exact literal 'flag_name' somewhere in the user's config handling" )"
case "$AQ" in *'status="recommend"'*'intent="exact-grep"'*'--grep='*'flag_name'*) ok "real quoted literal survives surrounding apostrophes";; *) no "quoted literal lost among apostrophes: $AQ";; esac
EC="$( route 'I just edited targetSymbol; did I change its contract?' )"
case "$EC" in *'status="recommend"'*'intent="edit-contract"'*'--edit-check='*'targetSymbol'*) ok "post-edit exact symbol -> --edit-check";; *) no "edit contract route wrong: $EC";; esac
# ── all-lowercase symbol names are reachable, but only from a symbol SLOT ──────────────────────────────
# An indexed name with no capital and no separator (`classify`) used to be discarded by a casing filter,
# so NO symbol-gated route could ever reach it. Casing was a proxy for "is this a symbol mention or just a
# word"; sentence POSITION is the real discriminator, so these arms assert both directions of it. The two
# recall arms are red against a pre-fix binary (both abstained, resolved_symbols="0"); the four precision
# arms are the guard that the relaxation did not buy recall with prose false-positives.
LW="$( route 'How does classify work?' )"
case "$LW" in *'status="recommend"'*'intent="understand-symbol"'*'--expand='*'classify'*) ok "lowercase name in an understand slot -> --expand";; *) no "lowercase understand route wrong: $LW";; esac
LE="$( route 'I just edited classify; did I change its contract?' )"
case "$LE" in *'status="recommend"'*'intent="edit-contract"'*'--edit-check='*'classify'*) ok "lowercase name in a post-edit slot -> --edit-check";; *) no "lowercase edit-contract route wrong: $LE";; esac
# Same words, no slot: an ordinary noun phrase must stay unresolved even though `report` IS indexed here.
LN="$( route 'did I change the report that goes out on Friday?' )"
case "$LN" in *'--edit-check='*) no "a determiner-led noun phrase minted a symbol route: $LN";; *) ok "prose noun phrase resolves no lowercase symbol";; esac
LN2="$( route 'how does the report look this quarter?' )"
case "$LN2" in *'--expand='*) no "a determiner-led noun phrase minted an --expand route: $LN2";; *) ok "prose noun phrase mints no --expand";; esac
# The stop list keeps the router from arguing with itself: `summary` is indexed, but the router's own
# intent vocabulary must never double as a symbol mention.
LS="$( route 'How does classify work? I just edited classify and report and summary too' )"
case "$LS" in *'--connect='*) no "several lowercase words minted a --connect route: $LS";; *) ok "several lowercase words never mint --connect";; esac
LC="$( route 'how do classify, report and summary connect?' )"
case "$LC" in *'--connect='*) no "three lowercase words minted a --connect route: $LC";; *) ok "three lowercase words never satisfy the three-symbol --connect";; esac

# ── paraphrase tolerance: neither intent may recognise only the wording it was written against ─────────
# exact-grep and edit-contract shipped as fixed OR-chains of four or five literal phrases. These six are
# the realistic paraphrases that missed; all six abstained against a pre-fix binary. The two guard arms
# below are why widening the vocabulary is safe: the floor is never the whole gate — exact-grep still
# needs a literal the user QUOTED, and edit-contract still needs exactly one resolved symbol.
for P in 'I need every place that says "targetSymbol" verbatim' \
         'look for occurrences of "cacheValue" across the repo' \
         'where does the string "alphaNode" show up in the codebase'; do
    G="$( route "$P" )"
    case "$G" in *'status="recommend"'*'intent="exact-grep"'*'--grep='*) ok "exact-grep paraphrase routes: ${P:0:44}";; *) no "exact-grep paraphrase missed [$P]: $G";; esac
done
for P in "did targetSymbol's contract change after my patch" \
         'I modified targetSymbol - is it still compatible with callers' \
         'just finished editing targetSymbol, could this break anyone'; do
    E="$( route "$P" )"
    case "$E" in *'status="recommend"'*'intent="edit-contract"'*'--edit-check='*'targetSymbol'*) ok "edit-contract paraphrase routes: ${P:0:44}";; *) no "edit-contract paraphrase missed [$P]: $E";; esac
done
XW="$( route 'where does the team stand on the quarterly plan and every place it slipped' )"
case "$XW" in *'--grep='*) no "exact-search wording alone minted a grep with no quoted literal: $XW";; *) ok "widened exact-grep wording still needs a quoted literal";; esac
EW="$( route 'i modified the slide deck after my patch of the agenda, did i change anything' )"
case "$EW" in *'--edit-check='*) no "post-edit wording alone minted an --edit-check with no resolved symbol: $EW";; *) ok "widened post-edit wording still needs one resolved symbol";; esac

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

# ── the five surfaces that shipped without any routing coverage ────────────────────────────────────────
# Each is asked for close to its own vocabulary, so each needs conjunctive evidence (the surface word AND
# an intent word) and the two that carry a user-supplied value fire only when the task supplies it — the
# router may not substitute a placeholder, because --edit-plan/--grep would then refuse the command it was
# handed. All ten arms are red against a pre-fix binary: every one of these abstained with score="0".
EP="$( route 'Apply the edits in refactor.json as a multi-edit transaction' )"
case "$EP" in *'status="recommend"'*'intent="apply-edit-plan"'*'--edit-plan='*'refactor.json'*'--dry-run'*) ok "edit-plan wording + named plan -> --edit-plan --dry-run";; *) no "edit-plan route wrong: $EP";; esac
EP0="$( route 'how do I run a transactional multi-edit against this repo?' )"
case "$EP0" in *'--edit-plan='*) no "edit-plan route invented a plan file the task never named: $EP0";; *) ok "edit-plan abstains rather than invent a plan path";; esac
HD="$( route 'Find every occurrence of "targetSymbol" and give me safe-edit handles' )"
case "$HD" in *'status="recommend"'*'intent="grep-handles"'*'--grep='*'--handles'*) ok "handle wording + quoted literal -> --grep --handles";; *) no "grep-handles route wrong: $HD";; esac
# --handles is a MODIFIER on --grep/--regex; without a literal to anchor it there is no command to make.
HD0="$( route 'give me safe-edit handles for the grep hits' )"
case "$HD0" in *'--handles'*) no "grep-handles emitted a --handles with no literal to anchor it: $HD0";; *) ok "grep-handles abstains without a quoted literal";; esac
# The word-bounded arm: "config handling" is NOT a handles request, and must leave exact-grep alone.
HD1="$( route "Search for the exact literal 'flag_name' somewhere in the user's config handling" )"
case "$HD1" in *'intent="exact-grep"'*) ok "'handling' does not steal exact-grep from its own route";; *) no "substring 'handle' hijacked exact-grep: $HD1";; esac
CL="$( route 'I want the compact legend on this map' )"
case "$CL" in *'status="recommend"'*'intent="compact-legend"'*'--legend=compact'*) ok "compact-legend wording -> --legend=compact";; *) no "compact-legend route wrong: $CL";; esac
CX="$( route 'set up the codex integration and tell me if it is wired correctly' )"
case "$CX" in *'status="recommend"'*'intent="codex-doctor"'*'--doctor --agent=codex'*) ok "codex + integration wording -> --doctor --agent=codex";; *) no "codex-doctor route wrong: $CX";; esac
CX0="$( route 'codex is a nice name, should we use it for the new project?' )"
case "$CX0" in *'--agent=codex'*) no "a passing mention of codex minted a doctor route: $CX0";; *) ok "codex alone never mints a doctor route";; esac
TG="$( route 'why did the test-gate pick those shell gates - show me the evidence' )"
case "$TG" in *'status="recommend"'*'intent="gate-evidence"'*'--test-gate'*) ok "shell-gate evidence wording -> --test-gate";; *) no "gate-evidence route wrong: $TG";; esac
TG0="$( route 'i want a sanity pass over my diff — which tests do i even need here?' )"
case "$TG0" in *'intent="gate-evidence"'*) no "'which tests' alone minted a gate-evidence route: $TG0";; *) ok "'which tests' alone is not a shell-gate evidence request";; esac

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
for f in --verify --connect --expand --grep --grep-context --edit-check --from-trace --situ --pack-task --exemplar --for \
         --edit-plan --dry-run --handles --legend --doctor --agent=codex --test-gate; do "$BIN" --help 2>&1 | grep -q -- "$f" || no "recommended flag absent from --help: $f"; done

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
