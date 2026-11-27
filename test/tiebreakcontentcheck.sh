#!/usr/bin/env bash
# tiebreakcontentcheck.sh — TIE-BREAK-1117: two printed orders whose last tie broke on NodeId now break on a content key
# (CodeRabbit's review of #676, threads 4588520035 and 4588520057).
#
# THE CONTRACT THIS PINS. A printed order is deterministic, and a tie breaks on a canonical content key, never on an index.
#
#   M  formembers.h mem= order: question words, owner's file, path, line, and then the NAME (it used to be NodeId). Two members
#      declared on one line tie on every other key. Both legend clauses name the key, so a reader derives the printed order
#      from the clause alone. On a single root NodeId is assigned in (path, line, name, byte, scope) order (ingest_model.h
#      assignSymbols), so the printed list is the same on both binaries; what is red on the old binary is the clause, which
#      stopped at "line" and left a same-line pair underived.
#   T  graph.h applyNameTower (the name tier) and resolveAllByScopeQualified (the Scope::name / dotted `Svc._make` tier): the
#      last tie is symbolContentKey (path, line, name, byte range), never NodeId. A verb that seeds a walk in that order
#      (--verify's witness through shortestPathAny) prints the definition the content order picks. On a multi-root workspace
#      NodeIds are label-major and path bytes are not: roots `a` and `a-b` give a/svc.py the lower ids, while "a-b/svc.py"
#      sorts first by bytes ('-' 0x2D < '/' 0x2F). The old binary's witness is a/svc.py; this one's is a-b/svc.py.
#
# Arms ([P] red on main 5fb68b71a, [G] green on both):
#   M1 [P] compact clause derives the printed mem= order of a same-line pair (premise: >= 1 listed pair on one line)
#   M2 [P] full clause, the same
#   M3 [G] the printed list itself: alpha before zulu (they share line 7), mike after them
#   T1 [P] workspace a + a-b: --verify=calls(_make,sink) witness is a-b/svc.py (the name tier, applyNameTower)
#   T2 [P] the same through the dotted tier: calls(Svc._make,sink)
#   T3 [G] argv order does not leak: roots given as `a-b a` print T1's answer byte for byte
#   T4 [G] negative, single root holding the same two directories: ids already follow path bytes, both binaries print a-b/
#   N  every arm counts what it checked; zero checked is a FAIL, never a pass
#
# Usage:  bash test/tiebreakcontentcheck.sh [BIN]   |   RIPWIRE_BIN=asan/ripwire bash test/tiebreakcontentcheck.sh
# BIN is $1, else RIPWIRE_BIN, else build/ripwire. Exits non-zero on any failure.

set -u
ROOT="$( cd "$( dirname "$0" )/.." && pwd )"
. "$ROOT/test/lib/clean-env.sh"
unset RIPWIRE_NO_MEMBER_NAMES RIPWIRE_NO_BODY_FOLD RIPWIRE_NO_BODY_SLOT RIPWIRE_NO_OWNER_HOP
BIN="${1:-${RIPWIRE_BIN:-$ROOT/build/ripwire}}"
[ "${BIN#/}" = "$BIN" ] && BIN="$ROOT/$BIN"
echo "tiebreakcontentcheck: BIN=$BIN"
fail=0
checked=0
ok(){ printf '  PASS  %s\n' "$*" || { fail=1; printf '  FAIL  could not write the PASS line for: %s\n' "$*"; }; checked=$(( checked + 1 )); return 0; }
no(){ printf '  FAIL  %s\n' "$*"; fail=1; }

[ -x "$BIN" ] || { echo "no ripwire binary at $BIN — build first"; exit 2; }
command -v python3 >/dev/null 2>&1 || { echo "python3 required"; exit 2; }

TMP="$( mktemp -d )"; trap 'rm -rf "$TMP"' EXIT
export HOME="$TMP/home"; mkdir -p "$HOME"

cat > "$TMP/chk.py" <<'PY'
import html, re, sys
cmd, args = sys.argv[1], sys.argv[2:]
def load(p):
    return open(p, "rb").read().decode("utf-8", "replace")
def attrs(s):
    return dict((k, html.unescape(v)) for k, v in re.findall(r'(\w+)="([^"]*)"', s))
def fail(msg):
    print(msg); sys.exit(1)
