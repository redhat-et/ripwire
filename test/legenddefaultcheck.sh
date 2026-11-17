#!/usr/bin/env bash
# The PROSE-FREE legend posture is the DEFAULT (--legend=dict), and it is lossless.
#
# WHAT THIS GUARDS. docs/EVALS.md "PRE-REGISTRATION 2026-11-17 (amendment 4) -- ITEM D". The legend is a
# near-fixed per-answer cost (531..4,305 B, median 1,796, measured over 311 recorded answers), so its SHARE
# grows as the answer shrinks: 14.0 % of a --for bundle, 62.6 % of a --whereis answer. At a 2 KB budget it
# costs 36 points of symbol-grain completeness and ALL of the item grain's -- a 2 KB answer under the old
# default was almost entirely schema prose. The owner's choice of three options was option (a): drop the
# prose, leave every root attribute exactly where it is.
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
#   (A)  the posture IS the default -- a flagless XML run, no flag named
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
def_out="$WORK/default.xml"
"$BIN" . --callers=main >"$def_out" 2>/dev/null
if [ ! -s "$def_out" ]; then
    bad "(A1) a flagless --callers run wrote no stdout -- nothing to check"
    echo "FAILURES"; exit 1
fi
if grep -qF 'legend="dict"' "$def_out"; then
    pass "(A1) the DEFAULT answer carries legend=\"dict\" -- the posture needs no flag"
else
    bad "(A1) the default answer does not carry legend=\"dict\" -- the posture is not the default"
fi
if grep -qF '<!-- ripwire ' "$def_out"; then
    bad "(A2) the default answer still carries a '<!-- ripwire ' prose legend -- the prose was not dropped"
else
    pass "(A2) the default answer carries no prose legend comment"
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
    a, rca = run(v)                       # the DEFAULT -- no flag
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
    want = [p for p in pairs(ra) if p[0] not in POINTER]
    have = pairs(rb)
    if want != have:
        lost = [p for p in have if p not in want]
        added = [p for p in want if p not in have]
        why.append("root attributes moved (lost %s, changed %s)" % (lost[:3], added[:3]))
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
    da = [c for c in ca if not c.startswith("<!-- ripwire ")]
    db_ = [c for c in cb if not c.startswith("<!-- ripwire ")]
    if da != db_:
        why.append("data comments changed (%d vs %d)" % (len(da), len(db_)))
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
    pass "(D3c) the default is shorter than the posture it replaced (${db} B < ${cb} B)"
else
    bad "(D3c) the default (${db} B) did not get shorter than --legend=compact (${cb} B)"
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
# (N) NEGATIVE CONTROL. --json is not XML and has no legend to drop, so the posture must not touch it.
# ===================================================================================================
"$BIN" . --callers=main --json >"$WORK/a.json" 2>/dev/null
"$BIN" . --callers=main --json >"$WORK/b.json" 2>/dev/null
if cmp -s "$WORK/a.json" "$WORK/b.json" && [ -s "$WORK/a.json" ] && ! grep -qF 'legend="dict"' "$WORK/a.json"; then
    pass "(N1) a --json answer is untouched by the posture -- no pointer, no prose, nothing moved"
else
    bad "(N1) the posture reached a --json answer, or that answer was empty/unstable"
fi

# ===================================================================================================
# (Z) DETERMINISM. The posture depends on argv alone -- never on whether an earlier run happened.
# ===================================================================================================
"$BIN" . --callers=main >"$WORK/z1.xml" 2>/dev/null
"$BIN" . --callers=main >"$WORK/z2.xml" 2>/dev/null
if cmp -s "$WORK/z1.xml" "$WORK/z2.xml"; then
    pass "(Z1) two default runs are byte-identical"
else
    bad "(Z1) two default runs differ -- the posture is not a function of argv alone"
fi

if [ "$fail" -ne 0 ]; then echo "legenddefaultcheck: FAILURES"; exit 1; fi
echo "legenddefaultcheck: ALL PASS"
