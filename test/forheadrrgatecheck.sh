#!/usr/bin/env bash
# forheadrrgatecheck.sh — HEAD-RR-GATE (card B34): the head round-robin lifts a file's best row into r=1..8 only when that
# row's OWN lens rank (its place in the (score desc, id asc) order, the r= it holds with RIPWIRE_NO_HEAD_RR=1) is <= 8
# (src/serialize.h kHeadRoundRobinLiftMaxLensRank, headRoundRobinOrder). A file whose best row ranks past 8 gets no head slot;
# the slot goes to the next row in score order. RIPWIRE_NO_HEAD_RR_GATE=1 is the A/B handle (the round-robin before the gate).
#
# Arms ([P] RED on main 74456897f, [G] hold on both binaries):
#   B1 [P] generated tree, 8 strong rows in one file + countJobs in another at lens rank 9: countJobs keeps r=9, and the
#          answer is byte-identical to RIPWIRE_NO_HEAD_RR=1 (nothing moved, no files_first=)
#   B2 [G] the same tree with 7 strong rows (countJobs at lens rank 8, the bar itself): countJobs is lifted to r=2, files_first= set
#   B3 [G] RIPWIRE_NO_HEAD_RR_GATE=1 on the 8-row tree: countJobs is lifted to r=2 again (the pre-gate round-robin)
#   B4 [P] --json and MCP `for` on the 8-row tree: countJobs keeps r=9 there too (one selection for every surface)
#   B5 [G] MCP `for` on the 7-row tree: countJobs is lifted to r=2
#   M1 [P] test/forheadrrfix/mono: the answer is the GATED round-robin of its RIPWIRE_NO_HEAD_RR=1 order (independent model);
#          schedulerWorkerCount (lens rank 11) keeps r=11, and the ungated model differs (the fixture exercises the gate)
#   M2 [G] test/forheadrrfix/pair: run_scheduled_jobs (lens rank 7) is still lifted to r=2 (the gated model)
#   X1 [G] determinism (two runs byte-identical)   X2 [G] xmllint well-formed
#
# The trees of B1..B5 are generated at test time (nothing committed for whole-repo runs to see).
# Usage:  bash test/forheadrrgatecheck.sh [BIN]   |   RIPWIRE_BIN=asan/ripwire bash test/forheadrrgatecheck.sh
# BIN is $1, else RIPWIRE_BIN, else build/ripwire; the first output line names the binary used. Exits non-zero on any failure.

set -u
# SIBLING-DEMOTE (forsiblingdemote.h) turns deep same-file rows into <t> pointers; this gate reads the head order of the <d> rows,
# so it pins the undemoted answer (as forheadrrcheck does). The demote's own rules are pinned in forsiblingdemotecheck.
export RIPWIRE_NO_SIBLING_DEMOTE=1
ROOT="$( cd "$( dirname "$0" )/.." && pwd )"
. "$ROOT/test/lib/clean-env.sh"
unset RIPWIRE_NO_HEAD_RR RIPWIRE_NO_HEAD_RR_GATE RIPWIRE_NO_DOCS_AFTER_CODE
BIN="${1:-${RIPWIRE_BIN:-$ROOT/build/ripwire}}"
[ "${BIN#/}" = "$BIN" ] && BIN="$ROOT/$BIN"
echo "forheadrrgatecheck: BIN=$BIN"
fail=0
ok(){ printf '  PASS  %s\n' "$*" || { fail=1; printf '  FAIL  could not write the PASS line for: %s\n' "$*"; }; return 0; }
no(){ printf '  FAIL  %s\n' "$*"; fail=1; }

[ -x "$BIN" ] || { echo "no ripwire binary at $BIN — build first"; exit 2; }
command -v python3 >/dev/null 2>&1 || { echo "python3 required"; exit 2; }
FIX="$ROOT/test/forheadrrfix"
[ -d "$FIX/mono/src" ] && [ -d "$FIX/pair" ] || { echo "fixture test/forheadrrfix missing"; exit 2; }

