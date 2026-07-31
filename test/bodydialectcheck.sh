#!/usr/bin/env bash
# bodydialectcheck.sh — §H5 / §B8.3 / §B10.2 / §C4: the XML and JSON dialects of a --pack-task bundle must
# describe the SAME document, and the sections that truncate must SAY so in the one truncation vocabulary.
#
# WHAT WENT WRONG (all four measured on this repo before the fix, PLAN_outputAudit4_2026-07-30.md):
#
#  §H5  `--pack-task --json` chose its bodies a SECOND time. The XML pass handed every candidate to
#       packBodies — which groups by FILE and stops on a BYTE budget — and counted the resulting <b> elements
#       as bodies_kept; the JSON tail then re-sliced the first bodies_kept ids in RANK order and emitted each
#       one WHOLE. Two selections, one number over both:
#         --pack-task="redact secrets from emitted text" --token-budget=8000
#             XML  {redactInPlace, redactSecrets}      JSON {redactInPlace, loadRecallBody}   bodies_kept=2
#         --pack-task="serializeJson runDefaultMap" --token-budget=5000
#             XML 8 100 B (its one body TRUNCATED to fit)   JSON 42 200 B   stated ceiling 11 800 B
#       packBodiesJson had no budgetBytes parameter, no `used`, and no truncation vocabulary at all.
#
#  §B8.3 <bodies> carried NO attributes — "kept N of M" existed only in the header's comment prose — and
#       <callers>/<far>/<notes>/<tests> spelled the KEPT count `count=`, which pageview.h rule 2 lists as a
#       TOTAL spelling, with no capped= bit on any of them.
#
#  §B10.2 the redaction tally DOUBLE-CHARGED under --json: the XML sections redact and tally, then the JSON
#       sections re-serialize the same text through the same counter. MEASURED 4 claimed / 2 markers emitted,
#       JSON dialect only (--for reports the same number in both dialects, because it renders once).
#
#  §C4  `--max-tokens --json` shaped the map and disclosed nothing about the shaping — no max_tokens, no
#       fit_bytes, no over_ceiling, on the surface whose entire audience is machines.
#
# HOW THIS GATE IS BUILT: the parity arms compare SETS parsed out of both dialects, never byte counts of one
# against the other — the two encodings legitimately differ in size. And the XML side is parsed with an XML
# parser, not grep: a <b> body carries raw source in CDATA, so `grep -c '<bodies>'` matches a doc comment that
# merely mentions the tag (test/detailcheck.sh was passing for exactly that reason before this round).
#
# Usage:
#   bash test/bodydialectcheck.sh
#   bash test/bodydialectcheck.sh asan/ctxpack
#   CTXPACK_BIN=asan/ctxpack bash test/bodydialectcheck.sh
#
# Exits non-zero on any failure; prints PASS/FAIL per check and ALL PASS on success.

set -u
ROOT="$( cd "$( dirname "$0" )/.." && pwd )"
BIN="${1:-${CTXPACK_BIN:-$ROOT/build/ctxpack}}"
[ "${BIN#/}" = "$BIN" ] && BIN="$ROOT/$BIN"
TMP="$( mktemp -d )"; trap 'rm -rf "$TMP"' EXIT
fail=0
ok(){ printf '  PASS  %s\n' "$*"; }
no(){ printf '  FAIL  %s\n' "$*"; fail=1; }

[ -x "$BIN" ] || { echo "bodydialectcheck: no ctxpack binary at $BIN — build first (cmake --build build -j)"; exit 2; }
command -v python3 >/dev/null 2>&1 || { echo "bodydialectcheck: python3 is required"; exit 2; }

echo "bodydialectcheck: BIN=$BIN"

# ── (A) §H5 — the two dialects name the SAME bodies, in the same order, at every budget ────────────────────
# Tasks chosen so the bodies do NOT fall in one-per-file rank order: that is the only shape where a
# file-grouped emission and a rank-ordered re-slice can disagree, and a single-task gate would miss it.
python3 - "$BIN" "$ROOT" <<'PY'
import json, subprocess, sys, xml.etree.ElementTree as ET

BIN, ROOT = sys.argv[1], sys.argv[2]
TASKS = ["redact secrets from emitted text", "serializeJson runDefaultMap", "default map serialization",
         "git churn mining", "emit xml map header", "token budget ceiling"]
