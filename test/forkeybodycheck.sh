#!/usr/bin/env bash
# forkeybodycheck.sh — KB1 (src/forkeybody.h; results/KB1_ACTREADY_1119/PREREG.md): the first page of a --for answer carries the
# definition body of the symbol the question names in backticks, right after the block that answers it, bounded and disclosed.
#
# THE CONTRACT IS ADDITIVE. The key-body group (its legend comment + <bodies of="key">) is the only thing it adds: delete the group
# and the answer is the RIPWIRE_NO_KEY_BODY=1 twin byte for byte (est_tokens= aside, re-priced over the added bytes; on a routed
# answer the compact legend's present-only `bodies of=key` reading aside). And the page the group starts on does not count it, so
# every page holds the twin's rows: no row is pushed to a later page by a body.
# ARMS
#   (K0)  routed who-calls: one <bodies of="key" shown="1" total="1" capped="0">, the source definition's body (never the bodyless
#         header declaration), its CDATA holding the definition line
#   (K1)  routed placement: the block is the root's last child, after the verb's rows; the compact legend defines it (bodies of=key)
#   (K1n) routed coverage: ON minus the block == the knob-off twin, legend comments aside (the compact legend gains the present-only
#         readings the block's attributes need); the comparison CAN fail (one byte dropped)
#   (K2)  MCP `for` routes by the same rule and carries the same <bodies of="key"> element, byte for byte (RT2 parity)
#   (K3)  unrouted (this repo's src/, a conceptual question naming two functions): the group sits directly after the first top-level
#         row block of the whole answer (--page-bytes=0), legend first, and EVERY name the question backticks rides. The membership
#         arm reads the expected names FROM THE QUESTION rather than pinning a literal ['streamCuts','pageEnds'], so a change to
#         the body SELECTOR (SEL1's S1, or any later fold change) cannot turn this arm red by moving which definition page 1
#         happens to serve — it is red only when a backticked name does not ride. Rule E2 (the last code-shaped span leads) is
#         pinned the same way, from the question's own span order.
#   (K3n) unrouted coverage: ON minus the group == the twin (est_tokens= masked); the comparison CAN fail (one byte dropped)
#   (K4)  pages: at the default 12 KB page, every page of ON minus the group == the twin's page (est_tokens= masked), the page count
#         is the twin's and the group rides page 1: a body pushes no row to a later page
#   (K5)  ceiling (routed): a body over 4000 B is cut at a line end and says so — truncated="1" lines="1-K/T", next= the --expand of the rest
#   (K6)  cap (routed): three named symbols -> all three ride at CB1's cap of 5 (shown="3" total="3"), rule E2's symbol first
#   (K6b) cap OVERFLOW (routed): SIX named symbols -> shown="5" total="6" capped="1", next= the sixth's --expand. This is the
#         arm that actually exercises kKeyBodyMax; K6 alone would pass on any cap of 3 or more.
#   (K7)  negative controls, byte-identical with and without the knob: no backticks; a span naming nothing; a namesake flood (13
#         definitions); a definition only in a test file; --legend=first; --signatures-only; --token-budget
#   (K12) THE CONTRACT ARM (owner ruling 87, 2026-11-20): the key group carries its OWN body even when the page already serves that
#         same definition elsewhere. Same p= and same l= in two places on one page is CORRECT — a body served elsewhere does not
#         satisfy KB1. Non-vacuous by construction and in that order: the arm first proves the knob-off twin's page 1 really does
#         carry that definition's body, and only then requires the key group to carry it anyway (so the ON answer is NOT the twin).
#         (K12) RETIRES the old (K8), which pinned the opposite — no key block when the page already carried the body. Ruling 87
#         overturns that clause of KB1's frozen rule (results/KB1_ACTREADY_1119/PREREG.md lines 25-26: "A body the page already
#         carries (same p= and l= in the first 12,000 B) is not repeated"); K8 was that clause's gate and cannot survive it.
#   (K13) THE DISCLOSURE TRIPLE IS INTERNALLY CONSISTENT, on every key group this gate produces: capped="1" iff shown< total
#         iff next= is present, and shown<=total always. An invariant on the TAG ALONE — it needs no knowledge of how many
#         definitions exist, so it catches any mechanism that filters candidates before counting them, not just the one
#         ruling 87 removed. The unfixed binary emitted `<bodies of="key" shown="3" total="3" capped="1">` — capped= asserting
#         a cut, shown==total asserting nothing was withheld, and NO next= — three contradictory claims in one tag.
#   (K14) total= IS THE KEYED-DEFINITION COUNT, pinned against a count known BY CONSTRUCTION rather than against anything the
#         tool reports: each of compute_total, alpha_one, beta_two, gamma_three, big_function and run_main has exactly ONE
#         bodied source definition in this fixture's src/ (lib.h's declaration is bodiless and never counts — see K0), so a
#         question naming three of them has 3 keyed definitions and one naming six has 6. Non-vacuity FIRST: page 1 must
#         really serve one of those bodies elsewhere, or a filter-before-count had nothing to remove and the arm proves
#         nothing. CLAUDE.md non-negotiable 3 — a count that cannot be a total is labelled a floor; total= is not a floor.
#   (K9)  well formed (xmllint) and deterministic (two runs byte-identical)
#   (K10) ordering: a Python @overload pair of one-line stubs and the real definition -> the real (multi-line) body takes the first slot
#   (K11) a warned routed answer (who-calls through a macro: the --for page is carried) holds ONE key block: the carried page's moves up
set -u
ROOT="$( cd "$( dirname "$0" )/.." && pwd )"
BIN="${RIPWIRE_BIN:-${1:-$ROOT/build/ripwire}}"
[ "${BIN#/}" = "$BIN" ] && BIN="$ROOT/$BIN"
[ -x "$BIN" ] || { echo "no ripwire binary at $BIN -- build first (cmake --build build -j)"; exit 2; }
command -v python3 >/dev/null 2>&1 || { echo "forkeybodycheck: python3 required"; exit 2; }
fail=0
ok(){ printf '  PASS  %s\n' "$*" || { fail=1; printf '  FAIL  could not write the PASS line for: %s\n' "$*"; }; return 0; }
no(){ printf '  FAIL  %s\n' "$*"; fail=1; }
say(){ if [ "$1" = 0 ]; then ok "$2"; else no "$3"; fi; }
DIR="${KEEP_DIR:-$( mktemp -d )}"; [ -n "${KEEP_DIR:-}" ] || trap 'rm -rf "$DIR"' EXIT; mkdir -p "$DIR"
echo "forkeybodycheck: BIN=$BIN"
unset RIPWIRE_NO_KEY_BODY

