#!/usr/bin/env bash
# forqsitescheck.sh — θ11 (src/forqsites.h, RIPWIRE_THETA11=1, default OFF): page 1 of a --for answer carries, inside its root right
# before </ctx>, the question's own tokens with every file:line they occur on, one <qs> line each, 1,000 B of lines, one legend
# comment line before them.
# ARMS (each counts what it saw and FAILS on zero)
#   (Q1) knob on, a backticked name: <qs t="my_special_fn"> lists src/a.c:1 and src/b.c:3 — whole word, so the line holding only
#        my_special_fnx is not a site; the block is INSIDE the root: the legend line, the <qs> lines, then </ctx> ends the answer
#   (Q2) an option is a substring site: --frob-level is found on its line in src/b.c
#   (Q3) the caps: a token on 151 lines is not listed; every n= is <= 150 and the <qs> lines total <= 1,000 B
#   (Q4) NEGATIVE: a question with no identifier-shaped token and no rare plain word emits no block — counted against Q1's emit
#   (Q5) knob off is byte-identical: unset == RIPWIRE_THETA11=0, neither has <qs>, and the knob-on answer less its block is the
#        knob-off answer byte for byte (the block is purely additive)
#   (Q6) deterministic: two knob-on runs are byte-identical
#   (Q7) EXTENSIONLESS files are read: a Makefile and a NEWS (no extension, no grammar) list their my_special_fn lines
#   (Q8) REPO RARITY: a plain word on 2 lines (frobnicator) is listed; one on 25 lines (widgetry, prose) is not; one on 26 lines
#        the code calls (gadgetize, a function) is — all three counted
#   (Q9) MCP: the `for` tool's answer carries the same <qs> lines inside its root; knob off it carries none
#   (Q10) BUDGETED + PAGED: --token-budget keeps the block inside the root; --page-bytes page 2 has none; --legend=first carries it
#   (Q11) WORKSPACE: two roots run from a directory holding neither; an extensionless file's site is read from its root on disk and printed
#         under its label (the crawl row carries the label, not the disk path)
#   (Q12) FLOORS: a fixture whose crawl counted 501 extensionless files (rows keep 500) prints n="N+" on every line; an unreadable
#         text file floors too; the main fixture, every file read, prints no `+` (counted against Q1's lines)
#   (Q13) WORD-BOUNDED BEFORE THE CAP: a line of 4,000,003 `z` holds ~4 M substring matches of `zzz` (the scan's match cap) and no
#         whole-word one; the whole-word site on the next line is still found (the cap counts only whole-word sites)
set -u
ROOT="$( cd "$( dirname "$0" )/.." && pwd )"
BIN="${RIPWIRE_BIN:-${1:-$ROOT/build/ripwire}}"
[ "${BIN#/}" = "$BIN" ] && BIN="$ROOT/$BIN"
[ -x "$BIN" ] || { echo "no ripwire binary at $BIN -- build first (cmake --build build -j)"; exit 2; }
command -v python3 >/dev/null 2>&1 || { echo "forqsitescheck: python3 required"; exit 2; }
fail=0
WORK="$( mktemp -d )"; trap 'rm -rf "$WORK"' EXIT
echo "forqsitescheck: BIN=$BIN"
unset RIPWIRE_THETA11
FX="$WORK/fx"; mkdir -p "$FX/src"
printf 'int my_special_fn( int x ) { return x; }\nint other( int y ) { return y + 1; }\n' >"$FX/src/a.c"
printf '#include "a.h"\nint caller( void )\n{ return my_special_fn( 2 ); }\nconst char* opt = "--frob-level";\nint my_special_fnx = 3;\n' >"$FX/src/b.c"
printf '/* the frobnicator */\nint frob( void ) { return 1; } /* frobnicator */\n' >"$FX/src/c.c"
printf 'all:\n\tcc -DUSE=my_special_fn src/a.c\n' >"$FX/Makefile"
printf 'v1.0\n* my_special_fn now returns its argument\n' >"$FX/NEWS"
python3 - "$FX" <<'PY'
import sys
fx = sys.argv[1]
open(fx + '/src/many.c', 'w').write(''.join(f'int v{i} = TOO_MANY_HITS + {i};\n' for i in range(151)))
open(fx + '/src/w.c', 'w').write(''.join(f'int w{i} = {i}; /* widgetry */\n' for i in range(25)))
open(fx + '/src/g.c', 'w').write('int gadgetize( int x ) { return x; }\nint use( void )\n{\n' + ''.join(f'    gadgetize( {i} );\n' for i in range(25)) + '    return 0;\n}\n')
PY
POS='why does `my_special_fn` return the wrong value with --frob-level and TOO_MANY_HITS, see the frobnicator, the widgetry and gadgetize'
NEG='why is it slow when it starts up'
rw(){ ( cd "$FX" && "$BIN" "$FX" --no-cache "--for=$1" "${@:2}" 2>/dev/null ); }
RIPWIRE_THETA11=1 rw "$POS" >"$WORK/on.xml"
RIPWIRE_THETA11=1 rw "$POS" >"$WORK/on2.xml"
rw "$POS" >"$WORK/off.xml"
RIPWIRE_THETA11=0 rw "$POS" >"$WORK/off0.xml"
RIPWIRE_THETA11=1 rw "$NEG" >"$WORK/neg_on.xml"
rw "$NEG" >"$WORK/neg_off.xml"
RIPWIRE_THETA11=1 rw "$POS" --token-budget=600 >"$WORK/budget.xml"
RIPWIRE_THETA11=1 rw "$POS" --legend=first >"$WORK/lfirst.xml"
RIPWIRE_THETA11=1 rw "$POS" --page-bytes=1500:1 >"$WORK/page1.xml"
RIPWIRE_THETA11=1 rw "$POS" --page-bytes=1500:2 >"$WORK/page2.xml"
# Q11: a two-root workspace, run from $FX (a directory holding neither root, so a labelled path does not resolve against the cwd)
mkdir -p "$WORK/wsa" "$WORK/wsb"
printf 'int my_special_fn( int x ) { return x; }\n' >"$WORK/wsa/a.c"
printf 'v2.0\n* my_special_fn is documented here\n' >"$WORK/wsa/NEWS"
printf 'int caller( void ) { return my_special_fn( 1 ); }\n' >"$WORK/wsb/b.c"
( cd "$FX" && RIPWIRE_THETA11=1 "$BIN" "$WORK/wsa" "$WORK/wsb" --no-cache '--for=why does `my_special_fn` return the wrong value' 2>/dev/null ) >"$WORK/ws.xml"
# Q12: 501 extensionless files (the crawl keeps 500 rows) -> every count a floor; an unreadable text file -> a floor
FL="$WORK/fl"; mkdir -p "$FL/src" "$FL/notes"
printf 'int my_special_fn( int x ) { return x; }\n' >"$FL/src/a.c"
for i in $( seq 0 500 ); do printf 'note %s\n' "$i" >"$FL/notes/n$i"; done
( cd "$FL" && RIPWIRE_THETA11=1 "$BIN" "$FL" --no-cache '--for=why does `my_special_fn` return the wrong value' 2>/dev/null ) >"$WORK/floor_rows.xml"
UR="$WORK/ur"; mkdir -p "$UR/src"
printf 'int my_special_fn( int x ) { return x; }\n' >"$UR/src/a.c"
printf '* my_special_fn\n' >"$UR/NEWS"; chmod 000 "$UR/NEWS"
( cd "$UR" && RIPWIRE_THETA11=1 "$BIN" "$UR" --no-cache '--for=why does `my_special_fn` return the wrong value' 2>/dev/null ) >"$WORK/floor_unread.xml"
chmod 600 "$UR/NEWS"
# Q13: the match cap is spent on whole-word sites only
CP="$WORK/cap"; mkdir -p "$CP/src"
python3 -c "import sys; open(sys.argv[1], 'w').write('/* ' + 'z' * 4000003 + ' */\\nint zzz = 1;\\n')" "$CP/src/big.c"
printf 'int f( void ) { return zzz; }\n' >"$CP/src/f.c"
( cd "$CP" && RIPWIRE_THETA11=1 "$BIN" "$CP" --no-cache '--for=why is `zzz` wrong' 2>/dev/null ) >"$WORK/cap.xml"
python3 - "$WORK" "$FX" "$BIN" "$POS" <<'PY' || fail=1
import json, os, re, subprocess, sys
W, FX, BIN, POS = sys.argv[1:5]; bad = 0
rd = lambda n: open(os.path.join(W, n), encoding='utf-8', errors='replace').read()
def P(m): print('  PASS  ' + m)
def F(m):
    global bad; bad = 1; print('  FAIL  ' + m)
