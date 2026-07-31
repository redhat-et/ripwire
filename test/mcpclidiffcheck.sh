#!/usr/bin/env bash
# mcpclidiffcheck.sh — the STRUCTURAL gate for the §B6 clone-seam class: for every MCP verb with a CLI
# twin, the two surfaces must agree, and the two MCP ARMS must agree with each other.
#
# WHY A DIFF GATE AND NOT MORE ASSERTS. Every §B6 finding was a divergence between two emitters of ONE
# computation — a call-site argument, a missing legend clause, a renamed JSON key — never an algorithm. No
# per-verb assert catches that class, because each surface passes its own tests in isolation; only a
# COMPARISON does. This gate is that comparison, run over the whole twinned surface at once, so the NEXT
# divergence is caught by arithmetic instead of by a human reading two outputs side by side.
#
# THE THREE SURFACES it compares, per verb:
#   CLI    — `ripwire <dir> --<flag>=…`
#   LIVE   — a JSON-RPC tools/call piped into `ripwire --mcp` on stdin  (what a real MCP client speaks to)
#   BATCH  — the same question inside the `batch` verb's sub-query chain (the SECOND dispatch)
#
# WHAT IT COMPARES (three lenses, each catching a different half of the class):
#   1. ROOT-ATTRIBUTE SET   — the XML twins (impact/uses/lego/exemplar/owners/path_between): the attribute
#                             NAMES on the payload's root element must be the same set on all three. This
#                             is the lens that sees a dropped honesty marker (M1's ambiguous=/unresolved=,
#                             M2's low_confidence=/over_ccx_bar=/candidates=, M4's paging half).
#   2. JSON KEY SET         — the JSON twins (quality_delta/grep): header keys AND row keys, CLI --json vs
#                             MCP. This is the lens that sees M5 (regressions array-vs-int, `r`, minor,
#                             at) and M12's missing files=/order= without caring about the values.
#   3. LEGEND CLAUSE        — a disclosure the CLI legend states and the MCP payload does not: the class
#                             M12 is (owners' depth collision) and M10 (analyze's first-screen stanza).
#
# WHAT IT DELIBERATELY DOES NOT COMPARE: values that are legitimately surface-specific (a CLI-only budget
# attribute, git stamps that move) — the gate normalizes NUMBERS out of attribute comparison and asserts on
# NAMES, because the divergences this class produces are structural, and pinning values would make the gate
# fail for reasons that are not bugs.
#
# Usage:
#   test/mcpclidiffcheck.sh                                    # uses build/ripwire
#   test/mcpclidiffcheck.sh /path/to/other/ripwire             # positional binary
#   RIPWIRE_BIN=build_base/ripwire test/mcpclidiffcheck.sh     # env binary (the RED run)
#
# Exits non-zero on any divergence. Does NOT edit regression.sh.

set -u
ROOT="$( cd "$( dirname "$0" )/.." && pwd )"
BIN="${1:-${RIPWIRE_BIN:-$ROOT/build/ripwire}}"
[ "${BIN#/}" = "$BIN" ] && BIN="$ROOT/$BIN"
TMP="$( mktemp -d )"; trap 'rm -rf "$TMP"' EXIT
fail=0

ok(){ printf '  PASS  %s\n' "$*"; }
no(){ printf '  FAIL  %s\n' "$*"; fail=1; }

[ -x "$BIN" ] || { echo "no ripwire binary at $BIN — build first (cmake --build build -j)"; exit 2; }
command -v python3 >/dev/null 2>&1 || { echo "python3 required for JSON assertions"; exit 2; }

echo "mcpclidiffcheck: BIN=$BIN  CORPUS=$ROOT"

# ── the three surfaces ──────────────────────────────────────────────────────────────────────────────────
mcp_text() {
    printf '%s\n' '{"jsonrpc":"2.0","id":1,"method":"initialize"}' "$1" \
        | "$BIN" --mcp 2>/dev/null | tail -1 | python3 -c '
import sys, json
r = json.load(sys.stdin)
print("__ERROR__:" + r["error"].get("message","") if "error" in r else r["result"]["content"][0]["text"])
'
}
batch_sub() {
    printf '%s\n' '{"jsonrpc":"2.0","id":1,"method":"initialize"}' \
        '{"jsonrpc":"2.0","id":2,"method":"tools/call","params":{"name":"batch","arguments":{"path":"'"$ROOT"'","queries":['"$1"']}}}' \
        | "$BIN" --mcp 2>/dev/null | tail -1 | python3 -c '
import sys, json, re, html
r = json.load(sys.stdin)
if "error" in r: print("__ERROR__:" + r["error"].get("message","")); raise SystemExit
t = r["result"]["content"][0]["text"]
m = re.search(r"<q i=\"0\" verb=\"[^\"]*\" ok=\"0\" err=\"([^\"]*)\"", t)
if m: print("__ERROR__:" + html.unescape(m.group(1))); raise SystemExit
m = re.search(r"<!\[CDATA\[(.*)\]\]>", t, re.S)
print(m.group(1) if m else "__NOPAYLOAD__")
'
}
call() { printf '{"jsonrpc":"2.0","id":2,"method":"tools/call","params":{"name":"%s","arguments":%s}}' "$1" "$2"; }