BUDGETS = [4000, 5000, 6500, 8000, 12000]

def run(args):
    return subprocess.run([BIN, ROOT] + args + ["--no-cache"], capture_output=True)

bad, shapes, truncSeen, omitSeen = [], 0, 0, 0
for task in TASKS:
    for bud in BUDGETS:
        shapes += 1
        x = run([f"--pack-task={task}", f"--token-budget={bud}"]).stdout
        j = run([f"--pack-task={task}", f"--token-budget={bud}", "--json"]).stdout
        try:
            # insert_comments: the XML names each over-budget skip in a COMMENT, and the default parser drops
            # comment nodes entirely — a parity arm built on the default parser reads "XML omitted nothing"
            # for every shape and passes vacuously.
            root = ET.fromstring(x, ET.XMLParser(target=ET.TreeBuilder(insert_comments=True)))
        except ET.ParseError as e:
            bad.append(f"{task!r}@{bud}: XML did not parse ({e})");  continue
        try:
            d = json.loads(j)
        except Exception as e:
            bad.append(f"{task!r}@{bud}: JSON did not parse ({e})");  continue

        bodiesEl = root.find(".//bodies")
        xnames   = [b.get("n") for b in bodiesEl.findall("b")] if bodiesEl is not None else []
        jnames   = [b["n"] for b in d.get("bodies", [])]
        if xnames != jnames:
            bad.append(f"{task!r}@{bud}: body SETS differ\n      XML  {xnames}\n      JSON {jnames}")
        if d.get("bodies_kept") != len(jnames):
            bad.append(f'{task!r}@{bud}: bodies_kept={d.get("bodies_kept")} but {len(jnames)} bodies emitted')
        if bodiesEl is not None and bodiesEl.get("shown") != str(len(xnames)):
            bad.append(f'{task!r}@{bud}: <bodies shown="{bodiesEl.get("shown")}"> but {len(xnames)} <b> elements')

        # truncation parity: the XML appends "<!-- truncated -->" INSIDE the CDATA of a body it cut.
        xtrunc = sorted(b.get("n") for b in (bodiesEl.findall("b") if bodiesEl is not None else [])
                        if b.text and "<!-- truncated -->" in b.text)
        jtrunc = sorted(b["n"] for b in d.get("bodies", []) if b.get("truncated"))
        truncSeen += len(xtrunc)
        if xtrunc != jtrunc:
            bad.append(f"{task!r}@{bud}: TRUNCATION differs — XML {xtrunc} vs JSON {jtrunc}")

        # omission parity: the XML names each over-budget skip in a comment; the JSON lists bodies_omitted.
        xomit = sorted(c.text.split(": ", 1)[1].strip()
                       for c in (list(bodiesEl) if bodiesEl is not None else [])
                       if not isinstance(c.tag, str) and "body omitted (over budget)" in (c.text or ""))
        jomit = sorted(d.get("bodies_omitted", []))
        omitSeen += len(xomit)
        if xomit != jomit:
            bad.append(f"{task!r}@{bud}: OMISSION differs — XML {xomit} vs JSON {jomit}")

print(f"  ..    compared {shapes} (task, budget) shapes; {truncSeen} truncated bodies and {omitSeen} omission markers exercised")
if truncSeen == 0:
    bad.append("no shape truncated a body — the truncation-parity arm proved nothing (widen BUDGETS/TASKS)")
if omitSeen == 0:
    bad.append("no shape omitted a body — the omission-parity arm proved nothing (widen BUDGETS/TASKS)")
for b in bad:
    print("  FAIL  (A) " + b)
sys.exit(1 if bad else 0)
PY
[ $? = 0 ] && ok "(A) §H5: XML and JSON name the same body set, the same truncations and the same omissions at every budget" \
           || no "(A) §H5 dialect parity broken (listed above)"

