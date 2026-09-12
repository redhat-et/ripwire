#!/usr/bin/env bash
# helpbudgetcheck.sh — `--help` is a TWO-TIER surface, and this gate is the fence around both tiers.
#
# THE PROBLEM IT EXISTS FOR. `--help` used to print one flat 185 KB / ~46 000-token document: every flag's
# one-line purpose AND every disclosure that flag has ever earned, interleaved, in reading order. On a tool
# whose entire pitch is token efficiency that is the most expensive thing it can be asked to print — more
# than almost any ANSWER it produces — and an agent that wanted to know which flag to reach for paid for
# 154 flags' worth of edge-case prose to find out.
#
# THE FIX IS A SPLIT, NOT A CULL, and that distinction is the whole point of this gate. Nothing was deleted:
#   tier 1  `--help`              one plain line per flag. Scannable, budgeted, the first screen.
#   tier 2  `--help=<flag>`       that one flag's full entry, every disclosure intact.
#           `--help=<section>`    one group at full detail.
#           `--help=all`          the entire former document, still one call away.
# CLAIM non-negotiable #3 (honesty in output is a feature) is why tier 2 is long, and it stays long. This
# gate's job is to make sure tier 1 stays SHORT while tier 2 stays COMPLETE — the two failure modes are
# opposite, so both get an arm, and a change that fixes one by breaking the other cannot pass.
#
# A THIRD FAILURE MODE, learned the expensive way in v0.6.0: the arms that compare the two tiers read
# both of them with the EMITTER'S OWN four-space row rule, so a row the emitter misclassifies is missing
# from both sides and the comparison is green about exactly the rows that were lost. Arm (K) exists
# because of that: its population is the flag table `parseArgs` actually scans, which shares no code with
# the help text. A gate whose population comes from the thing it measures is not a fence.
#
# WHY A GATE AND NOT A ONE-TIME TIDY: a help text grows one honest sentence at a time. Every disclosure in
# the 46 000 tokens was added by someone who was right to add it. Without a budget that fails, tier 1 is
# re-absorbed into tier 2 within a few rounds by exactly the same well-intentioned process that produced the
# original. The ceiling is the durable part of this change; the rewrite is just what got it under the ceiling.
#
# UNITS: tokens, not bytes — the project's user-facing unit (owner directive). Help text is English prose,
# which this repo has MEASURED at 3.1-4.7 B/tok (src/serialize.h §H7, bench/tokenaudit 2026-09-09). This
# gate converts at a flat 4.0 B/tok, the same rate the 46 000-token figure above was quoted at, so the
# before/after numbers are comparable. The conversion is deterministic and needs no tokenizer installed.
#
# Usage:
#   bash test/helpbudgetcheck.sh
#   RIPWIRE_BIN=asan/ripwire bash test/helpbudgetcheck.sh
#
# Exits non-zero on any failure; prints PASS/FAIL per arm and ALL PASS on success.

set -u
ROOT="$( cd "$( dirname "$0" )/.." && pwd )"
BIN="${1:-${RIPWIRE_BIN:-$ROOT/build/ripwire}}"
case "$BIN" in /*) ;; *) BIN="$ROOT/$BIN" ;; esac
TMP="$( mktemp -d )"; trap 'rm -rf "$TMP"' EXIT
fail=0
ok(){ printf '  PASS  %s\n' "$*" || { fail=1; printf '  FAIL  could not write the PASS line for: %s\n' "$*"; }; return 0; }
no(){ printf '  FAIL  %s\n' "$*"; fail=1; }

[ -x "$BIN" ] || { echo "no ripwire binary at $BIN — build first (cmake --build build -j)"; exit 2; }

# The published tier-1 ceiling. Raising this number is a DECISION, not a maintenance step: it says the
# first screen is allowed to cost more. Say why in the commit message if you move it.
CEILING_TOKENS=7000
BYTES_PER_TOKEN=4          # integer divisor; see UNITS above

"$BIN" --help      >"$TMP/concise" 2>/dev/null
"$BIN" --help=all  >"$TMP/full"    2>/dev/null

[ -s "$TMP/concise" ] || { no "(A) --help printed nothing"; exit 1; }
[ -s "$TMP/full" ]    || { no "(A) --help=all printed nothing — tier 2 is unreachable"; exit 1; }

# ── the row extractor, used identically by arms B, C and the control ──────────────────────────────────
# A ROW is a two-column entry line: four spaces, a label, two-or-more spaces, then its description. That
# shape covers the flags AND the shared legend rows that live in the same table (counts_floor="1",
# pr_iters="N", <dir>).
#
# WHAT IT CANNOT FENCE, stated here because the earlier wording claimed the opposite. Four spaces is the
# EMITTER'S OWN rule (src/cli.h classifyHelpLine), so a line the emitter misreads is invisible to this
# extractor too — it drops out of BOTH sides of arm (B)'s comparison and (B) then reports that nothing
# was culled. v0.6.0 shipped with twelve six-space flag rows and this extractor called it clean. Arm (K)
# is the fence that does not share this definition: its population comes from the parse tables.
rows(){ grep -E '^    (--[^ ]+|[^ ]+  +[^ ])' "$1" | sed -E 's/^    ([^ ]+) .*/\1/'; }

