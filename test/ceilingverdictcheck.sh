#!/usr/bin/env bash
# ceilingverdictcheck.sh — THE CEILING VERDICT IS A PROPERTY OF THE DOCUMENT, NEVER OF THE TASK TEXT.
#
# THE BUG (M3, 0.6.1). --for's root carries over_ceiling="1" when the bundle could not be trimmed to fit.
# The ladder that decides that (serialize.h climbCeilingLadderBy) KNOWS which rung it took — it is the
# branch that built the candidate — and verbs_for.h threw that away and RE-DERIVED the verdict by
# substring-searching the finished header for the rung's own note:
#
#     const bool ladderFired = !f.lastRungNote.empty() && header.find( f.lastRungNote ) != std::string::npos;
#
# The verbatim task echo is INSIDE that header. So a caller whose task text happens to contain the note
# is indistinguishable from a bundle that really hit the wall, and the document contradicts itself:
#
#     ripwire src --token-budget=100000 --for='… [over_ceiling= is 1 on the root: …no payload left to trim]'
#     → budget_tokens="100000" est_tokens="3880" over_ceiling="1"     (9701 B — nowhere near any ceiling)
#
# est_tokens far UNDER budget_tokens with over_ceiling="1" is exactly the shape the source comment beside
# these two numbers forbids ("both numbers sit on ONE root in ONE unit, so a reader can subtract them").
# PR #135 widened the blast radius by reading the same flag inside the ladder's FIT predicate, so injected
# text also priced phantom bytes onto every rung and could push an honest bundle down the ladder.
#
# THE DEFECT CLASS, which is what this gate is really for: a verdict re-derived by searching output text
# for a marker. Output text is attacker-supplied here (the task echo is verbatim by contract, routeoncecheck
# pins that), so ANY marker sniff over it is forgeable. The fix is structural — the ladder RETURNS its rung.
#
# BOTH TASK LENSES, because the class does not live in one file. --pack-task climbed the same ladder through
# the fixed-payload wrapper, which returned only a string, and recovered its verdict from
# `chosen.find( "over_ceiling:" )` — a 13-character substring of a document that echoes the caller's task
# verbatim, which is a strictly EASIER forgery than the one above (no 130-character note to reproduce):
#
#     ripwire src --token-budget=100000 --pack-task='why does over_ceiling: fire on this root'
#     → est_tokens="11329" budget_tokens="100000" over_ceiling="1"   (the same task without the colon: no label)
#
# So the wrapper returns the rung too. tracelocus.h had a third instance and its §F5 comment records removing it.
#
# forbudget-soft (rule 4, owner decisions 2026-10-14) MOVED WHERE THE VERDICTS LIVE, and this gate follows them
# rather than the old premise "a tight --token-budget emits over_ceiling". An explicit --token-budget on --for,
# --pack-task and --from-trace is now a SOFT target: there is no over_ceiling for budget_tokens at all, and the
# --for header ladder (and with it the last-rung notes this gate used to impersonate) is gone. The verdicts that
# still exist, and so the surfaces the forgery class can still reach:
#   · the --for RUNAWAY GUARD (serialize.h kForRunawayGuardBytes / forRunawayGuardNote): over_ceiling="1" only
#     from the structural row-drop cut (verbs_for.h forGuardCut = forSigsCut.rowDropCut) — e.g. --pack-top-n=400;
#   · --max-tokens on --for --detail (the body ceiling, est_tokens > max_tokens);
#   · the DEFAULT --pack-task (no flag, 6000 tokens): its hard ceiling ladder + over_ceiling are unchanged;
#   · --from-trace --max-tokens (est_tokens > max_tokens).
# On each: the FORGED task (the verdict's own clause, verbatim) and a PLAIN twin (the same words, the marker
# punctuation removed, so the ranking is the same) must get the SAME verdict and the SAME shape — and where the
# verdict is real (the guard cut, a tight --max-tokens, a header floor past 6000 tokens) BOTH carry it, so a
# green "no forged label" cannot come from a deleted attribute. On the soft lenses the arms are now
# FORGE + NOLBL: forged vs plain give identical shown/total/next=/rows, and neither is labelled.
#
# WHAT IS ASSERTED, per arm (codes from the lane brief: FORGE, NOLBL):
#   (0)/(0b)/(0c)/(0d) the probes are LIVE: each forged clause is what the code emits / splices today;
#   (1)/(6) the forged text reaches the emitted document (the injection vector is exercised);
#   (2) wide soft budget, (2b) default regime, (3) tight soft budget — --for: FORGE + NOLBL;
#   (3g) the guard cut: forged and plain BOTH labelled, identical shape (the verdict still fires when real);
#   (3m) --for --detail --max-tokens: forged vs plain identical verdict at a wide and a tight ceiling;
#   (4) the soft sweep over both lenses: FORGE + NOLBL at every point (counted, never vacuous);
#   (7)/(8) --pack-task wide/tight soft: FORGE + NOLBL; (8d) the DEFAULT --pack-task: FORGE, and a real label;
#   (8t) --from-trace --max-tokens: FORGE at a wide and a tight ceiling;
#   (5) the source-shape recurrence guard; (9) the map's unmeasured --max-tokens fit.
#
#   bash test/ceilingverdictcheck.sh                    # build/ripwire
#   bash test/ceilingverdictcheck.sh build_base/ripwire # or RIPWIRE_BIN=… — both seams honored

