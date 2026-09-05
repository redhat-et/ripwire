#!/usr/bin/env bash
# sliceflowsenscheck.sh — gate for the FLOW-SENSITIVE reaching definitions of --slice=SYM:VAR (docs/EVALS.md,
# "Flow-sensitive slice in the small — reaching definitions with kills and joins, PRE-REGISTERED 2026-09-03").
# A def of VAR is killed by the next unconditional def on every path and the defs on merging paths JOIN
# (if/elif/else, switch, loop back-edges, try handlers, for/while-else, match, #ifdef); every USE row prints
# rd= — the exact lines of the defs that reach it — and the root says which rule is in force (reach="cfg" |
# "linear"). --slice-flow, --since and the MCP verb consume the same reach table the rows print.
#
# RED-FIRST PROOF SHAPE: the baseline binary prints no rd= and no reach= and joins nothing, so arms (1)-(7)
# all fail against it on slice-SPECIFIC bytes; none asserts a bare exit code.
#
# Arms:
#   (0)  fixture composition floor: >=10 kill, >=10 join, >=10 straight-line functions in expect.tsv
#   (1)  THE SENTINEL: every use row of every (file, fn, var) in test/sliceflowsensfix/expect.tsv carries
#        exactly the expected rd= (both directions), and every source-order edge that DISAPPEARED is
#        explained by a verified reason (exit=K / branch=K: K strictly between the vanished def and the use;
#        unit=K / try=K: the folding statement or the try at K, at or before the def — and the fixture line K
#        reads as that kind of statement) — no unexplained, no spurious reason
#   (2)  reach="cfg" on a C++ and a Python root, reach="linear" on the JS control
#   (3)  legend honesty: "no flow sensitivity" is GONE; rd= and reach= defined; the unit rule and each
#        per-construct disclosure named (goto, lambda/nested body, alias, global/nonlocal, try, linear)
#   (4)  --legend=compact defines rd= and reach= too, rows byte-identical to the full tier
#   (5)  --slice-flow inherits: backward from y in cj11 reaches BOTH defs of x at d=1
#   (6)  --since inherits: wrapping a def in an `if` ADDS the join's edge (edges_added="1")
#   (7)  MCP parity: the `slice` verb's payload is byte-identical to the CLI on the fixture root
#   (8)  determinism x2 on a C++ and a Python run
#   (9)  xmllint well-formedness (plain, flow, since)
#
# Usage:  RIPWIRE_BIN=build/ripwire bash test/sliceflowsenscheck.sh   |   bash test/sliceflowsenscheck.sh path/to/ripwire

set -u
ROOT="$( cd "$( dirname "$0" )/.." && pwd )"
BIN="${1:-${RIPWIRE_BIN:-$ROOT/build/ripwire}}"
[ "${BIN#/}" = "$BIN" ] && BIN="$ROOT/$BIN"
FIX="$ROOT/test/sliceflowsensfix"
EXPECT="$FIX/expect.tsv"
fail=0
ok(){ printf '  PASS  %s\n' "$*"; }
no(){ printf '  FAIL  %s\n' "$*"; fail=1; }

[ -x "$BIN" ] || { echo "no ripwire binary at $BIN — build first"; exit 2; }
[ -f "$EXPECT" ] || { echo "no expectations at $EXPECT"; exit 2; }
echo "sliceflowsenscheck: BIN=$BIN"

TMP="$( mktemp -d )"; trap 'rm -rf "$TMP"' EXIT

run(){ ( cd "$FIX" && "$BIN" . "$@" --no-cache 2>/dev/null ); }
elem(){ printf '%s' "$1" | sed 's/.*--><slice/<slice/'; }
attr(){ printf '%s' "$( elem "$1" )" | grep -oE "^<slice [^>]*" | grep -oE "$2=\"[^\"]*\"" | head -1; }
legend(){ printf '%s' "$1" | sed 's/--><slice.*//'; }

# ── (0) + (1): the sentinel, scored by one python pass over expect.tsv ─────────────────────────────
cat > "$TMP/score.py" <<'PY'
import re, subprocess, sys
fix, binp, expect = sys.argv[1], sys.argv[2], sys.argv[3]
rows = []
for ln in open(expect, encoding="utf-8"):
    if not ln.strip() or ln.startswith("#"):
        continue
    f = ln.rstrip("\n").split("\t")
    while len(f) < 7:
        f.append("")
    rows.append(dict(file=f[0], fn=f[1], var=f[2], cls=f[3], line=int(f[4]), rd=f[5], reason=f[6].strip()))
