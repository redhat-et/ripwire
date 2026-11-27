#!/usr/bin/env bash
# The PROSE-FREE legend posture (--legend=dict) is OPT-IN, and it is lossless.
#
# WHAT THIS GUARDS. docs/EVALS.md "PRE-REGISTRATION 2026-11-17 (amendment 4) -- ITEM D". The legend is a
# near-fixed per-answer cost (531..4,305 B, median 1,796, measured over 311 recorded answers), so its SHARE
# grows as the answer shrinks: 14.0 % of a --for bundle, 62.6 % of a --whereis answer. At a 2 KB budget it
# costs 36 points of symbol-grain completeness and ALL of the item grain's -- a 2 KB answer under the old
# default was almost entirely schema prose. The owner's choice of three options was option (a): drop the
# prose, leave every root attribute exactly where it is. It is OPT-IN rather than the default: the flip reds
# 89 of 849 gates, 80 of them asserting that every attribute an answer emits is defined in THAT ANSWER'S legend,
# which a prose-free answer cannot satisfy. (D0) below gates the opt-in-ness itself, so "the default is unchanged"
# is a check rather than a comment.
#
# THE BAR IS NOT THE BYTE SAVING. It is that the saving changes MARKUP ONLY. The prose goes; the rows, the
# data comments, the CDATA bodies and every pre-existing root attribute stay, in place and with their
# values. The posture adds three attributes (legend= dict= dictv=) and removes one comment. Anything else
# that moves is a defect, and D1 below admits no tolerance for it.
#
# WHY A POINTER AND NOT SILENCE. METHODOLOGY.md section 9 principle 3: a disclosed cut is still terminal, so
# long as the answer hands over the one deterministic call that fetches what it left out.
# dict="ripwire --legend-dict" is that call and dictv= lets the reader check it resolves to THIS binary's
# dictionary. (D5) asserts both halves, and would have caught the defect in
# trap-legend-clause-must-be-registered-not-written: an attribute emitted with no dictionary row ships
# undocumented, and under this default it ships undocumented AND unexplained.
#
# Arms:
#   (D0) the DEFAULT is UNCHANGED -- a flagless run must be byte-identical to --legend=compact
#   (A)  the posture applies when ASKED -- --legend=dict
#   (D1) LOSSLESS, per verb and per legend family: body byte-identical to --legend=compact's, root
#        attributes identical as (name,value) pairs once the three pointer attributes are set aside
#   (D3) both opt-outs still work: --legend=compact restores the prose, --legend=full restores more of it
#        (and, with RIPWIRE_BASE_BIN, is byte-identical to the pre-change binary's default)
#   (D5) every attribute the prose-free answer emits has a --legend-dict row, and the emitted dictv=
#        equals --legend-dict's own
#   (N)  negative control: a non-XML answer (--json) is byte-identical with and without the posture
#   (M)  non-vacuity: both D1 and D5 must FAIL by mutation before their real arms are believed
#   (Z)  determinism: two default runs are byte-identical
set -u
BIN="${RIPWIRE_BIN:-${1:-./build/ripwire}}"
if [ ! -x "$BIN" ]; then echo "no ripwire binary at $BIN -- build first (cmake --build build -j)"; exit 2; fi
command -v python3 >/dev/null 2>&1 || { echo "legenddefaultcheck: python3 required"; exit 2; }
fail=0
pass() { printf '  PASS  %s\n' "$1"; }
bad()  { printf '  FAIL  %s\n' "$1"; fail=1; }

WORK=$(mktemp -d); trap 'rm -rf "$WORK"' EXIT

DV=$("$BIN" --legend-dict 2>/dev/null | head -1 | grep -oE '[0-9a-f]{8,}' | head -1)
if [ -z "$DV" ]; then bad "(A0) --legend-dict prints no dictv= -- the pointer this default emits has no version to name"; echo "FAILURES"; exit 1; fi
pass "(A0) --legend-dict names a dictionary version ($DV)"

# ===================================================================================================
# (A) THE POSTURE IS THE DEFAULT. No flag is named on this run: that is the whole point of the band.
# ===================================================================================================
# (D0) THE OPT-IN IS GATED. Without this arm, a later change that flipped the default would pass every other arm
# here -- they would simply stop needing the flag. The 89-gate blast radius is the reason the flip is deferred, so
# "deferred" has to be an assertion.
"$BIN" . --callers=main >"$WORK/flagless.xml" 2>/dev/null
"$BIN" . --callers=main --legend=compact >"$WORK/asked_compact.xml" 2>/dev/null
if cmp -s "$WORK/flagless.xml" "$WORK/asked_compact.xml" && [ -s "$WORK/flagless.xml" ]; then
    pass "(D0) the DEFAULT is unchanged -- a flagless run is byte-identical to --legend=compact"
else
    bad "(D0) a flagless run differs from --legend=compact -- the posture became the default, which is NOT what this band ships"