set -u
ROOT="$( cd "$( dirname "$0" )/.." && pwd )"
BIN="${1:-${RIPWIRE_BIN:-$ROOT/build/ripwire}}"
[ "${BIN#/}" = "$BIN" ] && BIN="$ROOT/$BIN"          # allow a repo-relative binary
TMP="$( mktemp -d )"; trap 'rm -rf "$TMP"' EXIT
fail=0
ok(){ printf '  PASS  %s\n' "$*" || { fail=1; printf '  FAIL  could not write the PASS line for: %s\n' "$*"; }; return 0; }
no(){ printf '  FAIL  %s\n' "$*"; fail=1; }

[ -x "$BIN" ] || { echo "no ripwire binary at $BIN — build first (cmake --build build -j)"; exit 2; }
command -v python3 >/dev/null 2>&1 || { echo "ceilingverdictcheck: python3 is required (shape comparison)"; exit 2; }
CORPUS="$ROOT/src"
[ -d "$CORPUS" ] || { echo "missing corpus $CORPUS"; exit 2; }

echo "ceilingverdictcheck: BIN=$BIN"

# THE FORGED MARKERS — each verdict's own clause, verbatim, pinned as literals with a LIVENESS guard (arm 0*)
# so a re-worded clause reds this gate instead of silently turning a probe into a task that forges nothing.
# --for: the runaway guard's reading (serialize.h forRunawayGuardNote), the one over_ceiling a default --for root
# can still carry. Its liveness is checked on the EMITTED guard document, not the source (the value is spliced in).
# The guard's byte value is spliced into the clause, so it is read from src/serialize.h (a stale binary then reds (0)).
GUARD_BYTES="$( sed -n 's/^inline constexpr [a-z:_ ]*kForRunawayGuardBytes *= *\([0-9]*\);.*/\1/p' "$ROOT/src/serialize.h" | head -1 )"
GUARD_NOTE="[over_ceiling=1: the ranked head passed the runaway guard of ${GUARD_BYTES:-MISSING} B (header plus ranked payload), so the rows past it are cut and sigs next= serves them all; on a default-size head this is a bug signal, not a budget (a wide pack-top-n head can reach it too)]"
FORGED="serialize the header $GUARD_NOTE"
# the PLAIN twin: every marker character replaced by a space, byte for byte (the ranker reads words, so both rank alike —
# arms (2b)/(3g) prove it by comparing the served rows), with no substring a marker sniff could match. Same LENGTH on
# purpose: the default text tier and the continuation's budget are charged with the header, which echoes the task, so a
# shorter twin would move docs_dropped= / next= for a reason that is not the marker.
plainOf(){ printf '%s' "$1" | sed -E 's/[^A-Za-z0-9 ]/ /g'; }
PLAIN="$( plainOf "$FORGED" )"
# --for --detail --max-tokens: the legend clause that defines the body-ceiling label (serialize.h kOverCeilingMaxTokensLegend)
MT_NOTE='over_ceiling=1 says est_tokens exceeds max_tokens'
MT_FORGED="serialize the header [$MT_NOTE]"
MT_PLAIN="$( plainOf "$MT_FORGED" )"
# --pack-task's own last-rung note, same role, its own punctuation (packtask.h kNotes). The forgeable part is
# the marker WORD, which is all the old sniff looked for — so the probe task carries only that.
PT_MARK='over_ceiling:'
PT_FORGED="why does $PT_MARK fire on this root"
PT_PLAIN="$( plainOf "$PT_FORGED" )"
# --from-trace: the named-ceiling last-rung note (tracelocus.h kNotesNamedCeiling), up to its first apostrophe (an
# attribute escapes it, and grep -F reads the raw bytes). The trace SOURCE is what this lens echoes (task=, src=), so
# the forged text rides the trace file's NAME.
TR_NOTE='[over_ceiling: the header floor (verbatim src echo + fixed legend) plus the innermost frame'
SRC="$ROOT/src/verbs_for.h"
PSRC="$ROOT/src/packtask.h"
TSRC="$ROOT/src/tracelocus.h"