groups = []
for r in rows:
    key = (r["file"], r["fn"], r["var"])
    if key not in groups:
        groups.append(key)
classes = {}
for r in rows:
    classes.setdefault(r["cls"], set()).add(r["fn"])
for c in ("kill", "join", "straight", "disclosed", "linear"):
    print("CLASS %s fns=%d rows=%d" % (c, len(classes.get(c, ())), sum(1 for r in rows if r["cls"] == c)))
EXIT = re.compile(r"\b(return|break|continue|throw|raise|goto)\b")
BRANCH = re.compile(r"\b(else|elif|if|case|default|switch|match|except)\b")
UNIT = re.compile(r"\b(def|lambda|class)\b|\[ ?& ?\]")
TRY = re.compile(r"\btry\b")
wrong = 0; checked = 0; edges = 0; explained = 0; unexplained = 0; spurious = 0
srcs = {}
for (file, fn, var) in groups:
    out = subprocess.run([binp, ".", "--slice=%s:%s:%s" % (file, fn, var), "--no-cache"], cwd=fix,
                         capture_output=True, text=True).stdout
    body = out.split("--><slice", 1)[-1]
    found = []
    for m in re.finditer(r'<s l="(\d+)" k="(\w+)" t="([\w-]+)"((?: [a-z_]+="[^"]*")*)>', body):
        attrs = dict(re.findall(r' ([a-z_]+)="([^"]*)"', m.group(4)))
        found.append(dict(line=int(m.group(1)), k=m.group(2), pp=attrs.get("pp") == "1", rd=attrs.get("rd")))
    exp = {r["line"]: r for r in rows if (r["file"], r["fn"], r["var"]) == (file, fn, var)}
    seen = set()
    if file not in srcs:
        srcs[file] = open(fix + "/" + file, encoding="utf-8").read().split("\n")
    for row in found:
        if row["k"] not in ("use", "both"):
            continue
        checked += 1
        e = exp.get(row["line"])
        if e is None:
            wrong += 1; print("WRONG %s:%s:%s l=%d has no expectation (rd=%s)" % (file, fn, var, row["line"], row["rd"])); continue
        seen.add(row["line"])
        if row["rd"] != e["rd"]:
            wrong += 1; print("WRONG %s:%s:%s l=%d rd=%s expected %s" % (file, fn, var, row["line"], row["rd"], e["rd"]))
        else:
            edges += 0 if e["rd"] == "-" else len(e["rd"].split(","))
        # the source-order rule, re-derived from the tool's own rows: last unconditional def before the use + pp defs after it
        old = set()
        for d in found:
            if d["line"] >= row["line"] or d["k"] not in ("def", "both"):
                continue
            if not d["pp"]:
                old = set()
            old.add(d["line"])
        new = set() if e["rd"] == "-" else set(int(x) for x in e["rd"].split(","))
        gone = sorted(old - new)
        reason = e["reason"]
        if gone:
            m = re.fullmatch(r"(exit|branch|unit|try)=(\d+)", reason)
            okr = False
            if m:
                k = int(m.group(2)); text = srcs[file][k - 1] if 0 < k <= len(srcs[file]) else ""
                kind = m.group(1)
                pat = EXIT if kind == "exit" else BRANCH if kind == "branch" else UNIT if kind == "unit" else TRY
                placed = all(k <= d < row["line"] for d in gone) if kind in ("unit", "try") else all(d < k < row["line"] for d in gone)
                okr = placed and bool(pat.search(text))
            if okr:
                explained += len(gone)
            else:
                unexplained += len(gone); print("UNEXPLAINED %s:%s:%s l=%d lost source-order def(s) %s reason=%r" % (file, fn, var, row["line"], gone, reason))
        elif reason:
            spurious += 1; print("SPURIOUS %s:%s:%s l=%d reason=%r but no source-order edge disappeared" % (file, fn, var, row["line"], reason))
    for line, e in exp.items():
        if line not in seen:
            wrong += 1; print("WRONG %s:%s:%s expected a use row at l=%d, none emitted" % (file, fn, var, line))
print("SENTINEL groups=%d use_rows=%d edges=%d wrong=%d explained=%d unexplained=%d spurious=%d" % (len(groups), checked, edges, wrong, explained, unexplained, spurious))
PY
python3 "$TMP/score.py" "$FIX" "$BIN" "$EXPECT" >"$TMP/score.out" 2>&1
grep -v '^CLASS\|^SENTINEL' "$TMP/score.out" | head -20
for c in kill join straight; do
    n="$( grep -oE "^CLASS $c fns=[0-9]+" "$TMP/score.out" | grep -oE '[0-9]+$' )"
    [ "${n:-0}" -ge 10 ] && ok "(0) fixture composition: $c functions = $n (>= 10)" || no "(0) fixture composition: $c functions = ${n:-0} (< 10)"
