#!/usr/bin/env bash
# ITEM R — `--for` serves its answer FIRST: the legend goes last, and a RESOLVED routed section goes ahead
# of <sigs>. A PERMUTATION, and this gate's whole job is to prove it is one.
#
# WHY THIS IS THE ONE LEVER LEFT. Four pre-registered attempts to make a --for answer shorter by CUTTING
# failed their own zero-gold-loss rules: a fixed tail cap (item K), a specific height of 64 (K1), collapsing
# the tail when a routed element is PRESENT (item C, lost on 19 cells), and collapsing it when a routed verb
# RESOLVES (item C', lost on 3 of the 27 it fires on). Unconditional tail removal costs 92 anchors across 63
# of 275 cells. A permutation removes nothing, so it cannot lose an anchor and cannot fail that bar.
#
# WHAT IT BUYS, measured as offline permutations of all 216 recorded --for cells before any code was written:
# gold items found at a 2 KB budget 0.4 % -> 54.8 %, at 4 KB 19.3 % -> 70.6 %, at 8 KB 69.5 % -> 84.1 %;
# median bytes-to-complete 10,279 -> 5,541; ZERO of 212 cells worse; 27 of 27 repos improved. On the 13 cells
# carrying <path reachable="1"> or <met_bridge>, bytes-to-complete falls from 37,125 B (92.9 % depth) to
# 3,377 B (8.0 %).
#
# WHY THE LEGEND MAY MOVE AT ALL. G4 constrains the legend's COUNT -- "the legend is emitted once per answer
# on the CLI" -- not its position, and its next clause already describes an answer that "ends with" its
# legend material. The legend STAYS IN THE ANSWER, so the ~80 gates asserting "defined in this answer" still
# pass; this is the ref posture's move without the ref posture's drop, which src/legenddict.h already
# documents as "rows first ... legend comment ... moved after the rows".
#
# RESOLVED IS NARROW, AND THAT IS NOT AN ACCIDENT. Three separate bands this round mistook element PRESENCE
# for resolution. <lego> and <compose> ship as `shown="0" capped="1"` STUBS when nothing resolved, and
# <graph_verb> is often an unresolved `reachable="0"` cascade -- moving any graph_verb has a worst case of
# +17,479 B, of which one cell's answering path was 1,348 B. So: <reexports> with BOTH a <def> row and at
# least one <rx> row, or <graph_verb> whose resolved element is <path reachable="1"> or <met_bridge> -- and
# only the resolved element moves.
#
# Arms:
#   (R1)  PERMUTATION: the multiset of top-level blocks is identical to the legacy order's, byte for byte
#   (R1n) the negative control -- a DROPPED row must make R1 fail, or R1 asserts nothing
#   (R2)  the legend is LAST, and still present (count unchanged: G4 is about count)
#   (R3)  a RESOLVED routed section precedes <sigs>; an UNRESOLVED one does not move
#   (R4)  byte-for-byte identical totals: a permutation changes no byte count
#   (R5)  determinism -- two runs byte-identical, and the order depends on argv alone
#   (R6)  the default order is reproducible
#   (R9)  --legend=first is the legend-first order: the legend precedes the rows
#   (R9d) AF1 (owner decision 2026-11-18): the DEFAULT is answer-first -- its rows precede its legend
set -u
# SIGX (src/forsigx.h, TL1 M1) runs AFTER this permutation and is lossless but not a permutation (it adds the <x r=R> envelopes and
# the <sigx> block). This gate pins the PERMUTATION alone, so SIGX is off here; test/forsigxcheck.sh pins SIGX, and its (S1) rebuilds
# this gate's answer-first document from the default one byte for byte.
export RIPWIRE_NO_SIGX=1
# KB1 (src/forkeybody.h) likewise runs after the permutation and ADDS the key-body group, so it is off here too; test/forkeybodycheck.sh
# (K3n) proves the default answer minus that group is this gate's document byte for byte (est_tokens= aside).
export RIPWIRE_NO_KEY_BODY=1
ROOT="$( cd "$( dirname "$0" )/.." && pwd )"
BIN="${RIPWIRE_BIN:-${1:-$ROOT/build/ripwire}}"
[ "${BIN#/}" = "$BIN" ] && BIN="$ROOT/$BIN"
if [ ! -x "$BIN" ]; then echo "no ripwire binary at $BIN -- build first (cmake --build build -j)"; exit 2; fi
command -v python3 >/dev/null 2>&1 || { echo "foranswerfirstcheck: python3 required"; exit 2; }
fail=0
ok(){ printf '  PASS  %s\n' "$*" || { fail=1; printf '  FAIL  could not write the PASS line for: %s\n' "$*"; }; return 0; }
no(){ printf '  FAIL  %s\n' "$1"; fail=1; }
WORK="$( mktemp -d )"; trap 'rm -rf "$WORK"' EXIT
echo "foranswerfirstcheck: BIN=$BIN"

# The opt-out knob is GATE ENVIRONMENT ONLY, never a binary knob -- the same posture test/legendtarget.sh's
# RIPWIRE_LEGEND_PINS=strict uses. Without a legacy baseline R1 has nothing to compare against, and a
# permutation gate with no baseline is a gate that cannot fail.
# AF1 (owner decision 2026-11-18): answer-first IS the default now, and the default answer is PAGED (src/forpages.h,
# test/forpagescheck.sh). This gate compares WHOLE answers, so the answer-first side asks --page-bytes=0, and the legacy
# baseline is the opt-out --legend=first. The budgeted path (R7) does not page, so it takes $OPTIN alone.
OPTIN="--legend=last"   # answer-first, spelled
WHOLE="--page-bytes=0"  # the whole answer in one call: the permutation is judged on whole documents
LEGACY="--legend=first" # the legend-first order the permutation is measured against