attr(){ grep -o " $2=\"[0-9]*\"" <<< "$1" | head -1 | tr -cd '0-9'; }   # leading space: est_tokens must not match inside a longer name
# THE LABEL IS A ROOT ATTRIBUTE, so every arm reads it off the ROOT ELEMENT and not off the document. Both
# lenses echo the caller's task into an XML COMMENT with no quote escaping, so `over_ceiling="1"` typed into a
# task lands in the document verbatim and a whole-document grep would report a label nobody emitted — this
# gate's own probes would then be checking the probe. Attribute VALUES are escaped (`"` -> &quot;, `>` -> &gt;),
# so the root open tag cannot be spoofed the same way and `<ctx [^>]*>` cannot run past its own '>'.
rootOf(){ grep -o '<ctx [^>]*>' "$1" | head -1; }
hasLabel(){ rootOf "$1" | grep -c 'over_ceiling="1"' || true; }

# THE SHAPE a verdict could be forged into: the root's posture attributes, every windowed section's
# shown/total/capped/next_offset/past_target/docs_dropped and its next= (the task text replaced by TASK, since the
# continuation re-asks the caller's own task), the <trace> counts, and the served <sigs> rows in rank order. Two
# documents whose tasks differ only in marker punctuation must print the SAME shape. Exit 3 = no <ctx> root.
SHAPE="$TMP/shape.py"
cat > "$SHAPE" <<'PY_EOF'
import html, re, sys
s = open( sys.argv[1], encoding = 'utf-8', errors = 'replace' ).read()
task = sys.argv[2]
s = re.sub( r'<!\[CDATA\[.*?\]\]>', '', s, flags = re.S )      # a body's text is not the shape
s = re.sub( r'<!--.*?-->', '', s, flags = re.S )                # nor is the legend (it echoes the task)
root = re.search( r'<ctx\b([^>]*)>', s )
if root is None: sys.exit( 3 )
def attrs( text ): return dict( re.findall( r'(\w+)="([^"]*)"', text ) )
def norm( v ):
    v = html.unescape( v )
    return v.replace( task, 'TASK' ) if task else v
ra = attrs( root.group( 1 ) )
print( 'root ' + ' '.join( '%s=%s' % ( k, ra[k] ) for k in ( 'route', 'bundle', 'bodies', 'reason', 'budget_tokens', 'max_tokens', 'over_ceiling' ) if k in ra ) )
for m in re.finditer( r'<(sigs|bodies|callers|far|hops|tail|tests|notes|trace)\b([^>]*)>', s ):
    a = attrs( m.group( 2 ) )
    keep = [ '%s=%s' % ( k, a[k] ) for k in ( 'shown', 'total', 'capped', 'next_offset', 'past_target', 'docs_dropped',
                                              'format', 'frame_lines', 'parsed', 'in_corpus', 'suspects', 'merged', 'unresolved', 'skipped' ) if k in a ]
    if 'next' in a: keep.append( 'next=' + norm( a['next'] ) )
    print( m.group( 1 ) + ' ' + ' '.join( keep ) )
sg = re.search( r'<sigs\b[^>]*>(.*?)</sigs>', s, re.S )
rows = []
if sg:
    for d in re.finditer( r'<d ([^>]*)>', sg.group( 1 ) ):
        a = attrs( d.group( 1 ) )
        r = a.get( 'r', '' )
        rows.append( ( int( r ) if r.isdigit() else 10**9, a.get( 'p', '?' ) + ':' + a.get( 'l', '?' ) + ':' + a.get( 'n', '?' ) ) )