done
S="$( grep '^SENTINEL' "$TMP/score.out" )"
printf '  INFO  %s\n' "$S"
W="$( printf '%s' "$S" | grep -oE 'wrong=[0-9]+' | cut -d= -f2 )"
U="$( printf '%s' "$S" | grep -oE 'unexplained=[0-9]+' | cut -d= -f2 )"
P="$( printf '%s' "$S" | grep -oE 'spurious=[0-9]+' | cut -d= -f2 )"
R="$( printf '%s' "$S" | grep -oE 'use_rows=[0-9]+' | cut -d= -f2 )"
[ -n "$S" ] && [ "${W:-1}" = 0 ] && [ "${R:-0}" -ge 30 ] \
    && ok "(1) sentinel: 0 wrong rd= across $R use rows" \
    || no "(1) sentinel: wrong=${W:-?} of ${R:-0} use rows (see WRONG lines above)"
[ -n "$S" ] && [ "${U:-1}" = 0 ] && [ "${P:-1}" = 0 ] \
    && ok "(1) every disappeared source-order edge carries a verified exit=/branch= reason, none spurious" \
    || no "(1) disappearances: unexplained=${U:-?} spurious=${P:-?}"

# ── (2) reach= per family ───────────────────────────────────────────────────────────────────────────
C="$( run --slice=joins.cpp:cj01:x )"
Y="$( run --slice=joins.py:pj01:x )"
J="$( run --slice=linear.js:lj01:x )"
[ "$( attr "$C" reach )" = 'reach="cfg"' ] && [ "$( attr "$Y" reach )" = 'reach="cfg"' ] \
    && ok '(2) C++ and Python roots carry reach="cfg"' \
    || { no '(2) expected reach="cfg" on the C++ and Python roots'; elem "$C" | head -c 300; echo; }
[ "$( attr "$J" reach )" = 'reach="linear"' ] \
    && ok '(2) the JS control carries reach="linear" (source-order rule, disclosed)' \
    || no '(2) expected reach="linear" on the JS root'

# ── (3) legend honesty ──────────────────────────────────────────────────────────────────────────────
L="$( legend "$C" )"
printf '%s' "$L" | grep -q 'no flow sensitivity' \
    && no '(3) the legend still says "no flow sensitivity"' \
    || ok '(3) "no flow sensitivity" is gone from the legend'
miss=""
for phrase in 'rd=' 'reach=' 'STATEMENT' 'goto' 'lambda' 'alias' 'global' 'try' 'linear' 'kill' 'join'; do
    printf '%s' "$L" | grep -qi -- "$phrase" || miss="$miss $phrase"
done
[ -z "$miss" ] && ok '(3) legend defines rd=/reach=, states the statement unit and names each disclosed construct' \
               || no "(3) legend omits:$miss"

# ── (4) compact tier ────────────────────────────────────────────────────────────────────────────────
K="$( run --slice=joins.cpp:cj01:x --legend=compact )"
printf '%s' "$( legend "$K" )" | grep -q 'rd=' && printf '%s' "$( legend "$K" )" | grep -q 'reach=' \
    && ok '(4) compact legend defines rd= and reach=' \
    || no '(4) compact legend must define rd= and reach='
