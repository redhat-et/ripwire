#!/usr/bin/env bash
# forpathfusecheck.sh — the PATH-TOKEN RANK FUSION of a routed --for head (lane rank-fusion, train 33; src/forpathfuse.h
# forPathFusion / forPathFusionOn, src/serialize.h kForPathFusedNote, <sigs path_fused=N>).
#
# THE CONTRACT THIS PINS (arms tagged [P] are RED on the base binary 9eaefd6d; [G] arms are twins and near-miss negatives that
# hold on both binaries and must keep holding — PROCESS rule 4):
#   WHAT   where the head round-robin applies, r=2..8 follow a fused file order: the score head's distinct files plus a second
#          list — the query's subtokens found in a file's path (basename stem w 1, a directory w 1/2, idf over eligible files) —
#          by reciprocal rank (k 60, alpha 0.1). r=1 never moves. A fused file whose best row was outside the shown rows brings
#          that ONE row in (total= counts it, nothing is removed). <sigs path_fused=N> + its present-only legend reading.
#   WHO    exempt, byte-identical to RIPWIRE_NO_PATH_FUSION=1: everything the head round-robin exempts (a budget, a question
#          naming a file, --no-route, the name-exact route, RIPWIRE_NO_HEAD_RR=1), a question whose words are in no eligible
#          path. Ineligible paths (a tests/ tree, a docs/ tree, prose) never enter through the path list; a path word must be a
#          WHOLE subtoken (copying/modes.ts is no match for "copy mode").
#
# Arms:
#   F1 [P] the path file (src/copy/mode.ts, outside the 40 score rows) enters the head-8; r=1 unchanged; total= = twin + 1; the
#          shown rows are the twin's plus that file's best row; path_fused= present with its reading; the twin carries neither
#   F2 [P] --json: the XML ON order, "path_fused" equal to the XML attribute;  F2m [P] MCP `for`: the same order, path_fused=
#   F3 [G] exempt, byte-identical to RIPWIRE_NO_PATH_FUSION=1: --token-budget=1200, a question naming src/engine.ts, --no-route,
#          RIPWIRE_NO_HEAD_RR=1, a question with no word in any path
#   F4 [G] ineligible or partial paths, byte-identical to the twin: tests/copy/mode.ts, docs/copy/mode.ts, copying/modes.ts
#   X1 [G] determinism   X2 [G] xmllint well-formed   X3 [G] no "--" inside a legend comment
#
# Usage:  bash test/forpathfusecheck.sh [BIN]   |   RIPWIRE_BIN=asan/ripwire bash test/forpathfusecheck.sh
# BIN is $1, else RIPWIRE_BIN, else build/ripwire; the first output line names the binary used. Exits non-zero on any failure.

set -u
ROOT="$( cd "$( dirname "$0" )/.." && pwd )"
. "$ROOT/test/lib/clean-env.sh"
unset RIPWIRE_NO_HEAD_RR RIPWIRE_NO_PATH_FUSION RIPWIRE_NO_BODY_FOLD RIPWIRE_NO_DOCS_AFTER_CODE
BIN="${1:-${RIPWIRE_BIN:-$ROOT/build/ripwire}}"
[ "${BIN#/}" = "$BIN" ] && BIN="$ROOT/$BIN"
echo "forpathfusecheck: BIN=$BIN"
fail=0
ok(){ printf '  PASS  %s\n' "$*" || { fail=1; printf '  FAIL  could not write the PASS line for: %s\n' "$*"; }; return 0; }
no(){ printf '  FAIL  %s\n' "$*"; fail=1; }
[ -x "$BIN" ] || { echo "no ripwire binary at $BIN — build first"; exit 2; }
command -v python3 >/dev/null 2>&1 || { echo "python3 required"; exit 2; }

TMP="$( mktemp -d )"; trap 'rm -rf "$TMP"' EXIT
export HOME="$TMP/home"; mkdir -p "$HOME"

Q="How does copy mode work when the buffer selection moves?"
# fixture: one file floods the score head (45 rows matching the question's words), three small helpers, and one file whose PATH
# holds the question's words but whose one function matches a single word weakly — rank > 40 by score, first by path.
mkfix(){ local d="$1" pathfile="$2"; mkdir -p "$d/src" "$( dirname "$d/$pathfile" )"
    { for i in $( seq 1 45 ); do
        printf 'export function selectionMoveBuffer%s(buffer: number[], selection: number): number {\n' "$i"
        printf '  // move the buffer selection: copy the selection, then move the buffer when the selection moves\n'
        printf '  return buffer[selection] + %s;\n}\n' "$i"
      done; } >"$d/src/engine.ts"
    printf 'export function bufferSize(buffer: number[]): number {\n  return buffer.length;\n}\n' >"$d/src/size.ts"
    printf 'export function selectionStart(selection: number): number {\n  return selection;\n}\n' >"$d/src/start.ts"
    printf 'export function movesCount(moves: number): number {\n  return moves;\n}\n' >"$d/src/count.ts"
    printf 'export function enterTool(state: number): number {\n  // the selection\n  return state + 1;\n}\n' >"$d/$pathfile"; }