# ── (A) tier 1 fits the published budget ──────────────────────────────────────────────────────────────
cb="$( wc -c <"$TMP/concise" | tr -d ' ' )"
fb="$( wc -c <"$TMP/full"    | tr -d ' ' )"
ct=$(( cb / BYTES_PER_TOKEN ))
ft=$(( fb / BYTES_PER_TOKEN ))
if [ "$ct" -le "$CEILING_TOKENS" ]; then
    ok "(A) --help costs ~${ct} tokens (${cb} B), at or under the published ${CEILING_TOKENS}-token ceiling; --help=all is ~${ft} tokens"
else
    no "(A) --help costs ~${ct} tokens (${cb} B), OVER the ${CEILING_TOKENS}-token ceiling — shorten a summary or move prose to tier 2"
fi

# ── (B) nothing was CULLED: every tier-2 row is still advertised in tier 1 ────────────────────────────
# This is the arm that distinguishes a split from a deletion. If a flag exists at all, a reader who runs
# plain --help must be able to SEE that it exists, even if its detail lives one call away.
rows "$TMP/full"    | sort -u >"$TMP/rows.full"
rows "$TMP/concise" | sort -u >"$TMP/rows.concise"
nfull="$( wc -l <"$TMP/rows.full" | tr -d ' ' )"
[ "$nfull" -ge 100 ] || no "(B) presence guard: only $nfull rows extracted from --help=all — the extractor stopped matching, so arms B/C prove nothing"
comm -23 "$TMP/rows.full" "$TMP/rows.concise" >"$TMP/missing"
if [ ! -s "$TMP/missing" ]; then
    ok "(B) all $nfull rows in --help=all are advertised in --help — the split culled nothing"
else
    no "(B) $( wc -l <"$TMP/missing" | tr -d ' ' ) rows exist in --help=all but not in --help: $( tr '\n' ' ' <"$TMP/missing" )"
fi

# ── (C) tier 1 is ONE LINE PER ROW ────────────────────────────────────────────────────────────────────
# The property that makes tier 1 scannable and keeps arm (A) from being met by prose that merely got
# tighter. A continuation line in tier 1 is prose that belongs in tier 2.
if grep -nE '^ {5,}[^ ]' "$TMP/concise" >"$TMP/cont" 2>/dev/null; then
    no "(C) --help carries $( wc -l <"$TMP/cont" | tr -d ' ' ) continuation lines — tier 1 must be one line per row; first: $( head -1 "$TMP/cont" | cut -c1-120 )"
else
    ok "(C) every row in --help is a single line — the first screen stays scannable"
fi

# ── (D) tier 2 actually serves a single flag, and serves it WHOLE ─────────────────────────────────────
# Sample the longest entries: those are the ones whose disclosures were relocated, so those are the ones
# whose relocation must be provably reachable.
probed=0
for f in --for --token-budget --uses --impact --recall; do
    "$BIN" "--help=$f" >"$TMP/one" 2>/dev/null
    if [ ! -s "$TMP/one" ]; then no "(D) --help=$f printed nothing — its detail is unreachable"; continue; fi
    one="$( wc -l <"$TMP/one" | tr -d ' ' )"
    # the same flag's line count inside the full document, for comparison
    # NOTE: awk runs END even after `exit`, so `on` is cleared before exiting — otherwise this prints
    # the count twice and every downstream `[ ]` sees a two-line string, which is the shape of a gate
    # that reports FAIL for a reason unrelated to what it is testing.
    inall="$( awk -v f="$f" '
        !on && $0 ~ "^    " f "([=[ ]|$)" { on = 1; n = 1; next }
        on && /^ {5,}[^ ]/                { n++; next }
        on                                 { print n; on = 0; exit }
        END                                { if( on ) print n }' "$TMP/full" )"
    [ -n "$inall" ] || inall=0
    if [ "$one" -ge "$inall" ] && [ "$one" -gt 1 ]; then
        ok "(D) --help=$f serves its whole entry ($one lines; $inall in --help=all)"
        probed=$(( probed + 1 ))
    else
        no "(D) --help=$f served $one lines but --help=all carries $inall — tier 2 is TRUNCATING, which is the deletion this split exists to avoid"
    fi