rows.sort()
print( 'rows %d %s' % ( len( rows ), ' '.join( x[1] for x in rows ) ) )
PY_EOF
# sameShape FILE_A TASK_A FILE_B TASK_B — 0 when both documents parse to the same shape; else prints the first diff
sameShape(){
    python3 "$SHAPE" "$1" "$2" > "$TMP/sa" || { echo "    no <ctx> root in $( basename "$1" )"; return 1; }
    python3 "$SHAPE" "$3" "$4" > "$TMP/sb" || { echo "    no <ctx> root in $( basename "$3" )"; return 1; }
    grep -q '^rows [1-9]' "$TMP/sa" || { echo "    $( basename "$1" ) serves no <sigs> row — nothing to compare"; return 1; }
    cmp -s "$TMP/sa" "$TMP/sb" && return 0
    diff "$TMP/sa" "$TMP/sb" | head -4 | cut -c1-220 | sed 's/^/    /'
    return 1
}
# forgeArm LABEL FORGED_DOC FORGED_TASK PLAIN_DOC PLAIN_TASK WANT — FORGE: identical shape; both labels == WANT (0|1)
forgeArm(){
    local fo po
    [ -s "$2" ] && [ -s "$4" ] || { no "$1: a probe produced no document (forged $( wc -c < "$2" | tr -d ' ' ) B, plain $( wc -c < "$4" | tr -d ' ' ) B)"; return; }
    fo="$( hasLabel "$2" )";  po="$( hasLabel "$4" )"
    if [ "$fo" != "$po" ]; then
        no "$1: FORGED — the marker text changed the root's verdict (forged over_ceiling=$fo vs plain $po)"
    elif [ "$fo" != "$6" ]; then
        no "$1: both roots carry over_ceiling count=$fo, expected $6 ($( [ "$6" = 1 ] && echo 'the verdict is real here and must still fire' || echo 'no ceiling this root names is exceeded' ))"
    elif ! sameShape "$2" "$3" "$4" "$5"; then
        no "$1: the forged and plain tasks served different shapes (diff above) — the marker text moved the answer"
    else
        ok "$1: forged and plain tasks get the same verdict (over_ceiling $( [ "$6" = 1 ] && echo 'on both' || echo 'on neither' )) and the same shown/total/next=/rows"
    fi
}

cliFor(){  "$BIN" "$CORPUS" --no-cache "$@" 2>/dev/null; }

# ── the runs. The soft sweep first: its 300 and 100000 points are also arms (2), (3), (7), (8). ────────────────
SWEEP="300 500 1000 2000 4000 20000 100000"
for b in $SWEEP; do
    cliFor --token-budget="$b" --for="$FORGED"          > "$TMP/for.$b.f"
    cliFor --token-budget="$b" --for="$PLAIN"           > "$TMP/for.$b.p"
    cliFor --token-budget="$b" --pack-task="$PT_FORGED" > "$TMP/pt.$b.f"
    cliFor --token-budget="$b" --pack-task="$PT_PLAIN"  > "$TMP/pt.$b.p"
done
cliFor --for="$FORGED"                  > "$TMP/for.def.f"
cliFor --for="$PLAIN"                   > "$TMP/for.def.p"
cliFor --pack-top-n=400 --for="$FORGED" > "$TMP/for.guard.f"
cliFor --pack-top-n=400 --for="$PLAIN"  > "$TMP/for.guard.p"

# (0) the --for probe is live: the clause the forged task carries is, byte for byte, the clause the runaway guard
#     splices — read off the PLAIN guard document, whose task carries no marker, so only the code can have put it there.
if [ "$( hasLabel "$TMP/for.guard.p" )" -ge 1 ] && grep -qF -e "$GUARD_NOTE" "$TMP/for.guard.p"; then
    ok "(0) the forged clause is the runaway guard's own reading, as emitted on a guard cut (the --for probe can forge)"
else
    no "(0) the plain --pack-top-n=400 run carries no over_ceiling=\"1\" with this gate's GUARD_NOTE verbatim — re-pin GUARD_NOTE (serialize.h forRunawayGuardNote), or the forgery probe is inert and every --for arm passes for the wrong reason"
fi
if grep -qF -e "| $PT_MARK the header floor" "$PSRC"; then
    ok "(0b) '$PT_MARK' is still the marker in --pack-task's last-rung note in src/packtask.h (the pack-task probe can forge)"
else
    no "(0b) src/packtask.h's last-rung note no longer spells '$PT_MARK' — re-pin PT_MARK, or the pack-task arms prove nothing"
fi
if grep -qF -e "\" $MT_NOTE\"" "$ROOT/src/serialize.h"; then
    ok "(0c) the --max-tokens label's definition is still '$MT_NOTE' in src/serialize.h (the --detail probe can forge)"
else
    no "(0c) src/serialize.h no longer defines the max_tokens label as '$MT_NOTE' — re-pin MT_NOTE"
fi
if grep -qF -e "\" $TR_NOTE" "$TSRC"; then
    ok "(0d) the --from-trace named-ceiling note still opens '$TR_NOTE' in src/tracelocus.h (the trace probe can forge)"
else
    no "(0d) src/tracelocus.h's named-ceiling note no longer opens '$TR_NOTE' — re-pin TR_NOTE"
fi