fi
if grep -qF 'legend="dict"' "$WORK/flagless.xml"; then
    bad "(D0b) the flagless answer carries legend=\"dict\" -- the posture must be asked for"
else
    pass "(D0b) the flagless answer carries no pointer -- the posture is opt-in"
fi

def_out="$WORK/default.xml"
"$BIN" . --callers=main --legend=dict >"$def_out" 2>/dev/null
if [ ! -s "$def_out" ]; then
    bad "(A1) --callers --legend=dict wrote no stdout -- nothing to check"
    echo "FAILURES"; exit 1
fi
if grep -qF 'legend="dict"' "$def_out"; then
    pass "(A1) --legend=dict carries legend=\"dict\" on the root"
else
    bad "(A1) --legend=dict did not take the posture"
fi
if grep -qF '<!-- ripwire ' "$def_out"; then
    bad "(A2) --legend=dict still carries a '<!-- ripwire ' prose legend -- the prose was not dropped"
else
    pass "(A2) --legend=dict carries no prose legend comment"
fi
# The DATA comment is not prose and must survive. Dropping it would be a silent cut of the answer's own
# counts, which section 9 principle 4 puts on the honest side of the line. Asserted per verb in (D1)
# below, by comparing the NON-prose comments of the two postures exactly -- an earlier version of this arm
# grepped for `<!-- key=` here and failed on --callers, whose counts do not ride a comment of their own.

# ===================================================================================================
# (D1) LOSSLESS, and (D5) RESOLVABLE. Both need to read structure, so both run in one python pass.
# Reported PER LEGEND FAMILY, because --for/--grep/--slice carry their own native dialects and a pooled
# check would pass while one family was left behind. A family with no cells is reported as n=0, never as
# passing -- see the hazard registered with the band.
# ===================================================================================================
python3 - "$BIN" "$DV" <<'PY'
import re, subprocess, sys
BIN, DV = sys.argv[1], sys.argv[2]
ROOT = re.compile(r"<([A-Za-z_][A-Za-z0-9_-]*)\b[^>]*>")
ATTR = re.compile(r'([A-Za-z_][A-Za-z0-9_-]*)="([^"]*)"')
POINTER = {"legend", "dict", "dictv"}
# est_tokens is NOT a pointer attribute and is NOT exempt: it is the one root attribute that MUST move,
# because it prices the DELIVERED document and the posture deletes the prose legend from it. Exempting it
# outright would let a repricing bug through, so (D1) sets it aside from the equality and (D1t) below
# asserts its DIRECTION and its MAGNITUDE instead — a strictly stronger test than equality could be.
REPRICED = {"est_tokens"}
REPRICED = {"est_tokens"}   # amendment 4a: the one attribute that MUST change

def head_comments(doc, lo, hi):
    """Comments in the two head runs only -- before the root open, and right after it.

    Bounded exactly as src/legenddict.h headComments is: the scan stops at the first byte that is neither a
    comment nor whitespace. A document-wide `<!--` search is NOT equivalent and must never be used here --
    --expand and --for carry ripwire's own source in CDATA, and that source contains comment-shaped text
    (`<!--" + add + "-->` was collected by exactly such a sweep). Amendment 4a records the measurement.
    """
    out, i = [], lo
    while i < hi:
        if doc.startswith("<!--", i):
            j = doc.find("-->", i)
            if j < 0:
                break
            out.append(doc[i:j + 3])
            i = j + 3
        elif doc[i] in " \n\r\t":
            i += 1
        else:
            break
    return out

def run(*args):
    r = subprocess.run([BIN, "."] + list(args), capture_output=True, text=True)
    return r.stdout, r.returncode

def split(doc):
    """(root-open, body-with-comments-intact, comments) or None when it is not one XML document.

    The root is NOT at offset 0: compactlegend.h's families emit their legend and data comments BEFORE the
    root element, while --for/--expand put theirs inside it. An earlier version of this helper matched the
    root at the start of the document, so it read all eleven compactlegend.h verbs as "not XML" and skipped
    them -- the gate reported PASS on the two families it could see and measured nothing on the rest.
    Leading comments and whitespace are therefore stepped over before the root is matched.
    """
    i, n = 0, len(doc)
    while i < n:
        while i < n and doc[i] in " \n\r\t":
            i += 1
        if doc.startswith("<!--", i):
            j = doc.find("-->", i)
            if j < 0:
                return None
            i = j + 3
            continue
        if doc.startswith("<?", i):
            j = doc.find("?>", i)
            if j < 0:
                return None
            i = j + 2
            continue
        break
    m = ROOT.match(doc, i)
    if not m:
        return None
    close = "</%s>" % m.group(1)
    j = doc.rfind(close)
    end = j if j > m.end() else len(doc)
    # The head comment run AFTER the root open belongs to the head, not the body: compactlegend.h's families
    # put their legend before the root, --for and --expand put theirs just inside it. Leaving it in the body
    # would make a legitimate drop look like a body change on exactly those two families.
    inner = head_comments(doc, m.end(), end)
    bodyBegin = m.end() + sum(len(c) for c in inner)
    while bodyBegin < end and doc[bodyBegin] in " \n\r\t":
        bodyBegin += 1
    return m.group(0), doc[bodyBegin:end], head_comments(doc, 0, m.start()) + inner

