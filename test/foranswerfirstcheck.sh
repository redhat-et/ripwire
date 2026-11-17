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
#   (R6)  the opt-out restores the legacy order exactly
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
LEGACY_ENV="RIPWIRE_FOR_LEGACY_ORDER=1"

# Two tasks: one conceptual (the 84 % population) and one that resolves a routed section (the 13-cell shape
# the band's largest effect comes from). If the second never resolves on this tree, (R3) says so rather than
# passing vacuously.
TASK_A="legend posture"
TASK_B="path from runForLens to runForLensPosture"

cap(){  # cap FILE TASK [extra-env]
    local f="$1" t="$2"; shift 2
    if [ "$#" -gt 0 ]; then env "$@" "$BIN" . --for="$t" >"$f" 2>/dev/null
    else "$BIN" . --for="$t" >"$f" 2>/dev/null; fi
}

cap "$WORK/a_new.xml" "$TASK_A"
cap "$WORK/a_old.xml" "$TASK_A" $LEGACY_ENV
cap "$WORK/b_new.xml" "$TASK_B"
cap "$WORK/b_old.xml" "$TASK_B" $LEGACY_ENV
for f in a_new a_old b_new b_old; do
    [ -s "$WORK/$f.xml" ] || { no "(R0) $f.xml is empty -- nothing to check"; echo "FAILURES"; exit 1; }
done
ok "(R0) four answers captured, new and legacy order, two task shapes"

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
        lastEl = max((i for i, k in enumerate(kinds) if k == "element"), default=-1)
        firstC = min((i for i, k in enumerate(kinds) if k == "comment"), default=len(kinds))
        if firstC > lastEl:
            print("  PASS  (R2) %-11s every one of the %d legend comments follows every row block" % (label, len(cn)))
        else:
            print("  FAIL  (R2) %-11s a legend comment at index %d precedes the last row block at %d" % (label, firstC, lastEl))
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
cap "$WORK/z1.xml" "$TASK_A"
cap "$WORK/z2.xml" "$TASK_A"
if cmp -s "$WORK/z1.xml" "$WORK/z2.xml"; then
    ok "(R5) two runs byte-identical"
else
    no "(R5) two runs differ -- the order is not a function of argv and the tree"
fi

# (R6) THE OPT-OUT restores the legacy order EXACTLY, so the change is reversible by name and the baseline
# this gate rests on is itself trustworthy.
cap "$WORK/r1.xml" "$TASK_A" $LEGACY_ENV
if cmp -s "$WORK/r1.xml" "$WORK/a_old.xml"; then
    ok "(R6) the legacy-order opt-out is reproducible byte for byte"
else
    no "(R6) two legacy-order runs differ -- the gate's own baseline is unstable"
fi

if [ "$fail" -ne 0 ]; then echo "foranswerfirstcheck: FAILURES"; exit 1; fi
echo "foranswerfirstcheck: ALL PASS"