# (1) the vector really reaches the emitted document — the task echo carries the marker into the header a
#     sniff would search. Without this the forgery arms could pass because nothing was injected at all.
if grep -qF -e "$GUARD_NOTE" "$TMP/for.def.f" && ! grep -qF -e "$GUARD_NOTE" "$TMP/for.def.p"; then
    ok "(1) the forged clause reaches the emitted default --for document, and only through the task (the injection vector is exercised)"
else
    no "(1) the forged task text does not appear in the default --for document (or the plain twin carries it too) — the injection never happened, so arms (2)-(4) prove nothing"
fi

# (2) wide SOFT budget: a document far inside the target it states must not be labelled, and must not state a
#     self-contradicting pair of numbers; forbudget-soft (rule 4): its plain twin must also be shape-identical (FORGE).
fw_est="$( attr "$( rootOf "$TMP/for.100000.f" )" est_tokens )"
fw_bud="$( attr "$( rootOf "$TMP/for.100000.f" )" budget_tokens )"
# TOKEN-BUDGET-MONOTONE (rule 4, 2026-11-14): a budget the answer fits returns the unbudgeted answer byte for byte, so the root
# names no budget_tokens= at all here (nothing was shed); the pair judged is est_tokens= against the budget asked
fw_bud="${fw_bud:-100000}"
if [ -z "$fw_est" ] || [ -z "$fw_bud" ]; then
    no "(2) the wide-budget forged run emitted no est_tokens=/budget_tokens= pair to judge (est='$fw_est' budget='$fw_bud')"
elif [ "$fw_est" -ge "$fw_bud" ]; then
    no "(2) the wide-budget probe is not wide enough to be unambiguous: est_tokens=$fw_est is not under budget_tokens=$fw_bud — raise the sweep's top"
else
    forgeArm "(2) --for --token-budget=100000 (est_tokens=$fw_est)" "$TMP/for.100000.f" "$FORGED" "$TMP/for.100000.p" "$PLAIN" 0
fi

# (2b) forbudget-soft (rule 4) — REPLACES the kept-rows last-rung reason (src/verbs_for.h kNotesKeptRows, deleted with
#      the --for header ladder). The DEFAULT regime is where the --for guard verdict lives: the guard's own clause in
#      the task must not label a default answer, nor move one row of it.
forgeArm "(2b) default --for (no budget)" "$TMP/for.def.f" "$FORGED" "$TMP/for.def.p" "$PLAIN" 0

# (3) forbudget-soft (rule 4) — REPLACES "the same task at --token-budget=300 still carries over_ceiling" (a soft target
#     has no ceiling verdict now). FORGE + NOLBL at a target the answer blows: same shown/total/next=/rows, no label.
ft_est="$( attr "$( rootOf "$TMP/for.300.f" )" est_tokens )"
if [ -n "$ft_est" ] && [ "$ft_est" -gt 300 ]; then
    forgeArm "(3) --for --token-budget=300 (est_tokens=$ft_est, past the soft target)" "$TMP/for.300.f" "$FORGED" "$TMP/for.300.p" "$PLAIN" 0
else
    no "(3) --for --token-budget=300 is not past its target (est_tokens='$ft_est') — the tight point no longer probes a blown target"
fi

# (3g) THE CONTRAST the old (3) was for — the verdict still fires when it is real. --pack-top-n=400 passes the runaway
#      guard: BOTH tasks are labelled (from the structural cut), and the forged text moves nothing.
forgeArm "(3g) --for --pack-top-n=400 (the runaway guard cut)" "$TMP/for.guard.f" "$FORGED" "$TMP/for.guard.p" "$PLAIN" 1

# (3m) the --max-tokens body ceiling on --for --detail (a hard verdict that lives): forged definition vs plain, at a
#      ceiling the answer fits and at one it blows — the same verdict both times, real where real.
cliFor --detail=3 --max-tokens=100000 --for="$MT_FORGED" > "$TMP/mt.wide.f"
cliFor --detail=3 --max-tokens=100000 --for="$MT_PLAIN"  > "$TMP/mt.wide.p"
cliFor --detail=3 --max-tokens=300    --for="$MT_FORGED" > "$TMP/mt.tight.f"
cliFor --detail=3 --max-tokens=300    --for="$MT_PLAIN"  > "$TMP/mt.tight.p"
grep -qF -e "$MT_NOTE" "$TMP/mt.tight.p" \
    && ok "(3m) the tight plain run defines its label with '$MT_NOTE' (the clause the forged task carries)" \
    || no "(3m) the tight plain --max-tokens run does not define over_ceiling with '$MT_NOTE' — the probe impersonates nothing"
