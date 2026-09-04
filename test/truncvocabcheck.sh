#!/usr/bin/env bash
# truncvocabcheck.sh — the gate for §P8's "Vocabulary" bullet 1: ONE truncation vocabulary across the whole
# tool, so a caller that can read "were rows dropped?" out of one verb can read it out of every verb.
#
# The audit counted SIX spellings for the same fact: shown=+capped= (the target); +hits_capped= (the floor
# marker); shown_<thing>= with no capped= at all (--communities, --graph-query); BOTH conventions in one
# element (--seams); the six-attribute paging block (--lint, now shared via src/pageview.h); and
# payload="capped", a STRING ENUM on --for's <sigs> that only string-matching could read. --abi added a
# seventh hazard the audit did not name: capped= holding a dropped-row COUNT, so `capped="12"` and
# `capped="1"` meant unrelated things under one attribute name.
#
# The convention is stated ONCE, in src/pageview.h under "THE TRUNCATION VOCABULARY". This gate is its
# executable half; every emitter comment points at that block rather than restating it. If you are adding a
# verb that can truncate, you satisfy this gate by following rules 1-3 there — you do not need to edit it.
#
# Asserts:
#   (A) UNIVERSAL SWEEP over ~20 verbs' real output, parsed as XML (so CDATA bodies can never be mistaken
#       for markup): every element carrying shown= carries capped="0|1"; every shown_<noun>= carries
#       <noun>_capped="0|1"; EVERY capped-family attribute in the tool is the 0|1 boolean and never a count;
#       and payload= appears nowhere. This is the check that makes the vocabulary a property of the TOOL
#       rather than of the verbs someone remembered to list.
#   (B) TRUNCATED case, per verb: the total + shown= + capped="1" are all present, and shown= equals the
#       number of rows actually emitted — the disclosure has to be arithmetic, not decoration.
#   (C) UNTRUNCATED case, per verb: capped="0". The bit is present-and-zero, never absent: "no capped
#       attribute" must never be something a caller has to interpret. (The FLOOR markers of rule 4 —
#       hits_capped=/findings_capped= — are the documented exception: absent there means "not a floor", as
#       --lint's §P0.2 legend promises. They are still 0|1 when present, which (A) enforces.)
#   (D) the three retired spellings are GONE: payload="capped", shown_seam_pairs=, and capped-as-a-count.
#   (E) §B8.3 — THE NAMED ROSTER, which exists because (A) has a structural blind spot: its rules are all
#       "if shown= then …", so an element that emits NOTHING is invisible to it. <bodies> carried no
#       attributes at all for several rounds and (A) could not see it; four pack-task sections spelled
#       their KEPT count `count=` — a TOTAL spelling under rule 2 — and (A) could not see that either. The
#       five budgeted SECTION elements are therefore named here, and each must be seen at least once (an
#       element nobody captured is an element nobody checked).
#
# Usage:
#   test/truncvocabcheck.sh
#   RIPWIRE_BIN=asan/ripwire test/truncvocabcheck.sh
#
# Exits non-zero on any failure; prints PASS/FAIL per check and ALL PASS on success.

set -u
ROOT="$( cd "$( dirname "$0" )/.." && pwd )"
BIN="${1:-${RIPWIRE_BIN:-$ROOT/build/ripwire}}"
[ "${BIN#/}" = "$BIN" ] && BIN="$ROOT/$BIN"
TMP="$( mktemp -d )"; trap 'rm -rf "$TMP"' EXIT
fail=0
ok(){ printf '  PASS  %s\n' "$*"; }
no(){ printf '  FAIL  %s\n' "$*"; fail=1; }

[ -x "$BIN" ] || { echo "no ripwire binary at $BIN — build first (cmake --build build -j)"; exit 2; }
command -v python3 >/dev/null 2>&1 || { echo "truncvocabcheck: python3 required"; exit 2; }

echo "truncvocabcheck: BIN=$BIN"