def pairs(text):
    return sorted(ATTR.findall(text or ""))

def family(rootopen):
    t = ROOT.match(rootopen)
    tag = t.group(1) if t else "?"
    sc = re.search(r'schema="([^"]*)"', rootopen)
    return "%s/%s" % (tag, sc.group(1) if sc else "-")

# One verb per legend family the CLI can reach without a fixture of its own. --for, --grep and --slice are
# the native-dialect families the hazard names; the rest ride compactlegend.h.
VERBS = ["--callers=main", "--callees=main", "--impact=main", "--uses=main", "--path=main,main",
         "--around=main", "--expand=main", "--hotspots", "--clones", "--lint", "--dead-code",
         "--for=legend posture", "--grep=legend", "--slice=main"]

fams, nbad, nskip = {}, 0, 0
for v in VERBS:
    a, rca = run(v, "--legend=dict")      # the posture, ASKED for
    b, rcb = run(v, "--legend=compact")   # the opt-out that restores the prose
    pa, pb = split(a), split(b)
    if not pa or not pb:
        # Not one XML document (a refusal, an empty answer, a non-XML verb). Acceptable ONLY if the two
        # postures agree exactly; otherwise the posture changed an answer it does not claim to handle.
        if a == b and rca == rcb:
            nskip += 1
            print("  PASS  (D1-skip) %-22s no XML legend here, and both postures agree byte-for-byte" % v)
        else:
            nbad += 1
            print("  FAIL  (D1-skip) %-22s not an XML answer, but the postures DISAGREE (%d B vs %d B, rc %d vs %d)"
                  % (v, len(a), len(b), rca, rcb))
        continue
    ra, ba, ca = pa
    rb, bb, cb = pb
    fam = family(ra)
    f = fams.setdefault(fam, {"n": 0, "bad": 0, "reduced": 0, "unreduced": 0})
    f["n"] += 1
    # UNREDUCED, AND HONEST ABOUT IT. The band's registered negative control: a family whose legend this
    # dictionary cannot reproduce (--expand, --around) or that never reaches the capture layer at all
    # (--for, excluded by nativeCompactLegendVerb by design) is served UNCHANGED, with its prose, exactly as
    # 0.6.x served it. That is a missed saving, never a wrong answer, so it PASSES -- but it is counted
    # apart and printed as coverage, because a gate that let it read as "reduced" would report the pooled
    # saving of a posture that had not been applied. The hazard was registered with the band for this reason.
    if not (set(k for k, _ in pairs(ra)) & POINTER):
        if a == b and rca == rcb:
            f["unreduced"] += 1
            print("  PASS  (D1-unreduced) %-18s served UNCHANGED and byte-identical to the opt-out -- no saving, no loss" % v)
        else:
            f["bad"] += 1; nbad += 1
            print("  FAIL  (D1-unreduced) %-18s not reduced, but the answer CHANGED (%d B vs %d B)" % (v, len(a), len(b)))
        continue
    why = []
    # 1. THE BODY IS BYTE-IDENTICAL. Comments are left in on purpose: a data comment that moved or vanished
    #    is exactly the defect this arm exists to catch, so it may not be normalised away first.
    if ba != bb:
        why.append("body differs (%d B vs %d B)" % (len(ba), len(bb)))
    # 2. ROOT ATTRIBUTES, NAME AND VALUE. Comparing name SETS would pass when shown="2" became shown="1".
    want = [p for p in pairs(ra) if p[0] not in POINTER and p[0] not in REPRICED]
    have = [p for p in pairs(rb) if p[0] not in REPRICED]
    if want != have:
        lost = [p for p in have if p not in want]
        added = [p for p in want if p not in have]
        why.append("root attributes moved (lost %s, changed %s)" % (lost[:3], added[:3]))
    # (D1t) THE REPRICED ATTRIBUTE, by direction and magnitude. est_tokens is the one root attribute that
    #       MUST move: it prices the DELIVERED document, and this posture deletes the prose legend from it.
    #       Exempting it outright would let a repricing bug through, so it is set aside from the equality
    #       above and checked here instead — strictly stronger than equality could be.
    #
    #       ORIENTATION, because I got this backwards the first time and it is the second inverted
    #       est_tokens direction test in this project: `ra`/`a` is the PROSE-FREE answer (it is the one
    #       carrying the POINTER attributes, which is exactly how the D1-unreduced arm above detects it),
    #       and `rb`/`b` is the --legend=compact opt-out. So the prose-free side must be the SMALLER one.
    ea = dict( pairs( ra ) ).get( "est_tokens" )   # prose-free
    eb = dict( pairs( rb ) ).get( "est_tokens" )   # compact opt-out
    if ( ea is None ) != ( eb is None ):
        why.append( "est_tokens present in one posture only (prose-free=%s compact=%s)" % ( ea, eb ) )
    elif ea is not None:
        free, prose = int( ea ), int( eb )
        saved = len( b ) - len( a )                # compact bytes minus prose-free bytes
        priced = prose - free
        if priced <= 0:
            why.append( "est_tokens did not fall: compact=%d prose-free=%d, yet the posture deleted the prose legend" % ( prose, free ) )
        elif saved <= 0:
            why.append( "est_tokens fell %d tokens but the prose-free answer is not smaller (%d B vs %d B)" % ( priced, len( a ), len( b ) ) )
        elif not ( 0.4 <= ( priced * 2.5 ) / saved <= 2.6 ):
            why.append( "est_tokens fell %d tokens for %d delivered bytes — outside the markup rate band" % ( priced, saved ) )
    # 3. THE POINTER IS COMPLETE. All three or none -- a dictv= without a dict= is a reference the reader
    #    cannot resolve, which is the silent-cut failure the band forbids.
    got = {k for k, _ in pairs(ra)} & POINTER
    if got != POINTER:
        why.append("pointer incomplete: %s" % sorted(got))
    elif dict(pairs(ra))["dictv"] != DV:
        why.append("dictv=%s is not this binary's %s" % (dict(pairs(ra))["dictv"], DV))
    # 4. NO PROSE in the default, and the prose really WAS there in the opt-out -- otherwise this verb
    #    proves nothing about dropping it.
    if any(c.startswith("<!-- ripwire ") for c in ca):
        why.append("prose legend still present under the default")
    if not any(c.startswith("<!-- ripwire ") for c in cb):
        why.append("--legend=compact carries no prose legend, so this verb cannot show it was dropped")
    # 5. THE DATA COMMENTS SURVIVE, EXACTLY. Counts are data, not prose: whatever non-prose comments the
    #    opt-out carries, the default must carry the same ones, byte for byte and in the same order.
    #
    #    CLASSIFIED BY SURVIVAL, NOT BY PREFIX (lane legend-session-default, 2026-11-18). The posture only ever
    #    REMOVES dictionary text from a head comment; it never writes a comment of its own. So a comment of the
    #    prose-free answer is DATA exactly when it came through untouched, and legend RESIDUE when it is a
    #    reduction of one. The old rule read `<!-- ripwire ` and nothing else, which was right only while the
    #    posture dropped the whole dictionary: once it drops one TIER, the definitions outside that tier stay in
    #    a head comment that begins with the first survivor instead, and all eight reduced verbs reported
    #    "data comments changed (1 vs 0)" -- a new data comment the posture had not written. src/legenddict.h
    #    records the same hazard for the binary's own classifier: at least seven head comments are legend content
    #    that does not open `<!-- ripwire `, so a prefix rule cannot tell them apart. The protection this arm
    #    exists for is unchanged and is asserted both ways below: every data comment of the opt-out survives
    #    verbatim and in order, and the prose-free answer adds nothing that was not already there.
    db_ = [c for c in cb if not c.startswith("<!-- ripwire ")]
    da  = [c for c in ca if c in db_]
    if da != db_:
        why.append("data comments changed (%d of %d survived verbatim and in order)" % (len(da), len(db_)))
    # A residue comment is a REDUCTION of one the opt-out carries: sentences were taken OUT of the middle, so it
    # is not a substring of any one of them, but every sentence it still carries must be in that answer. A
    # sentence that is not is text the posture WROTE, which it is not allowed to do.
    opt_out_text = " ".join(cb)
    strayed = []
    for c in ca:
        if c in db_:
            continue
        for seg in c[4:-3].split(". "):
            seg = seg.strip()
            if len(seg) > 24 and seg not in opt_out_text:
                strayed.append(seg)
    if strayed:
        why.append("the posture wrote %d comment sentence(s) of its own (first: %s)" % (len(strayed), strayed[0][:70]))
    if why:
        f["bad"] += 1; nbad += 1
        print("  FAIL  (D1) %-22s %s" % (v, "; ".join(why)))
    else:
        f["reduced"] += 1
        print("  PASS  (D1) %-22s lossless: body byte-identical, %d root attributes kept with their values, %d B saved"
              % (v, len(want), len(b) - len(a)))