[ "$( elem "$C" | sed 's/ schema="[^"]*"//' )" = "$( elem "$K" | sed 's/ schema="[^"]*"//' )" ] \
    && ok '(4) compact rows are byte-identical to the full tier' \
    || no '(4) compact tier changed the rows'

# ── (5) --slice-flow inherits the reach table ──────────────────────────────────────────────────────
FB="$( run --slice=joins.cpp:cj11:y --slice-flow=back )"
elem "$FB" | grep -q '<s l="137" k="def" t="decl" v="x" d="1" f="142">' && elem "$FB" | grep -q '<s l="140" k="def" t="assign" v="x" d="1" f="142">' \
    && ok '(5) backward from y reaches BOTH defs of x (l=137 and l=140) at d=1 — the join, inherited' \
    || { no '(5) expected v="x" rows at l=137 and l=140, both d="1" f="142"'; elem "$FB"; echo; }

# ── (6) --since inherits: a def wrapped in an if ADDS the join edge ────────────────────────────────
G(){ git -C "$1" -c user.email=g@t -c user.name=g -c commit.gpgsign=false -c init.defaultBranch=main "${@:2}"; }
SR="$TMP/since"; mkdir -p "$SR/src"; git init -q "$SR" 2>/dev/null
printf 'int f( int a )\n{\n    int x = 1;\n    x = 2;\n    return x;\n}\n' > "$SR/src/s.cpp"
G "$SR" add -A; G "$SR" commit -q -m v1
printf 'int f( int a )\n{\n    int x = 1;\n    if( a )\n    {\n        x = 2;\n    }\n    return x;\n}\n' > "$SR/src/s.cpp"
G "$SR" add -A; G "$SR" commit -q -m v2
SD="$( cd "$SR" && "$BIN" . --slice=f:x --since=HEAD~1 --no-cache 2>/dev/null )"
printf '%s' "$SD" | grep -q 'edges_added="1"' && printf '%s' "$SD" | grep -q '<se op="+" d="0" u="2" dl="3" ul="8"/>' \
    && ok '(6) --since reports the join: the pre-if def now reaches the return (edges_added="1", dl="3" ul="8")' \
    || { no '(6) expected edges_added="1" with <se op="+" d="0" u="2" dl="3" ul="8"/>'; printf '%s\n' "$SD" | sed 's/.*--><slice/<slice/'; }
printf '%s' "$SD" | sed 's/--><slice.*//' | grep -q 'no flow sensitivity' \
    && no '(6) the --since legend still says "no flow sensitivity"' \
    || ok '(6) the --since legend no longer claims "no flow sensitivity"'
printf '%s' "$SD" | sed 's/--><slice.*//' | grep -q 'reach=' \
    && ok '(6) the --since legend points at the root reach= rule' \
    || no '(6) the --since legend must name the reach= rule its edges follow'

# ── (7) MCP parity ──────────────────────────────────────────────────────────────────────────────────
mcp_call() { printf '%s\n' "$@" | ( cd "$FIX" && "$BIN" --mcp 2>/dev/null ); }
MCP="$( mcp_call '{"jsonrpc":"2.0","id":1,"method":"initialize"}' \
                 '{"jsonrpc":"2.0","id":2,"method":"tools/call","params":{"name":"slice","arguments":{"path":".","symbol":"joins.cpp:cj11:y","flow":"back"}}}' \
        | tail -1 | python3 -c 'import sys,json; r=json.load(sys.stdin); print(r["result"]["content"][0]["text"] if "result" in r else "__ERROR__")' )"
# M1 RE-PIN (terminality round A, 2026-09-05): the MCP legend default is compact, so the CLI operand of this
# comparison is the compact one — compact <-> compact, the posture both surfaces actually serve. $FB (full)
# stays exactly as it is for arms (5) and (6), which read the FULL legend's wording; only this arm's operand
# moves, so nothing else in the file is re-calibrated.
FBC="$( run --slice=joins.cpp:cj11:y --slice-flow=back --legend=compact )"
[ -n "$MCP" ] && [ "$MCP" = "$FBC" ] \
    && ok '(7) the MCP slice payload is byte-identical to the CLI on the fixture (rd= and reach= included)' \
    || { no '(7) MCP and CLI slice payloads differ on the fixture'; printf '%s\n' "$MCP" | head -c 400; echo; }

# ── (8) determinism ─────────────────────────────────────────────────────────────────────────────────
C2="$( run --slice=joins.cpp:cj01:x )"; Y2="$( run --slice=joins.py:pj01:x )"
[ "$C" = "$C2" ] && [ "$Y" = "$Y2" ] && ok '(8) determinism x2 (C++ and Python runs byte-identical)' || no '(8) output differs between runs'

# ── (9) well-formedness ─────────────────────────────────────────────────────────────────────────────
if command -v xmllint >/dev/null 2>&1; then
    { printf '%s' "$C" | xmllint --noout - 2>/dev/null && printf '%s' "$FB" | xmllint --noout - 2>/dev/null && printf '%s' "$SD" | xmllint --noout - 2>/dev/null; } \
        && ok '(9) xmllint: plain, flow and since documents well-formed' \
        || no '(9) xmllint rejected a slice document'
else
    printf '  SKIP  (9) xmllint not installed\n'
fi

[ "$fail" = 0 ] && { echo "sliceflowsenscheck: ALL PASS"; exit 0; } || { echo "sliceflowsenscheck: FAIL"; exit 1; }