done
[ "$probed" -ge 3 ] || no "(D) presence guard: only $probed of 5 probes reached a verdict"

# ── (E) tier 1 invents nothing: every tier-1 row label is a real flag ─────────────────────────────────
comm -13 "$TMP/rows.full" "$TMP/rows.concise" >"$TMP/extra"
if [ ! -s "$TMP/extra" ]; then
    ok "(E) --help advertises no row that --help=all does not define"
else
    no "(E) --help advertises rows absent from --help=all: $( tr '\n' ' ' <"$TMP/extra" )"
fi

# ── (K) every flag the PARSER accepts is NAMED on the first screen ────────────────────────────────────
# WHY THIS ARM EXISTS, AND WHY IT DOES NOT USE `rows`. Arms (B), (C) and (E) all take their population
# from the help text through `rows`, which is the EMITTER'S OWN four-space rule. A row the emitter
# misclassifies is therefore absent from BOTH sides of arm (B)'s comparison, so (B) prints "the split
# culled nothing" about exactly the rows that were culled. That is what shipped in v0.6.0: twelve flag
# rows carried a six-space indent, classifyHelpLine() read them as continuation prose, fifteen real flags
# vanished from tier 1 — and every arm in this file stayed green. A gate that takes its population from
# the thing it measures cannot catch that thing being wrong (CONTRIBUTING §2, shape 1).
#
# So this arm's population comes from the OTHER side of the binary. test/flaguniverse.py reads the parse
# tables (kBoolFlags / kViewFlags / kIntFlags) and the hand-written parseArgs arms — what the tool
# ACCEPTS — which lives in a different region of src/cli.h from the help strings and shares no code with
# the help emitter. Three other gates already derive their flag universe the same way.
#
# WHAT IT PROVES, AND THE NARROWER PART (CONTRIBUTING §2, shape 7): it asserts each accepted flag is
# NAMED somewhere in tier 1, not that each has a ROW of its own. A sub-knob advertised inside its
# parent's one-line summary — "[--around-depth=N, default 1]" inside --around's row — passes here by
# design, because that IS how the first screen advertises it. The claim being fenced is the one the
# --help=<miss> refusal makes out loud: "`ripwire --help` lists every row". A flag the first screen never
# spells cannot be found by a reader who runs only --help, and saying otherwise is a false claim about
# the tool's own output — the thing non-negotiable #3 forbids.
python3 "$ROOT/test/flaguniverse.py" "$ROOT/src/cli.h" 2>/dev/null | cut -f1 | sed -E 's/=$//' | sort -u >"$TMP/universe"
nuni="$( grep -c . "$TMP/universe" 2>/dev/null )"; [ -n "$nuni" ] || nuni=0

# The DEBT LIST: accepted flags this arm does not require tier 1 to name, each with the reason it is off
# the list. It is a list, not a rule, and it is committed so the gap is on the record rather than in
# someone's head — a flag added tomorrow fails this arm instead of joining the gap silently. Shortening
# it is a documentation change; lengthening it is a decision a reviewer must see and agree with.
cat >"$TMP/unadvertised" <<'EOF'
--eval=knownitem        an --eval harness alias (kBoolFlags "alias" row); eval-only, no entry in --help=all either
--anchor                a --for lens modifier, internal; no entry in --help=all either
--cochange-boost        a --for lens modifier, internal; no entry in --help=all either
--no-prefilter          a --grep search-path switch, internal; no entry in --help=all either
--most-important-last   DEPRECATED spelling, accepted only for back-compat (deprecatedOrderFlag -> --order=important-last)
--stable                DEPRECATED spelling, accepted only for back-compat (deprecatedOrderFlag -> --order=stable)
--no-auto-order         DEPRECATED spelling, accepted only for back-compat (deprecatedOrderFlag -> --order=important-first)
--route                 a back-compat NO-OP: routing is the default now, and --no-route is the spelling tier 1 carries
--connect-radius        a sub-knob, advertised inside --connect's own tier-2 prose rather than as a row
--include-builtins      a sub-knob, advertised inside --external-surface's own tier-2 prose rather than as a row
--zoom-levels           a sub-knob, advertised inside --zoom's own tier-2 prose rather than as a row
EOF