# ── (B) §H5 — the JSON bodies obey the SAME byte budget the XML does ───────────────────────────────────────
# The single-body shape is the sharpest: XML truncates runDefaultMap to fit, and the JSON used to ship it
# whole. The assertion is not "JSON == XML bytes" (the encodings differ) but "JSON is under the ceiling the
# bundle itself states", which the pre-fix 42 KB document was not.
for BUD in 5000 8000 12000; do
    "$BIN" "$ROOT" --pack-task="serializeJson runDefaultMap" --token-budget=$BUD --json --no-cache >"$TMP/big.json" 2>/dev/null
    JB="$( wc -c < "$TMP/big.json" | tr -d ' ' )"
    CEIL="$( python3 -c 'import json,sys; print(json.load(open(sys.argv[1]))["budget_ceiling_bytes"])' "$TMP/big.json" 2>/dev/null )"
    if [ -z "$CEIL" ]; then
        no "(B) --token-budget=$BUD --json: no budget_ceiling_bytes in the document"
    elif [ "$JB" -le "$CEIL" ]; then
        ok "(B) --token-budget=$BUD: JSON bundle ${JB} B is under its own stated ceiling ${CEIL} B"
    else
        no "(B) --token-budget=$BUD: JSON bundle ${JB} B EXCEEDS its own stated ceiling ${CEIL} B with no over_ceiling contract"
    fi
done

# ── (C) §B8.3 — every pack-task section element carries the pageview.h rule-1/2/3 triple ───────────────────
# This is the sweep-widening the finding asks for: truncvocabcheck's universal arm keys on shown=, so an
# element that emits NO shown= is invisible to it. Here the roster is named, so a section that drops the
# triple is a FAILURE rather than an absence.
"$BIN" "$ROOT/src" --pack-task="rank symbols by pagerank" --no-cache >"$TMP/sec.xml" 2>/dev/null
python3 - "$TMP/sec.xml" <<'PY'
import sys, xml.etree.ElementTree as ET
root = ET.parse(sys.argv[1]).getroot()
# <sigs> is rule 5 (a bare capped="1" on a byte-trimmed payload, no row total) and is deliberately excluded.
ROSTER = ["bodies", "callers", "far"]     # notes/tests are absent on a corpus with no .ctxpack_notes / no tests
ROWTAG = {"bodies": "b", "callers": "s", "far": "s", "notes": "target", "tests": "test"}
bad = []
seen = 0
for tag in ROSTER + ["notes", "tests"]:
    el = root.find(f".//{tag}")
    if el is None:
        if tag in ROSTER: bad.append(f"<{tag}> absent from the bundle — the roster arm cannot prove anything")
        continue
    seen += 1
    a = el.attrib
    for want in ("shown", "total", "capped"):
        if want not in a: bad.append(f'<{tag}> is missing {want}= (pageview.h rules 1/2/3)')
    if "count" in a:
        bad.append(f'<{tag}> still carries count="{a["count"]}" — rule 2 lists count= as a TOTAL spelling')
    if a.get("capped") not in ("0", "1"):
        bad.append(f'<{tag} capped="{a.get("capped")}"> is not the 0|1 boolean')
    if "shown" in a and "total" in a:
        rows = len(el.findall(ROWTAG[tag]))
        if a["shown"] != str(rows):
            bad.append(f'<{tag} shown="{a["shown"]}"> but {rows} <{ROWTAG[tag]}> rows emitted (the disclosure must be arithmetic)')
        if (a["capped"] == "1") != (int(a["shown"]) < int(a["total"])):
            bad.append(f'<{tag} shown={a["shown"]} total={a["total"]} capped="{a["capped"]}"> — the bit disagrees with the arithmetic')
print(f"  ..    checked {seen} section elements")
for b in bad: print("  FAIL  (C) " + b)
sys.exit(1 if bad else 0)
PY
[ $? = 0 ] && ok "(C) §B8.3: every pack-task section element carries shown=/total=/capped=, arithmetic and no count=" \
           || no "(C) §B8.3 vocabulary deviations (listed above)"

# ── (D) §B10.2 — the redaction tally is a property of the CONTENT, not of the dialect ──────────────────────
CORP="$TMP/redcorp"; mkdir -p "$CORP/src"
cat > "$CORP/src/probe.cpp" <<'PROBE_EOF'
#include <cstdio>

// Probe loader for the deployment credential store.
// Example key from the AWS documentation: AKIAIOSFODNN7EXAMPLE
// Rotate quarterly, never commit a live key.
const char* probeSecretLoader()
{
    const char* token = "ghp_ABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789";
    std::printf( "loading deployment credential\n" );
    return token;
}

