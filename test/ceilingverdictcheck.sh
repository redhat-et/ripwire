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
# So the wrapper returns the rung too, and arms (6)-(8) are that lens's reproduction. tracelocus.h had a third
# instance and its §F5 comment records removing it; arm (5) is the source-shape recurrence guard over all three.
#
# WHAT IS ASSERTED, and why it is not simply "over_ceiling must be absent". forLensOverCeiling fires on two
# independent grounds (verbs_for.h): the token comparison est_tokens > budget_tokens, and the BYTE comparison
# the ladder's last rung is — the document past ceilingAllowanceBytes( budget ) = budget x 2.36 x 1.15
# (serialize.h). The second is deliberately WIDER than the first, so "over_ceiling implies est > budget" would
# be a false invariant. The honest one, which is what arm (4) sweeps, is the disjunction: the label may ride
# only on a document that is over one of the two ceilings its own root states, in numbers a reader can check.
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
CORPUS="$ROOT/src"
[ -d "$CORPUS" ] || { echo "missing corpus $CORPUS"; exit 2; }

echo "ceilingverdictcheck: BIN=$BIN"

# The forged marker is the ladder's LAST-RUNG note, verbatim. Pinned here as a literal rather than parsed out
# of the C++ (it is a two-line string concatenation), with a PRESENCE GUARD below so a re-worded note reds
# this gate instead of silently turning the probe into a task that forges nothing (trap: a vanishing probe
# target). Both halves are checked, because the source splits the constant between them.
MARK_A='over_ceiling= is 1 on the root: the header floor (verbatim task echo + fixed legend) exceeds this budget'
MARK_B='- no payload left to trim]'
MARK="[$MARK_A $MARK_B"
FORGED="serialize the header $MARK"
PLAIN='serialize the header ranking'
# --pack-task's own last-rung note, same role, its own punctuation (packtask.h kNotes). The forgeable part is
# the marker WORD, which is all the old sniff looked for — so the probe task carries only that.
PT_MARK='over_ceiling:'
PT_FORGED="why does $PT_MARK fire on this root"
PT_PLAIN='why does over ceiling fire on this root'

# (0) the probe is live: the note this task impersonates is still the note the code splices.
SRC="$ROOT/src/verbs_for.h"
PSRC="$ROOT/src/packtask.h"
if grep -qF -e "$MARK_A" "$SRC" && grep -qF -e "$MARK_B" "$SRC"; then   # -e: MARK_B starts with '-'
    ok "(0) the forged marker is still the ladder's last-rung note in src/verbs_for.h (the probe can forge)"
else
    no "(0) the last-rung note in src/verbs_for.h no longer matches this gate's MARK_A/MARK_B — re-pin them, or the forgery probe is inert and every arm below passes for the wrong reason"
fi
if grep -qF -e "| $PT_MARK the header floor" "$PSRC"; then
    ok "(0b) '$PT_MARK' is still the marker in --pack-task's last-rung note in src/packtask.h (the pack-task probe can forge)"
else
    no "(0b) src/packtask.h's last-rung note no longer spells '$PT_MARK' — re-pin PT_MARK, or arms (6)-(8) prove nothing"
fi

run(){ "$BIN" "$CORPUS" --no-cache --token-budget="$1" --for="$2" 2>/dev/null; }
runPack(){ "$BIN" "$CORPUS" --no-cache --token-budget="$1" --pack-task="$2" 2>/dev/null; }
attr(){ grep -o " $2=\"[0-9]*\"" <<< "$1" | head -1 | tr -cd '0-9'; }   # leading space: est_tokens must not match inside a longer name
# THE LABEL IS A ROOT ATTRIBUTE, so every arm reads it off the ROOT ELEMENT and not off the document. Both
# lenses echo the caller's task into an XML COMMENT with no quote escaping, so `over_ceiling="1"` typed into a
# task lands in the document verbatim and a whole-document grep would report a label nobody emitted — this
# gate's own probes would then be checking the probe. Attribute VALUES are escaped (`"` -> &quot;, `>` -> &gt;),
# so the root open tag cannot be spoofed the same way and `<ctx [^>]*>` cannot run past its own '>'.
rootOf(){ grep -o '<ctx [^>]*>' "$1" | head -1; }
hasLabel(){ rootOf "$1" | grep -c 'over_ceiling="1"' || true; }