mkfix "$TMP/f" src/copy/mode.ts
mkfix "$TMP/t" tests/copy/mode.ts
mkfix "$TMP/dd" docs/copy/mode.ts
mkfix "$TMP/p" src/copying/modes.ts

# run OUT ROOTDIR TWIN(0|1) ARGS... — one call; TWIN=1 sets RIPWIRE_NO_PATH_FUSION=1; RUN_ENV adds NAME=VALUE words; rc kept beside
run(){ local out="$1" dir="$2" off="$3"; shift 3
    ( cd "$dir" || exit 97
      if [ "$off" = 1 ]; then env ${RUN_ENV:-} RIPWIRE_NO_PATH_FUSION=1 "$BIN" "$dir" --no-cache "$@"; else env ${RUN_ENV:-} "$BIN" "$dir" --no-cache "$@"; fi ) >"$out" 2>"$out.err"
    printf '%s' "$?" >"$out.rc"; }
ran(){ [ "$( cat "$1.rc" )" = 0 ] && [ -s "$1" ] && return 0; no "$2: rc=$( cat "$1.rc" ) bytes=$( wc -c <"$1" | tr -d ' ' )"; return 1; }

cat > "$TMP/chk.py" <<'PY'
import html, json, re, sys
cmd, args = sys.argv[1], sys.argv[2:]
def load(p): return open(p, "rb").read().decode("utf-8", "replace")
def attrs(s): return dict((k, html.unescape(v)) for k, v in re.findall(r'(\w+)="([^"]*)"', s))
def rows(t):
    out = []
    for m in re.finditer(r'<d ([^>]*)>', t):
        a = attrs(m.group(1))
        if "r" in a: out.append((int(a["r"]), a.get("p", ""), a.get("n", "")))
    return [(p, n) for r, p, n in sorted(out)]
def sigs(t):
    m = re.search(r'<sigs\b([^>]*)>', t); return attrs(m.group(1)) if m else {}
def legend(t): return " ".join(re.findall(r'<!--(.*?)-->', t, re.S))
def fail(msg): print(msg); sys.exit(1)
if cmd == "fused":         # ON TWIN PATH — PATH enters the head-8, r=1 kept, one row added, path_fused= + reading on ON only
    on, off, path = load(args[0]), load(args[1]), args[2]
    ron, roff = rows(on), rows(off)
    if not ron or not roff: fail("no rows")
    if path in [p for p, n in roff]: fail("premise: %s is already a twin row" % path)
    if path not in [p for p, n in ron[:8]]: fail("%s not in the head-8: %s" % (path, [p for p, n in ron[:8]]))
    if ron[0] != roff[0]: fail("r=1 moved: %s -> %s" % (roff[0], ron[0]))
    added = set(ron) - set(roff); gone = set(roff) - set(ron)
    if gone or len(added) != 1 or list(added)[0][0] != path: fail("rows: added %s, removed %s" % (sorted(added), sorted(gone)))
    son, soff = sigs(on), sigs(off)
    if len(ron) != len(roff) + 1: fail("%d rows vs twin %d" % (len(ron), len(roff)))
    if ("total" in son) != ("total" in soff) or ("total" in son and int(son["total"]) != int(soff["total"]) + 1):
        fail("total= %s vs twin %s" % (son.get("total"), soff.get("total")))
    if not son.get("path_fused", "").isdigit() or int(son["path_fused"]) < 1: fail("path_fused= %r" % son.get("path_fused"))
    if "path_fused=N:" not in legend(on): fail("path_fused= without its reading")
    if "path_fused" in soff or "path_fused=N:" in legend(off): fail("the twin carries path_fused=")
    print("%s at r=%d, path_fused=%s, rows %d -> %d" % (path, [p for p, n in ron].index(path) + 1, son["path_fused"], len(roff), len(ron)))
elif cmd == "json":        # JSON XMLON — the JSON rows in the XML ON order, "path_fused" == the XML attribute
    j = json.loads(load(args[0])); x = load(args[1])
    def walk(o):
        if isinstance(o, dict):
            if "sigs" in o and isinstance(o["sigs"], list): return o
            for v in o.values():
                r = walk(v)
                if r is not None: return r
        return None
    b = walk(j)
    if b is None: fail("no sigs array")
    jr = [(s.get("p", ""), s.get("n", "")) for s in b["sigs"]]
    if jr[:8] != rows(x)[:8]: fail("json head %s != xml head %s" % (jr[:8], rows(x)[:8]))
    jp = re.search(r'"path_fused":(\d+)', load(args[0]))
    if not jp or jp.group(1) != sigs(x).get("path_fused"): fail("path_fused json %s vs xml %s" % (jp and jp.group(1), sigs(x).get("path_fused")))
    print("json head == xml head, path_fused=%s" % jp.group(1))