forgeArm "(3m) --for --detail=3 --max-tokens=100000" "$TMP/mt.wide.f"  "$MT_FORGED" "$TMP/mt.wide.p"  "$MT_PLAIN" 0
forgeArm "(3m) --for --detail=3 --max-tokens=300"    "$TMP/mt.tight.f" "$MT_FORGED" "$TMP/mt.tight.p" "$MT_PLAIN" 1

# (4) forbudget-soft (rule 4) — REPLACES "every labelled document in the sweep is genuinely over a ceiling" (labelled == 0
#     was a FAIL). On the soft lenses a label is now never genuine, so the sweep asserts FORGE + NOLBL at every
#     (lens, budget) point, counted so the arm cannot pass on zero comparisons. The real labels are (3g)/(3m)/(8d)/(8t).
compared=0; bad=0
for b in $SWEEP; do
    for lens in for pt; do
        if [ "$lens" = for ]; then ft="$FORGED"; pt="$PLAIN"; else ft="$PT_FORGED"; pt="$PT_PLAIN"; fi
        fd="$TMP/$lens.$b.f"; pd="$TMP/$lens.$b.p"
        if [ ! -s "$fd" ] || [ ! -s "$pd" ]; then bad=$(( bad + 1 )); echo "    $lens budget=$b: a probe produced no document"; continue; fi
        compared=$(( compared + 1 ))
        fo="$( hasLabel "$fd" )"; po="$( hasLabel "$pd" )"
        if [ "$fo" != 0 ] || [ "$po" != 0 ]; then
            bad=$(( bad + 1 )); echo "    $lens budget=$b: over_ceiling on a soft target (forged $fo, plain $po)"
        elif ! sameShape "$fd" "$ft" "$pd" "$pt"; then
            bad=$(( bad + 1 )); echo "    $lens budget=$b: ^ forged and plain shapes differ"
        fi
    done
done
if [ "$compared" -eq 0 ]; then
    no "(4) the sweep compared nothing — the invariant held vacuously"
elif [ "$bad" -eq 0 ]; then
    ok "(4) at all $compared (lens x soft budget) points: no over_ceiling, and forged/plain tasks serve the same shape"
else
    no "(4) $bad of $( echo "$SWEEP" | wc -w | tr -d ' ' )x2 soft sweep points labelled a soft target or let the marker text move the answer"
fi

# (6) THE PACK-TASK INJECTION VECTOR is live — the same presence guard arm (1) is for the --for lens.
if grep -qF "$PT_MARK" "$TMP/pt.100000.f"; then
    ok "(6) the forged marker reaches the emitted --pack-task document (the injection vector is exercised)"
else
    no "(6) the forged pack-task text does not appear in the emitted document — the injection never happened, so arm (7) proves nothing"
fi

# (7) THE PACK-TASK HEADLINE, arm (2)'s twin: a 13-character substring in the task must not label the root.
pw_est="$( attr "$( rootOf "$TMP/pt.100000.f" )" est_tokens )"
pw_bud="$( attr "$( rootOf "$TMP/pt.100000.f" )" budget_tokens )"
if [ -z "$pw_est" ] || [ -z "$pw_bud" ]; then
    no "(7) the wide-budget forged --pack-task run emitted no est_tokens=/budget_tokens= pair to judge (est='$pw_est' budget='$pw_bud')"
elif [ "$pw_est" -ge "$pw_bud" ]; then
    no "(7) the wide-budget --pack-task probe is not unambiguous: est_tokens=$pw_est is not under budget_tokens=$pw_bud — raise the sweep's top"
else
    forgeArm "(7) --pack-task --token-budget=100000 (est_tokens=$pw_est)" "$TMP/pt.100000.f" "$PT_FORGED" "$TMP/pt.100000.p" "$PT_PLAIN" 0
fi

# (8) forbudget-soft (rule 4) — REPLACES "--pack-task --token-budget=300 still carries over_ceiling" (an explicit budget is
#     a soft target): FORGE + NOLBL at a target the bundle blows.
pt_est="$( attr "$( rootOf "$TMP/pt.300.f" )" est_tokens )"
if [ -n "$pt_est" ] && [ "$pt_est" -gt 300 ]; then
    forgeArm "(8) --pack-task --token-budget=300 (est_tokens=$pt_est, past the soft target)" "$TMP/pt.300.f" "$PT_FORGED" "$TMP/pt.300.p" "$PT_PLAIN" 0
else
    no "(8) --pack-task --token-budget=300 is not past its target (est_tokens='$pt_est') — the tight point no longer probes a blown target"
fi