# The extraction, factored out so the control below re-runs the IDENTICAL one over mutated input.
unnamedFlags(){
    python3 - "$1" "$TMP/universe" "$TMP/unadvertised" <<'PY'
import re, sys
text   = open( sys.argv[ 1 ], encoding = 'utf-8' ).read()
uni    = [ l.strip() for l in open( sys.argv[ 2 ], encoding = 'utf-8' ) if l.strip() ]
exempt = { l.split()[ 0 ] for l in open( sys.argv[ 3 ], encoding = 'utf-8' ) if l.split() }
for flag in uni:
    if flag in exempt:
        continue
    # a whole-token match: --not must not be satisfied by --notes
    if not re.search( re.escape( flag ) + r'(?![A-Za-z0-9-])', text ):
        print( flag )
PY
}

if [ "$nuni" -lt 150 ]; then
    no "(K) presence guard: test/flaguniverse.py yielded only $nuni flags from src/cli.h — the scrape broke, so this arm proves nothing"
else
    # a stale debt-list entry would silently widen the exemption, so every name on it must still be a flag
    stale="$( cut -d' ' -f1 "$TMP/unadvertised" | sort -u | comm -23 - "$TMP/universe" | tr '\n' ' ' )"
    [ -z "$( printf '%s' "$stale" | tr -d ' ' )" ] || no "(K) the unadvertised debt list names flags parseArgs does not accept: $stale — prune it"
    unnamedFlags "$TMP/concise" >"$TMP/unnamed"
    nex="$( grep -c . "$TMP/unadvertised" )"
    if [ ! -s "$TMP/unnamed" ]; then
        ok "(K) all $nuni flags parseArgs accepts are named in --help ($nex on the committed unadvertised list)"
    else
        no "(K) $( grep -c . "$TMP/unnamed" ) flags parseArgs ACCEPTS are named nowhere in --help — the first screen does not list them, so \`--help\` does not list every row:"
        tr '\n' ' ' <"$TMP/unnamed" | sed 's/^/          /; s/ *$/\n/'
    fi
fi

# ── (L) CONTROL: arm (K)'s extraction can actually FAIL ───────────────────────────────────────────────
# Same discipline as (H): mutate REAL input, assert the mutation took, re-run the IDENTICAL extraction.
# --lego is the probe because it is one row, one spelling, and on no exemption list.
grep -v -- '--lego' "$TMP/concise" >"$TMP/concise.nolego"
if cmp -s "$TMP/concise" "$TMP/concise.nolego"; then
    no "(L) control: the mutation did not take — --lego was not found in --help, so the control proves nothing"
elif unnamedFlags "$TMP/concise.nolego" | grep -q -- '^--lego$'; then
    ok "(L) control fires: a flag dropped from the first screen is reported by arm (K)'s own extraction"
else
    no "(L) control did NOT fire: arm (K)'s extraction cannot detect an unadvertised flag — arm (K) is inert"
fi

# ── (F) the gate-held homes inside the help text survive the split ────────────────────────────────────
# test/legendcostcheck.sh reads the compact-legend saving FLOOR out of the help text — one place,
# deliberately. A split that moved that sentence into a tier nobody reads would silently defuse that gate,
# so this arm asserts the sentence is still where legendcostcheck looks for it.
if grep -qE 'at least [0-9]+% of a' "$TMP/full" && grep -qE '\-\-callers/--uses/--impact/--affected' "$TMP/full"; then
    ok "(F) the compact-legend saving floor and its verb list are still in the help text legendcostcheck reads"
else
    no "(F) --help=all no longer carries the 'at least N% of a' floor or its verb list — legendcostcheck.sh is now defused"
fi

# ── (G) a missing <dir> no longer costs a full help document ──────────────────────────────────────────
# Forgetting the positional path is the single most likely first-run mistake, and it used to print the
# entire 46 000-token help to stderr. An UNKNOWN FLAG already cost 32 bytes, so the tool always knew the
# right answer for a mistake — it just did not apply it here.
"$BIN" --callers=foo >/dev/null 2>"$TMP/err"; eb="$( wc -c <"$TMP/err" | tr -d ' ' )"
if [ "$eb" -le 4000 ] && grep -q -- '--help' "$TMP/err"; then
    ok "(G) a missing <dir> costs ${eb} B on stderr (~$(( eb / BYTES_PER_TOKEN )) tokens) and still points at --help"
else
    no "(G) a missing <dir> printed ${eb} B on stderr — a typo must not cost a help document (and must name --help)"
fi