# ── fixture ─────────────────────────────────────────────────────────────────────────────────────────────────────────────
F="$DIR/fx"; mkdir -p "$F/src" "$F/tests" "$F/flood"
printf 'int compute_total( int a );\n' >"$F/src/lib.h"
{
    printf '#include "lib.h"\nint compute_total( int a )\n{\n    return a + 1;\n}\n'
    printf 'int alpha_one( int x )\n{\n    return x * 2;\n}\n'
    printf 'int beta_two( int x )\n{\n    return x * 3;\n}\n'
    printf 'int gamma_three( int x )\n{\n    return x * 4;\n}\n'
    printf 'int big_function( int x )\n{\n    int acc = 0;\n'
    for i in $( seq 1 160 ); do printf '    acc += x * %d; /* step %d of the long accumulation */\n' "$i" "$i"; done
    printf '    return acc;\n}\n'
} >"$F/src/lib.c"
printf '#include "lib.h"\nint run_main( void )\n{\n    return compute_total( 2 ) + alpha_one( 1 ) + beta_two( 1 ) + gamma_three( 1 ) + big_function( 1 );\n}\n' >"$F/src/main.c"
for i in $( seq 1 13 ); do printf 'int flood_fn%s( void );\nint flood_fn( void )\n{\n    return %d;\n}\n' "" "$i" >"$F/flood/f$i.c"; done
printf 'int only_in_test( void )\n{\n    return 7;\n}\nint test_main( void )\n{\n    return only_in_test();\n}\n' >"$F/tests/test_lib.c"

P="$DIR/py"; mkdir -p "$P/pkg"
cat >"$P/pkg/util.py" <<'PYSRC'
from typing import overload


@overload
def pick_one(x: int) -> int: ...
@overload
def pick_one(x: str) -> str: ...
def pick_one(x):
    if isinstance(x, int):
        return x + 1
    return x.strip()
PYSRC
printf 'from pkg.util import pick_one