# (8d) THE CONTRAST (8) was for, where the hard ladder still lives: the DEFAULT --pack-task (no flag, 6000 tokens). A
#      short forged task is not labelled; a task whose header floor alone passes 6000 tokens IS — forged or plain alike.
cliFor --pack-task="$PT_FORGED" > "$TMP/ptd.f"
cliFor --pack-task="$PT_PLAIN"  > "$TMP/ptd.p"
forgeArm "(8d) default --pack-task" "$TMP/ptd.f" "$PT_FORGED" "$TMP/ptd.p" "$PT_PLAIN" 0
PT_HUGE_F="$( python3 -c 'import sys; print( ( ( sys.argv[1] + " " ) * 420 ).strip() )' "$PT_FORGED" )"
PT_HUGE_P="$( python3 -c 'import sys; print( ( ( sys.argv[1] + " " ) * 420 ).strip() )' "$PT_PLAIN" )"
cliFor --pack-task="$PT_HUGE_F" > "$TMP/pth.f"
cliFor --pack-task="$PT_HUGE_P" > "$TMP/pth.p"
forgeArm "(8d) default --pack-task, a ${#PT_HUGE_F}-char task (header floor past 6000 tokens)" "$TMP/pth.f" "$PT_HUGE_F" "$TMP/pth.p" "$PT_HUGE_P" 1

# (8t) --from-trace --max-tokens (the hard ceiling this lens still labels): the trace file's NAME carries the note.
mkdir -p "$TMP/tr" || no "(8t) cannot create $TMP/tr"
TR_F="$TMP/tr/trace $TR_NOTE.txt"
TR_P="$TMP/tr/$( plainOf "trace $TR_NOTE" ).txt"
printf 'src/graph.h:120:5: error: no member named zz\nsrc/serialize.h:200: in escapeXml\n' > "$TR_F"
cp "$TR_F" "$TR_P"
for mt in 100000 200; do
    cliFor --from-trace="$TR_F" --max-tokens="$mt" > "$TMP/tr.$mt.f"
    cliFor --from-trace="$TR_P" --max-tokens="$mt" > "$TMP/tr.$mt.p"
done
grep -qF -e "$TR_NOTE" "$TMP/tr.100000.f" \
    && ok "(8t) the forged trace name reaches the emitted --from-trace document (the injection vector is exercised)" \
    || no "(8t) the forged trace name does not appear in the --from-trace document — the injection never happened"
forgeArm "(8t) --from-trace --max-tokens=100000" "$TMP/tr.100000.f" "$TR_F" "$TMP/tr.100000.p" "$TR_P" 0
forgeArm "(8t) --from-trace --max-tokens=200"    "$TMP/tr.200.f"    "$TR_F" "$TMP/tr.200.p"    "$TR_P" 1

# (5) RECURRENCE GUARD on the SOURCE SHAPE — and read its limits before you lean on it. It is a grep over one
#     spelling, in two directions, with comments stripped so a sentence ABOUT the defect cannot red it:
#       · NEGATIVE — no marker sniff: no `header.find(` in the --for finishing path, no `lastRungNote` field
#         for one to search for, and no `chosen.find(` in --pack-task. spliceBefore's `doc.find( boundary )`
#         is a different operation on a different string (a boundary the emitter itself wrote), not matched.
#       · POSITIVE — each lens's verdict is ASSIGNED from a structural value. This half is what a RENAME cannot
#         walk past: reintroducing the defect through a differently-named field deletes these assignments and reds here.
#         forbudget-soft (rule 4): the --for verdict no longer comes from a ladder rung (`lastRungFired = ( chosen.rung`,
#         deleted with the header ladder); it is the runaway guard's row-drop cut, `forGuardCut = forSigsCut.rowDropCut`,
#         handed to the root as `.guardOver = forGuardCut`. --pack-task's default ladder keeps its rung assignment.
#     WHAT IT IS NOT: a proof. Any guard shaped like a grep can be evaded by a spelling it does not know; the arms
#     that DISCRIMINATE are the behavioural ones above. Treat a green (5) as "the known shapes are absent".
stripped(){ sed 's|//.*||' "$1"; }
badfind="$( stripped "$SRC"  | grep -c 'header\.find('  || true )"
badnote="$( stripped "$SRC"  | grep -c 'lastRungNote'   || true )"
badpack="$( stripped "$PSRC" | grep -c 'chosen\.find('  || true )"
forcut="$(  stripped "$SRC"  | grep -cE 'forGuardCut *= *forSigsCut\.rowDropCut' || true )"
forasn="$(  stripped "$SRC"  | grep -cE '\.guardOver *= *forGuardCut'           || true )"
packasn="$( stripped "$PSRC" | grep -cE 'chosen\.rung == (rw::)?CeilingRung::OverCeiling' || true )"
if [ "$badfind" -eq 0 ] && [ "$badnote" -eq 0 ] && [ "$badpack" -eq 0 ] && [ "$forcut" -ge 1 ] && [ "$forasn" -ge 1 ] && [ "$packasn" -ge 1 ]; then
    ok "(5) --for assigns its verdict from the guard's row-drop cut and --pack-task from the rung its ladder returned; no marker sniff remains (spelling-level guard only)"
