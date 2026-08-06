#!/usr/bin/env bash
# namingcalibrationcheck.sh — §9.5: the naming-* lint rules, judged against REAL renames instead of
# against an argument.
#
# WHY THIS GATE EXISTS. naming-body-mismatch shipped on plausibility and was measured INVERTED — it
# flagged the best-named symbols in the tree. This gate is the instrument that would have caught that
# before it shipped, and it exists so the NEXT naming metric has to clear a measurement. Ground truth is
# free and local: a repo's git history holds real `old -> new` renames chosen by developers who knew the
# domain. `--naming-calibration` mines them, joins each to the symbol it became at HEAD, and scores BOTH
# spellings with the same rule predicates --lint runs. A useful rule fires on the abandoned spelling and
# not on the chosen one.
#
# THE PROXY IS NOISY AND THIS GATE SAYS SO IN ITS OWN OUTPUT. People rename for rebrands, module moves,
# API changes, type changes and reverts — not only because a name was bad. Measured on this repo the
# single largest mined family is a whole-project rebrand (ctxpack -> ripwire), which carries no naming
# information at all. So a proxy computed over a handful of pairs is noise wearing a decimal point, and
# the LIVE arm below SKIPS rather than passes when the sample is under its declared floor. A gate that
# silently passes on three samples is worse than no gate.
#
# TWO ARMS, and they answer different questions:
#   B. LIVE — the verb on the repo under test. Reports the real numbers; enforces the floors only when
#      the sample can carry them. It runs FIRST so that its SKIP banner lands inside the first bytes of
#      output, which is where test/pargates.py looks when deciding whether a gate proved anything.
#   A. INSTRUMENT — a synthetic repo whose renames are hand-derivable. Proves mine -> join -> score
#      actually works. Without it, "every rule scored 0" is indistinguishable from "the scorer is
#      broken", so this arm is enforced ALWAYS, including on the runs where arm B skips.
#
# THE FLOORS ARE DECLARED HERE, NOT DERIVED FROM WHAT TODAY'S RULES SCORE. They are set from what a
# useful rule ought to achieve, so that a rule missing one is a FINDING and not a reason to move the bar.
#   PROXY_FLOOR      0.70  a rule that fires on both spellings equally scores exactly 0.50 — that is pure
#                          chance and no signal at all. 0.70 is "roughly 7 of 10 fires land on the name
#                          the developer abandoned", the least that would make a rule worth a reader's
#                          attention. It is NOT tuned to today's rules.
#   MIN_PAIRS        30    fewer labelled pairs than this and no per-rule proxy is estimable; arm B SKIPS.
#   MIN_RULE_FIRES   10    a rule firing fewer times than this over the whole corpus gets a reported
#                          "insufficient", never a pass and never a fail. One fire is not a precision.
set -u
ROOT="$( cd "$( dirname "$0" )/.." && pwd )"
BIN="${RIPWIRE_BIN:-$ROOT/build/ripwire}"
[ "${BIN#/}" = "$BIN" ] && BIN="$ROOT/$BIN"
TMP="$( mktemp -d )"; trap 'rm -rf "$TMP"' EXIT
fail=0
ok(){ printf '  PASS  %s\n' "$*"; }
no(){ printf '  FAIL  %s\n' "$*"; fail=1; }
note(){ printf '  ....  %s\n' "$*"; }

PROXY_FLOOR=0.70
MIN_PAIRS=30
MIN_RULE_FIRES=10
SCORED_RULES="naming-short naming-wordy naming-underscore naming-case naming-predicate naming-setter"

[ -x "$BIN" ] || { echo "no ripwire binary at $BIN — build first"; exit 2; }
command -v git >/dev/null 2>&1 || { echo "namingcalibrationcheck: SKIP — no git on PATH"; exit 0; }

# one row per line, so the usual per-attribute sed works on a minified one-line document
rows(){ tr '<' '\n' < "$1"; }
attr(){ sed -n "s/.*[ \"]$2=\"\([^\"]*\)\".*/\1/p" <<<"$1" | head -1; }
rulerow(){ rows "$1" | grep "^r n=\"$2\"" | head -1; }