print("  INFO  (D1) coverage per legend family -- reduced vs served-whole:")
red = sum(f["reduced"] for f in fams.values())
unr = sum(f["unreduced"] for f in fams.values())
for fam in sorted(fams):
    f = fams[fam]
    print("           %-34s n=%d reduced=%d unreduced=%d bad=%d" % (fam, f["n"], f["reduced"], f["unreduced"], f["bad"]))
print("  INFO  (D1) COVERAGE: %d of %d families reduced, %d served whole" % (red, red + unr, unr))
if red == 0:
    print("  FAIL  (D1-vacuous) no family reduced -- the posture was never applied, so nothing here is evidence")
    nbad += 1
if nskip == len(VERBS):
    print("  FAIL  (D1-vacuous) every verb skipped -- this gate measured nothing")
    nbad += 1

# (D5) EVERY ATTRIBUTE EMITTED HAS A DICTIONARY ROW. Under this default the dictionary is the ONLY place
# the reader can learn an attribute, so an undocumented one is not merely undocumented -- it is lost.
roster = subprocess.run([BIN, "--legend-dict=roster"], capture_output=True, text=True).stdout
full   = subprocess.run([BIN, "--legend-dict"], capture_output=True, text=True).stdout
if not (roster.strip() or full.strip()):
    print("  FAIL  (D5) --legend-dict printed nothing -- the pointer this default emits resolves to no dictionary")
    nbad += 1