WIDE=100000
"$BIN" "$CORPUS" --no-cache --token-budget="$WIDE" --for="$FORGED" > "$TMP/forged.wide" 2>/dev/null
"$BIN" "$CORPUS" --no-cache --token-budget="$WIDE" --for="$PLAIN"  > "$TMP/plain.wide"  2>/dev/null
"$BIN" "$CORPUS" --no-cache --token-budget=300     --for="$FORGED" > "$TMP/forged.tight" 2>/dev/null
"$BIN" "$CORPUS" --no-cache --token-budget="$WIDE" --pack-task="$PT_FORGED" > "$TMP/pt.forged.wide" 2>/dev/null
"$BIN" "$CORPUS" --no-cache --token-budget="$WIDE" --pack-task="$PT_PLAIN"  > "$TMP/pt.plain.wide"  2>/dev/null
"$BIN" "$CORPUS" --no-cache --token-budget=300     --pack-task="$PT_FORGED" > "$TMP/pt.forged.tight" 2>/dev/null

# (1) the vector really reaches the emitted document — the task echo carries the marker into the header the
#     old code searched. Without this the forgery arm could pass because nothing was injected at all.
if grep -qF "$MARK_A" "$TMP/forged.wide"; then
    ok "(1) the forged marker reaches the emitted header (the injection vector is exercised)"
else
    no "(1) the forged task text does not appear in the emitted document — the injection never happened, so arm (2) proves nothing"
fi

# (2) THE HEADLINE: a document 27x inside its own byte allowance must not be labelled over its ceiling, and
#     must not state a self-contradicting pair of numbers.
fw_est="$( attr "$( rootOf "$TMP/forged.wide" )" est_tokens )"
fw_bud="$( attr "$( rootOf "$TMP/forged.wide" )" budget_tokens )"
fw_over="$( hasLabel "$TMP/forged.wide" )"
if [ -z "$fw_est" ] || [ -z "$fw_bud" ]; then
    no "(2) the wide-budget forged run emitted no est_tokens=/budget_tokens= pair to judge (est='$fw_est' budget='$fw_bud')"
elif [ "$fw_over" -ne 0 ]; then
    no "(2) FORGED: task text put over_ceiling=\"1\" on a root that states est_tokens=$fw_est under budget_tokens=$fw_bud ($( wc -c < "$TMP/forged.wide" | tr -d ' ' ) B) — the verdict was read off the task echo, not off the document"
elif [ "$fw_est" -ge "$fw_bud" ]; then
    no "(2) the wide-budget probe is not wide enough to be unambiguous: est_tokens=$fw_est is not under budget_tokens=$fw_bud — raise WIDE"
else
    ok "(2) task text cannot forge over_ceiling=\"1\" (est_tokens=$fw_est under budget_tokens=$fw_bud, attribute absent)"
fi

# (3) CONTRAST — the SAME task at a budget it genuinely blows must still be labelled. Arms (2) and (3) differ
#     in NOTHING but the number after --token-budget, so (2) cannot be green because the attribute was deleted.
ft_est="$( attr "$( rootOf "$TMP/forged.tight" )" est_tokens )"
ft_over="$( hasLabel "$TMP/forged.tight" )"
if [ "$ft_over" -ge 1 ]; then
    ok "(3) the same task at --token-budget=300 still carries over_ceiling=\"1\" (est_tokens=$ft_est) — the verdict still fires when it is real"
else
    no "(3) --token-budget=300 emitted no over_ceiling=\"1\" (est_tokens=$ft_est) — the label is gone, not fixed, and arm (2) is green for the wrong reason"
fi

