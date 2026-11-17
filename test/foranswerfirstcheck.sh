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
#   (R9)  ITEM R IS OFF BY DEFAULT -- the legend precedes the rows unless --legend=last asked
set -u
ROOT="$( cd "$( dirname "$0" )/.." && pwd )"
BIN="${RIPWIRE_BIN:-${1:-$ROOT/build/ripwire}}"
[ "${BIN#/}" = "$BIN" ] && BIN="$ROOT/$BIN"
if [ ! -x "$BIN" ]; then echo "no ripwire binary at $BIN -- build first (cmake --build build -j)"; exit 2; fi
command -v python3 >/dev/null 2>&1 || { echo "foranswerfirstcheck: python3 required"; exit 2; }
fail=0
ok(){ printf '  PASS  %s\n' "$1"; }
no(){ printf '  FAIL  %s\n' "$1"; fail=1; }
WORK="$( mktemp -d )"; trap 'rm -rf "$WORK"' EXIT
echo "foranswerfirstcheck: BIN=$BIN"

# The opt-out knob is GATE ENVIRONMENT ONLY, never a binary knob -- the same posture test/legendtarget.sh's
# RIPWIRE_LEGEND_PINS=strict uses. Without a legacy baseline R1 has nothing to compare against, and a
# permutation gate with no baseline is a gate that cannot fail.
OPTIN="--legend=last"   # ITEM R IS OPT-IN: the DEFAULT is legend-first, --legend=last asks for answer-first

# Two tasks: one conceptual (the 84 % population) and one that resolves a routed section (the 13-cell shape
# the band's largest effect comes from). If the second never resolves on this tree, (R3) says so rather than
# passing vacuously.
TASK_A="legend posture"
TASK_B="path from runForLens to runForLensPosture"

cap(){  # cap FILE TASK [extra-args-to-the-binary]
    local f="$1" t="$2"; shift 2
    "$BIN" . --for="$t" "$@" >"$f" 2>/dev/null
}

cap "$WORK/a_new.xml" "$TASK_A" $OPTIN
cap "$WORK/a_old.xml" "$TASK_A"
cap "$WORK/b_new.xml" "$TASK_B" $OPTIN
cap "$WORK/b_old.xml" "$TASK_B"
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

def multiset(bs):
    return sorted(t for _, _, t in bs)

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
        print("  PASS  (R1) %-11s permutation: %d top-level blocks identical byte for byte, root and trailer unchanged"
              % (label, len(b_new)))
    else:
        lost = [t[:60] for t in multiset(b_old) if t not in multiset(b_new)]
        print("  FAIL  (R1) %-11s NOT a permutation -- %d blocks vs %d; first missing: %s"
              % (label, len(b_new), len(b_old), (lost[:1] or ["<root/trailer differs>"])[0]))
        bad += 1

    # (R4) A permutation changes no byte count.
    if len(newd) == len(oldd):
        print("  PASS  (R4) %-11s byte count unchanged (%d B)" % (label, len(newd)))
    else:
        print("  FAIL  (R4) %-11s byte count moved %d -> %d -- a permutation cannot" % (label, len(oldd), len(newd)))
        bad += 1

    # (R2) THE LEGEND IS LAST, and still present. G4 constrains COUNT, so the count must not move either.
    cn, co = comments(b_new), comments(b_old)
    if len(cn) != len(co):
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
        def blockLocal( idx ):
            m = re.match( r'<!--\s*([A-Za-z_][\w-]*)', b_new[ idx ][ 2 ] )
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
cap "$WORK/z1.xml" "$TASK_A" $OPTIN
cap "$WORK/z2.xml" "$TASK_A" $OPTIN
if cmp -s "$WORK/z1.xml" "$WORK/z2.xml"; then
    ok "(R5) two runs byte-identical"
else
    no "(R5) two runs differ -- the order is not a function of argv and the tree"
fi

# (R6) THE DEFAULT IS REPRODUCIBLE, so the baseline every arm above rests on is itself trustworthy.
cap "$WORK/r1.xml" "$TASK_A"
if cmp -s "$WORK/r1.xml" "$WORK/a_old.xml"; then
    ok "(R6) the default order is reproducible byte for byte"
else
    no "(R6) two default runs differ -- the gate's own baseline is unstable"
fi

# (R9) ITEM R IS OFF UNLESS ASKED FOR. This is the arm the owner's opt-in decision rests on, and no other arm
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
        ok "(R9) $subj: the DEFAULT serves its legend BEFORE the rows (legend@$1 < sigs@$2) -- item R is opt-in"
    else
        no "(R9) $subj: the default no longer puts the legend first (legend@$1 sigs@$2) -- item R leaked into the default"
    fi
done

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
"$BIN" . --for="legend posture" --detail=5 $OPTIN >"$WORK/rich_new.xml" 2>/dev/null
"$BIN" . --for="legend posture" --detail=5 >"$WORK/rich_old.xml" 2>/dev/null
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
    for m in re.finditer( rb'<!--\s*([A-Za-z_][\w-]*)', raw ):
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

if [ "$fail" -ne 0 ]; then echo "foranswerfirstcheck: FAILURES"; exit 1; fi
echo "foranswerfirstcheck: ALL PASS"