known = set(re.findall(r'\b([a-z_][a-z0-9_]*)=', roster + " " + full))
a, _ = run("--callers=main")
emitted = {k for k, _ in pairs(a)} - POINTER
missing = sorted(k for k in emitted if k not in known)
if missing:
    print("  FAIL  (D5) attributes with no --legend-dict row: %s" % missing)
    nbad += 1
else:
    print("  PASS  (D5) all %d emitted attributes have a --legend-dict row, and dictv= matches (%s)" % (len(emitted), DV))

# (M) NON-VACUITY, by mutation. Both checks above must be able to go red, or their PASS means nothing.
base = split(a)
if base is None:
    print("  FAIL  (M1) the mutation control's own answer is not one XML document -- D1 cannot be shown to fire")
    nbad += 1
elif "<s " not in base[1]:
    print("  FAIL  (M1) no <s row in the control answer's BODY to plant into -- D1's mutation control did not run")
    nbad += 1
else:
    # PLANT INSIDE THE BODY, not inside the document. An earlier version of this control replaced the first
    # `<s ` in the whole answer, which landed in the legend PROSE -- the prose spells `<s t= n= sc= k=` --
    # so the body it then compared was unchanged and the control reported that D1 could not fire. What the
    # control has to show is that the body D1 compares really holds the rows, so a one-attribute change in a
    # row is visible to it.
    b0 = base[1]
    b1 = b0.replace("<s ", '<s zzqq9="1" ', 1)
    if b1 != b0 and len(b0) > 0:
        print("  PASS  (M1) D1 can fire -- the compared body holds the rows (%d B), and a planted row attribute changes it" % len(b0))
    else:
        print("  FAIL  (M1) a planted row attribute did not change the compared body -- D1 cannot fire")
        nbad += 1
if "zzqq9" in known:
    print("  FAIL  (M2) a nonsense attribute is 'known' to the dictionary -- D5 cannot fire"); nbad += 1
else:
    print("  PASS  (M2) D5 can fire -- a nonsense attribute is not in the dictionary")

sys.exit(1 if nbad else 0)
PY
if [ $? -ne 0 ]; then fail=1; fi

# ===================================================================================================
# (D3) THE OPT-OUTS. A default may only change if the old behaviour is still reachable BY NAME.
# ===================================================================================================
"$BIN" . --callers=main --legend=compact >"$WORK/compact.xml" 2>/dev/null
"$BIN" . --callers=main --legend=full    >"$WORK/full.xml"    2>/dev/null
cb=$(wc -c <"$WORK/compact.xml" | tr -d ' '); fb=$(wc -c <"$WORK/full.xml" | tr -d ' '); db=$(wc -c <"$def_out" | tr -d ' ')
if grep -qF '<!-- ripwire ' "$WORK/compact.xml"; then
    pass "(D3a) --legend=compact restores the prose legend (${cb} B vs ${db} B at the default)"
else
    bad "(D3a) --legend=compact no longer carries the prose legend -- the opt-out is gone"
fi
if [ "$fb" -ge "$cb" ]; then
    pass "(D3b) --legend=full is at least as long as compact (${fb} B >= ${cb} B)"
else
    bad "(D3b) --legend=full (${fb} B) is SHORTER than --legend=compact (${cb} B)"
fi
if [ "$db" -lt "$cb" ]; then
    pass "(D3c) --legend=dict is shorter than --legend=compact (${db} B < ${cb} B)"
else
    bad "(D3c) --legend=dict (${db} B) is not shorter than --legend=compact (${cb} B)"
fi
# Byte-identity against the PRE-CHANGE binary is the only arm that can prove --legend=compact reproduces
# TODAY, rather than merely still carrying prose. It needs that binary, so it SKIPs loudly without one.
if [ -n "${RIPWIRE_BASE_BIN:-}" ] && [ -x "${RIPWIRE_BASE_BIN}" ]; then
    "$RIPWIRE_BASE_BIN" . --callers=main >"$WORK/base.xml" 2>/dev/null
    if cmp -s "$WORK/base.xml" "$WORK/compact.xml"; then
        pass "(D3d) --legend=compact is byte-identical to the pre-change binary's DEFAULT answer"
    else
        bad "(D3d) --legend=compact differs from the pre-change binary's default -- the opt-out does not restore today"
    fi