# (4) THE INVARIANT SWEEP — over_ceiling="1" may ride only on a document that is over one of the two ceilings
#     its own root names: est_tokens > budget_tokens (tokens) or bytes > budget x 2.36 x 1.15 (the ladder's
#     allowance, serialize.h ceilingAllowanceBytes). Swept over both tasks so a pass needs the property to hold
#     on the forged AND the honest text, and counted so the arm cannot be vacuous.
#     Swept over BOTH lenses now, because both climb this ladder and only one of them was ever gated.
labelled=0; violations=0
for b in 300 500 1000 2000 4000 20000 100000; do
    # "lens:task" pairs — the split is on the FIRST colon, and every lens name is colon-free, so a task that
    # contains one (the --for marker does) survives intact.
    for probe in "for:$FORGED" "for:$PLAIN" "pack-task:$PT_FORGED" "pack-task:$PT_PLAIN"; do
        lens="${probe%%:*}";  task="${probe#*:}"
        if [ "$lens" = for ]; then run "$b" "$task" > "$TMP/sweep.xml"; else runPack "$b" "$task" > "$TMP/sweep.xml"; fi
        [ -s "$TMP/sweep.xml" ] || { no "(4) $lens --token-budget=$b produced no document"; continue; }
        [ "$( hasLabel "$TMP/sweep.xml" )" -ne 0 ] || continue
        labelled=$(( labelled + 1 ))
        est="$( attr "$( rootOf "$TMP/sweep.xml" )" est_tokens )";  bytes="$( wc -c < "$TMP/sweep.xml" | tr -d ' ' )"
        allow="$( awk -v b="$b" 'BEGIN{ printf "%d", b * 2.36 * 1.15 }' )"
        if [ -n "$est" ] && [ "$est" -le "$b" ] && [ "$bytes" -le "$allow" ]; then
            violations=$(( violations + 1 ))
            no "(4) $lens budget=$b: over_ceiling=\"1\" on a document inside BOTH ceilings it names (est_tokens=$est <= $b, bytes=$bytes <= allowance $allow) — task: $( printf '%.40s' "$task" )…"
        fi
    done
done
if [ "$labelled" -eq 0 ]; then
    no "(4) no swept run carried over_ceiling=\"1\" at all — the invariant held vacuously; the sweep's tight budgets must produce at least one labelled document"
elif [ "$violations" -eq 0 ]; then
    ok "(4) every one of the $labelled labelled documents in the sweep is genuinely over a ceiling its own root states"
fi

# (6) THE PACK-TASK INJECTION VECTOR is live — the same presence guard arm (1) is for the --for lens.
if grep -qF "$PT_MARK" "$TMP/pt.forged.wide"; then
    ok "(6) the forged marker reaches the emitted --pack-task document (the injection vector is exercised)"
else
    no "(6) the forged pack-task text does not appear in the emitted document — the injection never happened, so arm (7) proves nothing"
fi

# (7) THE PACK-TASK HEADLINE, arm (2)'s twin: a 13-character substring in the task must not label the root.
pw_est="$( attr "$( rootOf "$TMP/pt.forged.wide" )" est_tokens )"
pw_bud="$( attr "$( rootOf "$TMP/pt.forged.wide" )" budget_tokens )"
pw_over="$( hasLabel "$TMP/pt.forged.wide" )"
pp_over="$( hasLabel "$TMP/pt.plain.wide" )"
if [ -z "$pw_est" ] || [ -z "$pw_bud" ]; then
    no "(7) the wide-budget forged --pack-task run emitted no est_tokens=/budget_tokens= pair to judge (est='$pw_est' budget='$pw_bud')"
elif [ "$pw_over" -ne "$pp_over" ]; then
    no "(7) FORGED: the marker word in a --pack-task task changed the root's verdict (forged over_ceiling=$pw_over vs plain $pp_over) on est_tokens=$pw_est under budget_tokens=$pw_bud — the verdict was read off the task echo"