def run():
    return pick_one(1)
' >"$P/pkg/main.py"
M="$DIR/mac"; mkdir -p "$M"
printf '#include "lib.h"
int compute_total( int a )
{
    return a + 1;
}
' >"$M/lib.c"
printf 'int compute_total( int a );
#define TOTAL( x ) compute_total( x )
' >"$M/lib.h"
for f in a b; do printf '#include "lib.h"
int use_%s( void )
{
    return TOTAL( 1 );
}
' "$f" >"$M/$f.c"; done
cli(){ ( cd "$F" && "$BIN" . --no-cache --for="$1" "${@:2}" 2>/dev/null ); }
off(){ ( cd "$F" && RIPWIRE_NO_KEY_BODY=1 "$BIN" . --no-cache --for="$1" "${@:2}" 2>/dev/null ); }
mcpfor(){ python3 - "$BIN" "$1" "$2" <<'PY'
import json, subprocess, sys
binp, path, task = sys.argv[1:4]
req = [ {"jsonrpc": "2.0", "id": 1, "method": "initialize"},
        {"jsonrpc": "2.0", "id": 2, "method": "tools/call", "params": {"name": "for", "arguments": {"path": path, "task": task}}} ]
p = subprocess.run([binp, "--mcp"], input="".join(json.dumps(r) + "\n" for r in req), capture_output=True, text=True)
for line in p.stdout.splitlines():
    try:
        r = json.loads(line)
    except ValueError:
        continue
    if r.get("id") == 2:
        sys.stdout.write("".join(c.get("text", "") for c in r.get("result", {}).get("content", [])))
PY
}

QR='Who calls `compute_total`?'
QU='How does `compute_total` work?'
cli "$QR" >"$DIR/r.on"; off "$QR" >"$DIR/r.off"; cli "$QR" >"$DIR/r.on2"
mcpfor "$F" "$QR" >"$DIR/r.mcp"
QS='How do `pageEnds` and `streamCuts` decide where a page of an answer-first document is cut?'
srcon(){ ( cd "$ROOT" && "$BIN" src --no-cache --for="$QS" "$@" 2>/dev/null ); }
srcoff(){ ( cd "$ROOT" && RIPWIRE_NO_KEY_BODY=1 "$BIN" src --no-cache --for="$QS" "$@" 2>/dev/null ); }
srcon --page-bytes=0 >"$DIR/u.on"; srcoff --page-bytes=0 >"$DIR/u.off"; srcon --page-bytes=0 >"$DIR/u.on2"
for k in 1 2 3 4 5 6; do
    srcon --page-bytes=12000:$k >"$DIR/pg$k.on"; srcoff --page-bytes=12000:$k >"$DIR/pg$k.off"
done
srcon >"$DIR/def.on"
cli 'Who calls `big_function`?' >"$DIR/big.on"
cli 'Who calls `alpha_one`, `beta_two` or `gamma_three`?' >"$DIR/cap.on"
# CB1: six names, so the cap of 5 is exercised and not merely outnumbered (K6b)
cli 'Who calls `alpha_one`, `beta_two`, `gamma_three`, `compute_total`, `big_function` or `run_main`?' >"$DIR/cap6.on"
# (K13)/(K14): the same names UNROUTED, so insertKeyBodies runs and a filter-before-count would show. Three names = 3 keyed
# definitions by construction, six = 6. The routed cap6.on above is the control: the routed path never consulted the page.
cli '`compute_total`, `alpha_one` and `beta_two`' >"$DIR/tot3.on"
cli '`compute_total`, `alpha_one`, `beta_two`, `gamma_three`, `big_function` and `run_main`' >"$DIR/tot6.on"
n=0
for q in 'How does compute_total work?' 'How does `no_such_symbol_here` work?' 'How does `flood_fn` work?' 'How does `only_in_test` work?'; do
    n=$(( n + 1 )); cli "$q" >"$DIR/neg$n.on"; off "$q" >"$DIR/neg$n.off"
done
for arm in "--legend=first" "--signatures-only" "--token-budget=3000"; do
    n=$(( n + 1 )); cli "$QU" $arm >"$DIR/neg$n.on"; off "$QU" $arm >"$DIR/neg$n.off"