// Deployment entry point that consumes the loaded deployment credential.
int probeDeployMain()
{
    const char* t = probeSecretLoader();
    return t == nullptr ? 1 : 0;
}
PROBE_EOF
RTASK="probeSecretLoader deployment credential loader"
tally_and_markers(){ # <label> <extra args...>
    local label="$1"; shift
    "$BIN" "$CORP" --pack-task="$RTASK" "$@" --no-cache >"$TMP/r.out" 2>"$TMP/r.err"
    local claimed marks
    claimed="$( sed -n 's/.*redacted \([0-9][0-9]*\) secret.*/\1/p' "$TMP/r.err" | head -1 )"
    marks="$( grep -o 'REDACTED:' "$TMP/r.out" | wc -l | tr -d ' ' )"
    printf '%s %s' "${claimed:-none}" "$marks"
}
read -r XML_CLAIM XML_MARK <<<"$( tally_and_markers xml )"
read -r JSN_CLAIM JSN_MARK <<<"$( tally_and_markers json --json )"
if [ "$XML_CLAIM" = "$XML_MARK" ] && [ "$JSN_CLAIM" = "$JSN_MARK" ] && [ "$XML_CLAIM" = "$JSN_CLAIM" ]; then
    ok "(D) §B10.2: tally == markers in BOTH dialects and agrees across them (xml $XML_CLAIM/$XML_MARK, json $JSN_CLAIM/$JSN_MARK)"
else
    no "(D) §B10.2: redaction tally is dialect-dependent or over-counts — xml claimed=$XML_CLAIM markers=$XML_MARK, json claimed=$JSN_CLAIM markers=$JSN_MARK"
fi
# the control: --for renders ONCE, so it never had the double-charge. If it moves, the fix reached too far.
"$BIN" "$CORP" --for=probeSecretLoader --json --no-cache >"$TMP/rf.out" 2>"$TMP/rf.err"
FOR_CLAIM="$( sed -n 's/.*redacted \([0-9][0-9]*\) secret.*/\1/p' "$TMP/rf.err" | head -1 )"
FOR_MARK="$( grep -o 'REDACTED:' "$TMP/rf.out" | wc -l | tr -d ' ' )"
[ -n "$FOR_CLAIM" ] && [ "$FOR_CLAIM" = "$FOR_MARK" ] \
    && ok "(D) control: --for --json tally still exact ($FOR_CLAIM/$FOR_MARK)" \
    || no "(D) control: --for --json claimed=$FOR_CLAIM markers=$FOR_MARK"
# and the secrets themselves must still be GONE from the JSON — a tally fix must never become a redaction fix
grep -qF 'ghp_ABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789' "$TMP/r.out" \
    && no "(D) LEAK: raw github token in --pack-task --json" \
    || ok "(D) --pack-task --json still redacts (raw token absent)"

# ── (E) §C4 — the --max-tokens fit discloses itself in the JSON dialect too ────────────────────────────────
"$BIN" "$ROOT/src" --max-tokens=1200 --json --no-cache >"$TMP/mt.json" 2>/dev/null
python3 - "$TMP/mt.json" <<'PY'
import json, sys
d = json.load(open(sys.argv[1]))
bad = [k for k in ("max_tokens", "fit_bytes", "fit_measured_in") if k not in d]
if d.get("max_tokens") != 1200: bad.append(f'max_tokens={d.get("max_tokens")} (want 1200)')
# fit_measured_in exists because the top-K search measures the XML rendering while this document is JSON;
# emitting fit_bytes without naming its dialect would trade a silence for a false implication.
if d.get("fit_measured_in") != "xml": bad.append(f'fit_measured_in={d.get("fit_measured_in")!r} (want "xml")')
for b in bad: print("  FAIL  (E) --max-tokens --json: " + str(b))
sys.exit(1 if bad else 0)
PY
[ $? = 0 ] && ok "(E) §C4: --max-tokens --json carries max_tokens/fit_bytes/fit_measured_in" \
           || no "(E) §C4 disclosure keys missing (listed above)"
# a plain map (no --max-tokens) must stay byte-identical — the keys are absent-unless-produced
"$BIN" "$ROOT/src" --json --top-k=5 --no-cache 2>/dev/null | grep -q 'max_tokens' \
    && no "(E) a map with no --max-tokens leaked a max_tokens key (must be absent-unless-produced)" \
    || ok "(E) a map with no --max-tokens carries no fit keys (absent-unless-produced)"