TMP="$( mktemp -d )"; trap 'rm -rf "$TMP"' EXIT
export HOME="$TMP/home"; mkdir -p "$HOME"

Q_GEN="How does the scheduler dispatch queued jobs?"
Q_MONO="How does the scheduler dispatch queued jobs to workers?"
Q_PAIR="How is the job scheduler initialised and run?"

# gen DIR K — K strong rows in src/dispatch.ts (every query term), one weak row countJobs in src/count.ts that ranks just below them
gen(){ python3 - "$1" "$2" <<'PY'
import os, sys
root, k = sys.argv[1], int(sys.argv[2])
names = "Alpha Bravo Charlie Delta Echo Foxtrot Golf Hotel India Juliet".split()
os.makedirs(os.path.join(root, "src"), exist_ok=True)
with open(os.path.join(root, "src", "dispatch.ts"), "w") as f:
    for i in range(k):
        f.write("export function schedulerDispatchQueuedJobs%s(jobs: string[]): number {\n  let n = 0;\n"
                "  for (const j of jobs) { if (j.length > %d) { n++; } }\n  return n;\n}\n\n" % (names[i], i))
with open(os.path.join(root, "src", "count.ts"), "w") as f:
    f.write("export function countJobs(jobs: string[]): number {\n  return jobs.length;\n}\n")
PY
}
gen "$TMP/k8" 8 || { echo "could not generate the 8-row tree"; exit 2; }
gen "$TMP/k7" 7 || { echo "could not generate the 7-row tree"; exit 2; }

# run OUT ROOTDIR ENV ARGS... — one --for call (ENV: none | off = RIPWIRE_NO_HEAD_RR=1 | nogate = RIPWIRE_NO_HEAD_RR_GATE=1)
run(){ local out="$1" dir="$2" env="$3"; shift 3
    ( cd "$dir" || exit 97
      case "$env" in
        off)    RIPWIRE_NO_HEAD_RR=1 "$BIN" "$dir" --no-cache "$@" ;;
        nogate) RIPWIRE_NO_HEAD_RR_GATE=1 "$BIN" "$dir" --no-cache "$@" ;;
        *)      "$BIN" "$dir" --no-cache "$@" ;;
      esac ) >"$out" 2>"$out.err"
    printf '%s' "$?" >"$out.rc"; }
ran(){ [ "$( cat "$1.rc" )" = 0 ] && [ -s "$1" ] && return 0; no "$2: rc=$( cat "$1.rc" ) bytes=$( wc -c <"$1" | tr -d ' ' )"; return 1; }
# mcp OUT ROOTDIR TASK — one MCP `for` call
mcp(){ mkdir -p "$TMP/mcphome"
    printf '%s\n' '{"jsonrpc":"2.0","id":1,"method":"initialize"}' \
                  '{"jsonrpc":"2.0","id":2,"method":"tools/call","params":{"name":"for","arguments":{"path":"'"$2"'","task":"'"$3"'"}}}' \
        | ( cd "$2" || exit 97; TMPDIR="$TMP/mcphome" "$BIN" --mcp ) >"$1" 2>"$1.err"
    printf '%s' "$?" >"$1.rc"; }

cat > "$TMP/chk.py" <<'PY'
import html, json, re, sys
cmd, args = sys.argv[1], sys.argv[2:]
def load(p): return open(p, "rb").read().decode("utf-8", "replace")
def attrs(s): return dict((k, html.unescape(v)) for k, v in re.findall(r'(\w+)="([^"]*)"', s))
def xml_rows(t):
    out = []
    for m in re.finditer(r'<d ([^>]*)>', t):
        a = attrs(m.group(1))
        if "r" in a: out.append((int(a["r"]), a.get("p", ""), a.get("n", "")))
    return sorted(out)
def mcp_body(t):
    body = ""
    for line in t.splitlines():
        try: o = json.loads(line)
        except ValueError: continue
        if o.get("id") == 2:
            for c in o.get("result", {}).get("content", []): body += c.get("text", "")
    return body