done
cli '`compute_total`' >"$DIR/dup.on"; off '`compute_total`' >"$DIR/dup.off"
( cd "$P" && "$BIN" . --no-cache --for='Who calls `pick_one`?' 2>/dev/null ) >"$DIR/ovl.on"
( cd "$M" && "$BIN" . --no-cache --for='Who calls `compute_total`?' 2>/dev/null ) >"$DIR/mac.on"

python3 - "$DIR" "$QS" <<'PY'
import os, re, sys
W = sys.argv[1]; bad = 0
# The unrouted question's own backtick spans, in question order. K3's membership and K3's E2 ordering are
# derived from THIS, never from a literal name list: the contract is "every name the question backticks
# rides", which is what ruling 87 restored, and it must not have to be re-edited when the selector moves.
QNAMES = re.findall(r'`([A-Za-z_]\w*)`', sys.argv[2])
def rd(n):
    p = os.path.join(W, n)
    return open(p, "rb").read().decode("latin-1") if os.path.exists(p) else ""
def say(ok, msg):
    global bad
    print("  %s  %s" % ("PASS" if ok else "FAIL", msg)); bad += 0 if ok else 1
KEY = re.compile(r'<bodies of="key"[^>]*>.*?</bodies>', re.S)
LEG = re.compile(r'<!-- bodies of=key:.*?-->', re.S)
READING = re.compile(r' bodies of=key: [^.]*?\(longer: truncated=1 lines= next=\)\.')
mask = lambda d: re.sub(r' est_tokens="\d+"', ' est_tokens="#"', d)
BODYRE = re.compile(r'<b ([^>]*)>(.*?)</b>', re.S)
def bodyrows(block):
    """every <b> of a bodies block as (name, path, line, cdata) -- the identity ruling 87 reasons about is (path, line)"""
    out = []
    for m in BODYRE.finditer(block):
        at = lambda k: (re.search(r'\b%s="([^"]*)"' % k, m.group(1)) or [None, ""])[1]
        out.append((at("n"), at("p"), at("l"), m.group(2)))
    return out
def served_elsewhere(doc, path, line, upto):
    """is this (path, line) carried by a <b> row OUTSIDE any key group, within the first `upto` bytes? (bodyServed's own test)"""
    stripped = KEY.sub(lambda m: " " * len(m.group(0)), doc)
    return any(p == path and l == line for _, p, l, _ in bodyrows(stripped[:upto]))
def blocks(d):
    """top-level children of the root (comments and elements), CDATA-safe, as (kind, name, begin, end)"""
    i = d.find(">", d.find("<ctx")) + 1; close = d.rfind("</ctx>"); out = []; depth = 0; start = None; name = None
    j = i
    while j < close:
        if d.startswith("<!--", j) and depth == 0:
            e = d.find("-->", j) + 3; out.append(("c", "", j, e)); j = e; continue
        if d.startswith("<![CDATA[", j):
            j = d.find("]]>", j) + 3; continue
        if d.startswith("<!--", j):
            j = d.find("-->", j) + 3; continue
        if d[j] == "<":
            e = d.find(">", j); tag = d[j:e + 1]
            if tag.startswith("</"):
                depth -= 1
                if depth == 0: out.append(("e", name, start, e + 1))
            elif tag.endswith("/>"):
                if depth == 0: out.append(("e", re.match(r"<([\w-]+)", tag).group(1), j, e + 1))
            else:
                if depth == 0: start = j; name = re.match(r"<([\w-]+)", tag).group(1)
                depth += 1
            j = e + 1; continue
        j += 1
    return out

# (K0) routed
ron, roff, rmcp = rd("r.on"), rd("r.off"), rd("r.mcp")
k = KEY.findall(ron)
say(len(k) == 1 and '<bodies of="key" shown="1" total="1" capped="0">' in k[0] and 'p="src/lib.c"' in k[0] and 'n="compute_total"' in k[0]
    and "int compute_total( int a )" in k[0] and "return a + 1;" in k[0] and "lib.h" not in k[0] and '<route from="for"' in ron,
    "(K0) routed who-calls carries one key body: the source definition in src/lib.c, never the bodyless lib.h declaration")
# (K1) placement + reading
root = re.search(r"<(callers|uses|impact)\b", re.sub(r"<!--.*?-->", "", ron, flags=re.S))
tagname = root.group(1) if root else "?"
say(bool(k) and ron.rstrip().endswith(k[0] + "</%s>" % tagname) and "bodies of=key:" in ron[:ron.find("<" + tagname)],
    "(K1) the key block is the routed root's last child, after the verb's rows; the compact legend defines bodies of=key")