# Two tasks: one conceptual (the 84 % population) and one that resolves a routed section (the 13-cell shape
# the band's largest effect comes from). If the second never resolves on this tree, (R3) says so rather than
# passing vacuously.
TASK_A="legend posture"
TASK_B="path from runForLens to runForLensPosture"

cap(){  # cap FILE TASK [extra-args-to-the-binary]
    local f="$1" t="$2"; shift 2
    "$BIN" . --for="$t" "$@" >"$f" 2>/dev/null
}

cap "$WORK/a_new.xml" "$TASK_A" $OPTIN $WHOLE
cap "$WORK/a_old.xml" "$TASK_A" $LEGACY
cap "$WORK/b_new.xml" "$TASK_B" $OPTIN $WHOLE
cap "$WORK/b_old.xml" "$TASK_B" $LEGACY
for f in a_new a_old b_new b_old; do
    [ -s "$WORK/$f.xml" ] || { no "(R0) $f.xml is empty -- nothing to check"; echo "FAILURES"; exit 1; }
done
ok "(R0) four answers captured, opt-in and default order, two task shapes"

python3 - "$WORK" <<'PY'
import re, sys, os
WORK = sys.argv[1]
WS = " \n\r\t"

def read(n):
    with open(os.path.join(WORK, n), encoding="utf-8", errors="replace") as fh:
        return fh.read()

ROOT = re.compile(r"<([A-Za-z_][A-Za-z0-9_-]*)\b[^>]*>")

def blocks(doc):
    """Top-level children of the root, as (kind, name, exact text) in document order.

    A hand-rolled scanner, not a regex: --for answers carry ripwire's own C++ inside CDATA, and that source
    contains both comment-shaped and tag-shaped text. 228 of 295 recorded answers carry CDATA, and an
    unmasked scan once lost an entire 16.9 KB section from a different band's instrument.
    """
    m = ROOT.search(doc)
    if not m:
        return None, None, None
    open_tag, i = m.group(0), m.end()
    close = "</%s>" % m.group(1)
    endAt = doc.rfind(close)
    if endAt < i:
        endAt = len(doc)
    out, depth, start, kind = [], 0, None, None
    while i < endAt:
        if doc.startswith("<!--", i):
            j = doc.find("-->", i)
            if j < 0: break
            if depth == 0: out.append(("comment", None, doc[i:j+3]))
            i = j + 3
            continue
        if doc.startswith("<![CDATA[", i):
            j = doc.find("]]>", i)
            i = (j + 3) if j >= 0 else endAt
            continue
        if doc.startswith("</", i):
            j = doc.find(">", i)
            if j < 0: break
            depth -= 1
            if depth == 0 and start is not None:
                out.append(("element", kind, doc[start:j+1])); start = None
            i = j + 1
            continue
        if doc[i] == "<":
            j = doc.find(">", i)
            if j < 0: break
            tag = doc[i:j+1]
            nm = re.match(r"<([A-Za-z_][A-Za-z0-9_-]*)", tag)
            selfclose = tag.endswith("/>")
            if depth == 0:
                if selfclose:
                    out.append(("element", nm.group(1) if nm else "?", tag))
                else:
                    start, kind = i, (nm.group(1) if nm else "?")
            if not selfclose:
                depth += 1
            i = j + 1
            continue
        i += 1
    return open_tag, out, doc[endAt:]

def kids(text):
    """Direct children of one container element's text, as (kind, name, exact text): the same CDATA-safe scan,
    run on the element's interior (a wrapper root lets blocks() do it)."""
    i = text.find(">") + 1; j = text.rfind("</")
    if text.endswith("/>") and i == len(text): return []
    _, out, _ = blocks("<w>" + text[i:j] + "</w>")
    return out or []

def units(bs):
    """AF2 (results/AF2_FIRST12K_1118 §SPEC): a unit is each top-level block's open tag, close tag and each of its
    DIRECT children (rows and comments) -- a top-level comment or self-closing element is one unit. AF2's move A
    lifts direct-child comments out of a section into the legend, so a whole-block multiset can no longer be
    equal; the UNIT multiset must be, and that still fails on any dropped row (R1n)."""
    out = []
    for k, n, t in bs:
        if k == "comment" or t.endswith("/>") and t.find(">") + 1 == len(t):
            out.append(t); continue
        out.append(t[:t.find(">") + 1]); out.append(t[t.rfind("</"):])
        out += [c for _, _, c in kids(t)]
    return out

def multiset(bs):
    return sorted(units(bs))

def names(bs):
    return [n for k, n, _ in bs if k == "element"]

def comments(bs):
    return [t for k, _, t in bs if k == "comment"]