else
    printf '  SKIP  (D3d) byte-identity of --legend=compact vs the pre-change default (set RIPWIRE_BASE_BIN=<path>)\n'
fi

# ===================================================================================================
# (N) NEGATIVE CONTROL. --json is not XML and has no legend to drop. Two halves: a plain --json answer is
# untouched and carries no pointer, and ASKING for the posture on it REFUSES -- naming the value as typed.
# ===================================================================================================
"$BIN" . --callers=main --json >"$WORK/a.json" 2>/dev/null
if [ -s "$WORK/a.json" ] && ! grep -qF 'legend="dict"' "$WORK/a.json"; then
    pass "(N1) a plain --json answer carries no pointer -- the posture cannot reach it"
else
    bad "(N1) a --json answer was empty, or carried the pointer"
fi
"$BIN" . --callers=main --json --legend=dict >"$WORK/b.json" 2>"$WORK/b.jerr"; rc=$?
if [ "$rc" -ne 0 ] && [ ! -s "$WORK/b.json" ] && grep -qF -- "--legend=dict" "$WORK/b.jerr"; then
    pass "(N2) --json --legend=dict REFUSES (rc=$rc), writes no stdout, and names the value AS TYPED"
else
    bad "(N2) --json --legend=dict must refuse naming --legend=dict -- rc=$rc, $(wc -c <"$WORK/b.json" | tr -d " ")B stdout, stderr: $(head -c 120 "$WORK/b.jerr")"
fi

# ===================================================================================================
# (Z) DETERMINISM. The posture depends on argv alone -- never on whether an earlier run happened.
# ===================================================================================================
"$BIN" . --callers=main --legend=dict >"$WORK/z1.xml" 2>/dev/null
"$BIN" . --callers=main --legend=dict >"$WORK/z2.xml" 2>/dev/null
if cmp -s "$WORK/z1.xml" "$WORK/z2.xml"; then
    pass "(Z1) two --legend=dict runs are byte-identical"
else
    bad "(Z1) two --legend=dict runs differ -- the posture is not a function of argv alone"
fi