# (K1n) coverage
nocom = lambda d: re.sub(r"<!--.*?-->", "", d, flags=re.S)
stripped = nocom(KEY.sub("", ron, count=1))
say(stripped == nocom(roff) and roff != "", "(K1n) routed ON minus the block == the RIPWIRE_NO_KEY_BODY=1 twin, byte for byte (legend comments aside)")
say(stripped[:-1] != nocom(roff), "(K1n) negative control: the same comparison fails when one byte is dropped")
# (K2) MCP parity
km = KEY.findall(rmcp)
say(len(km) == 1 and k and km[0] == k[0], "(K2) MCP `for` carries the same <bodies of=\"key\"> element as the CLI, byte for byte")
# (K3) unrouted placement
uon, uoff = rd("u.on"), rd("u.off")
B = blocks(uon)
first = next((x for x in B if x[0] == "e"), None)
idx = B.index(first) if first else -1
okp = first is not None and idx + 2 < len(B) and B[idx + 1][0] == "c" and uon[B[idx + 1][2]:].startswith("<!-- bodies of=key:") \
      and B[idx + 2][1] == "bodies" and uon[B[idx + 2][2]:].startswith('<bodies of="key"') and B[idx + 1][2] == first[3]
say(okp, "(K3) unrouted: the key group (legend, then <bodies of=\"key\">) sits directly after the first row block <%s>" % (first[1] if first else "?"))
ku = KEY.findall(uon)
# MEMBERSHIP, derived from the question and not from a literal list (R1b's fragility finding, endorsed by ruling 87's brief):
# pin THAT every backticked name rides, each once, not WHICH names they are -- so a selector change (SEL1 S1) cannot redden it.
urows = bodyrows(ku[0]) if len(ku) == 1 else []
unames = [n for n, _, _, _ in urows]
members = len(ku) == 1 and sorted(unames) == sorted(QNAMES) and len(set(unames)) == len(unames)
# each named body really is that definition (name-derived, replacing a pinned product signature string): its CDATA opens the
# definition of the name it claims.
defline = members and all(any(n == q and re.search(r'\b%s\s*\(' % re.escape(q), c) for n, _, _, c in urows) for q in QNAMES)
say(members and defline and unames == QNAMES[::-1] and len(QNAMES) == 2,
    "(K3) unrouted: every name the question backticks rides, each once, each carrying its own definition line, rule E2's symbol "
    "(the last code-shaped span) first -- question names %s, expected %s, got %s" % (QNAMES, QNAMES[::-1], unames))
ustrip = LEG.sub("", KEY.sub("", uon, count=1), count=1)
say(mask(ustrip) == mask(uoff) and uoff != "", "(K3n) unrouted ON minus the group == the twin (est_tokens= masked), byte for byte")
say(mask(ustrip)[:-1] != mask(uoff), "(K3n) negative control: the same comparison fails when one byte is dropped")
say(re.search(r' est_tokens="(\d+)"', uon) and re.search(r' est_tokens="(\d+)"', uoff)
    and int(re.search(r' est_tokens="(\d+)"', uon).group(1)) > int(re.search(r' est_tokens="(\d+)"', uoff).group(1)),
    "(K3) est_tokens= rises over the added bytes")
# (K4) pages
pages_on = [rd("pg%d.on" % i) for i in range(1, 7)]; pages_off = [rd("pg%d.off" % i) for i in range(1, 7)]
npg = lambda d: int(re.search(r' pages="(\d+)"', d).group(1)) if re.search(r' pages="(\d+)"', d) else 1
n_on, n_off = npg(pages_on[0]), npg(pages_off[0])
same = n_on == n_off and n_off >= 2
withkey = 0
for i in range(min(n_off, 6)):
    a, b = pages_on[i], pages_off[i]
    withkey += bool(KEY.search(a))
    same = same and mask(LEG.sub("", KEY.sub("", a, count=1), count=1)) == mask(b)