# over_ceiling: each dialect must label its OWN document truthfully — a BICONDITIONAL, not an agreement.
#
# This arm read "both dialects must label it at --max-tokens=400" until the wave-3 merge, and it went red when
# the concurrent lane's §C4 fix made the verdict measure the EMITTED dialect instead of always measuring XML.
# Measured at N=400 on src/: XML is 1044 B against a 849 B fit (genuinely over, correctly labelled) and JSON
# is 287 B against the same 849 (genuinely under). So the old arm demanded a FALSE statement from the JSON
# dialect. It was asserting a COINCIDENCE — that the two dialects happen to agree — where the property is
# "each dialect tells the truth about the document it emitted", and the coincidence stopped holding precisely
# because the code got more honest. The biconditional below is strictly stronger: it still catches a dialect
# silently exceeding without labelling (the original §H5/§C4 defect) AND it catches a dialect crying wolf.
for MODE in xml json; do
    if [ "$MODE" = xml ]; then
        "$BIN" "$ROOT/src" --max-tokens=400 --no-cache >"$TMP/oc.out" 2>/dev/null
        LABEL="$( grep -c 'over_ceiling=1' "$TMP/oc.out" )"
    else
        "$BIN" "$ROOT/src" --max-tokens=400 --json --no-cache >"$TMP/oc.out" 2>/dev/null
        LABEL="$( grep -c '"over_ceiling":true' "$TMP/oc.out" )"
    fi
    OC_B="$( wc -c <"$TMP/oc.out" | tr -d ' ' )"
    OC_FIT="$( grep -o 'fit_bytes[":= ]*[0-9]*' "$TMP/oc.out" | grep -o '[0-9]*$' | head -1 )"
    [ -n "$OC_FIT" ] || { no "(E) $MODE --max-tokens=400 emitted no fit_bytes to check the label against"; continue; }
    if [ "$OC_B" -gt "$OC_FIT" ]; then WANT=1; else WANT=0; fi
    if { [ "$WANT" = 1 ] && [ "$LABEL" -ge 1 ]; } || { [ "$WANT" = 0 ] && [ "$LABEL" = 0 ]; }; then
        ok "(E) $MODE --max-tokens=400: ${OC_B} B vs fit ${OC_FIT} B, over_ceiling label agrees (want=$WANT)"
    else
        no "(E) $MODE --max-tokens=400: ${OC_B} B vs fit ${OC_FIT} B wants label=$WANT, got $LABEL"
    fi
done

# ── (F) determinism, both dialects ────────────────────────────────────────────────────────────────────────
for D in "" "--json"; do
    "$BIN" "$ROOT/src" --pack-task="rank symbols by pagerank" $D --no-cache >"$TMP/det1" 2>/dev/null
    "$BIN" "$ROOT/src" --pack-task="rank symbols by pagerank" $D --no-cache >"$TMP/det2" 2>/dev/null
    cmp -s "$TMP/det1" "$TMP/det2" && ok "(F) --pack-task ${D:-xml} is byte-deterministic across runs" \
                                   || no "(F) --pack-task ${D:-xml} differs between two runs"
done