def json_rows(t):
    flat = []
    def walk(o, p=""):
        if isinstance(o, dict):
            if "r" in o and "n" in o: flat.append((int(o["r"]), o.get("p", p), o["n"]))
            for v in o.values(): walk(v, o.get("p", p) if isinstance(o.get("p"), str) else p)
        elif isinstance(o, list):
            for v in o: walk(v, p)
    walk(json.loads(t))
    return sorted(flat)
def rows_of(kind, path):
    t = load(path)
    return {"xml": xml_rows, "mcp": lambda s: xml_rows(mcp_body(s)), "json": json_rows}[kind](t)
def model(off, gate, k=8):
    """the round-robin, independently, over the score-ordered rows (r= = lens rank): a row past `gate` opens no file"""
    rs = [(p, n) for r, p, n in off]; lens = [r for r, p, n in off]
    head, files, nms, taken = [], set(), set(), set()
    for i, (p, n) in enumerate(rs):
        if len(head) == k: break
        if lens[i] > gate or p in files or n in nms: continue
        head.append(i); taken.add(i); files.add(p); nms.add(n)
    return [rs[i] for i in head] + [rs[i] for i in range(len(rs)) if i not in taken]
def fail(msg): print(msg); sys.exit(1)
if cmd == "rankof":        # KIND FILE NAME R — the row named NAME is shown at r=R
    rs = rows_of(args[0], args[1]); got = [r for r, p, n in rs if n == args[2]]
    if got != [int(args[3])]: fail("%s at r=%s, expected r=%s (head %s)" % (args[2], got, args[3], [n for r, p, n in rs[:4]]))
    print("%s at r=%s" % (args[2], args[3]))
elif cmd == "gated":       # ON OFF GATENAME GATER — ON is the gated round-robin of OFF; the ungated model differs (the gate fires)
    on, off = xml_rows(load(args[0])), xml_rows(load(args[1]))
    ron = [(p, n) for r, p, n in on]
    if sorted(ron) != sorted((p, n) for r, p, n in off): fail("the shown rows differ (a row added or removed)")
    want = model(off, 8)
    if ron != want: fail("order %s, expected %s" % ([n for p, n in ron[:8]], [n for p, n in want[:8]]))
    if len(args) > 2:
        if model(off, 10**9) == want: fail("the ungated model equals the gated one: the fixture no longer exercises the gate")
        if [r for r, p, n in on if n == args[2]] != [int(args[3])]: fail("%s not at r=%s" % (args[2], args[3]))
    print("head %s" % [n for p, n in ron[:3]])
elif cmd == "nofiles":     # FILE — no files_first= on the answer
    if "files_first=" in load(args[0]) or '"files_first"' in load(args[0]): fail("files_first present")
    print("no files_first=")
elif cmd == "files":       # FILE — files_first= present
    if "files_first=" not in load(args[0]): fail("no files_first=")
    print("files_first= present")
PY
chk(){ local label="$1"; shift; local msg; if msg="$( python3 "$TMP/chk.py" "$@" 2>&1 )"; then ok "$label: $msg"; else no "$label: $msg"; fi; }

# ── B1..B3: the bar on the generated trees ────────────────────────────────────────────────────────────────────────────────
run "$TMP/k8.on" "$TMP/k8" none --for="$Q_GEN"; run "$TMP/k8.off" "$TMP/k8" off --for="$Q_GEN"; run "$TMP/k8.ng" "$TMP/k8" nogate --for="$Q_GEN"
if ran "$TMP/k8.on" B1 && ran "$TMP/k8.off" "B1 (score-order twin)"; then
    chk "B1 lens rank 9 (score order)" rankof xml "$TMP/k8.off" countJobs 9
    chk "B1 lens rank 9 is not lifted" rankof xml "$TMP/k8.on" countJobs 9
    chk "B1 no files_first=" nofiles "$TMP/k8.on"
    if cmp -s "$TMP/k8.on" "$TMP/k8.off" && cmp -s "$TMP/k8.on.err" "$TMP/k8.off.err"; then ok "B1 byte-identical to RIPWIRE_NO_HEAD_RR=1 (stdout + stderr)"
    else no "B1 the answer differs from RIPWIRE_NO_HEAD_RR=1"; fi