elif [ "$pw_over" -ne 0 ]; then
    no "(7) both --pack-task probes are labelled at budget_tokens=$pw_bud (est_tokens=$pw_est) — WIDE is not wide enough for the contrast to mean anything; raise it"
elif [ "$pw_est" -ge "$pw_bud" ]; then
    no "(7) the wide-budget --pack-task probe is not unambiguous: est_tokens=$pw_est is not under budget_tokens=$pw_bud — raise WIDE"
else
    ok "(7) task text cannot forge over_ceiling=\"1\" on --pack-task (est_tokens=$pw_est under budget_tokens=$pw_bud, attribute absent on the root, and absent on the plain twin too)"
fi

# (8) PACK-TASK CONTRAST, arm (3)'s twin: same task, a budget it genuinely blows, label still there.
pt_est="$( attr "$( rootOf "$TMP/pt.forged.tight" )" est_tokens )"
if [ "$( hasLabel "$TMP/pt.forged.tight" )" -ge 1 ]; then
    ok "(8) the same --pack-task at --token-budget=300 still carries over_ceiling=\"1\" (est_tokens=$pt_est) — the verdict still fires when it is real"
else
    no "(8) --pack-task --token-budget=300 emitted no over_ceiling=\"1\" (est_tokens=$pt_est) — the label is gone, not fixed, and arm (7) is green for the wrong reason"
fi

# (5) RECURRENCE GUARD on the SOURCE SHAPE — and read its limits before you lean on it. It is a grep over one
#     spelling, in two directions, with comments stripped so a sentence ABOUT the defect cannot red it:
#       · NEGATIVE — no marker sniff: no `header.find(` in the --for finishing path, no `lastRungNote` field
#         for one to search for, and no `chosen.find(` in --pack-task. spliceBefore's `doc.find( boundary )`
#         is a different operation on a different string (a boundary the emitter itself wrote), not matched.
#       · POSITIVE — each lens's verdict is ASSIGNED from the value the ladder returned. This half is what a
#         RENAME cannot walk past: reintroducing the defect through a differently-named field (a `rungMarker`
#         carrying the note text, say) deletes these assignments and reds here, where the negative half alone
#         stayed green through exactly that mutation while arms (2)/(4) went red.
#     WHAT IT IS NOT: a proof. Any guard shaped like a grep can be evaded by a spelling it does not know, and
#     the arms that DISCRIMINATE are (2)/(4) for --for and (7)/(4) for --pack-task — behavioural, over real
#     documents. Treat a green (5) as "the known shapes are absent", never as "the verdict cannot be forged".
stripped(){ sed 's|//.*||' "$1"; }
badfind="$( stripped "$SRC"  | grep -c 'header\.find('  || true )"
badnote="$( stripped "$SRC"  | grep -c 'lastRungNote'   || true )"
badpack="$( stripped "$PSRC" | grep -c 'chosen\.find('  || true )"
forasn="$(  stripped "$SRC"  | grep -cE 'lastRungFired *= *\( *chosen\.rung'        || true )"
packasn="$( stripped "$PSRC" | grep -cE 'chosen\.rung == (rw::)?CeilingRung::OverCeiling' || true )"
if [ "$badfind" -eq 0 ] && [ "$badnote" -eq 0 ] && [ "$badpack" -eq 0 ] && [ "$forasn" -ge 1 ] && [ "$packasn" -ge 1 ]; then
    ok "(5) both lenses assign the verdict from the rung the ladder returned, and no marker sniff remains (spelling-level guard only — (2)/(4)/(7) are the discriminating arms)"
else
    no "(5) the rung verdict is re-derived from emitted text, or no longer assigned from the ladder's return: verbs_for.h header.find(=$badfind lastRungNote=$badnote rung-assignment=$forasn; packtask.h chosen.find(=$badpack rung-assignment=$packasn — each of the last two must be >= 1)"
fi

[ "$fail" -eq 0 ] && echo "ALL PASS" || echo "ceilingverdictcheck: FAILURES ABOVE"
exit "$fail"