# ---------------------------------------------------------------------------------------------------
# corpora. BIG = this repo's own src/ (every row cap engages: 207 communities, 1399 fns, a 100+ blast
# radius). TINY = a two-symbol tree small enough that NOTHING can be capped, which is the only way to
# test the untruncated half — a cap that is never exercised proves capped="0" is reachable, and a cap
# that is always exercised proves capped="1" is not a constant.
# ---------------------------------------------------------------------------------------------------
BIG="$ROOT/src"
TINY="$TMP/tiny"
mkdir -p "$TINY"
cat > "$TINY/a.c" <<'EOF'
int leafOne( int x ) { return x + 1; }
int rootOne( int x ) { return leafOne( x ) + 1; }
EOF

run(){ "$BIN" "$@" 2>/dev/null; }

# ---------------------------------------------------------------------------------------------------
# (A) the universal sweep. Capture a broad slice of the tool's XML surface, then hold EVERY element in
#     EVERY document to the vocabulary. Verbs are captured best-effort: one that exits non-zero or needs
#     git history this checkout does not have is skipped rather than failed, but the sweep still refuses
#     to pass on an empty harvest (see the >= 12 floor below) — a silently-empty sweep is not a green one.
# ---------------------------------------------------------------------------------------------------
cap(){ local name="$1"; shift; run "$@" > "$TMP/sweep_$name.xml"; [ -s "$TMP/sweep_$name.xml" ] || rm -f "$TMP/sweep_$name.xml"; }

cap communities   "$BIG" --communities
cap seams         "$ROOT" --seams
cap query         "$BIG" --graph-query='kind(all,fn)'
cap query_small   "$BIG" --graph-query='kind(all,fn)' --top-k=3
cap impact        "$BIG" --impact=escapeXml
cap extsurface    "$BIG" --external-surface
cap extsurface_n  "$BIG" --external-surface --pack-top-n=2
cap grep          "$BIG" --grep=capped
cap match         "$BIG" --match='(call_expression)'
cap lint          "$BIG" --lint
cap lintpage      "$BIG" --lint --limit=3
cap hotspots      "$ROOT" --hotspots
cap clones        "$BIG" --clones
cap cochange      "$ROOT" --cochange
cap owners        "$ROOT" --owners
cap tree          "$BIG" --tree
cap deps          "$BIG" --deps
cap callers       "$BIG" --callers=escapeXml
cap callees       "$BIG" --callees=writeCommunities
cap whereis       "$ROOT" --whereis=escapeXml
cap docdrift      "$ROOT" --doc-drift
cap forbundle     "$BIG" --for="rank symbols by pagerank and serialize the map"
cap forbudget     "$BIG" --for="rank symbols" --token-budget=800
cap packtask      "$BIG" --pack-task="rank symbols by pagerank"
cap skillscan     "$ROOT" --scan-skills="$ROOT/skills"
cap abi           "$ROOT" --stray-content --abi
cap map           "$BIG"
# §B8.3: the BUDGETED SECTION elements. <bodies> reaches the sweep only through a verb that emits bodies, and
# neither --expand nor --for --detail was captured — which is part of how it went several rounds carrying no
# attributes at all (see arm (E)).
cap expand        "$BIG" --expand=packBodies
cap fordetail     "$BIG" --for="emit full definition bodies" --detail=3
cap packtasktests "$ROOT" --pack-task="escapeXml"          # this shape reaches the <tests> section
# <notes> only exists where a .ripwire_notes does, so build one — in a THROWAWAY corpus, never the tree.
NOTECORP="$TMP/notecorp"; mkdir -p "$NOTECORP"
cat > "$NOTECORP/widget.c" <<'NOTE_EOF'
int widgetHelper( int x ) { return x + 1; }
int widgetMain( int x ) { return widgetHelper( x ) * 2; }
NOTE_EOF
"$BIN" "$NOTECORP" --note-add="widgetHelper: the off-by-one lives here" >/dev/null 2>&1
[ -s "$NOTECORP/.ripwire_notes" ] || { echo "truncvocabcheck: --note-add wrote no notes — the <notes> roster arm cannot run"; exit 2; }
cap packtasknotes "$NOTECORP" --pack-task="widgetHelper off by one"

python3 - "$TMP" <<'PY'
import glob, os, re, sys, xml.etree.ElementTree as ET

tmp = sys.argv[1]
docs = sorted(glob.glob(os.path.join(tmp, "sweep_*.xml")))
problems, scanned, elements = [], [], 0