CLAUSE = re.compile(r'; (d mem=|mem= on an owner d row:)[^;]*?mem_more= (names cut|the member names not listed)(?=;| ?-->|$)')
if cmd == "order":            # FILE OWNER OWNERPATH QUESTION NAME@PATH:LINE... : the clause's keys derive the printed mem= order
    t = load(args[0]); owner, opath, q = args[1], args[2], args[3]
    rows = [attrs(m.group(1)) for m in re.finditer(r'<d ([^>]*)>', t)]
    rs = [r for r in rows if r.get("n") == owner and r.get("p") == opath]
    if len(rs) != 1: fail(f"{len(rs)} rows named {owner} at {opath}")
    pos = {}
    for spec in args[4:]:
        n, _, pl = spec.partition("@"); pth, _, ln = pl.rpartition(":"); pos[n] = (pth, int(ln))
    got = rs[0].get("mem", "").split(",") if rs[0].get("mem") else []
    if set(got) - set(pos): fail(f"{owner} lists {sorted(set(got) - set(pos))}, which the arm has no position for")
    prem = sum(1 for i, a in enumerate(got) for b in got[i + 1:] if pos[a] == pos[b])
    if prem == 0: fail(f"premise: 0 listed pairs declared on one line (mem={got}): vacuous")
    m = CLAUSE.search(" ".join(re.findall(r'<!--(.*?)-->', t, re.S)))
    if not m: fail("no mem= clause in the legend")
    paren = re.search(r'\(([^)]*)\)', m.group(0))
    if not paren: fail(f"the clause states no order: {m.group(0)!r}")
    keys = []
    for tok in paren.group(1).split(","):
        w = " ".join(re.sub(r"\b(first|then|next|own|the)\b", " ", tok.lower()).split())
        k = {"question words": "qw", "owner's file": "file", "path": "path", "line": "line", "name": "name"}.get(w)
        if k: keys.append(k)
    qw = set(re.findall(r"[a-z0-9]+", q.lower()))
    def over(n):
        return len({x.lower() for x in re.findall(r"[A-Z]?[a-z0-9]+|[A-Z]+(?![a-z])", n)} & qw)
    def key(n):
        v = {"qw": -over(n), "file": pos[n][0] != opath, "path": pos[n][0], "line": pos[n][1], "name": n}
        return tuple(v[k] for k in keys)
    want = sorted(got, key=key)
    tied = [(a, b) for a, b in zip(want, want[1:]) if key(a) == key(b)]
    if tied: fail(f"the clause's keys {keys} leave {tied} unordered: the printed order cannot be derived from it ({m.group(0)!r})")
    if want != got: fail(f"printed {got}, the clause's keys {keys} derive {want}")
    print(f"same-line pairs={prem} keys={'/'.join(keys)} mem={','.join(got)}")
elif cmd == "list":           # FILE OWNER WANT : the printed mem= list
    t = load(args[0])
    rs = [attrs(m.group(1)) for m in re.finditer(r'<d ([^>]*)>', t) if attrs(m.group(1)).get("n") == args[1]]
    if len(rs) != 1: fail(f"{len(rs)} rows named {args[1]}")
    if rs[0].get("mem") != args[2]: fail(f"mem={rs[0].get('mem')!r}, want {args[2]!r}")
    print(f"mem={args[2]}")
elif cmd == "witness":        # FILE FROMDEFS WANTPATH : a confirmed --verify whose first witness row sits at WANTPATH
    t = load(args[0])
    v = re.search(r'<verify ([^>]*)>', t)
    if not v: fail("no <verify> element")
    va = attrs(v.group(1))
    if va.get("verdict") != "confirmed": fail(f"verdict={va.get('verdict')!r}")
    if va.get("from_defs") != args[1]: fail(f"premise: from_defs={va.get('from_defs')!r}, want {args[1]} (two definitions tie)")
    s = [attrs(m.group(1)) for m in re.finditer(r'<s ([^>]*)/>', t)]
    if not s: fail("no witness rows")
    if not s[0].get("p", "").startswith(args[2]): fail(f"witness starts at {s[0].get('p')!r}, want {args[2]}...")
    print(f"witness {' -> '.join(x.get('p', '') for x in s)}")
elif cmd == "premise":        # LABEL_LO LABEL_HI PATH_LO PATH_HI : label order and path byte order disagree
    lo, hi, plo, phi = args
    if not ( lo < hi and phi < plo ): fail(f"premise: labels {lo} < {hi} and paths {phi} < {plo} must both hold")
    print(f"labels {lo} < {hi}; bytes {phi} < {plo}")