on, off, off0, neg_on, neg_off = rd('on.xml'), rd('off.xml'), rd('off0.xml'), rd('neg_on.xml'), rd('neg_off.xml')
QS = re.compile(r'^<qs t="([^"]*)" n="(\d+)\+?">(.*)</qs>$', re.M)
LEG = '<!-- qs:'
def strip(p): return p[len(FX) + 1:] if p.startswith(FX + '/') else p
def sites(body): return {(strip(p), int(l)) for p, ls in re.findall(r'(.+?):(\d+(?:,\d+)*)(?: |$)', body) for l in ls.split(',')}
def rows_of(doc): return {m.group(1): (int(m.group(2)), sites(m.group(3)), m.group(0)) for m in QS.finditer(doc)}
def inside_root(doc):
    """the block sits right before the answer's final </ctx>: legend line, <qs> lines, </ctx>"""
    body = doc.rstrip('\n')
    if not body.endswith('</ctx>') or LEG not in body: return False
    tail = body[body.rfind(LEG):-len('</ctx>')]
    lines = tail.rstrip('\n').split('\n')
    return lines[0].startswith(LEG) and lines[0].endswith('-->') and len(lines) > 1 and all(QS.match(l) for l in lines[1:])
rows = rows_of(on)
# Q1
r = rows.get('my_special_fn')
if not rows: F('(Q1) knob on emitted no <qs> line at all (every arm below would be vacuous)')
elif r and {('src/a.c', 1), ('src/b.c', 3)} <= r[1] and ('src/b.c', 5) not in r[1] and inside_root(on):
    P(f'(Q1) my_special_fn: src/a.c:1 src/b.c:3 (my_special_fnx not a site); the block is inside the root, before </ctx>; {len(rows)} <qs> lines')