# ===================================================================================================
# (D6) THE POINTER NAMES A READ THAT RESOLVES WHAT IT DROPPED -- AND THE CHEAPEST ONE.
#      BAND S (session default), arms S1 and S3. docs/EVALS.md.
#
# WHY THIS ARM EXISTS, measured. (D5) above asks only that every emitted attribute have SOME row in the
# dictionary, and the whole dictionary is 131,822 B. Under that contract this posture served a reader as
# if it held all 1,157 lines (applyDictPosture called LegendSession::serveAll), so it dropped EVERY
# definition and pointed at the only read that could resolve them. Measured on cpython
# --impact=PyObject_Str, warm: --legend=dict read 7,219 B, which is 577 B BELOW the 7,796 B the same cell
# serves to a caller that actually holds core+impact (--legend-have=0a04c49c2eaff940). A posture that is
# cheaper than the honest one is not a win -- it is 577 B borrowed from the reader at 131,822/3,812 = 34x
# interest. The tier the answer's own schema names resolves the same definitions for 3,812 B.
#
# So the bar is NOT the byte saving, and it is not "a row exists somewhere":
#   (D6a) dict= names ONE TIER, not the whole dictionary -- `ripwire --legend-dict=KEY`, and that read works
#   (D6b) that read is CHEAPER than the whole dictionary, which is the only thing that makes it a remedy
#   (D6c) NO UNDER-SERVING: the posture is never shorter than the same cell served to a caller that really
#         holds the tier dict= names. This is the arm the defect fails.
#   (D6d) the tier is the ANSWER'S OWN -- an --impact answer may not point at some other verb's pack
#   (M3)  non-vacuity: the arm must REJECT the defect's own pointer value, or its PASS means nothing
# ===================================================================================================
"$BIN" --legend-dict >"$WORK/full.txt" 2>/dev/null
fullb=$(wc -c <"$WORK/full.txt" | tr -d ' ')
d6=0
for probe in "--callers=main" "--impact=main" "--uses=main"; do
    pout="$WORK/d6.xml"
    "$BIN" . "$probe" --legend=dict >"$pout" 2>/dev/null
    if [ ! -s "$pout" ] || ! grep -qF 'legend="dict"' "$pout"; then
        printf '  INFO  (D6) %-18s not reduced by this posture -- no pointer to grade\n' "$probe"
        continue
    fi
    d6=$(( d6 + 1 ))
    ptr=$(grep -o 'dict="[^"]*"' "$pout" | head -1 | sed 's/^dict="//; s/"$//')
    # The answer's own schema key, from schema="ripwire.KEY/v1" on the root.
    key=$(grep -o 'schema="ripwire\.[^"/]*' "$pout" | head -1 | sed 's/^schema="ripwire\.//')
    tier=$(printf '%s' "$ptr" | sed -n 's/^ripwire --legend-dict=\([a-z][a-z-]*\)$/\1/p')
    if [ -z "$tier" ]; then
        bad "(D6a) $probe: dict=\"$ptr\" names no tier -- it points at the whole dictionary (${fullb} B), the one read this posture exists to avoid"
        continue
    fi
    "$BIN" --legend-dict="$tier" >"$WORK/tier.txt" 2>/dev/null; trc=$?
    tierb=$(wc -c <"$WORK/tier.txt" | tr -d ' ')
    if [ "$trc" -ne 0 ] || [ ! -s "$WORK/tier.txt" ] || ! head -1 "$WORK/tier.txt" | grep -q '^ripwire legend dictionary'; then
        bad "(D6a) $probe: dict=\"$ptr\" does not resolve -- \`--legend-dict=$tier\` exited $trc with ${tierb} B"
        continue
    fi
    pass "(D6a) $probe: dict= names the tier '$tier', and that read resolves (${tierb} B)"
    if [ "$tierb" -lt "$fullb" ]; then
        pass "(D6b) $probe: the named read is cheaper than the whole dictionary (${tierb} B < ${fullb} B)"
    else
        bad "(D6b) $probe: the named read (${tierb} B) is no cheaper than the whole dictionary (${fullb} B) -- it is not a remedy"
    fi
    have=$(head -1 "$WORK/tier.txt" | sed -n 's/.* have=\([0-9a-f]*\) .*/\1/p')
    if [ -z "$have" ]; then
        bad "(D6c) $probe: tier '$tier' line 1 carries no have= -- a reader cannot assert this holding next call"
    else
        "$BIN" . "$probe" --legend=compact >"$WORK/prose.xml" 2>/dev/null
        if [ ! -s "$WORK/prose.xml" ]; then
            bad "(D6c) $probe: --legend=compact wrote no answer -- there is no inline legend to say what the posture dropped"
        else
            # EVERY DEFINITION THIS POSTURE DROPPED IS IN THE TIER ITS POINTER NAMES. This is arm S1 stated
            # literally, per DEFINITION, and it is deliberately not a byte compare of two answers: the ref posture
            # MOVES its survivors after the rows while this one leaves them in place, so the two can never be
            # byte-identical however honest both are, and a >= on raw bytes measures only the two pointer
            # encodings (74 B of root attributes here against a 93 B <about/> child there -- 19 B on every probe).
            #
            # So: walk the WHOLE dictionary. A line that the inline (--legend=compact) answer carries and this
            # posture does not is a line the posture DROPPED, and it must be a line of the named tier. The
            # non-vacuity count is printed, because a run that matched no dictionary line would report a clean
            # sweep having tested nothing -- a rate of 0 or 100 % with no exceptions is an instrument fault here.
            python3 -I - "$pout" "$WORK/prose.xml" "$WORK/tier.txt" "$WORK/full.txt" "$probe" "$tier" <<'D6PY'
import sys
rd = lambda p: open(p, encoding="utf-8", errors="surrogateescape").read()
dictdoc, prose, tier, full, probe, name = rd(sys.argv[1]), rd(sys.argv[2]), rd(sys.argv[3]), rd(sys.argv[4]), sys.argv[5], sys.argv[6]
# Line 1 of a tier is its header (have=/entries=/of=) and the last is its footer sentence: neither is a definition.
tierlines = set(l for l in tier.splitlines()[1:-1] if len(l) > 24)
lines     = [l for l in full.splitlines() if len(l) > 24]
carried   = [l for l in lines if l in prose]                      # this verb's inline legend really spells it
dropped   = [l for l in carried if l not in dictdoc]              # ... and the posture left it out
unresolved = [l for l in dropped if l not in tierlines]
if not carried:
    print('  FAIL  (D6c-vacuous) %s: no dictionary line was found in the inline legend -- the arm tested nothing '
          '(instrument fault until one cell is hand-checked)' % probe)
    sys.exit(1)
if unresolved:
    print('  FAIL  (D6c) %s: %d of %d dropped definitions are in NEITHER the tier \'%s\' nor the answer -- '
          'the cheapest read that resolves them is the whole dictionary. First: %s'
          % (probe, len(unresolved), len(dropped), name, unresolved[0][:90]))
    sys.exit(1)
print('  PASS  (D6c) %s: all %d dropped definitions are lines of the tier \'%s\' (of %d the inline legend carries; '
      '%d kept in the answer)' % (probe, len(dropped), name, len(carried), len(carried) - len(dropped)))
sys.exit(0)
D6PY
            [ $? -ne 0 ] && fail=1
        fi
    fi
    if [ "$tier" = "core" ] || [ "$tier" = "$key" ]; then
        pass "(D6d) $probe: the tier named ('$tier') is this answer's own (schema key '$key')"
    else
        bad "(D6d) $probe: the pointer names tier '$tier' but the answer's schema key is '$key' -- another verb's pack resolves the wrong definitions"
    fi