say(same and withkey == 1 and KEY.search(pages_on[0]), "(K4) %d pages at 12 KB either way; every ON page minus the group == the twin's page; the group rides page 1" % n_off)
say(rd("def.on") == pages_on[0], "(K4) the default page 1 is the spelled --page-bytes=12000:1 page, key group included")
# (K5) ceiling
big = KEY.findall(rd("big.on"))
m = re.search(r'<b [^>]*truncated="1"[^>]*>', big[0]) if big else None
say(bool(m) and re.search(r' lines="1-\d+/\d+"', m.group(0)) and re.search(r' next="--expand=[^"]*:big_function:\d+-\d+"', m.group(0))
    and len(big[0]) < 4600 and '<bodies of="key" shown="1" total="1" capped="1">' in big[0],
    "(K5) a body over 4000 B is cut and says so: truncated=1 lines=1-K/T, next= the --expand of the lines not shown, capped=1")
# (K6) cap
cap = KEY.findall(rd("cap.on"))
names = re.findall(r'<b [^>]*\bn="(\w+)"', cap[0]) if cap else []
# CB1 re-worded this arm in the commit that moved the knob, as PREREG_CB1_1119_v2.md M5 requires. It used to
# pin shown="2" total="3" capped="1" against kKeyBodyMax=2 and name the third symbol in next=. The cap is now 5
# -- DERIVED from GA1 DEV's p90 of gold functions per task (median 1, q75 3, p90 5, max 12; a cap of 2 could
# satisfy only 71.9% of tasks, 5 satisfies 94.4%) -- so all three ride and there is no third to point at. The
# arm still pins the SAME two properties it always pinned: every named symbol that fits is served, and rule
# E2's symbol leads. What it can no longer pin here is the overflow shape; that moves to K6b below, which uses
# SIX names so the cap of 5 is exercised rather than merely outnumbered.
say(bool(cap) and cap[0].startswith('<bodies of="key" shown="3" total="3"') and names == ["gamma_three", "alpha_one", "beta_two"],
    "(K6) three named symbols all ride under the cap of 5: shown=3 total=3, E2's symbol first (%s)" % names)
# (K6b) the overflow shape the old K6 used to pin, at the new cap: six names -> five bodies, capped=1, next= the sixth
cap6 = KEY.findall(rd("cap6.on"))
names6 = re.findall(r'<b [^>]*\bn="(\w+)"', cap6[0]) if cap6 else []
say(bool(cap6) and cap6[0].startswith('<bodies of="key" shown="5" total="6" capped="1"')
    and len(names6) == 5 and re.search(r'^<bodies [^>]*next="--expand=', cap6[0]),
    "(K6b) six named symbols: shown=5 total=6 capped=1, next= the sixth -- the cap of 5 bounds the block (%s; shell %s)"
    % (names6, cap6[0][:70] if cap6 else None))
# (K7) negative controls
labels = ["no backticks", "a span naming nothing", "a namesake flood (13 defs)", "a test-only definition", "--legend=first", "--signatures-only", "--token-budget=3000"]
for i, lab in enumerate(labels, 1):
    a, b = rd("neg%d.on" % i), rd("neg%d.off" % i)
    say(a != "" and a == b and "bodies of=\"key\"" not in a, "(K7) %s: byte-identical with and without the knob, no key block" % lab)
# (K12) THE CONTRACT ARM (ruling 87). Order matters: PROVE the page already serves the body, THEN require the key group to carry
# its own copy. A prohibition-shaped arm ("no key block") is free on unfixed code; this one asserts a positive that only the fix
# can produce, and it names the duplicate it demands so the red says what is missing.
don, doff = rd("dup.on"), rd("dup.off")
twinrow = next(((p, l) for n, p, l, _ in bodyrows(doff[:12000]) if n == "compute_total"), None)
say(twinrow is not None,
    "(K12) NON-VACUITY: the knob-off twin's page 1 does carry compute_total's body elsewhere, so this arm has something to "
    "duplicate (p=,l= %s)" % (twinrow,))
kd = KEY.findall(don)
krows = bodyrows(kd[0]) if len(kd) == 1 else []
dup = twinrow is not None and len(krows) == 1 and (krows[0][1], krows[0][2]) == twinrow and krows[0][0] == "compute_total"
say(dup and don != doff and "compute_total" in (krows[0][3] if krows else ""),
    "(K12) CONTRACT: the key group carries its own body of the definition page 1 already serves -- same p= and l= in both places, "
    "and the answer is therefore NOT the knob-off twin (twin row %s, key rows %s)" % (twinrow, [(n, p, l) for n, p, l, _ in krows]))