bad = 0
for label, new_n, old_n in (("conceptual", "a_new.xml", "a_old.xml"), ("routed", "b_new.xml", "b_old.xml")):
    newd, oldd = read(new_n), read(old_n)
    o_new, b_new, t_new = blocks(newd)
    o_old, b_old, t_old = blocks(oldd)
    if b_new is None or b_old is None:
        print("  FAIL  (R1) %-11s not one XML document" % label); bad += 1; continue

    # (R1) THE PERMUTATION. Same blocks, byte for byte, in some order. Root open tag and trailer identical.
    if multiset(b_new) == multiset(b_old) and o_new == o_old and t_new == t_old:
        print("  PASS  (R1) %-11s permutation: %d units identical byte for byte (AF2: open/close tags + direct children), root and trailer unchanged"
              % (label, len(multiset(b_new))))
    else:
        lost = [t[:60] for t in multiset(b_old) if t not in multiset(b_new)]
        print("  FAIL  (R1) %-11s NOT a permutation -- %d units vs %d; first missing: %s"
              % (label, len(multiset(b_new)), len(multiset(b_old)), (lost[:1] or ["<root/trailer differs>"])[0]))
        bad += 1

    # (R4) A permutation changes no byte count.
    if len(newd) == len(oldd):
        print("  PASS  (R4) %-11s byte count unchanged (%d B)" % (label, len(newd)))
    else:
        print("  FAIL  (R4) %-11s byte count moved %d -> %d -- a permutation cannot" % (label, len(oldd), len(newd)))
        bad += 1

    # (R2) THE LEGEND IS LAST, and still present. G4 constrains COUNT, so the count must not move either.
    cn, co = comments(b_new), comments(b_old)
    # AF2 A: a comment lifted out of a section becomes a top-level legend comment, so G4's COUNT is over every comment a
    # unit can be (top-level + direct children of a section), never over the top level alone.
    allc = lambda bs: sum(1 for u in units(bs) if u.startswith("<!--"))
    if allc(b_new) != allc(b_old):
        print("  FAIL  (R2) %-11s comment count moved %d -> %d -- G4 is about count" % (label, allc(b_old), allc(b_new)))
        bad += 1
    elif False:
        print("  FAIL  (R2) %-11s legend comment count moved %d -> %d -- G4 is about count" % (label, len(co), len(cn)))
        bad += 1
    elif not cn:
        print("  FAIL  (R2) %-11s no top-level comment to place -- this task proves nothing about the legend" % label)
        bad += 1
    else:
        kinds = [k for k, _, _ in b_new]

        # A BLOCK-LOCAL legend is EXEMPT here, by design: it names its own element and travels with that block
        # so it still sits immediately before the block's open tag. Excluding them is not a relaxation of R2 --
        # R2 and R8 TOGETHER are stricter than R2 alone ever was. R2 alone said "every comment is at the tail";
        # R2+R8 say "the DOCUMENT legend is at the tail AND each block legend is exactly adjacent to its block",
        # which forbids strictly more arrangements. R8 is what makes this exemption safe, so if R8 is ever
        # deleted this exemption must go with it.
        # AF1-fix: `<!-- ripwire for X …` is the other spelling of a block-local legend (foranswerfirst.h commentFirstWord)
        def blockLocal( idx ):
            m = re.match( r'<!--\s*(?:ripwire for )?([A-Za-z_][\w-]*)', b_new[ idx ][ 2 ] )
            if not m:
                return False
            for k2, n2, _ in b_new[ idx + 1: ]:
                if k2 == "comment":
                    continue          # several comments may queue in front of one block
                return n2 == m.group( 1 )
            return False              # nothing follows it: the document legend by position as well as by name

        docC   = [ i for i, k in enumerate( kinds ) if k == "comment" and not blockLocal( i ) ]
        local  = sum( 1 for i, k in enumerate( kinds ) if k == "comment" and blockLocal( i ) )
        lastEl = max( ( i for i, k in enumerate( kinds ) if k == "element" ), default = -1 )
        firstC = min( docC, default = len( kinds ) )
        if not docC:
            print("  FAIL  (R2) %-11s every comment is block-local -- no document legend was placed, so R2 proves nothing" % label)
            bad += 1
        elif firstC > lastEl:
            print("  PASS  (R2) %-11s every one of the %d document legend comments follows every row block (%d block-local, pinned by R8)" % (label, len(docC), local))
        else:
            print("  FAIL  (R2) %-11s a document legend comment at index %d precedes the last row block at %d" % (label, firstC, lastEl))
            bad += 1

    # (R3) A RESOLVED routed section precedes <sigs>; an UNRESOLVED one does not move.
    nm = names(b_new)
    resolved = []
    for k, n, t in b_new:
        if k != "element":
            continue
        if n == "reexports" and "<def" in t and "<rx" in t:
            resolved.append(n)
        elif n == "graph_verb" and ('reachable="1"' in t or "<met_bridge" in t):
            resolved.append(n)
    if resolved:
        si = nm.index("sigs") if "sigs" in nm else len(nm)
        firstRes = min(nm.index(r) for r in resolved)
        if firstRes < si:
            print("  PASS  (R3) %-11s resolved %s precedes <sigs> (index %d < %d)" % (label, resolved[0], firstRes, si))
        else:
            print("  FAIL  (R3) %-11s resolved %s did NOT move ahead of <sigs> (%d >= %d)" % (label, resolved[0], firstRes, si))
            bad += 1
    else:
        unres = [n for k, n, t in b_new if k == "element" and n in ("graph_verb", "reexports", "lego", "compose")]
        print("  INFO  (R3) %-11s no RESOLVED routed section here; unresolved/stub blocks present: %s"
              % (label, ",".join(unres) if unres else "none"))
        if unres and "sigs" in nm:
            si = nm.index("sigs")
            moved = [n for n in unres if nm.index(n) < si]
            if moved:
                print("  FAIL  (R3b) %-11s an UNRESOLVED/stub block moved ahead of <sigs>: %s -- presence is not resolution" % (label, ",".join(moved)))
                bad += 1
            else:
                print("  PASS  (R3b) %-11s no unresolved or stub block moved ahead of <sigs>" % label)