# ══ (G) §B12.7 / CA4 verifier F-MED-1 — BODY BYTES, and the disclosure when they cannot match ═══════════
# THE GAP THIS CLOSES (trap #23). Arm (A) above compares body SETS, truncations and omissions and never
# body BYTES — which is exactly why the new §H5 header could claim "same set, same bytes, same truncation,
# BY CONSTRUCTION … it cannot drift because there is nothing to keep in step" and be FALSE, with a green
# gate underneath it. packBodies records EmittedBody::text at the push_back BEFORE appendCdataSafe, and
# appendCdataSafe is not an escape but a LOSSY SCRUB (xmlSafeByte maps every C0 byte except \t\n\r to a
# space; an invalid UTF-8 sequence becomes '?'). A def holding ESC + Latin-1 therefore reached XML at 140 B
# scrubbed and JSON at 148 B raw, in every budget and under --compress/--no-redact alike.
#
# THE DECISION (implemented, not deferred): the divergence is MANDATORY and is now DISCLOSED. XML 1.0
# forbids C0 even escaped, so the XML side cannot stop scrubbing; JSON has \u00XX for all of them, so making
# the two agree is only possible by degrading JSON — deleting real bytes from the one dialect a consumer can
# recover the original from. jsonesc.h's header records that side's half. So the LOSSY side says so:
# `<b … scrubbed="1">` on the XML body and `"xml_scrubbed":true` on its JSON twin, both absent when the two
# are byte-equal.
#
# So this arm asserts the property the "by construction" claim should have had all along:
#   (G1) on a CLEAN corpus the two dialects' body bytes are EQUAL, and neither carries the disclosure;
#   (G2) on a corpus carrying ESC + invalid UTF-8 they are NOT equal, and BOTH dialects say so;
#   (G3) the flag tracks the BYTES, not a guess: it is set exactly when XML != JSON, in both directions.
# (G1) is the arm that would have caught F-MED-1's claim; (G2) is the arm that proves the tell is live.
BD="$TMP/dial"
mkdir -p "$BD/clean" "$BD/dirty"
cat > "$BD/clean/c.cpp" <<'CEOF'
// a perfectly ordinary body: entity-escapable characters only (& < > " '), no C0, valid UTF-8.
int scrubProbe( int a, int b )
{
    if( a < b && b > 0 ) return a & b;
    return a;
}
CEOF
# ESC (0x1b) and a lone 0xe9 (Latin-1 'e-acute', an invalid UTF-8 lead) — one of each rule.
printf 'int scrubProbe( int a, int b )\n{\n    // \033 caf\351 marker\n    if( a < b ) return a & b;\n    return a;\n}\n' > "$BD/dirty/d.cpp"

bd_probe(){    # $1 = corpus dir -> prints "<xmlbytes> <jsonbytes> <xmlflag> <jsonflag>"
    "$BIN" "$1" --pack-task="scrubProbe marker" --no-cache        >"$TMP/bd.xml"  2>/dev/null
    "$BIN" "$1" --pack-task="scrubProbe marker" --json --no-cache >"$TMP/bd.json" 2>/dev/null
    python3 - "$TMP/bd.xml" "$TMP/bd.json" <<'PY'
import json, sys, xml.etree.ElementTree as ET
x = ET.parse( sys.argv[1] ).getroot()
b = x.find( ".//bodies/b" )
d = json.load( open( sys.argv[2] ) )
jb = ( d.get( "bodies" ) or [ {} ] )[0]
xt = b.text if b is not None and b.text is not None else ""
# the XML appends "\n<!-- truncated -->" INSIDE the CDATA on a cut body; strip it before comparing bytes.
xt = xt.split( "\n<!-- truncated -->" )[0]
print( len( xt.encode( "utf-8", "surrogateescape" ) ),
       len( ( jb.get( "body" ) or "" ).encode( "utf-8", "surrogateescape" ) ),
       "1" if ( b is not None and b.get( "scrubbed" ) == "1" ) else "0",
       "1" if jb.get( "xml_scrubbed" ) else "0",
       "1" if xt == ( jb.get( "body" ) or "" ) else "0" )
PY
}

read -r CX CJ CXF CJF CEQ <<EOF
$( bd_probe "$BD/clean" )
EOF
read -r DX DJ DXF DJF DEQ <<EOF
$( bd_probe "$BD/dirty" )
EOF

# (G1) clean corpus: bytes equal, no disclosure on either side.
{ [ "$CEQ" = 1 ] && [ "$CX" = "$CJ" ]; } \
    && ok "(G1) clean corpus: XML CDATA and JSON body are BYTE-EQUAL (${CX} B each)" \
    || no "(G1) clean corpus: XML ${CX} B vs JSON ${CJ} B — the dialects disagree where nothing forces them to"
{ [ "$CXF" = 0 ] && [ "$CJF" = 0 ]; } \
    && ok "(G1) clean corpus: neither dialect claims a scrub" \
    || no "(G1) clean corpus: scrubbed disclosure fired with nothing to disclose (xml=$CXF json=$CJF)"

# (G2) hostile corpus: bytes differ (mandatory), and BOTH dialects disclose it.
if [ "$DX" = 0 ] || [ "$DJ" = 0 ]; then
    no "(G2) the hostile-corpus probe emitted no body — it is not measuring the divergence it claims to"
elif [ "$DEQ" = 1 ]; then
    no "(G2) ESC + invalid UTF-8 survived into the XML CDATA unchanged (${DX} B == ${DJ} B) — either the G4 scrub stopped running or this probe stopped being hostile"