fi
if ran "$TMP/k8.ng" B3; then
    chk "B3 RIPWIRE_NO_HEAD_RR_GATE=1 lifts it again" rankof xml "$TMP/k8.ng" countJobs 2
fi
run "$TMP/k7.on" "$TMP/k7" none --for="$Q_GEN"; run "$TMP/k7.off" "$TMP/k7" off --for="$Q_GEN"
if ran "$TMP/k7.on" B2 && ran "$TMP/k7.off" "B2 (score-order twin)"; then
    chk "B2 lens rank 8 (score order)" rankof xml "$TMP/k7.off" countJobs 8
    chk "B2 lens rank 8 is lifted" rankof xml "$TMP/k7.on" countJobs 2
    chk "B2 files_first=" files "$TMP/k7.on"
fi

# ── B4/B5: --json and MCP `for` ───────────────────────────────────────────────────────────────────────────────────────────
run "$TMP/k8.json" "$TMP/k8" none --for="$Q_GEN" --json
ran "$TMP/k8.json" B4j && chk "B4 --json: lens rank 9 is not lifted" rankof json "$TMP/k8.json" countJobs 9
mcp "$TMP/k8.mcp" "$TMP/k8" "$Q_GEN"
ran "$TMP/k8.mcp" B4m && chk "B4 MCP for: lens rank 9 is not lifted" rankof mcp "$TMP/k8.mcp" countJobs 9
mcp "$TMP/k7.mcp" "$TMP/k7" "$Q_GEN"
ran "$TMP/k7.mcp" B5 && chk "B5 MCP for: lens rank 8 is lifted" rankof mcp "$TMP/k7.mcp" countJobs 2

# ── M1/M2: the committed head round-robin fixtures under the gated model ──────────────────────────────────────────────────
run "$TMP/mono.on" "$FIX/mono" none --for="$Q_MONO"; run "$TMP/mono.off" "$FIX/mono" off --for="$Q_MONO"
if ran "$TMP/mono.on" M1 && ran "$TMP/mono.off" "M1 (twin)"; then
    chk "M1 mono: the gated round-robin, schedulerWorkerCount keeps lens rank 11" gated "$TMP/mono.on" "$TMP/mono.off" schedulerWorkerCount 11
fi
run "$TMP/pair.on" "$FIX/pair" none --for="$Q_PAIR"; run "$TMP/pair.off" "$FIX/pair" off --for="$Q_PAIR"
if ran "$TMP/pair.on" M2 && ran "$TMP/pair.off" "M2 (twin)"; then
    chk "M2 pair: the gated round-robin" gated "$TMP/pair.on" "$TMP/pair.off"
    chk "M2 pair: run_scheduled_jobs (lens rank 7) is lifted" rankof xml "$TMP/pair.on" run_scheduled_jobs 2
fi

# ── X1/X2 ─────────────────────────────────────────────────────────────────────────────────────────────────────────────────
run "$TMP/k7.on2" "$TMP/k7" none --for="$Q_GEN"
if cmp -s "$TMP/k7.on" "$TMP/k7.on2"; then ok "X1 determinism"; else no "X1 two runs differ"; fi
if command -v xmllint >/dev/null 2>&1; then
    if xmllint --noout "$TMP/k7.on" 2>/dev/null && xmllint --noout "$TMP/k8.on" 2>/dev/null; then ok "X2 well-formed"; else no "X2 xmllint"; fi
fi

[ "$fail" = 0 ] && echo "forheadrrgatecheck: ALL PASS" || echo "forheadrrgatecheck: FAIL"
exit "$fail"