# attrs ELEMENT FILE — the attribute NAMES on the first <ELEMENT …> tag, sorted, space-separated.
# Names only: a value difference between surfaces is often legitimate, a missing NAME never is.
attrs() {
    python3 - "$1" "$2" <<'PY'
import re, sys
elem, path = sys.argv[1], sys.argv[2]
t = open(path).read()
m = re.search(r"<%s\b([^>]*)>" % re.escape(elem), t)
print(" ".join(sorted(set(re.findall(r'(\w[\w-]*)=\"', m.group(1))))) if m else "__NOELEMENT__")
PY
}

# ── LENS 1: root-attribute sets on the XML twins ────────────────────────────────────────────────────────
echo
echo "=== LENS 1 — root-attribute SET: CLI vs live MCP vs batch MCP ==="

# verb | element | CLI flag+value | MCP arguments | batch sub-query ("" = not batch-served)
# `impact` is probed WITH a page window on all three, because the paging half of the disclosure is exactly
# what M4 found missing on the MCP side and an un-paged probe cannot see it.
while IFS='|' read -r label elem cliargs mcpcall batchq; do
    [ -z "$label" ] && continue
    # eval, not word-splitting: one of these probes passes a task STRING with spaces, and $cliargs
    # unquoted would split it into three arguments and silently probe something else.
    eval "\"$BIN\" \"$ROOT\" $cliargs" 2>/dev/null >"$TMP/$label.cli"
    mcp_text "$mcpcall" >"$TMP/$label.live"
    A_CLI="$( attrs "$elem" "$TMP/$label.cli" )"
    A_LIVE="$( attrs "$elem" "$TMP/$label.live" )"
    # an ABSENT element, or one with no attributes at all, means the probe compared nothing — that is a
    # broken gate row, not a pass. Say so instead of reporting a vacuous match.
    if [ "$A_CLI" = "__NOELEMENT__" ] || [ -z "$A_CLI" ]; then
        no "LENS1 $label: the CLI probe yielded no <$elem …> attributes — the probe is broken, fix it before trusting this row"
        continue
    fi
    [ "$A_CLI" = "$A_LIVE" ] \
        && ok "LENS1 $label [live]: attribute set matches the CLI ($A_CLI)" \
        || no "LENS1 $label [live]: CLI has [$A_CLI] but MCP has [$A_LIVE]"
    [ -z "$batchq" ] && continue
    batch_sub "$batchq" >"$TMP/$label.batch"
    A_BAT="$( attrs "$elem" "$TMP/$label.batch" )"
    [ "$A_CLI" = "$A_BAT" ] \
        && ok "LENS1 $label [batch]: attribute set matches the CLI" \
        || no "LENS1 $label [batch]: CLI has [$A_CLI] but the batch arm has [$A_BAT]"
done <<EOF
impact|impact|--impact=escapeXml --limit=3 --offset=2|$( call impact '{"path":"'"$ROOT"'","symbol":"escapeXml","limit":3,"offset":2}' )|{"verb":"impact","symbol":"escapeXml","limit":3,"offset":2}
uses|uses|--uses=escapeXml|$( call uses '{"path":"'"$ROOT"'","symbol":"escapeXml"}' )|{"verb":"uses","symbol":"escapeXml"}
lego|iface|--lego=XmlWriter|$( call lego '{"path":"'"$ROOT"'","type":"XmlWriter"}' )|{"verb":"lego","type":"XmlWriter"}
exemplar|exemplar|--exemplar="zzz qqq wibble"|$( call exemplar '{"path":"'"$ROOT"'","kind":"zzz qqq wibble"}' )|{"verb":"exemplar","task":"zzz qqq wibble"}
path_between|path|--path=main,parseArgs|$( call path_between '{"path":"'"$ROOT"'","from":"main","to":"parseArgs"}' )|{"verb":"path_between","from":"main","to":"parseArgs"}
EOF