else
    ok "(G2) hostile corpus: XML ${DX} B (scrubbed) vs JSON ${DJ} B (verbatim) — the mandatory divergence is real"
    { [ "$DXF" = 1 ] && [ "$DJF" = 1 ]; } \
        && ok "(G2) BOTH dialects disclose it — <b scrubbed=\"1\"> and \"xml_scrubbed\":true" \
        || no "(G2) the divergence is SILENT in at least one dialect (xml_flag=$DXF json_flag=$DJF) — §B12.7's whole finding"
fi

# (G3) the flag is a function of the BYTES, in both directions — no corpus may be flagged-and-equal or
#      differing-and-silent. Stated as one biconditional so a future emitter cannot satisfy half of it.
g3=0
for pair in "$CEQ $CXF $CJF clean" "$DEQ $DXF $DJF dirty"; do
    set -- $pair
    if [ "$1" = 1 ] && { [ "$2" = 1 ] || [ "$3" = 1 ]; }; then g3=1; echo "     $4: bytes EQUAL but flagged"; fi
    if [ "$1" = 0 ] && { [ "$2" = 0 ] || [ "$3" = 0 ]; }; then g3=1; echo "     $4: bytes DIFFER but not flagged"; fi
done
[ "$g3" = 0 ] && ok "(G3) scrubbed=/xml_scrubbed track the body bytes exactly, in both directions" \
              || no "(G3) the disclosure and the bytes disagree"

# ══ (H) THE SCRUB DISCLOSURE IS A TABLE, AND THE TABLE IS SWEPT IN BOTH DIRECTIONS ══════════════════════
# Arm (G) proved the property for ONE of the three XML scrub markers — `<b scrubbed="1">`, the one that
# already had a JSON twin. serialize.h's header promises the fact is legible "from either one" of the two
# dialects, and there were THREE markers against ONE twin: for the task echo, the header's own headline
# example, VT / FF / ESC / invalid-UTF-8 all produced task_scrubbed="1" in XML and ZERO scrub keys in JSON.
# Gating only the marker that already worked is how that survived a round. So this arm sweeps every
# (surface, marker) pair over every input class and asserts the BICONDITIONAL in both directions: lossy =>
# both dialects say so, non-lossy => neither does. Agreement in one direction is trap #28's coincidence.
HB="$TMP/scrub"; mkdir -p "$HB"
printf 'int alphaWidget( int a ) { return a; }\nint betaCaller( void ) { return alphaWidget( 1 ); }\n' > "$HB/a.c"
: > "$TMP/scrubgaps"

# scrub_probe VERB TASK -> "<xml-markers> <json-markers>", each a sorted comma list or `none`.
scrub_probe(){
    _x="$( "$BIN" "$HB" "$1=$2" --top-k=1 --no-cache 2>/dev/null | head -c 600 \
           | grep -oE '(task|route)_scrubbed="1"' | sed 's/_scrubbed="1"//' | sort | tr '\n' ',' )"
    _j="$( "$BIN" "$HB" "$1=$2" --top-k=1 --json --no-cache 2>/dev/null | head -c 900 \
           | grep -oE '"(task|route)_xml_scrubbed":true' | sed 's/"//g; s/_xml_scrubbed:true//' | sort | tr '\n' ',' )"
    printf '%s %s\n' "${_x:-none}" "${_j:-none}"
}

# The four lossy rules (three C0 kinds + invalid UTF-8), the legal control char that must NOT fire, and a
# clean query. \t is the false-positive probe: entity-escaping round-trips and is not a scrub.
h_fail=0
for _verb in --for --pack-task; do
    for _case in "clean:ordinary lookup query" \
                 "VT:$( printf 'alphaWidget\013x' )" \
                 "FF:$( printf 'alphaWidget\014x' )" \
                 "ESC:$( printf 'alphaWidget\033x' )" \
                 "BADUTF8:$( printf 'alphaWidget\377x' )" \
                 "TAB:$( printf 'alphaWidget\011x' )"; do
        _name="${_case%%:*}"; _task="${_case#*:}"
        read -r _xm _jm <<EOF
$( scrub_probe "$_verb" "$_task" )
EOF
        if [ "$_xm" != "$_jm" ]; then
            h_fail=1
            printf '%s %s\n' "$_verb" "$_name" >> "$TMP/scrubgaps"
            printf '     (H) %s %s: XML[%s] != JSON[%s] — one dialect is silent\n' "$_verb" "$_name" "$_xm" "$_jm"
        fi
    done