else
    no "(5) a verdict is re-derived from emitted text, or no longer assigned from a structural value: verbs_for.h header.find(=$badfind lastRungNote=$badnote guard-cut=$forcut guardOver-assignment=$forasn; packtask.h chosen.find(=$badpack rung-assignment=$packasn — the first three must be 0, the last three >= 1)"
fi

# ── (9) AN UNMEASURED FIT IS NOT A HELD CAP — the map's --max-tokens verdict when its probe cannot measure ──────────
# Both fit probes in runDefaultMap return 0 when their charge buffer fails, and 0 reads as "fits": the map used to
# print max_tokens=/fit_bytes= with NO over_ceiling, whose legend says absent = cap held — a verdict no measurement
# backed. The probes now DISCLOSE into MaxTokensFit, which prints over_ceiling=1 fail-closed beside fit_unmeasured=1
# (defined in its own legend comment), XML and JSON alike. The fault switch is non-NDEBUG only, so the arm reads the
# flavour and SKIPs on Release; the control (no switch) must carry neither.
CV_FLAVOUR="$( "$BIN" --version 2>/dev/null | sed -nE 's/^[^(]*\(([^,)]*).*/\1/p' )"
case "$CV_FLAVOUR" in
    Release|RelWithDebInfo|MinSizeRel)
        printf '  SKIP  (9) the charge-buffer fault switch is compiled out of this %s (NDEBUG) binary — the plain-flavour leg proves it\n' "$CV_FLAVOUR" ;;
    *)
        RIPWIRE_FAULT_CHARGE_BUFFER=1 "$BIN" "$ROOT/test/fixture" --max-tokens=3000 --no-cache >"$TMP/m8.xml" 2>/dev/null
        grep -q 'max_tokens=3000 fit_bytes=[0-9]* over_ceiling=1 fit_unmeasured=1' "$TMP/m8.xml" \
            && ok "(9) an unmeasured --max-tokens fit is labelled: over_ceiling=1 fit_unmeasured=1" \
            || no "(9) an unmeasured --max-tokens fit printed as a held cap: $( grep -o 'max_tokens=[0-9]* fit_bytes=[^-]*' "$TMP/m8.xml" | head -1 )"
        grep -q 'fit_unmeasured=1: ' "$TMP/m8.xml" \
            && ok "(9) fit_unmeasured= is defined in the same document" || no "(9) fit_unmeasured= rides with no definition"
        RIPWIRE_FAULT_CHARGE_BUFFER=1 "$BIN" "$ROOT/test/fixture" --max-tokens=3000 --json --no-cache 2>/dev/null | grep -q '"fit_bytes":[0-9]*,"fit_measured_in":"xml","over_ceiling":true,"fit_unmeasured":true' \
            && ok "(9) the JSON map carries over_ceiling:true AND fit_unmeasured:true on the same degrade (XML parity)" \
            || no "(9) the JSON map's unmeasured fit reads as a held cap, or as a measured overflow (no fit_unmeasured key)"
        # CodeRabbit thread 4053600628 (test/ceilingverdictcheck.sh:250): grep -q against a command whose
        # output was piped straight in passed vacuously if the unfaulted run failed or printed nothing at
        # all — no marker in empty output is still "no match". Capture rc and stdout FIRST, require exit 0
        # and the max_tokens=3000 stamp (proof the run actually produced this map), THEN assert absence.
        m9out="$( "$BIN" "$ROOT/test/fixture" --max-tokens=3000 --no-cache 2>/dev/null )"; m9rc=$?
        if [ "$m9rc" -eq 0 ] && printf '%s' "$m9out" | grep -q 'max_tokens=3000'; then
            printf '%s' "$m9out" | grep -q 'fit_unmeasured\|max_tokens=3000 fit_bytes=[0-9]* over_ceiling' \
                && no "(9) control: the unfaulted map carries fit_unmeasured/over_ceiling" \
                || ok "(9) control: the unfaulted map carries neither (the cap is measured and held)"
        else
            no "(9) control: the unfaulted run did not produce a max_tokens=3000 map (rc=$m9rc) — the control proves nothing"
        fi ;;
esac

[ "$fail" -eq 0 ] && echo "ALL PASS" || echo "ceilingverdictcheck: FAILURES ABOVE"
exit "$fail"