# ── (J) EVERY row is addressable, not a sample of them ────────────────────────────────────────────────
# Arm (D) proves five entries come back whole. This one proves the ADDRESS SCHEME holds for all of them:
# tier 1 advertising a row that `--help=<that row>` cannot retrieve would be the split's worst failure —
# the reader is told a flag exists and then cannot reach what it does. 155 help prints, no corpus parse.
addr_miss=0; addr_tot=0
while read -r lab; do
    [ -n "$lab" ] || continue
    addr_tot=$(( addr_tot + 1 ))
    "$BIN" "--help=$lab" >/dev/null 2>&1 || { addr_miss=$(( addr_miss + 1 )); echo "          UNREACHABLE: $lab"; }
done <"$TMP/rows.concise"
if [ "$addr_tot" -ge 100 ] && [ "$addr_miss" -eq 0 ]; then
    ok "(J) all $addr_tot advertised rows are retrievable with --help=<row>"
elif [ "$addr_tot" -lt 100 ]; then
    no "(J) presence guard: only $addr_tot rows to probe — the extractor broke, so this arm proves nothing"
else
    no "(J) $addr_miss of $addr_tot advertised rows cannot be retrieved with --help=<row>"
fi

# ── (I) no tier-1 summary is PROVABLY cut off mid-phrase ──────────────────────────────────────────────
# WHAT THIS ARM PROVES, AND THE PART IT DOES NOT — read this before trusting its name. Tier 1's real
# property is "every summary stands on its own", and no lexical rule decides that: "…how much you must
# know that is NOT in front of you" and "…turning ONE gate on" both end in a preposition and both are
# complete. An earlier draft of this arm flagged five such lines and would have made the prose WORSE to
# satisfy the checker.
#
# So the arm asserts a strictly narrower property it can actually decide: a summary must not end in
# dangling punctuation, must not leave a bracket/quote/backtick open, and must fit the width. Those three
# are sound — an unclosed parenthesis or a trailing comma is a truncation, never a style. A summary that
# ends mid-sentence on an ordinary word passes here and is caught by review, not by this gate. Naming
# that gap is the point (CONTRIBUTING §2, shape 7: an arm whose NAME does work its CODE does not).
python3 - "$TMP/concise" >"$TMP/trunc" <<'PY'
import re, sys
bad = []
for line in open( sys.argv[ 1 ], encoding = 'utf-8' ):
    line = line.rstrip( '\n' )
    m = re.match( r'^    (\S.*?)(   +|  (?=\S))(.+)$', line )
    if not m:
        continue
    label, desc = m.group( 1 ), m.group( 3 ).rstrip()
    why = []
    for o, c in ( ( '(', ')' ), ( '[', ']' ) ):
        if desc.count( o ) != desc.count( c ):
            why.append( 'unbalanced %s' % o )
    if desc.count( '"' ) % 2:
        why.append( 'unclosed quote' )
    if desc.count( '`' ) % 2:
        why.append( 'unclosed backtick' )
    if desc and desc[ -1 ] in ',;:/|+-—&':
        why.append( 'ends on %r' % desc[ -1 ] )
    if len( line ) > 132:
        why.append( 'line is %d chars, over 132' % len( line ) )
    if why:
        bad.append( '%s: %s' % ( label, '; '.join( why ) ) )
for b in bad:
    print( b )
PY
if [ ! -s "$TMP/trunc" ]; then
    ok "(I) no tier-1 summary ends on dangling punctuation, an open bracket, or past 132 columns"
else
    no "(I) $( grep -c . "$TMP/trunc" ) tier-1 summaries are provably truncated:"
    sed 's/^/          /' "$TMP/trunc"
fi

# ── (H) CONTROL: the extraction in arm (B) can actually FAIL ──────────────────────────────────────────
# Per CONTRIBUTING §2: mutate REAL input, assert the mutation took, then re-run the IDENTICAL extraction.
# Without this, arms B/C are green on any tree where `rows` silently stops matching.
sed '/^    --for/d' "$TMP/concise" >"$TMP/mutated"
if cmp -s "$TMP/concise" "$TMP/mutated"; then
    no "(H) control: the mutation did not take — --for was not found in --help, so the control proves nothing"
else
    rows "$TMP/mutated" | sort -u >"$TMP/rows.mutated"
    if comm -23 "$TMP/rows.full" "$TMP/rows.mutated" | grep -q '^--for'; then
        ok "(H) control fires: dropping --for from the tier-1 capture is caught by arm (B)'s own extraction"
    else
        no "(H) control did NOT fire: arm (B)'s extraction cannot detect a culled flag — arm (B) is inert"
    fi
fi

echo
if [ "$fail" -eq 0 ]; then
    echo "helpbudgetcheck: ALL PASS — tier 1 ~${ct} tokens (ceiling ${CEILING_TOKENS}), tier 2 ~${ft} tokens and complete across $nfull rows"
else
    echo "helpbudgetcheck: FAILURES above"
fi
exit "$fail"