done

# The residual this arm was written around is CLOSED (2026-07-31): src/packtask.h's JSON header now calls
# ctxRootJsonScrubKeys after its route key, so every lossy surface discloses in BOTH dialects. The pin did its
# job exactly as designed — it went red on the fix, naming the edit to make here, rather than quietly passing
# and leaving a stale tolerance behind. What remains is the plain biconditional: NO surface may be silent in
# one dialect and loud in the other, and a new gap reds by name.
OBSERVED="$( sort -u "$TMP/scrubgaps" )"
if [ -z "$OBSERVED" ]; then
    ok "(H) the scrub biconditional holds on every surface — no dialect-silent lossy row"
else
    no "(H) dialect-silent surface(s) — XML discloses the scrub and JSON does not:"
    printf '%s\n' "$OBSERVED" | sed 's/^/       /'
fi

# non-lossy input must leave BOTH dialects silent — asserted separately, because the equality above is also
# satisfied by both-marked, so a marker firing on an entity-escapable character would be invisible to it.
h_false=0
for _verb in --for --pack-task; do
    for _t in "ordinary lookup query" "$( printf 'alphaWidget\011x' )"; do
        read -r _xm _jm <<EOF
$( scrub_probe "$_verb" "$_t" )
EOF
        { [ "$_xm" = none ] && [ "$_jm" = none ]; } \
            || { h_false=1; printf '     %s fired on a non-lossy input: XML[%s] JSON[%s]\n' "$_verb" "$_xm" "$_jm"; }
    done
done
[ "$h_false" = 0 ] \
    && ok "(H) clean input and a legal tab leave BOTH dialects silent on both verbs (entity-escaping is not a scrub)" \
    || no "(H) a scrub marker fired where nothing was lost"

# The third marker, both verbs: <b scrubbed="1"> is emitted by --for --detail as well as --pack-task, and
# only ONE of those has a JSON dialect at all (--for --detail --json refuses). Pinned so that if --detail
# ever gains --json, this arm names the twin it will need instead of silently not covering it.
"$BIN" "$HB" --for=alphaWidget --detail=1 --json --no-cache >/dev/null 2>&1 \
    && no "(H) --for --detail --json now answers — its body objects need the xml_scrubbed twin; extend this arm" \
    || ok "(H) --for --detail has no JSON dialect, so <b scrubbed=\"1\"> has exactly one twin to keep in step"

# THE POPULATION, from source. The defect was never the machinery — it was a promise phrased as a RULE over
# an unenumerated set of call sites. Every file emitting a top-level JSON "task" key is either converted or
# carries a reason here, and a new one reds until someone classifies it.
CLASSIFIED="cli.h
lanes.h
main.cpp
packtask.h
partition.h"
#   cli.h        — the string appears only in usage/refusal prose, not in an emitted document
#   lanes.h      — --plan-lanes has no ctxRootOpen XML twin, so there is no XML marker to mirror
#   main.cpp     — CONVERTED: forLensJsonHeader calls ctxRootJsonScrubKeys
#   packtask.h   — the PINNED RESIDUAL above
#   partition.h  — a wrapper; the task it echoes is re-emitted by the packtask bundles it nests
EMITTERS="$( cd "$ROOT" && grep -l '\\"task\\"' src/*.h src/*.cpp 2>/dev/null | sed 's|.*/||' | sort -u )"
UNCLASSIFIED="$( printf '%s\n' "$EMITTERS" | grep -vxF "$CLASSIFIED" || true )"
[ -z "$UNCLASSIFIED" ] \
    && ok "(H) all $( printf '%s\n' "$EMITTERS" | wc -l | tr -d ' ' ) JSON task-key emitters are converted or classified" \
    || { no "(H) an unclassified JSON task-key emitter exists — convert it or give it a row"; printf '     %s\n' "$UNCLASSIFIED"; }
grep -q 'ctxRootJsonScrubKeys' "$ROOT/src/main.cpp" \
    && ok "(H) the converted emitter really goes through the one seam (not a hand-rolled copy)" \
    || no "(H) main.cpp's JSON header no longer calls ctxRootJsonScrubKeys"

echo
[ "$fail" = 0 ] && echo "ALL PASS" || echo "SOME CHECKS FAILED"
exit $fail