for path in docs:
    name = os.path.basename(path)[len("sweep_"):-len(".xml")]
    raw  = open(path, encoding="utf-8", errors="replace").read()
    try:
        # parse as XML so attribute-shaped text inside a CDATA body (--for ships real source code) can
        # never be mistaken for markup — the whole point of doing this with a parser and not a grep.
        root = ET.fromstring(raw)
    except ET.ParseError as e:
        problems.append(f"{name}: output is not parseable XML ({e})")
        continue
    scanned.append(name)
    for el in root.iter():
        elements += 1
        a = el.attrib
        for key, val in a.items():
            if key == "payload":
                problems.append(f'{name}: <{el.tag}> carries payload="{val}" — the retired string enum (rule 5)')
            if key == "capped" or key.endswith("_capped"):
                if val not in ("0", "1"):
                    problems.append(f'{name}: <{el.tag} {key}="{val}"> is not the 0|1 boolean (rule 3: capped is a bit, never a count)')
        if "shown" in a and "capped" not in a:
            problems.append(f"{name}: <{el.tag}> has shown= but no capped= (rule 3: the bit always rides with shown=)")
        for key in a:
            if key.startswith("shown_"):
                noun = key[len("shown_"):]
                if f"{noun}_capped" not in a:
                    problems.append(f"{name}: <{el.tag}> has {key}= but no {noun}_capped= (rules 1+3)")

if len(scanned) < 12:
    problems.append(f"sweep harvested only {len(scanned)} documents — too few to be a sweep (verbs failed to run?)")

print(f"  ..    swept {elements} elements across {len(scanned)} documents: {' '.join(scanned)}")
for p in problems:
    print("  FAIL  " + p)
sys.exit(1 if problems else 0)
PY
[ $? = 0 ] && ok "(A) universal sweep: shown=/shown_<noun>= always carry their 0|1 capped bit; no payload= enum" \
           || no "(A) universal sweep found vocabulary deviations (listed above)"

# ---------------------------------------------------------------------------------------------------
# (B) the TRUNCATED half, per verb: total + shown= + capped="1", and shown= == the rows actually emitted.
# ---------------------------------------------------------------------------------------------------
# truncated FILE ROOTTAG TOTALATTR SHOWNATTR CAPPEDATTR ROWTAG LABEL
truncated(){
    local f="$1" roottag="$2" totalattr="$3" shownattr="$4" cappedattr="$5" rowtag="$6" label="$7"
    [ -s "$f" ] || { no "$label: produced no output"; return; }
    local tag total shown capped rows
    tag="$( grep -o "<$roottag [^>]*>" "$f" | head -1 )"
    total="$(  printf '%s' "$tag" | sed -n "s/.*[[:space:]]$totalattr=\"\([^\"]*\)\".*/\1/p" )"
    shown="$(  printf '%s' "$tag" | sed -n "s/.*[[:space:]]$shownattr=\"\([^\"]*\)\".*/\1/p" )"
    capped="$( printf '%s' "$tag" | sed -n "s/.*[[:space:]]$cappedattr=\"\([^\"]*\)\".*/\1/p" )"
    rows="$( grep -o "<$rowtag[ /]" "$f" | wc -l | tr -d ' ' )"
    if [ -z "$total" ] || [ -z "$shown" ] || [ -z "$capped" ]; then
        no "$label: truncated run is missing one of $totalattr=/$shownattr=/$cappedattr= ($tag)"
    elif [ "$capped" != "1" ]; then
        no "$label: truncated run says $cappedattr=\"$capped\" (want 1; $totalattr=$total $shownattr=$shown)"
    elif [ "$shown" != "$rows" ]; then
        no "$label: $shownattr=$shown but $rows <$rowtag> rows were emitted (the disclosure must be arithmetic)"
    elif [ "$shown" -ge "$total" ] 2>/dev/null; then
        no "$label: $cappedattr=\"1\" while $shownattr=$shown >= $totalattr=$total (a cap that dropped nothing)"
    else
        ok "$label: $totalattr=$total $shownattr=$shown $cappedattr=\"1\" over $rows rows"
    fi
}