say(dup and served_elsewhere(don, krows[0][1], krows[0][2], 12000),
    "(K12) CONTRACT: and the duplicate is read back out of the DELIVERED answer -- the same (p=,l=) is served by a <b> row outside "
    "the key group on the same page, which is exactly what bodyServed used to veto")
# (K13) the disclosure triple is internally consistent. An invariant on the TAG ALONE: no count of our own enters it, so it
# holds whatever the fixture contains and fires on ANY filter-before-count, not only the one ruling 87 removed.
def triple(block):
    head = block[:block.find(">") + 1]
    g = lambda k: re.search(r'\b%s="(\d+)"' % k, head)
    val = lambda k: int(g(k).group(1)) if g(k) else -1
    return val("shown"), val("total"), val("capped"), ' next="' in head
NAMED6 = ("compute_total", "alpha_one", "beta_two", "gamma_three", "big_function", "run_main")
for tag, name in (("dup.on", "one name, unrouted"), ("tot3.on", "three names, unrouted"),
                  ("tot6.on", "six names, unrouted"), ("cap6.on", "six names, ROUTED (control: this path never read the page)")):
    blk = KEY.findall(rd(tag))
    if not blk:
        say(False, "(K13) %s: no key group at all, so the disclosure triple cannot be read (%s)" % (name, tag))
        continue
    sh, to, ca, nx = triple(blk[0])
    say(sh >= 0 and to >= 0 and ca >= 0 and sh <= to and (ca == 1) == (sh < to) and (ca == 1) == nx,
        "(K13) %s: shown=%d total=%d capped=%d next=%s -- capped=1 iff shown<total iff next= present, and shown<=total"
        % (name, sh, to, ca, nx))
# (K14) total= is the keyed-definition count known BY CONSTRUCTION (see the ARMS note), never a post-filter residue.
for tag, truth, want_shown, want_capped in (("tot3.on", 3, 3, 0), ("tot6.on", 6, 5, 1)):
    d = rd(tag)
    served = sorted({n for n, _, _, _ in bodyrows(KEY.sub(lambda m: " " * len(m.group(0)), d)[:12000]) if n in NAMED6})
    say(bool(served),
        "(K14) NON-VACUITY %s: page 1 serves %s elsewhere, so a filter-before-count had something to remove" % (tag, served))
    blk = KEY.findall(d)
    if not blk:
        say(False, "(K14) %s: no key group at all, so total= cannot be the keyed count (expected total=%d)" % (tag, truth))
        continue
    sh, to, ca, _ = triple(blk[0])
    say(to == truth and sh == want_shown and ca == want_capped,
        "(K14) %s: total=%d is the %d definitions the question's names place in src/, shown=%d capped=%d (expected total=%d shown=%d capped=%d)"
        % (tag, to, truth, sh, ca, truth, want_shown, want_capped))
# (K10) overload ordering
ov = KEY.findall(rd("ovl.on"))
bl = re.findall(r'<b [^>]*\bl="(\d+)"', ov[0]) if ov else []
say(bool(ov) and bl and "if isinstance(x, int):" in ov[0].split("</b>")[0], "(K10) the multi-line pick_one takes the first slot ahead of the @overload stubs (l=%s)" % bl)
# (K11) warned routed: one key block
mac = rd("mac.on")
say('warn="1"' in mac and 'page1="1"' in mac and len(KEY.findall(mac)) == 1 and mac.find('<bodies of="key"') < mac.find("<ctx task="),
    "(K11) a warned routed answer with a carried page holds one key block, ahead of the carried page")
# (K9)
say(ron == rd("r.on2") and uon == rd("u.on2"), "(K9) two runs byte-identical (routed, unrouted)")
sys.exit(1 if bad else 0)
PY
[ $? -eq 0 ] || fail=1
if command -v xmllint >/dev/null 2>&1; then
    for f in r.on u.on big.on cap.on cap6.on pg1.on r.mcp; do
        xmllint --noout "$DIR/$f" 2>/dev/null
        say $? "(K9) $f is well formed" "(K9) xmllint rejects $f"
    done
fi
[ "$fail" = 0 ] && echo "forkeybodycheck: ALL PASS" || echo "forkeybodycheck: FAILED"
exit "$fail"