elif cmd == "mcp":         # MCPOUT XMLON — the MCP answer's head-8 in the XML order, path_fused= present
    body = ""
    for line in load(args[0]).splitlines():
        try: o = json.loads(line)
        except ValueError: continue
        if o.get("id") == 2: body = "".join(c.get("text", "") for c in o.get("result", {}).get("content", []))
    if not body: fail("no MCP for answer")
    if rows(body)[:8] != rows(load(args[1]))[:8]: fail("mcp head %s != xml head %s" % (rows(body)[:8], rows(load(args[1]))[:8]))
    if "path_fused=" not in body: fail("no path_fused= on the MCP answer")
    print("mcp head == xml head")
elif cmd == "nodash":
    bad = [c for c in re.findall(r'<!--(.*?)-->', load(args[0]), re.S) if "--" in c]
    if bad: fail("a legend comment holds --")
PY
chk(){ local label="$1"; shift; local msg; if msg="$( python3 "$TMP/chk.py" "$@" 2>&1 )"; then ok "$label: $msg"; else no "$label: $msg"; fi; }

# ── F1: the path file enters the head ────────────────────────────────────────────────────────────────────────────────────
run "$TMP/f.on" "$TMP/f" 0 --for="$Q"; run "$TMP/f.off" "$TMP/f" 1 --for="$Q"
ran "$TMP/f.on" F1 && ran "$TMP/f.off" "F1 (twin)" && chk "F1 the path file enters the head, one row added, r=1 kept" fused "$TMP/f.on" "$TMP/f.off" src/copy/mode.ts

# ── F2: --json and MCP twins ────────────────────────────────────────────────────────────────────────────────────────────
run "$TMP/f.json" "$TMP/f" 0 --for="$Q" --json
ran "$TMP/f.json" F2 && chk "F2 --json: the XML order, path_fused" json "$TMP/f.json" "$TMP/f.on"
mkdir -p "$TMP/mcphome"
printf '%s\n' '{"jsonrpc":"2.0","id":1,"method":"initialize"}' \
              '{"jsonrpc":"2.0","id":2,"method":"tools/call","params":{"name":"for","arguments":{"path":"'"$TMP/f"'","task":"'"$Q"'"}}}' \
    | ( cd "$TMP/f" || exit 97; TMPDIR="$TMP/mcphome" "$BIN" --mcp ) >"$TMP/f.mcp" 2>/dev/null
printf '%s' "$?" >"$TMP/f.mcp.rc"
ran "$TMP/f.mcp" F2m && chk "F2m MCP for: the XML order, path_fused=" mcp "$TMP/f.mcp" "$TMP/f.on"

# ── F3/F4: exempt or ineligible answers are the twin byte for byte ────────────────────────────────────────────────────────
same(){ local label="$1" dir="$2"; shift 2
    run "$TMP/x.on" "$dir" 0 "$@"; run "$TMP/x.off" "$dir" 1 "$@"
    ran "$TMP/x.on" "$label" && ran "$TMP/x.off" "$label (twin)" || return 0
    if cmp -s "$TMP/x.on" "$TMP/x.off" && ! grep -q 'path_fused' "$TMP/x.on"; then ok "$label: byte-identical to RIPWIRE_NO_PATH_FUSION=1"
    else no "$label: differs from RIPWIRE_NO_PATH_FUSION=1 (or carries path_fused=)"; fi; }
same "F3 --token-budget=1200" "$TMP/f" --for="$Q" --token-budget=1200
same "F3 a question naming an indexed file" "$TMP/f" --for="How does src/engine.ts copy mode work when the buffer selection moves?"
same "F3 --no-route" "$TMP/f" --for="$Q" --no-route
same "F3 a question with no word in any path" "$TMP/f" --for="How does the buffer selection move?"
RUN_ENV="RIPWIRE_NO_HEAD_RR=1"; same "F3 RIPWIRE_NO_HEAD_RR=1" "$TMP/f" --for="$Q"; RUN_ENV=""
same "F4 a tests/ path" "$TMP/t" --for="$Q"
same "F4 a docs/ path" "$TMP/dd" --for="$Q"
same "F4 copying/modes.ts is no whole-subtoken match" "$TMP/p" --for="$Q"

# ── X: determinism, well-formedness, legend comments ────────────────────────────────────────────────────────────────────
run "$TMP/f.on2" "$TMP/f" 0 --for="$Q"
if cmp -s "$TMP/f.on" "$TMP/f.on2"; then ok "X1 determinism"; else no "X1 two runs differ"; fi
if command -v xmllint >/dev/null 2>&1; then
    if xmllint --noout "$TMP/f.on" 2>/dev/null; then ok "X2 xmllint well-formed"; else no "X2 xmllint rejects the fused answer"; fi
else echo "  SKIP  X2 xmllint not installed"; fi
chk "X3 no -- in a legend comment" nodash "$TMP/f.on"

[ "$fail" = 0 ] && echo "forpathfusecheck: PASS" || echo "forpathfusecheck: FAIL"
exit "$fail"