# (R1n) THE NEGATIVE CONTROL. R1 compares multisets; if deleting a row does not break it, it asserts nothing.
newd = read("a_new.xml")
_, bs, _ = blocks(newd)
victim = next((t for k, n, t in bs if k == "element" and n == "sigs"), None)
if victim is None:
    print("  FAIL  (R1n) no <sigs> block to delete -- the control cannot run")
    bad += 1
else:
    mutated = newd.replace(victim, "", 1)
    _, bm, _ = blocks(mutated)
    if bm is not None and multiset(bm) != multiset(bs):
        print("  PASS  (R1n) deleting the <sigs> block (%d B) DOES break the permutation check -- R1 can fail" % len(victim))
    else:
        print("  FAIL  (R1n) deleting a whole block did NOT break the permutation check -- R1 asserts nothing")
        bad += 1

sys.exit(1 if bad else 0)
PY
[ $? -eq 0 ] || fail=1

# (R5) DETERMINISM. The order depends on argv and the tree alone -- never on whether an earlier call happened.
cap "$WORK/z1.xml" "$TASK_A" $OPTIN $WHOLE
cap "$WORK/z2.xml" "$TASK_A" $OPTIN $WHOLE
if cmp -s "$WORK/z1.xml" "$WORK/z2.xml"; then
    ok "(R5) two runs byte-identical"
else
    no "(R5) two runs differ -- the order is not a function of argv and the tree"
fi

# (R6) THE DEFAULT IS REPRODUCIBLE, so the baseline every arm above rests on is itself trustworthy.
cap "$WORK/r1.xml" "$TASK_A" $LEGACY
if cmp -s "$WORK/r1.xml" "$WORK/a_old.xml"; then
    ok "(R6) the default order is reproducible byte for byte"
else
    no "(R6) two default runs differ -- the gate's own baseline is unstable"
fi