done
if [ "$d6" -eq 0 ]; then
    bad "(D6-vacuous) no probe was reduced by this posture -- D6 measured nothing, which is not a pass"
else
    pass "(D6) graded on $d6 probe(s)"
fi
# (M3) THE MUTATION CONTROL, run on every invocation. The arm has to REJECT the exact value the defect
# emitted; an arm that accepts both the defect and the fix has no evidence. This is the C1/C2 pair the
# band registered: C2 points at the whole dictionary while dropping only a tier, C1 drops more than the
# tier names.
if printf '%s' "ripwire --legend-dict" | sed -n 's/^ripwire --legend-dict=\([a-z][a-z-]*\)$/\1/p' | grep -q .; then
    bad "(M3a) D6a accepts the defect's own pointer value 'ripwire --legend-dict' -- the arm cannot fire"
else
    pass "(M3a) D6a can fire -- it rejects 'ripwire --legend-dict' (the whole-dictionary pointer)"
fi
# (M3b) D6c IS AN EQUALITY, so its control has to produce an inequality from a real pair. The WRONG holding does
# it: --impact's answer served to a caller holding the CORE alone carries the impact pack's definitions inline,
# where the same answer served to a caller holding core+impact does not. If those two came back identical, D6c's
# comparison is blind to which definitions were dropped and its PASS above means nothing.
m3core=$("$BIN" --legend-dict=core 2>/dev/null | head -1 | sed -n 's/.* have=\([0-9a-f]*\) .*/\1/p')
m3pack=$("$BIN" --legend-dict=impact 2>/dev/null | head -1 | sed -n 's/.* have=\([0-9a-f]*\) .*/\1/p')
if [ -z "$m3core" ] || [ -z "$m3pack" ] || [ "$m3core" = "$m3pack" ]; then
    bad "(M3b) the core and impact tiers have no distinct have= values -- D6c's control cannot be built"
else
    "$BIN" . --impact=main --legend-have="$m3core" >"$WORK/m3a.xml" 2>/dev/null
    "$BIN" . --impact=main --legend-have="$m3pack" >"$WORK/m3b.xml" 2>/dev/null
    if [ -s "$WORK/m3a.xml" ] && [ -s "$WORK/m3b.xml" ] && ! cmp -s "$WORK/m3a.xml" "$WORK/m3b.xml"; then
        pass "(M3b) D6c can fire -- the same answer under two different holdings differs ($(wc -c <"$WORK/m3a.xml" | tr -d ' ') B core vs $(wc -c <"$WORK/m3b.xml" | tr -d ' ') B core+impact)"
    else
        bad "(M3b) the same answer under two DIFFERENT holdings is identical -- D6c's equality cannot distinguish what was dropped"
    fi
fi

# ===================================================================================================
# (D7) ONE POSTURE PER ANSWER. --legend=dict with --legend-have= must REFUSE.
#      BAND S arm S1. Measured before the fix on cpython --impact=PyObject_Str: 7,864 B carrying BOTH
#      `legend="dict" dict="ripwire --legend-dict"` on the root AND
#      `<about legend="ref" have="core+impact" .../>` as the last child -- two legend declarations that
#      contradict each other. A reader that believes the root's legend="dict" ("the definitions are in the
#      dictionary, not here") does not look in the trailing comment, which is where the unheld ones are.
#      src/main.cpp asserted in a comment that "the two never both fire"; they did.
# ===================================================================================================
corev=$("$BIN" --legend-dict=core 2>/dev/null | head -1 | sed -n 's/.* have=\([0-9a-f]*\) .*/\1/p')
if [ -z "$corev" ]; then
    bad "(D7) --legend-dict=core line 1 carries no have= -- D7 has no holding to pass"
else
    "$BIN" . --callers=main --legend=dict --legend-have="$corev" >"$WORK/d7.xml" 2>"$WORK/d7.err"; rc7=$?
    d7b=$(wc -c <"$WORK/d7.xml" | tr -d ' ')
    if [ "$rc7" -ne 0 ] && [ ! -s "$WORK/d7.xml" ] \
       && grep -qF -- "--legend=dict" "$WORK/d7.err" && grep -qF -- "--legend-have=" "$WORK/d7.err"; then
        pass "(D7) --legend=dict with --legend-have= REFUSES (rc=$rc7), writes no stdout, and names both flags"
    elif grep -qF 'legend="dict"' "$WORK/d7.xml" && grep -qF 'legend="ref"' "$WORK/d7.xml"; then
        bad "(D7) the answer carries TWO legend declarations at once -- legend=\"dict\" on the root and legend=\"ref\" on <about> (${d7b} B, rc=$rc7)"
    else
        bad "(D7) --legend=dict with --legend-have= must refuse naming both flags -- rc=$rc7, ${d7b} B stdout, stderr: $(head -c 160 "$WORK/d7.err")"
    fi
fi

if [ "$fail" -ne 0 ]; then echo "legenddefaultcheck: FAILURES"; exit 1; fi
echo "legenddefaultcheck: ALL PASS"