# ── ARM B — the live measurement on the repo under test ───────────────────────────────────────────────
LIVE="$TMP/live.xml"
"$BIN" "$ROOT" --naming-calibration >"$LIVE" 2>/dev/null
livehdr="$( rows "$LIVE" | grep '^naming-calibration ' | head -1 )"
livepairs="$( attr "$livehdr" pairs )"
livecand="$( attr "$livehdr" candidates )"
livecommits="$( attr "$livehdr" commits )"
: "${livepairs:=0}" "${livecand:=0}" "${livecommits:=0}"

echo "LIVE CORPUS: $livecommits commits, $livecand raw substitutions mined, $livepairs labelled pairs"
skipping=0
if [ "$livepairs" -lt "$MIN_PAIRS" ]; then
    skipping=1
    # This banner is deliberately within the first bytes of output: test/pargates.py classifies a gate as
    # skipped — "ran, but proved nothing" — on exactly that, and this gate proving its INSTRUMENT works is
    # not the same thing as this gate having judged the RULES.
    echo "namingcalibrationcheck: SKIP — $livepairs labelled pairs is below the declared floor of $MIN_PAIRS, so no per-rule proxy is estimable"
    echo "  (renames are a NOISY proxy — rebrands, moves and API changes all look like renames — so a proxy over"
    echo "   $livepairs pairs would be noise wearing a decimal point. The instrument arm below is still enforced.)"
fi
for rule in $SCORED_RULES; do
    row="$( rulerow "$LIVE" "$rule" )"
    o="$( attr "$row" old )"; n="$( attr "$row" new )"; f="$( attr "$row" fired )"; p="$( attr "$row" proxy )"
    printf '  ----  %-18s old=%-4s new=%-4s fired=%-4s proxy=%s\n' "$rule" "${o:-0}" "${n:-0}" "${f:-0}" "${p:-n/a}"
done
if [ "$skipping" = "0" ]; then
    for rule in $SCORED_RULES; do
        row="$( rulerow "$LIVE" "$rule" )"
        fired="$( attr "$row" fired )"; : "${fired:=0}"
        proxy="$( attr "$row" proxy )"; : "${proxy:=0}"
        if [ "$fired" -lt "$MIN_RULE_FIRES" ]; then
            note "$rule: fired=$fired over the whole corpus — below MIN_RULE_FIRES=$MIN_RULE_FIRES, reported insufficient (neither pass nor fail)"
            continue
        fi
        if awk -v p="$proxy" -v floor="$PROXY_FLOOR" 'BEGIN { exit !( p + 0 >= floor + 0 ) }'; then
            ok "$rule: proxy=$proxy clears the declared floor of $PROXY_FLOOR (fired=$fired)"
        else
            no "$rule: proxy=$proxy is BELOW the declared floor of $PROXY_FLOOR (fired=$fired) — it fires on the name the developer CHOSE nearly as often as on the one they abandoned"
        fi
    done
fi

# ── ARM A — the instrument, on a synthetic repo whose every rename is hand-derivable ──────────────────
# Each planted rename is chosen so exactly ONE rule can speak about it, and which side it speaks on is
# derivable from the rule's own definition in src/naminglens.h:
#   computeTotalWeightedAverageScoreValue -> totalScore   naming-wordy      OLD (6 split tokens > 5)
#   handle__relay                         -> handleRelay  naming-underscore OLD (internal consecutive __)
#   fetch_remoteCount                     -> fetchRemote  naming-case       OLD (snake AND camel in one name)
#   isBrokenState                         -> stateCode    naming-predicate  OLD (is-prefixed, KNOWN int return)
#   okayNamed                             -> ab           naming-short      NEW  <- the false-positive side,
#                                                                                  planted on purpose: a
#                                                                                  scorer that only ever
#                                                                                  counts the old spelling
#                                                                                  cannot pass this arm
# plus two negative controls: a body edit that renames a PARAMETER (mined, then dropped by the join,
# because no rule could ever have seen it) and a one-to-many split (dropped as ambiguous — a split is
# several developer decisions wearing one label).
FIX="$TMP/fixture"
mkdir -p "$FIX"
cat >"$FIX/lens.cpp" <<'CPP'
int computeTotalWeightedAverageScoreValue( int amount )
{
    return amount + 100;
}

int handle__relay( int amount )
{
    return amount + 200;
}