else: F(f'(Q1) my_special_fn row wrong or block not inside the root: {r and r[2]!r}; end {on[-200:]!r}')
# Q2
r = rows.get('--frob-level')
if r and ('src/b.c', 4) in r[1]: P(f'(Q2) --frob-level is a substring site at src/b.c:4 (n={r[0]})')
else: F(f'(Q2) --frob-level row wrong: {r and r[2]!r}')
# Q3
lb = sum(len(v[2].encode()) + 1 for v in rows.values())
if rows and 'TOO_MANY_HITS' not in rows and all(v[0] <= 150 for v in rows.values()) and lb <= 1000:
    P(f'(Q3) TOO_MANY_HITS (151 lines) not listed; max n={max(v[0] for v in rows.values())}; <qs> lines {lb} B <= 1000')
else: F(f'(Q3) caps broken: TOO_MANY_HITS listed={"TOO_MANY_HITS" in rows}, bytes={lb}')
# Q4
if not rows: F('(Q4) vacuous: the positive question emitted nothing, so an empty negative proves nothing')
elif '<qs' in neg_on or LEG in neg_on: F('(Q4) a question with no identifier-shaped token or rare word emitted a block')
elif neg_on != neg_off or '</ctx>' not in neg_on: F('(Q4) the negative answer differs from its knob-off twin, or has no </ctx>')
else: P('(Q4) negative: no token kept -> no block; the knob-on answer equals the knob-off one byte for byte')
# Q5
if '</ctx>' not in off: F('(Q5) knob-off answer has no </ctx> (vacuous)')
elif off != off0 or '<qs' in off or LEG in off: F('(Q5) knob off: unset and RIPWIRE_THETA11=0 differ, or carry the block')
else:
    i = on.rfind(LEG); j = on.rfind('</ctx>')
    cand = {on[:i] + on[j:], on[:i - 1] + on[j:] if i > 0 else None}
    if off in cand: P(f'(Q5) knob off byte-identical (unset == =0, {len(off)} B); knob on = knob off + {len(on) - len(off)} B block')
    else: F('(Q5) the knob-on answer less its block is not the knob-off answer')
# Q6
if rd('on.xml') == rd('on2.xml') and rows: P('(Q6) two knob-on runs byte-identical')
else: F('(Q6) knob-on runs differ (or nothing emitted)')
# Q7
r = rows.get('my_special_fn')
got = sorted(p for p in (r[1] if r else ()) if p[0] in ('Makefile', 'NEWS'))
if got == [('Makefile', 2), ('NEWS', 2)]: P(f'(Q7) extensionless files read: {got}')
else: F(f'(Q7) extensionless sites wrong: {got} (row {r and r[2]!r})')
# Q8
fr, wd, gz = rows.get('frobnicator'), rows.get('widgetry'), rows.get('gadgetize')
if fr and fr[1] == {('src/c.c', 1), ('src/c.c', 2)} and wd is None and gz and gz[0] == 26:
    P('(Q8) rarity: frobnicator (2 lines) listed; widgetry (25 lines > 20, prose) not; gadgetize (26 lines, a called name) listed')