PY
arm(){
    local label="$1"; shift
    local out
    if out="$( python3 "$TMP/chk.py" "$@" 2>&1 )"; then ok "$label${out:+ — $out}"; else no "$label — $out"; fi
}
run(){   # NAME CWD ARGS... : stdout into $TMP/NAME.xml, no cache (a workspace refuses --cache=PATH; HOME is the scratch dir)
    local name="$1" cwd="$2"; shift 2
    ( cd "$cwd" || exit 1; "$BIN" "$@" --no-cache >"$TMP/$name.xml" 2>"$TMP/$name.err" ) \
        || no "$name: ripwire exited non-zero ($( head -c 200 "$TMP/$name.err" | tr '\n' ' ' ))"
}

echo "=== M: mem= order, two members declared on one line (formembers.h) ==="
mkdir -p "$TMP/m/src"
printf '%s\n' '//! Widget owner.' 'pub struct Widget {' '    pub data: u32,' '}' '' 'impl Widget {' \
    '    pub fn zulu(&self) -> u32 { 1 } pub fn alpha(&self) -> u32 { 2 }' '    pub fn mike(&self) -> u32 { 3 }' '}' >"$TMP/m/src/owner.rs"
Q_M="How does the widget data work?"
( cd "$TMP/m" && RIPWIRE_NO_BODY_FOLD=1 "$BIN" "$TMP/m" --for="$Q_M" --cache="$TMP/m_c.cache" >"$TMP/m_c.xml" 2>"$TMP/m_c.err" ) || no "m_c: ripwire exited non-zero"
( cd "$TMP/m" && RIPWIRE_NO_BODY_FOLD=1 "$BIN" "$TMP/m" --for="$Q_M" --legend=full --cache="$TMP/m_f.cache" >"$TMP/m_f.xml" 2>"$TMP/m_f.err" ) || no "m_f: ripwire exited non-zero"
M_POS=( zulu@src/owner.rs:7 alpha@src/owner.rs:7 mike@src/owner.rs:8 )
arm "M1 compact clause derives the same-line order" order "$TMP/m_c.xml" Widget src/owner.rs "$Q_M" "${M_POS[@]}"
arm "M2 full clause derives the same-line order"    order "$TMP/m_f.xml" Widget src/owner.rs "$Q_M" "${M_POS[@]}"
arm "M3 printed list: alpha, zulu (one line), mike" list  "$TMP/m_c.xml" Widget alpha,zulu,mike

echo "=== T: the name tower and the Scope::name tier (graph.h) ==="
mkdir -p "$TMP/ws/a" "$TMP/ws/a-b"
for r in a a-b; do
    printf '%s\n' 'def sink():' '    return 1' '' '' 'class Svc:' '    def _make(self):' '        return sink()' >"$TMP/ws/$r/svc.py"
done
arm "T0 premise: label order a < a-b, byte order a-b/svc.py < a/svc.py" premise a a-b a/svc.py a-b/svc.py
run t1  "$TMP/ws" a a-b --verify='calls(_make,sink)'
run t2  "$TMP/ws" a a-b --verify='calls(Svc._make,sink)'
run t3  "$TMP/ws" a-b a --verify='calls(_make,sink)'
run t4  "$TMP/ws" . --verify='calls(Svc._make,sink)'
arm "T1 workspace, name tier: the witness is a-b/svc.py"  witness "$TMP/t1.xml" 2 a-b/svc.py
arm "T2 workspace, dotted tier: the witness is a-b/svc.py" witness "$TMP/t2.xml" 2 a-b/svc.py
if [ -s "$TMP/t1.xml" ] && cmp -s "$TMP/t1.xml" "$TMP/t3.xml"; then ok "T3 roots given as a-b a print the a a-b answer byte for byte"; else no "T3 argv order changed the answer (or it is empty)"; fi
arm "T4 single root (negative): the witness is a-b/svc.py" witness "$TMP/t4.xml" 2 a-b/svc.py

echo
echo "checked=$checked"
if [ "$checked" -eq 0 ]; then no "N nothing was checked: vacuous"; fi
if [ "$fail" = "0" ]; then echo "tiebreakcontentcheck: ALL PASS"; else echo "tiebreakcontentcheck: FAILURES ABOVE"; fi
exit "$fail"