int fetch_remoteCount( int amount )
{
    return amount + 300;
}

int isBrokenState( int amount )
{
    return amount + 400;
}

int okayNamed( int amount )
{
    return amount + 500;
}

int stableHelper( int amount )
{
    return amount + 600;
}
CPP
cat >"$FIX/split.cpp" <<'CPP'
int oldRouter( int x )
{
    return x;
}
CPP

git -C "$FIX" init -q 2>/dev/null
git -C "$FIX" config user.email calibration@example.invalid
git -C "$FIX" config user.name  calibration
git -C "$FIX" config commit.gpgsign false
git -C "$FIX" add -A >/dev/null 2>&1
git -C "$FIX" commit -q -m "base" >/dev/null 2>&1

cat >"$FIX/lens.cpp" <<'CPP'
int totalScore( int amount )
{
    return amount + 100;
}

int handleRelay( int amount )
{
    return amount + 200;
}

int fetchRemote( int amount )
{
    return amount + 300;
}

int stateCode( int amount )
{
    return amount + 400;
}

int ab( int amount )
{
    return amount + 500;
}

int stableHelper( int counter )
{
    return counter + 600;
}
CPP
git -C "$FIX" commit -q -am "rename the five" >/dev/null 2>&1

cat >"$FIX/split.cpp" <<'CPP'
int routeA( int x )
{
    return x;
}

int routeB( int x )
{
    return x;
}
CPP
git -C "$FIX" commit -q -am "split the router" >/dev/null 2>&1

FIXOUT="$TMP/fixture.xml"
"$BIN" "$FIX" --naming-calibration >"$FIXOUT" 2>"$TMP/fixture.err"
rc=$?
[ "$rc" = "0" ] && ok "instrument: exit 0 (a measurement, never a verdict)" || no "instrument: exit $rc, expected 0"

hdr="$( rows "$FIXOUT" | grep '^naming-calibration ' | head -1 )"
[ -n "$hdr" ] || no "instrument: no <naming-calibration> element emitted"
fixpairs="$( attr "$hdr" pairs )"
[ "${fixpairs:-0}" = "5" ] && ok "instrument: the 5 planted renames survived mine + join (pairs=5)" \
                           || no "instrument: pairs=${fixpairs:-none}, expected 5 — mining or the join changed"

for want in \
    'o="computeTotalWeightedAverageScoreValue" n="totalScore"' \
    'o="handle__relay" n="handleRelay"' \
    'o="fetch_remoteCount" n="fetchRemote"' \
    'o="isBrokenState" n="stateCode"' \
    'o="okayNamed" n="ab"'
do
    grep -q "$want" "$FIXOUT" && ok "instrument: pair $want mined" || no "instrument: pair $want MISSING"
done

# per-rule, the hand-derived side. `old=` is the true-positive-ish side, `new=` the false-positive-ish one.
# A rule that fired on neither spelling has no proxy at all — pass "-" to say so, never "0.000", which
# would read as "measured, and terrible".
check_rule(){   # rule wantOld wantNew wantProxy ("-" = none expected)
    local row gotOld gotNew gotProxy
    row="$( rulerow "$FIXOUT" "$1" )"
    gotOld="$( attr "$row" old )"; gotNew="$( attr "$row" new )"; gotProxy="$( attr "$row" proxy )"
    [ -n "$gotProxy" ] || gotProxy="-"
    if [ "${gotOld:-x}" = "$2" ] && [ "${gotNew:-x}" = "$3" ] && [ "$gotProxy" = "$4" ]; then
        ok "instrument: $1 old=$2 new=$3 proxy=$4 — exactly the hand-derivation"
    else
        no "instrument: $1 old=${gotOld:-none} new=${gotNew:-none} proxy=$gotProxy, expected $2/$3/$4"
    fi
}
check_rule naming-wordy      1 0 1.000
check_rule naming-underscore 1 0 1.000
check_rule naming-case       1 0 1.000
check_rule naming-predicate  1 0 1.000
check_rule naming-short      0 1 0.000
check_rule naming-setter     0 0 -