truncated "$TMP/sweep_communities.xml" communities modules      shown_modules modules_capped community "(B) --communities modules"
truncated "$TMP/sweep_communities.xml" communities bridges      shown_bridges bridges_capped bridge    "(B) --communities bridges"
truncated "$TMP/sweep_query_small.xml" query       count        shown         capped         s         "(B) --graph-query"
truncated "$TMP/sweep_impact.xml"      impact      reaches      shown         capped         s         "(B) --impact"
truncated "$TMP/sweep_extsurface_n.xml" external-surface names  shown         capped         x         "(B) --external-surface"

# --seams over this repo is genuinely under its 20-pair cap, so its truncated case needs a corpus that
# exceeds it. Build one: 25 directory pairs, each with an untested cross-directory call.
SEAMSRC="$TMP/seamcorpus"
i=0
while [ $i -lt 25 ]; do
    mkdir -p "$SEAMSRC/m$i" "$SEAMSRC/n$i"
    printf 'int callee%d( int x ) { return x + 1; }\n' "$i" > "$SEAMSRC/n$i/b.c"
    printf 'int callee%d( int x );\nint caller%d( int x ) { return callee%d( x ); }\n' "$i" "$i" "$i" > "$SEAMSRC/m$i/a.c"
    i=$(( i + 1 ))
done
run "$SEAMSRC" --seams > "$TMP/seams_big.xml"
truncated "$TMP/seams_big.xml" seams seam_pairs shown capped seam "(B) --seams"