else: F(f'(Q8) rarity wrong: frobnicator={fr and fr[2]!r} widgetry={wd and wd[2]!r} gadgetize={gz and gz[2][:80]!r}')
# Q9 MCP
def mcp(env_on):
    env = {k: v for k, v in os.environ.items() if k != 'RIPWIRE_THETA11'}
    if env_on: env['RIPWIRE_THETA11'] = '1'
    req = [{"jsonrpc": "2.0", "id": 0, "method": "initialize"},
           {"jsonrpc": "2.0", "id": 1, "method": "tools/call", "params": {"name": "for", "arguments": {"task": POS}}}]
    p = subprocess.run([BIN, FX, "--mcp"], input="".join(json.dumps(x) + "\n" for x in req).encode(), capture_output=True, env=env, cwd=FX)
    for line in p.stdout.decode('utf8', 'replace').splitlines():
        try: r = json.loads(line)
        except ValueError: continue
        if r.get('id') == 1: return "".join(c.get('text', '') for c in r.get('result', {}).get('content', []))
    return ''
m_on, m_off = mcp(True), mcp(False)
mr = rows_of(m_on)
if mr and mr == rows and inside_root(m_on) and '<qs' not in m_off and '</ctx>' in m_off:
    P(f'(Q9) MCP `for`: the same {len(mr)} <qs> lines inside its root; knob off none')
else: F(f'(Q9) MCP: {len(mr)} lines (CLI {len(rows)}), same={mr == rows}, inside={inside_root(m_on)}, off has <qs>={"<qs" in m_off}, off empty={not m_off}')
# Q10
bud, lf, p1, p2 = rd('budget.xml'), rd('lfirst.xml'), rd('page1.xml'), rd('page2.xml')
okb = rows_of(bud) == rows and inside_root(bud)
okl = rows_of(lf) == rows and inside_root(lf)
okp = rows_of(p1) == rows and inside_root(p1) and '</ctx>' in p2 and '<qs' not in p2 and LEG not in p2 and ' page="2"' in p2
if okb and okl and okp: P(f'(Q10) --token-budget=600, --legend=first and --page-bytes page 1 carry the block inside the root; page 2 none')
else:
    p2_paged = ' page="2"' in p2
    F(f'(Q10) budget={okb} legend-first={okl} paged={okp} (page2 has page="2": {p2_paged})')
# Q11 workspace
ws = rd('ws.xml'); wr = rows_of(ws).get('my_special_fn')
news = sorted(p for p in (wr[1] if wr else ()) if p[0].endswith('NEWS'))
if wr and len(news) == 1 and news[0][1] == 2 and news[0][0] != 'NEWS' and inside_root(ws):
    P(f'(Q11) workspace: the extensionless file is read from its root and printed under its label: {news[0][0]}:2')
else: F(f'(Q11) workspace extensionless site wrong: {wr and wr[2]!r}')
# Q12 floors
FLR = re.compile(r'^<qs t="[^"]*" n="\d+\+">', re.M)
fr_rows, fr_unread = rd('floor_rows.xml'), rd('floor_unread.xml')
n_rows, n_unread = len(QS.findall(fr_rows)), len(QS.findall(fr_unread))
plus_main = len(re.findall(r'^<qs t="[^"]*" n="\d+\+">', on, re.M))
if n_rows and len(FLR.findall(fr_rows)) == n_rows and n_unread and len(FLR.findall(fr_unread)) == n_unread and rows and plus_main == 0:
    P(f'(Q12) floors: 501 counted extensionless rows -> {n_rows}/{n_rows} lines n="N+"; unreadable NEWS -> {n_unread}/{n_unread}; main fixture 0 of {len(rows)}')
else: F(f'(Q12) floors wrong: rows {len(FLR.findall(fr_rows))}/{n_rows}, unread {len(FLR.findall(fr_unread))}/{n_unread}, main + {plus_main} of {len(rows)}')
# Q13 word-bounded before the cap
cr = rows_of(rd('cap.xml')).get('zzz')
if cr and ('src/big.c', 2) in cr[1] and ('src/f.c', 1) in cr[1] and ('src/big.c', 1) not in cr[1]:
    P(f'(Q13) word-bounded before the cap: big.c:2 found past ~4 M non-word matches on line 1; f.c:1 too (n={cr[0]})')
else: F(f'(Q13) the whole-word site past the cap was lost: {cr and cr[2]!r}')
sys.exit(bad)
PY
[ "$fail" = 0 ] && echo "forqsitescheck: PASS" || echo "forqsitescheck: FAIL"
exit "$fail"