# analyze has no single root element the two share (the CLI map's <r> vs the MCP map's <r> ARE the same
# element, but the header STANZA is a comment) — so it gets its own comparison: the stanza's key set.
"$BIN" "$ROOT" --stable >"$TMP/analyze.cli" 2>/dev/null
mcp_text "$( call analyze '{"path":"'"$ROOT"'"}' )" >"$TMP/analyze.live"
batch_sub '{"verb":"analyze"}'                      >"$TMP/analyze.batch"
for arm in live batch; do
    python3 - "$TMP/analyze.cli" "$TMP/analyze.$arm" <<'PY'
import re, sys
def stanza(p):
    t = open(p).read()
    m = re.search(r"<!--\s*(files=[^>]*?)-->", t)
    if not m: return None, -1, -1
    return dict(re.findall(r"(\w+)=(\S+)", m.group(1))), t.find(m.group(0)), t.find("<r")
cv, _,  _  = stanza(sys.argv[1])
mv, mi, ri = stanza(sys.argv[2])
if cv is None: print("PROBE_BROKEN: the CLI map emitted no stanza"); raise SystemExit
problems = []
if mv is None:
    problems.append("the MCP map emits no stanza at all")
else:
    missing = set(cv) - set(mv)
    if missing: problems.append("MISSINGKEYS:" + ",".join(sorted(missing)))
    # VALUES too, for the corpus-level facts: both surfaces measured the SAME tree with the SAME parser,
    # so these must be EQUAL, and this is the half that catches a FALSE ZERO (a present key whose value is
    # a hard-coded 0 because a null accumulator was passed) — a key-set lens alone reads that as fine.
    # shown=/est_tokens= are deliberately excluded: they are a function of top-K, which the two surfaces
    # legitimately default differently.
    for k in ("files", "symbols", "edges", "ambiguous", "unresolved", "precise"):
        if k in cv and k in mv and cv[k] != mv[k]:
            problems.append("%s=%s on the CLI but %s here" % (k, cv[k], mv[k]))
    if not (0 <= mi < ri):
        problems.append("TRAILING (the stanza is emitted after <r>: not on the first screen)")
print("OK" if not problems else "; ".join(problems))
PY
done >"$TMP/analyze.res" 2>&1
[ "$( grep -c '^OK$' "$TMP/analyze.res" )" = "2" ] \
    && ok "LENS1 analyze: the header stanza carries every CLI key, on the first screen, on BOTH arms" \
    || no "LENS1 analyze: $( tr '\n' ' ' <"$TMP/analyze.res" )"

# ── LENS 2: JSON key sets on the JSON twins ─────────────────────────────────────────────────────────────
echo
echo "=== LENS 2 — JSON key SET: CLI --json vs MCP ==="

# W2FIX (2026-07-29): probe a DETERMINISTIC sandbox, not $ROOT. Probing the live repo made this arm
# environment-dependent: a user-stamped ./.ripwire_quality_baseline sidecar in the repo root fed the
# two arms DIFFERENT baselines (the CLI trusted a sidecar the MCP arm judged stale and ignored). That
# underlying divergence is now FIXED — R3 owner ruling 2026-07-29 revoked the CLI's reachable-ancestor
# carve-out and both arms route through the one quality::selectBaseline seam, with the CLI/MCP agreement
# arm living in test/qualitystalecheck.sh — but the sandbox stays, because this gate compares JSON KEY
# SETS and must not depend on whatever the developer's own repo root happens to contain. The sandbox has
# no sidecar, one commit, and one uncommitted new symbol, so BOTH arms measure vs git-HEAD and r[] is
# non-empty by construction.
QDSB="$TMP/qdsb"
mkdir -p "$QDSB/src" && cd "$QDSB" \
    && git init -q . && git config user.email t@t && git config user.name t \
    && printf 'int base( int a )\n{\n    return a + 1;\n}\n' >src/f.cpp \
    && git add -A && git commit -qm base \
    && printf '\nint freshRow( int a, int b )\n{\n    return a * b;\n}\n' >>src/f.cpp \
    && cd - >/dev/null || { no "LENS2 quality_delta: sandbox construction failed"; exit 1; }
"$BIN" "$QDSB" --quality-delta --json >"$TMP/qd.cli" 2>/dev/null
mcp_text "$( call quality_delta '{"path":"'"$QDSB"'"}' )" >"$TMP/qd.mcp"
python3 - "$TMP/qd.cli" "$TMP/qd.mcp" <<'PY' >"$TMP/qd.res" 2>&1
import json, sys
def load(p):
    t = open(p).read()
    if t.startswith("__ERROR__"): return None, t.strip()
    return json.loads(t), None