# the two group rules are reported unscored rather than as a meaningless 0/0
for group in naming-series naming-confusable; do
    row="$( rulerow "$FIXOUT" "$group" )"
    case "$row" in
        *'scope="group-rule"'*) ok "instrument: $group reported scope=group-rule, not a fake 0/0" ;;
        *) no "instrument: $group should be scope=group-rule, got: $row" ;;
    esac
    case "$row" in
        *proxy=*) no "instrument: $group must not carry a proxy= it cannot have earned" ;;
        *) ok "instrument: $group carries no proxy=" ;;
    esac
done

# negative controls
grep -q 'o="stableHelper"' "$FIXOUT" && no "instrument: an unrenamed symbol became a pair" \
                                     || ok "instrument: the unrenamed symbol never became a pair"
grep -q 'o="oldRouter"' "$FIXOUT" && no "instrument: a one-to-many split was scored as one rename" \
                                  || ok "instrument: the one-to-many split was not scored"
[ "$( attr "$hdr" drop_ambiguous )" -ge 2 ] 2>/dev/null \
    && ok "instrument: the split is counted in drop_ambiguous, not silently gone" \
    || no "instrument: drop_ambiguous=$( attr "$hdr" drop_ambiguous ), expected >=2"
[ "$( attr "$hdr" drop_new_absent )" -ge 1 ] 2>/dev/null \
    && ok "instrument: the parameter rename is counted in drop_new_absent, not silently gone" \
    || no "instrument: drop_new_absent=$( attr "$hdr" drop_new_absent ), expected >=1"

# determinism, well-formedness, minification, and the G5 additivity contract
"$BIN" "$FIX" --naming-calibration >"$TMP/fixture2.xml" 2>/dev/null
cmp -s "$FIXOUT" "$TMP/fixture2.xml" && ok "instrument: two runs byte-identical" || no "instrument: NOT deterministic"
if command -v xmllint >/dev/null 2>&1; then
    xmllint --noout "$FIXOUT" 2>/dev/null && ok "instrument: XML well-formed" || no "instrument: XML not well-formed"
    xmllint --noout "$LIVE" 2>/dev/null && ok "live: XML well-formed" || no "live: XML not well-formed"
else
    note "xmllint absent — well-formedness not checked here (the suite checks it elsewhere)"
fi
[ "$( wc -l <"$FIXOUT" | tr -d ' ' )" -le 1 ] && ok "instrument: output is minified (G4)" || no "instrument: stray newlines in output"
"$BIN" "$FIX" >"$TMP/plain.xml" 2>/dev/null
grep -q 'naming-calibration' "$TMP/plain.xml" && no "G5: a flagless run mentions naming-calibration" \
                                              || ok "G5: a flagless run is untouched by this verb"

# a non-git root must say it has no history rather than report a confident zero
NOGIT="$TMP/nogit"; mkdir -p "$NOGIT"; cp "$FIX/lens.cpp" "$NOGIT/"
"$BIN" "$NOGIT" --naming-calibration >"$TMP/nogit.xml" 2>/dev/null
grep -q 'probed="0" r="not-a-git-repo"' "$TMP/nogit.xml" \
    && ok "honesty: a non-git root reports probed=0, never a confident 'no renames'" \
    || no "honesty: a non-git root did not report probed=0 — it answered as if it had looked"

# the honesty contract, asserted on the OUTPUT and not merely believed of the source
grep -q 'NOISY PROXY' "$FIXOUT" && ok "honesty: the legend leads with the noisy-proxy caveat" \
                                || no "honesty: the legend does not state that this is a noisy proxy"
grep -q 'pairs="' "$FIXOUT" && ok "honesty: the report states its sample size" || no "honesty: no sample size in the report"

if [ "$fail" != "0" ]; then
    echo "namingcalibrationcheck: FAIL"
    exit 1
fi

# A skip path must never spell the words that mean "this gate judged the thing it exists to judge", and the
# two exits are kept textually apart for the same reason test/gateexitcheck.sh (D) scans for them together:
# a green-while-inert gate is the failure mode this whole suite is built against. The instrument arm passing
# is NOT the live judgement having happened.
if [ "$skipping" = "1" ]; then
    echo "namingcalibrationcheck: SKIP stands — instrument arm verified, live judgement withheld (banner above)"
    exit 0
fi

echo "namingcalibrationcheck: ALL PASS"
exit 0