# (R9) THE OPT-OUT IS LEGEND-FIRST. Until AF1 this was the arm the owner's opt-in decision rested on, and no other arm
# implies it: R1-R8 all compare an opt-in answer against the default, and every one of them would still pass if
# the permutation ALSO ran by default. Measured 2026-11-17: as the default this ordering left an active cut or
# floor disclosure outside the 2 KB prefix on 9 of 50 --for answers, so "off by default" is a correctness
# property here, not a preference.
for subj in a_old b_old; do
    legAt=$( python3 -c "
import sys
d = open( sys.argv[ 1 ], 'rb' ).read()
print( d.find( b'<!-- ripwire for' ), d.find( b'<sigs' ) )
" "$WORK/$subj.xml" )
    set -- $legAt
    if [ "$1" -ge 0 ] && [ "$2" -ge 0 ] && [ "$1" -lt "$2" ]; then
        ok "(R9) $subj: --legend=first serves its legend BEFORE the rows (legend@$1 < sigs@$2)"
    else
        no "(R9) $subj: --legend=first no longer puts the legend first (legend@$1 sigs@$2) -- the opt-out leaked answer-first"
    fi
done
# (R9d) AF1: the DEFAULT is answer-first. Without this arm R1-R8 would all pass with the flip reverted, because they
# compare two ASKED postures; this is the arm that makes "the default is answer-first" checkable.
cap "$WORK/dflt.xml" "$TASK_A"
legAt=$( python3 -c "
import sys
d = open( sys.argv[ 1 ], 'rb' ).read()
print( d.find( b'<!-- ripwire for' ), d.find( b'<sigs' ) )
" "$WORK/dflt.xml" )
set -- $legAt
if [ "$1" -ge 0 ] && [ "$2" -ge 0 ] && [ "$2" -lt "$1" ]; then
    ok "(R9d) the DEFAULT serves its rows BEFORE its legend (sigs@$2 < legend@$1) -- answer-first is the default"
else
    no "(R9d) the default is not answer-first (legend@$1 sigs@$2)"
fi

# (R7) THE BUDGETED PATH -- the regime where ordering actually decides what survives, and the one every arm
# above missed. runForLens() routes a fitting budget to runForLensFitted(), a SECOND code path that renders
# its own whole document; the permutation lived only on the default path. A feature live on one path and
# dead on another, with every arm green, is exactly how the inverted capture predicate shipped earlier in
# this same lane -- so the budgeted path gets its own arms rather than an assumption.
#
# The budget is set far above the answer's est_tokens so that a difference can only be an ORDERING
# difference and never a cut. (R7nv) proves that is so on THIS tree instead of trusting the constant.
BIG=100000
"$BIN" . --for="$TASK_A" --token-budget="$BIG" $OPTIN >"$WORK/a_bud.xml" 2>/dev/null
if [ ! -s "$WORK/a_bud.xml" ]; then
    no "(R7) the budgeted answer is empty -- the budget arms cannot run"
elif [ "$( wc -c <"$WORK/a_bud.xml" )" != "$( wc -c <"$WORK/a_new.xml" )" ]; then
    # A budget that BOUND would legitimately change the answer, and R7 would then be grading a cut.
    no "(R7nv) --token-budget=$BIG BOUND on this tree ($( wc -c <"$WORK/a_bud.xml" | tr -d ' ' ) B vs $( wc -c <"$WORK/a_new.xml" | tr -d ' ' ) B) -- raise BIG; R7 must compare orders, not cuts"
else
    ok "(R7nv) the budget binds nothing: same byte count, so any difference below is ordering alone"
    if cmp -s "$WORK/a_bud.xml" "$WORK/a_new.xml"; then
        ok "(R7) a budget that binds nothing leaves the answer-first order intact"
    else
        no "(R7) --token-budget changed the ORDER -- the permutation does not run on the budgeted path"
    fi
    # (R7n) THE MUTATION CONTROL. R7 is an equality test, so it is evidence only if the two orderings are
    # DISTINGUISHABLE by it. The budgeted answer must NOT equal the legacy-order answer -- if it did, R7
    # would pass with the permutation switched off everywhere, and the measured defect was exactly this:
    # --token-budget was byte-identical to RIPWIRE_FOR_LEGACY_ORDER=1.
    if cmp -s "$WORK/a_bud.xml" "$WORK/a_old.xml"; then
        no "(R7n) the budgeted answer is byte-identical to the LEGACY order -- a budget silently opts out of item R"
    else
        ok "(R7n) the budgeted answer differs from the legacy order -- R7 can fail"
    fi
fi

# (R8) A BLOCK-LOCAL LEGEND TRAVELS WITH ITS BLOCK.
#
# Two kinds of comment ride a --for answer and they are not interchangeable. The DOCUMENT legend opens with
# the verb or the root ("<!-- ripwire for ...", "<!-- root ...") and documents the answer as a whole: item R
# moves that one to the tail on purpose. A BLOCK-LOCAL legend NAMES ITS OWN ELEMENT ("<!-- syms ..." before
# <syms>, "<!-- shortkey ..." before <shortkey>) and the house convention is that it sits in the comment
# IMMEDIATELY before that element's open tag, so the block can be switched off without moving a byte in
# front of it and so a reader meets the definition exactly where the block starts.
#
# Moving those to the tail broke readers that are RIGHT to depend on the adjacency. Measured: formaxtokens'
# judge strips one self-declaring trailing block before pricing and its pattern requires comment-then-block,
# so with the comment relocated 1,447 B stopped being stripped and est_tokens looked like it under-charged by
# exactly 579 tokens. That was not an est_tokens defect at all -- it was this adjacency.
"$BIN" . --for="legend posture" --detail=5 $OPTIN $WHOLE >"$WORK/rich_new.xml" 2>/dev/null
"$BIN" . --for="legend posture" --detail=5 $LEGACY >"$WORK/rich_old.xml" 2>/dev/null
python3 - "$WORK" <<'PY_EOF'
import os, re, sys
WORK = sys.argv[1]
bad  = 0

def read( n ):
    with open( os.path.join( WORK, n ), 'rb' ) as fh:
        return fh.read()

def selfNaming( raw ):
    """(comment span, named element) for every comment whose FIRST WORD is an element the document opens.

    The first word is the convention: a block-local legend names its own element, the document legend opens
    with the verb or the root instead."""
    out = []
    for m in re.finditer( rb'<!--\s*(?:ripwire for )?([A-Za-z_][\w-]*)', raw ):   # AF1-fix: both spellings
        word = m.group( 1 )
        end  = raw.find( b'-->', m.start() )
        if end < 0:
            continue
        if re.search( rb'<' + re.escape( word ) + rb'[ />]', raw ):
            out.append( ( m.start(), end + 3, word ) )
    return out

def adjacent( raw ):
    """Every self-naming comment is immediately followed by the element it names."""
    off = []
    for begin, end, word in selfNaming( raw ):
        if not raw[ end: ].startswith( b'<' + word ):
            off.append( word.decode() )
    return off

newd, oldd = read( 'rich_new.xml' ), read( 'rich_old.xml' )
pairs = selfNaming( oldd )
if not pairs:
    print( '  FAIL  (R8nv) the fixture carries NO self-naming comment -- R8 would pass vacuously' )
    bad += 1
else:
    print( '  PASS  (R8nv) the fixture carries %d self-naming comment(s): %s'
           % ( len( pairs ), ', '.join( sorted( { w.decode() for _, _, w in pairs } ) ) ) )

    # The legacy order is the reference: adjacency holds there by construction, so if it does NOT, the
    # predicate itself is wrong and every verdict below is worthless.
    offOld = adjacent( oldd )
    if offOld:
        print( '  FAIL  (R8ref) adjacency already fails in the LEGACY order for %s -- the predicate is wrong, not the permutation' % ', '.join( offOld ) )
        bad += 1
    else:
        print( '  PASS  (R8ref) adjacency holds in the legacy order -- the predicate is sound' )

        off = adjacent( newd )
        if off:
            print( '  FAIL  (R8) the permutation separated a block-local legend from its block: %s' % ', '.join( off ) )
            bad += 1
        else:
            print( '  PASS  (R8) every block-local legend still sits immediately before its own block' )

        # (R8n) MUTATION CONTROL. R8 is a "nothing is out of place" assertion, so it is evidence only if
        # putting something out of place makes it red. Relocate one self-naming comment to the tail.
        begin, end, word = pairs[ 0 ]
        moved = oldd[ :begin ] + oldd[ end: ]
        at    = moved.rfind( b'</ctx>' )
        moved = moved[ :at ] + oldd[ begin:end ] + moved[ at: ]
        if adjacent( moved ):
            print( '  PASS  (R8n) relocating the %s legend to the tail DOES make R8 red -- R8 can fail' % word.decode() )
        else:
            print( '  FAIL  (R8n) relocating a block-local legend did NOT make R8 red -- R8 asserts nothing' )
            bad += 1

sys.exit( 1 if bad else 0 )
PY_EOF
[ $? -eq 0 ] || fail=1

# (A1/A2/G) AF2's ORDER SPEC (results/AF2_FIRST12K_1118/READOUT.md §SPEC, built by lane AF1 2026-11-18). A: a comment that is
# a direct child of a top-level section joins the document legend; a zero-row <lego/>/<compose/> stub goes after </tail>.
# G: a RES section after </tail> moves ahead of <tail> only if the tail has more than 24 rows, ends past the page stop
# (12,000 B, src/foranswerfirst.h kAnswerPageBytesDefault), and tail row 24 still ends within it. The lit task is the
# fixture G must FIRE on (a quoted message gives a late <lit>); if this tree stops producing one, (G0) says so rather than
# passing on nothing.
# AF1-fix (2026-11-18): re-authored. A block legend spelled `ripwire for lit:` now travels with its <lit> (foranswerfirst.h
# commentFirstWord), so G sizes the old fixture's <lit> WITH its three legend comments (1,798 + 1,529 B) and the guard rightly
# declines it (tail row 24 would leave the stop); G is unchanged. This task's <lit> fits with its legend, so G fires again.
TASK_L="where is RIPWIRE_NO_SHORT_KEY read"
cap "$WORK/l_new.xml" "$TASK_L" $OPTIN $WHOLE
cap "$WORK/l_old.xml" "$TASK_L" $LEGACY
python3 - "$WORK" <<'PY_AF2'
import re, sys, os
W = sys.argv[1]; STOP = 12000; K = 24; bad = 0
RES = ("lit", "dotted_strings", "graph_verb", "callers", "selfhooks", "manifest_rows", "listed", "ep", "reexports", "exemplar_family")
def rd(n): return open(os.path.join(W, n), "rb").read().decode("latin-1")
def mask(d): return re.sub(r"<!--.*?-->|<!\[CDATA\[.*?\]\]>", lambda m: " " * len(m.group(0)), d, flags=re.S)
def tops(d):
    """top-level children of <ctx> as (name, begin, end) -- comments and CDATA masked first"""
    m = mask(d); r = re.search(r"<ctx\b[^>]*>", m); i = r.end(); end = m.rfind("</ctx>"); out = []; depth = 0; start = 0; name = ""
    for t in re.finditer(r"<(/?)([A-Za-z_][\w-]*)[^>]*?(/?)>", m[i:end]):
        a, b = i + t.start(), i + t.end()
        if t.group(1):
            depth -= 1
            if depth == 0: out.append((name, start, b))
        elif t.group(3):
            if depth == 0: out.append((t.group(2), a, b))
        else:
            if depth == 0: start, name = a, t.group(2)
            depth += 1
    return out
def say(ok, msg):
    global bad
    print("  %s  %s" % ("PASS" if ok else "FAIL", msg)); bad += 0 if ok else 1
fired = False
for lbl, nn, on in (("conceptual", "a_new.xml", "a_old.xml"), ("routed", "b_new.xml", "b_old.xml"), ("literal", "l_new.xml", "l_old.xml")):
    n, o = rd(nn), rd(on); tn, to = tops(n), tops(o); m = mask(n)
    names_n = [x[0] for x in tn]; names_o = [x[0] for x in to]
    # (A1) no section but <bodies> keeps a direct-child comment: A lifted them into the legend. <sigs> keeps no
    # demote:/decl-twin:/one-side: note either (AF4 T-C: the pointer's kind is its ptr=, so the notes define by attribute and may
    # leave; AF1 had kept them in place because they labelled the rows after them by position). Another <sigs> comment stays.
    def direct_comments(x, only=None):
        inner = n[n.find(">", x[1]) + 1:n.rfind("</", 0, x[2])] if not re.fullmatch(r"<[^>]*/>", n[x[1]:x[2]]) else ""
        inner = re.sub(r"<!\[CDATA\[.*?\]\]>", lambda q: " " * len(q.group(0)), inner, flags=re.S)
        c = 0; depth = 0
        for t in re.finditer(r"<!--.*?-->|<(/?)[A-Za-z_][\w-]*[^>]*?(/?)>", inner, re.S):
            if t.group(0).startswith("<!--"): c += depth == 0 and (only is None or re.match(only, t.group(0)) is not None)
            elif t.group(1): depth -= 1
            elif not t.group(2): depth += 1
        return c
    left = [(x[0], direct_comments(x, r"<!-- (demote|decl-twin|one-side):" if x[0] == "sigs" else None)) for x in tn if x[0] != "bodies"]
    left = [(nm, c) for nm, c in left if c]
    say(not left, "(A1) %-10s no section but <bodies> keeps a direct-child comment (<sigs>: no pointer note)%s" % (lbl, (" (%s)" % left) if left else ""))
    if "tail" not in names_n: print("  INFO  (G) %-10s no <tail>" % lbl); continue
    ti = names_n.index("tail"); tb, te = tn[ti][1], tn[ti][2]
    stubs = [x for x in tn if x[0] in ("lego", "compose") and x[1] < tb and re.fullmatch(r"<[^>]*/>", n[x[1]:x[2]])]
    say(not stubs, "(A2) %-10s no zero-row lego/compose stub sits ahead of <tail>" % lbl)
    rows = [q.end() + tb for q in re.finditer(r"<t\b[^>]*/>", m[tb:te])]
    si = names_n.index("sigs") if "sigs" in names_n else -1   # G places between <sigs> and <tail>; item R's routed move goes ahead of <sigs>
    moved = [x[0] for x in tn[si + 1:ti] if x[0] in RES and x[0] in names_o and names_o.index(x[0]) > names_o.index("tail")]
    if moved:
        fired = fired or lbl == "literal"
        say(len(rows) > K and rows[K - 1] <= STOP and te > STOP,
            "(G1) %-10s moved %s ahead of <tail>: tail has %d rows, row %d ends at %s <= %d, </tail> at %d > %d"
            % (lbl, ",".join(moved), len(rows), K, rows[K - 1] if len(rows) >= K else "?", STOP, te, STOP))
    else:
        print("  INFO  (G) %-10s nothing promoted (tail rows %d, </tail> at %d)" % (lbl, len(rows), te))
    if te <= STOP: say(not moved, "(G2) %-10s </tail> ends inside the stop, so nothing moved" % lbl)
say(fired, "(G0) the literal fixture FIRES G (a late <lit> promoted) -- if not, the tree drifted and G is untested here")
sys.exit(1 if bad else 0)
PY_AF2
[ $? -eq 0 ] || fail=1

# (CL) AF4 T-B -- CALLERS FIRST UNDER A CALLERS CUE (the P1 verb-route spec, section 2 (local results, not shipped), results/AF4_TOPLOAD_1118/PREREG.md).
# A who-calls question's <callers by="subject"> block is the FIRST row block of the answer-first document; a change / blast-radius
# or transitive question keeps it where it was. ORDER-ONLY: the who-calls answer is still a permutation of its legacy order
# (equal length, identical unit multiset). (CL1) is RED on the parent binary (f6288ec32 emits the block after <sigs>).
TASK_C="Which functions call \`topLevelBlocks\` directly?"
TASK_X="What is the blast radius of changing \`topLevelBlocks\`?"
TASK_T="Which functions call \`topLevelBlocks\` transitively?"
# (CL5) the T5d misfire shape (hb-rake-01/02): a change cue on the LEAF the sentence spells, then a pronoun call cue. The block's
# of= is qualified (rw::answerfirst::topLevelBlocks), so a change cue read only on the whole of= misses it while "calls it" matches.
TASK_R="What breaks if I change \`topLevelBlocks\`? List every non-test source file that defines or calls it."   # hb-rake-02's wording
cap "$WORK/c_new.xml" "$TASK_C" $OPTIN $WHOLE
cap "$WORK/c_old.xml" "$TASK_C" $LEGACY
cap "$WORK/x_new.xml" "$TASK_X" $OPTIN $WHOLE
cap "$WORK/t_new.xml" "$TASK_T" $OPTIN $WHOLE
cap "$WORK/r_new.xml" "$TASK_R" $OPTIN $WHOLE
python3 - "$WORK" <<'PY_CL'
import re, sys, os
W = sys.argv[1]; bad = 0
def rd(n): return open(os.path.join(W, n), "rb").read().decode("latin-1")
def cdata(d): return re.sub(r"<!\[CDATA\[.*?\]\]>", lambda m: " " * len(m.group(0)), d, flags=re.S)
def mask(d): return re.sub(r"<!--.*?-->", lambda m: " " * len(m.group(0)), cdata(d), flags=re.S)
def tops(d):
    """top-level row blocks of <ctx> as (name, open tag) in order -- comments and CDATA masked first"""
    m = mask(d); r = re.search(r"<ctx\b[^>]*>", m); i = r.end(); end = m.rfind("</ctx>"); out = []; depth = 0; start = 0; name = ""
    for t in re.finditer(r"<(/?)([A-Za-z_][\w-]*)[^>]*?(/?)>", m[i:end]):
        a, b = i + t.start(), i + t.end()
        if t.group(1):
            depth -= 1
            if depth == 0: out.append((name, d[start:d.find(">", start) + 1]))
        elif t.group(3):
            if depth == 0: out.append((t.group(2), d[a:b]))
        else:
            if depth == 0: start, name = a, t.group(2)
            depth += 1
    return out
def units(d):
    """AF2's unit multiset: root open/close, each top-level block's open and close tag, its direct children, top-level comments"""
    m = cdata(d); r = re.search(r"<ctx\b[^>]*>", m); end = m.rfind("</ctx>"); out = [d[:r.end()], d[end:]]; depth = 0; kid = 0
    for t in re.finditer(r"<!--.*?-->|<(/?)([A-Za-z_][\w-]*)[^>]*?(/?)>", m[r.end():end], re.S):
        a, b = r.end() + t.start(), r.end() + t.end()
        if t.group(0).startswith("<!--"):
            if depth <= 1: out.append(d[a:b])
        elif t.group(1):
            depth -= 1
            if depth == 0: out.append(d[a:b])
            elif depth == 1: out.append(d[kid:b])
        elif t.group(3):
            if depth <= 1: out.append(d[a:b])
        else:
            if depth == 0: out.append(d[a:b])
            elif depth == 1: kid = a
            depth += 1
    return sorted(out)
def say(ok, msg):
    global bad
    print("  %s  %s" % ("PASS" if ok else "FAIL", msg)); bad += 0 if ok else 1
def leads(d):
    t = tops(d)
    return bool(t) and t[0][0] == "callers" and ' by="subject"' in t[0][1], [x[0] for x in t][:4]
c_new, c_old, x_new, t_new, r_new = rd("c_new.xml"), rd("c_old.xml"), rd("x_new.xml"), rd("t_new.xml"), rd("r_new.xml")
has = lambda d: any(n == "callers" and ' by="subject"' in o for n, o in tops(d))
say(has(c_new) and has(x_new) and has(t_new) and has(r_new), "(CL0) all four fixture answers carry <callers by=\"subject\"> -- if not, the tree drifted and CL is untested")
ok, order = leads(c_new)
say(ok, "(CL1) who-calls: <callers by=\"subject\"> is the FIRST row block (order %s)" % order)
ok, order = leads(x_new)
say(not ok, "(CL2) blast-radius / change cue: the block does NOT lead (order %s)" % order)
ok, order = leads(t_new)
say(not ok, "(CL3) transitive cue: the block does NOT lead (order %s)" % order)
ok, order = leads(r_new)
say(not ok, "(CL5) change cue on the leaf + pronoun call cue (\"what breaks if I change X ... calls it\"): the block does NOT lead (order %s)" % order)
say(len(c_new) == len(c_old) and units(c_new) == units(c_old),
    "(CL4) the who-calls answer is a permutation of its legacy order: %d B vs %d B, %d units identical" % (len(c_new), len(c_old), len(units(c_new))))
i = c_new.find('<callers by="subject"'); j = c_new.find("</callers>", i); k = c_new.rfind("<s ", i, j)
cut = c_new[:k] + c_new[c_new.find("/>", k) + 2:] if k > 0 else c_new
say(units(cut) != units(c_old), "(CL4n) dropping one <callers> row DOES break CL4 -- CL4 can fail")
sys.exit(1 if bad else 0)
PY_CL
[ $? -eq 0 ] || fail=1

# (SD) TL1 M2 -- SAME-DIRECTORY TAIL LEAD (foranswerfirst.h tailSameDirFirst; lane TL1 PREREG M2, F1's post-hoc P1t lead). Inside
# <tail>, rows 1..24 keep their place; rows past 24 are stably partitioned, rows whose p= directory is the directory of a <sigs> <d>
# row with r <= 5 first. ORDER-ONLY: the answer is a permutation of its RIPWIRE_NO_TAIL_SAMEDIR=1 twin and of --legend=first.
TASK_S="legend posture"
cap "$WORK/s_new.xml" "$TASK_S" $OPTIN $WHOLE
RIPWIRE_NO_TAIL_SAMEDIR=1 cap "$WORK/s_off.xml" "$TASK_S" $OPTIN $WHOLE
cap "$WORK/s_old.xml" "$TASK_S" $LEGACY
python3 - "$WORK" <<'PY_SD'
import re, sys, os
W = sys.argv[1]; bad = 0
def rd(n): return open(os.path.join(W, n), "rb").read().decode("latin-1")
def say(ok, msg):
    global bad
    print("  %s  %s" % ("PASS" if ok else "FAIL", msg)); bad += 0 if ok else 1
def attr(tag, k):
    m = re.search(r' %s="([^"]*)"' % k, tag); return m.group(1) if m else ""
def tail_rows(d):
    i = d.find("<tail"); i = d.find(">", i) + 1; j = d.find("</tail>", i)
    return [m.group(0) for m in re.finditer(r"<([A-Za-z_][\w-]*)\b[^>]*?/>|<([A-Za-z_][\w-]*)\b[^>]*>.*?</\2>", d[i:j], re.S)]
def dirof(p):
    p = re.sub(r":[0-9:-]+$", "", p); return p[:p.rfind("/")] if "/" in p else ""
def heads(d):
    i = d.find("<sigs"); s = d[i:d.find("</sigs>", i)]
    return {dirof(attr(t, "p")) for t in re.findall(r"<d [^>]*>", s) if attr(t, "r").isdigit() and int(attr(t, "r")) <= 5 and attr(t, "p")}
new, off, old = rd("s_new.xml"), rd("s_off.xml"), rd("s_old.xml")
rn, ro = tail_rows(new), tail_rows(off); H = heads(off)
near = lambda r: dirof(attr(r[:r.find(">") + 1], "p")) in H
want = ro[:24] + [r for r in ro[24:] if near(r)] + [r for r in ro[24:] if not near(r)]
fires = len(ro) > 24 and want != ro
say(fires, "(SD0) the fixture FIRES: %d tail rows, %d past row 24 sit in a top-5 sigs directory (%s), and the twin's order differs -- if not, SD is untested" % (len(ro), sum(near(r) for r in ro[24:]), ",".join(sorted(H))))
say(rn[:24] == ro[:24], "(SD1) tail rows 1-24 are the twin's rows 1-24, in place")
say(rn == want, "(SD1) rows past 24: same-directory rows first, each part in the twin's own order")
units = lambda d: sorted(re.findall(r"<[^>]*>|[^<]+", d))
say(len(new) == len(off) and units(new) == units(off) and len(new) == len(old) and sorted(new) == sorted(old),
    "(SD2) a permutation: %d B, the same units as the RIPWIRE_NO_TAIL_SAMEDIR=1 twin and the same bytes as --legend=first" % len(new))
cut = new.replace(rn[-1], "", 1) if rn else new
say(units(cut) != units(off), "(SD2n) dropping one tail row DOES break SD2 -- SD2 can fail")
sys.exit(1 if bad else 0)
PY_SD
[ $? -eq 0 ] || fail=1

if [ "$fail" -ne 0 ]; then echo "foranswerfirstcheck: FAILURES"; exit 1; fi
echo "foranswerfirstcheck: ALL PASS"