# ---------------------------------------------------------------------------------------------------
# §P9 N6: --deps' <godfiles> nested listing (own total=/shown=/capped=, not to be confused with the
# root <deps>'s own primary per-file listing — both use a bare <f p=.../> row shape, distinguished here
# by attribute: the primary listing's rows carry includes=, godfiles' rows carry afferent=). The generic
# truncated()/untruncated() helpers above blind-count every <f > in the document, which would double-count
# across the two listings, so this is a dedicated check rather than a call through them.
# ---------------------------------------------------------------------------------------------------
GFTAG="$( grep -o '<godfiles [^>]*>' "$TMP/sweep_deps.xml" 2>/dev/null | head -1 )"
GFTOTAL="$(  printf '%s' "$GFTAG" | sed -n 's/.*[[:space:]]total="\([^"]*\)".*/\1/p' )"
GFSHOWN="$(  printf '%s' "$GFTAG" | sed -n 's/.*[[:space:]]shown="\([^"]*\)".*/\1/p' )"
GFCAPPED="$( printf '%s' "$GFTAG" | sed -n 's/.*[[:space:]]capped="\([^"]*\)".*/\1/p' )"
GFROWS="$( grep -oE '<f p="[^"]*" afferent="[0-9]+"' "$TMP/sweep_deps.xml" 2>/dev/null | wc -l | tr -d ' ' )"
if [ -z "$GFTAG" ]; then
    no "(B) --deps godfiles: no <godfiles> element found in the sweep capture"
elif [ -z "$GFTOTAL" ] || [ -z "$GFSHOWN" ] || [ -z "$GFCAPPED" ]; then
    no "(B) --deps godfiles: missing total=/shown=/capped= ($GFTAG)"
elif [ "$GFSHOWN" != "$GFROWS" ]; then
    no "(B) --deps godfiles: shown=\"$GFSHOWN\" but $GFROWS <f afferent=> rows were emitted"
elif [ "$GFCAPPED" != "1" ]; then
    no "(B) --deps godfiles: this repo's src/ has >12 god-files, expected capped=\"1\", got \"$GFCAPPED\" ($GFTAG)"
elif [ "$GFSHOWN" -ge "$GFTOTAL" ] 2>/dev/null; then
    no "(B) --deps godfiles: capped=\"1\" while shown=$GFSHOWN >= total=$GFTOTAL (a cap that dropped nothing)"
else
    ok "(B) --deps godfiles: total=$GFTOTAL shown=$GFSHOWN capped=\"1\" over $GFROWS <f afferent=> rows"
fi

# untruncated case: a tiny corpus with a FEW #include edges (well under the 12-row cap) proves capped="0"
# is reachable, not hardwired to 1.
GFTINY="$TMP/gftiny"; mkdir -p "$GFTINY"
cat > "$GFTINY/shared.h" <<'EOF'
int shared_fn(void);
EOF
for i in 1 2 3; do
    printf '#include "shared.h"\nint c%s(void) { return shared_fn(); }\n' "$i" > "$GFTINY/c$i.c"
done
GFTOUT="$( run "$GFTINY" --deps --no-cache )"
GFTTAG="$( printf '%s' "$GFTOUT" | grep -o '<godfiles [^>]*>' | head -1 )"
GFTCAPPED="$( printf '%s' "$GFTTAG" | sed -n 's/.*[[:space:]]capped="\([^"]*\)".*/\1/p' )"
GFTSHOWN="$(  printf '%s' "$GFTTAG" | sed -n 's/.*[[:space:]]shown="\([^"]*\)".*/\1/p' )"
GFTROWS="$( printf '%s' "$GFTOUT" | grep -oE '<f p="[^"]*" afferent="[0-9]+"' | wc -l | tr -d ' ' )"
if [ -z "$GFTTAG" ]; then
    no "(C) --deps godfiles: under-cap corpus produced no <godfiles> element: $GFTOUT"
elif [ "$GFTCAPPED" != "0" ]; then
    no "(C) --deps godfiles: under-cap corpus expected capped=\"0\", got \"$GFTCAPPED\" ($GFTTAG)"
elif [ "$GFTSHOWN" != "$GFTROWS" ]; then
    no "(C) --deps godfiles: shown=\"$GFTSHOWN\" but $GFTROWS rows emitted"
else
    ok "(C) --deps godfiles: under-cap corpus -> capped=\"0\" with shown=$GFTSHOWN == $GFTROWS rows (bit reachable, not hardwired)"
fi

# ---------------------------------------------------------------------------------------------------
# (C) the UNTRUNCATED half: capped="0", present and zero. A verb whose bit is hardwired to 1 passes (B)
#     and is still broken; this is the half that catches it.
# ---------------------------------------------------------------------------------------------------
untruncated(){
    local f="$1" roottag="$2" shownattr="$3" cappedattr="$4" rowtag="$5" label="$6"
    [ -s "$f" ] || { no "$label: produced no output"; return; }
    local tag shown capped rows
    tag="$( grep -o "<$roottag [^>]*>" "$f" | head -1 )"
    shown="$(  printf '%s' "$tag" | sed -n "s/.*[[:space:]]$shownattr=\"\([^\"]*\)\".*/\1/p" )"
    capped="$( printf '%s' "$tag" | sed -n "s/.*[[:space:]]$cappedattr=\"\([^\"]*\)\".*/\1/p" )"
    rows="$( grep -o "<$rowtag[ /]" "$f" | wc -l | tr -d ' ' )"
    if [ -z "$capped" ]; then
        no "$label: untruncated run has NO $cappedattr= at all — absent must never mean \"complete\" ($tag)"
    elif [ "$capped" != "0" ]; then
        no "$label: untruncated run says $cappedattr=\"$capped\" (want 0 — a false truncation alarm)"
    elif [ "$shown" != "$rows" ]; then
        no "$label: $shownattr=$shown but $rows <$rowtag> rows were emitted"
    else
        ok "$label: $cappedattr=\"0\" with $shownattr=$shown == $rows rows (no false alarm, bit not missing)"
    fi
}

run "$TINY" --communities                    > "$TMP/tiny_communities.xml"
run "$TINY" --graph-query='kind(all,fn)'     > "$TMP/tiny_query.xml"
run "$TINY" --impact=leafOne                 > "$TMP/tiny_impact.xml"
run "$TINY" --external-surface               > "$TMP/tiny_ext.xml"
# The untruncated --seams case used to point at "$ROOT" on the assumption that this repo sits under the
# 20-pair cap. That is a property of the tree, not of the tool, and it stopped holding the moment the
# source layout grew another directory — the gate then reported a FALSE truncation alarm about itself.
# Build the small corpus explicitly, exactly as the truncated case above builds the big one: 3 pairs,
# same shape, far under the cap. Now both halves of the pair own their fixture.
SEAMSMALL="$TMP/seamsmall"
i=0
while [ $i -lt 3 ]; do
    mkdir -p "$SEAMSMALL/m$i" "$SEAMSMALL/n$i"
    printf 'int callee%d( int x ) { return x + 1; }\n' "$i" > "$SEAMSMALL/n$i/b.c"
    printf 'int callee%d( int x );\nint caller%d( int x ) { return callee%d( x ); }\n' "$i" "$i" "$i" > "$SEAMSMALL/m$i/a.c"
    i=$(( i + 1 ))
done
run "$SEAMSMALL" --seams                     > "$TMP/tiny_seams.xml"

untruncated "$TMP/tiny_communities.xml" communities      shown_modules modules_capped community "(C) --communities modules"
untruncated "$TMP/tiny_query.xml"       query            shown         capped         s         "(C) --graph-query"
untruncated "$TMP/tiny_impact.xml"      impact           shown         capped         s         "(C) --impact"
untruncated "$TMP/tiny_ext.xml"         external-surface shown         capped         x         "(C) --external-surface"
untruncated "$TMP/tiny_seams.xml"       seams            shown         capped         seam      "(C) --seams"

# --for's <sigs> is rule 5: a BYTE-budget trim — the marker is capped="1" WITH the shown=/total= row pair
# (capture-audit 2026-09-04, arm (F) below), and it is ABSENT when the payload was not trimmed. Both states
# must be reachable.
run "$TINY" --for="add one to a number" > "$TMP/tiny_for.xml"
grep -q '<sigs>' "$TMP/tiny_for.xml" \
    && ok "(C) --for <sigs> untrimmed: bare <sigs>, no marker (rule 5: absent = untrimmed)" \
    || no "(C) --for <sigs> on a two-symbol corpus is not the bare untrimmed <sigs>"
grep -qE '<sigs shown="[0-9]+" total="[0-9]+" capped="1">' "$TMP/sweep_forbudget.xml" \
    && ok "(C) --for <sigs> trimmed by --token-budget: <sigs shown=N total=M capped=\"1\"> (rule 5, amended: the pair rides on a byte trim too)" \
    || no "(C) --for --token-budget=800 did not mark its trimmed payload <sigs shown= total= capped=\"1\">: $( grep -oE '<sigs[^>]*>' "$TMP/sweep_forbudget.xml" | head -1 )"

# ---------------------------------------------------------------------------------------------------
# (D) the retired spellings, named so a revert cannot pass quietly. Each of these three greps is RED
#     against the pre-migration binary, which is the proof this gate measures the change and not the sky.
# ---------------------------------------------------------------------------------------------------
# Scanned as ATTRIBUTES, not as text: --grep/--match echo matched source lines verbatim, and this repo's
# own source documents both retired spellings by name (pageview.h's rule 5 names payload="capped"; the
# --seams emitter names shown_seam_pairs=). A grep for the literal therefore fires on the tool CORRECTLY
# reporting its own comments — the exact false positive an attribute-level check cannot have.
retired(){
    local attr="$1"
    python3 - "$TMP" "$attr" <<'PY'
import glob, os, sys, xml.etree.ElementTree as ET
tmp, attr = sys.argv[1], sys.argv[2]
hits = []
for path in sorted(glob.glob(os.path.join(tmp, "*.xml"))):
    try:
        root = ET.fromstring(open(path, encoding="utf-8", errors="replace").read())
    except ET.ParseError:
        continue
    for el in root.iter():
        if attr in el.attrib:
            hits.append(f"{os.path.basename(path)}:<{el.tag}>")
print(" ".join(sorted(set(hits))))
sys.exit(1 if hits else 0)
PY
}
if out="$( retired payload )"; then ok "(D) payload= appears as an attribute in no verb's output (string enum retired)"
                             else no "(D) payload= is still an attribute somewhere: $out"; fi
if out="$( retired shown_seam_pairs )"; then ok "(D) shown_seam_pairs= is gone (--seams speaks one convention)"
                                       else no "(D) shown_seam_pairs= still emitted: $out"; fi
if [ -s "$TMP/sweep_abi.xml" ]; then
    abitag="$( grep -o '<abi [^>]*>' "$TMP/sweep_abi.xml" | head -1 )"
    printf '%s' "$abitag" | grep -qE 'capped="[01]"' \
        && ok "(D) --abi capped= is the 0|1 bit (the dropped-row COUNT moved to dropped=)" \
        || no "(D) --abi capped= is not a 0|1 bit: $abitag"
    printf '%s' "$abitag" | grep -q 'dropped="' \
        && ok "(D) --abi dropped= carries the count capped= used to hold" \
        || no "(D) --abi has no dropped= (the count lost its home)"
else
    ok "(D) --abi produced no output in this checkout (skipped)"
fi

# ---------------------------------------------------------------------------------------------------
# (E) §B8.3 — THE SWEEP'S OWN BLIND SPOT. Arm (A) judges an element only once it emits shown=: its rules
#     are all of the form "if shown= then …". An element that emits NOTHING AT ALL is therefore invisible
#     to it, which is exactly how <bodies> reached this round carrying no attributes while the JSON twin
#     emitted bodies_total/bodies_kept for the same section, and how four pack-task sections spelled their
#     KEPT count `count=` — a TOTAL spelling under rule 2 — with no capped= bit.
#
#     A sweep cannot infer that roster; it has to be NAMED. These five are the tool's budgeted section
#     elements: each always prints a row set out of a larger candidate set, so each must always carry the
#     rule-1/2/3 triple wherever it appears. (<sigs> is deliberately NOT here — it is rule 5, a bare
#     capped="1" on a byte-trimmed payload with no row total. <calls> is not here either: rule 3 lets an
#     UNCUT listing omit shown= and capped= together, which it does.)
#
#     "Absent from the sweep" is not a pass: an element nobody captured is an element nobody checked, so
#     each name must be seen in at least one document.
# ---------------------------------------------------------------------------------------------------
python3 - "$TMP" <<'PY'
import glob, os, sys, xml.etree.ElementTree as ET

ROSTER = {"bodies": "b", "callers": "s", "far": "s", "notes": "target", "tests": "test"}
seen, problems = {k: 0 for k in ROSTER}, []

for path in sorted(glob.glob(os.path.join(sys.argv[1], "sweep_*.xml"))):
    name = os.path.basename(path)[len("sweep_"):-len(".xml")]
    try:
        root = ET.parse(path).getroot()
    except ET.ParseError:
        continue                                    # arm (A) already reported the parse failure
    # the ROOT is excluded on purpose: --callers/--notes are VERBS whose own root element happens to share a
    # section name, and they disclose through pageview.h's paging block instead (<callers of= defs= count=>).
    # The roster is about SECTIONS — children of a bundle — not about tag names.
    for el in root.iter():
        tag = el.tag if isinstance(el.tag, str) else None
        if tag not in ROSTER or el is root: continue
        seen[tag] += 1
        a = el.attrib
        missing = [k for k in ("shown", "total", "capped") if k not in a]
        if missing:
            problems.append(f'{name}: <{tag}> is missing {"/".join(missing)}= (rules 1+2+3; a budgeted '
                            f'section element must never disclose nothing)')
            continue
        if "count" in a:
            problems.append(f'{name}: <{tag}> carries count="{a["count"]}" beside shown= — rule 2 lists '
                            f'count= as a TOTAL spelling, so the two collide')
        rows = len(el.findall(ROSTER[tag]))
        if a["shown"] != str(rows):
            problems.append(f'{name}: <{tag} shown="{a["shown"]}"> but {rows} <{ROSTER[tag]}> rows emitted')
        try:
            if (a["capped"] == "1") != (int(a["shown"]) < int(a["total"])):
                problems.append(f'{name}: <{tag} shown={a["shown"]} total={a["total"]} '
                                f'capped="{a["capped"]}"> — the bit contradicts the arithmetic')
        except ValueError:
            problems.append(f'{name}: <{tag}> shown=/total= are not integers ({a["shown"]}/{a["total"]})')

for tag, n in seen.items():
    if n == 0:
        problems.append(f"<{tag}> never appeared in the sweep — add a verb that emits it, or this roster "
                        f"entry checks nothing")

print(f"  ..    roster occurrences: " + " ".join(f"{k}={v}" for k, v in sorted(seen.items())))
for p in problems: print("  FAIL  " + p)
sys.exit(1 if problems else 0)
PY
[ $? = 0 ] && ok "(E) every budgeted section element carries the shown=/total=/capped= triple, arithmetic, no count= collision" \
           || no "(E) a budgeted section element discloses nothing or contradicts itself (listed above)"

# ---------------------------------------------------------------------------------------------------
# (F) capture-audit 2026-09-04 (lens 4 MEDIUM, lens 1 F7, lens 2 L5): capped="1" NEVER appears without
#     shown= and a total on the SAME element. The audited binary's --for printed `<sigs capped="1">` — 29
#     rows, nothing saying how many were eligible — while every sibling listing in the same bundle
#     (<tail total= shown= capped=>, <hops shown= total=>, <calls total= shown=>, <bodies shown= total=>)
#     carried the pair, and with --adaptive the header said "kept 40 of 40" over those 29 rows. Rule 5's
#     "bare capped" exemption is retired: a byte-budget trim still knows how many rows it was handed and
#     how many it printed, and the pair is exactly what an agent needs to decide whether to widen.
#
#     PROPERTY, over every swept document (the same harvest arm (A) parses): an element carrying the bare
#     capped= bit must carry shown= and a total — total= itself, or one of rule 2's own-name spellings.
#     A `<noun>_capped=` marker with no `shown_<noun>=` is rule 4 (a FLOOR on the total) and is not a
#     bare capped=, so it is not in scope here.
# ---------------------------------------------------------------------------------------------------
python3 - "$TMP" <<'PYF'
import glob, os, sys, xml.etree.ElementTree as ET
# rule 2's own-name totals, plus the per-row spellings the sweep meets: a <seam> row's untested= (the edges it
# lists a window of), a <module> row's size=, --deps' files=, --lint's findings=, --cochange's pairs=.
TOTALS = { "total", "hits", "modules", "bridges", "reaches", "seam_pairs", "names", "count", "rows", "size", "files", "groups",
           "untested", "findings", "pairs" }
problems, seen = [], 0
for path in sorted( glob.glob( os.path.join( sys.argv[1], "sweep_*.xml" ) ) ):
    name = os.path.basename( path )[ len( "sweep_" ):-len( ".xml" ) ]
    try:
        root = ET.parse( path ).getroot()
    except ET.ParseError:
        continue                                    # arm (A) already reported the parse failure
    for el in root.iter():
        a = el.attrib
        if a.get( "capped" ) != "1":
            continue
        seen += 1
        tag = el.tag if isinstance( el.tag, str ) else "?"
        if "shown" not in a:
            problems.append( f'{name}: <{tag} capped="1"> carries no shown= (rules 1+3: a cut needs the printed count)' )
        if not ( TOTALS & set( a.keys() ) ):
            problems.append( f'{name}: <{tag} capped="1"> carries no total (total= or a rule-2 own-name spelling) — a reader cannot tell what the cut was against' )
if seen == 0:
    problems.append( "no element in the sweep carried capped=\"1\" — the arm asserted nothing (the --for --token-budget and --impact captures should cut)" )
print( f"  ..    (F) {seen} element(s) carried capped=\"1\" across the sweep" )
for p in problems: print( "  FAIL  " + p )
# mutation: the assertion shape can fail
mut = ET.fromstring( '<sigs capped="1"><f p="x"/></sigs>' ).attrib
if mut.get( "capped" ) == "1" and "shown" not in mut:
    print( "  PASS  (F) mutation: a bare <sigs capped=\"1\"> IS detected" )
else:
    print( "  FAIL  (F) mutation: the arm cannot see a bare capped element" ); problems.append( "mutation" )
sys.exit( 1 if problems else 0 )
PYF
[ $? = 0 ] && ok "(F) every capped=\"1\" element in the sweep carries shown= and a total" \
           || no "(F) a capped=\"1\" element discloses no shown=/total (listed above)"

# ---------------------------------------------------------------------------------------------------
# G4: every document this gate reasoned about is well-formed XML. (A) already parses them, but xmllint
# is the project's own G4 oracle and catches what a permissive parser forgives.
# ---------------------------------------------------------------------------------------------------
if command -v xmllint >/dev/null 2>&1; then
    bad=""
    for f in "$TMP"/sweep_*.xml "$TMP"/tiny_*.xml "$TMP/seams_big.xml"; do
        [ -s "$f" ] || continue
        xmllint --noout "$f" 2>/dev/null || bad="$bad $( basename "$f" )"
    done
    [ -z "$bad" ] && ok "G4: every swept document is xmllint-clean" || no "G4: malformed XML from:$bad"
else
    ok "G4: xmllint unavailable (skipped)"
fi

[ $fail = 0 ] && echo "ALL PASS" || echo "FAILURES"
exit $fail