c, ce = load(sys.argv[1])
m, me = load(sys.argv[2])
if ce or me: print("PROBE_BROKEN cli=%s mcp=%s" % (ce, me)); raise SystemExit
problems = []
ck, mk = set(c), set(m)
if ck != mk: problems.append("header keys differ: cli-only=%s mcp-only=%s" % (sorted(ck-mk), sorted(mk-ck)))
for k in sorted(ck & mk):
    if type(c[k]) is not type(m[k]): problems.append("key %r: cli is %s, mcp is %s" % (k, type(c[k]).__name__, type(m[k]).__name__))
crk = set().union(*[set(r) for r in c.get("r", [])]) if c.get("r") else set()
mrk = set().union(*[set(r) for r in m.get("r", [])]) if m.get("r") else set()
if crk != mrk: problems.append("row keys differ: cli-only=%s mcp-only=%s" % (sorted(crk-mrk), sorted(mrk-crk)))
print("OK" if not problems else " | ".join(problems))
PY
[ "$( cat "$TMP/qd.res" )" = "OK" ] \
    && ok "LENS2 quality_delta: header keys, their TYPES, and row keys all match --json" \
    || no "LENS2 quality_delta: $( cat "$TMP/qd.res" )"

# grep: the CLI's XML root attributes vs the MCP JSON's header keys. The two spellings are deliberately
# different in FORM (attributes vs keys) but must cover the same FACTS, so the comparison is over names.
"$BIN" "$ROOT" --grep=pageDisclosure >"$TMP/grep.cli" 2>/dev/null
mcp_text "$( call grep '{"path":"'"$ROOT"'","pattern":"pageDisclosure"}' )" >"$TMP/grep.mcp"
python3 - "$TMP/grep.cli" "$TMP/grep.mcp" <<'PY' >"$TMP/grep.res" 2>&1
import json, re, sys
t = open(sys.argv[1]).read()
m = re.search(r"<grep\b([^>]*)>", t)
if not m: print("PROBE_BROKEN: the CLI probe emitted no <grep>"); raise SystemExit
cli = set(re.findall(r'(\w+)=\"', m.group(1)))
j = json.loads(open(sys.argv[2]).read())
mcp = set(j)
# `hits` is the CLI's row COUNT attribute and the MCP's row ARRAY — same fact, two shapes; `total` is the
# MCP's name for that count. Map them onto one another rather than reporting a difference that is a format.
mcp.discard("hits"); mcp.add("hits") if "total" in mcp else None
alias = {"total": "hits"}
mcp = { alias.get(k, k) for k in mcp }
missing = cli - mcp
print("OK" if not missing else "the MCP JSON is missing the CLI's " + ",".join(sorted(missing)))
PY
[ "$( cat "$TMP/grep.res" )" = "OK" ] \
    && ok "LENS2 grep: the MCP JSON covers every fact the CLI's <grep> root states" \
    || no "LENS2 grep: $( cat "$TMP/grep.res" )"

# ── LENS 3: legend clauses the CLI states and the MCP must too ──────────────────────────────────────────
echo
echo "=== LENS 3 — shared-legend clauses present on BOTH surfaces ==="
# Each row: label | a distinctive phrase from the CLI legend | CLI flag | MCP tools/call.
# The phrase is quoted from the CLI, so the gate can never pass because BOTH surfaces lost the clause.
while IFS='|' read -r label phrase cliargs mcpcall; do
    [ -z "$label" ] && continue
    eval "\"$BIN\" \"$ROOT\" $cliargs" 2>/dev/null >"$TMP/l3.cli"
    mcp_text "$mcpcall" >"$TMP/l3.mcp"
    grep -qF "$phrase" "$TMP/l3.cli" || { no "LENS3 $label: the CLI itself no longer states \"$phrase\" — the gate's anchor moved, re-derive it"; continue; }
    grep -qF "$phrase" "$TMP/l3.mcp" \
        && ok "LENS3 $label: the MCP payload carries the CLI's clause" \
        || no "LENS3 $label: the CLI states \"$phrase\" and the MCP payload does not"
done <<EOF
owners|two different things by DEPTH|--owners|$( call owners '{"path":"'"$ROOT"'"}' )
exemplar|chosen by ROLE, NEVER by text similarity|--exemplar=fn|$( call exemplar '{"path":"'"$ROOT"'","kind":"fn"}' )
uses|external=|--uses=escapeXml|$( call uses '{"path":"'"$ROOT"'","symbol":"escapeXml"}' )
EOF

echo
if [ "$fail" -eq 0 ]; then echo "ALL PASS"; exit 0; fi
echo "SOME CHECKS FAILED"; exit 1
