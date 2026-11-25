#!/usr/bin/env bash
# forqsitescheck.sh — θ11 (src/forqsites.h; switch src/forqsitesswitch.h): page 1 of a --for answer carries, inside its root right
# before </ctx>, the question's own tokens with every file:line they occur on, one <qs> element each, 1,000 B of elements, one legend
# comment before them, no newline (G4). DEFAULT ON (owner 11-24, THETA11-FLIP): a plain call is the ON arm; RIPWIRE_THETA11=0 is the OFF arm.
# ARMS (each counts what it saw and FAILS on zero)
#   (Q1) knob on, a backticked name: <qs t="my_special_fn"> lists src/a.c:1 and src/b.c:3 — whole word, so the line holding only
#        my_special_fnx is not a site; the block is INSIDE the root: the legend comment, the <qs> elements, then </ctx> ends the answer
#   (Q2) an option is a substring site: --frob-level is found on its line in src/b.c
#   (Q3) the caps: a token on 151 lines is not listed; every n= is <= 150 and the <qs> elements total <= 1,000 B (one separator byte each)
#   (Q4) NEGATIVE: a question with no identifier-shaped token and no rare plain word emits no block — counted against Q1's emit
#   (Q5) off is byte-identical: RIPWIRE_THETA11=0 has no <qs>, and the default answer less its block is the =0 answer byte for
#        byte (the block is purely additive)
#   (D)  the DEFAULT is on: a plain call carries the block and equals RIPWIRE_THETA11=1 byte for byte (positive and negative question)
#   (V)  --version names the posture: qsites=on for a plain call and under =1, qsites=off under RIPWIRE_THETA11=0
#   (I)  with BASE_BIN (a binary from before the block existed) set: the =0 answer equals BASE_BIN's byte for byte (SKIP unset)
#   (Q6) deterministic: two default runs are byte-identical
#   (G)  G4: no newline outside CDATA with the block on (default, =0, budgeted, legend-first, paged page 1); the block is one legend
#        comment and its <qs> elements back to back
#   (Q7) EXTENSIONLESS files are read: a Makefile and a NEWS (no extension, no grammar) list their my_special_fn lines
#   (Q8) REPO RARITY: a plain word on 2 lines (frobnicator) is listed; one on 25 lines (widgetry, prose) is not; one on 26 lines
#        the code calls (gadgetize, a function) is — all three counted
#   (Q9) MCP: the `for` tool's answer carries the same <qs> elements inside its root by default; under =0 it carries none
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
rw "$POS" >"$WORK/on.xml"
rw "$POS" >"$WORK/on2.xml"
RIPWIRE_THETA11=1 rw "$POS" >"$WORK/on1.xml"
RIPWIRE_THETA11=0 rw "$POS" >"$WORK/off.xml"
rw "$NEG" >"$WORK/neg_on.xml"
RIPWIRE_THETA11=1 rw "$NEG" >"$WORK/neg_on1.xml"
RIPWIRE_THETA11=0 rw "$NEG" >"$WORK/neg_off.xml"
rw "$POS" --token-budget=600 >"$WORK/budget.xml"
rw "$POS" --legend=first >"$WORK/lfirst.xml"
rw "$POS" --page-bytes=1500:1 >"$WORK/page1.xml"
rw "$POS" --page-bytes=1500:2 >"$WORK/page2.xml"
# (V) the posture --version names; (I) the =0 answer against a binary from before the block existed
"$BIN" --version >"$WORK/v_def.txt" 2>&1
"$BIN" --version >"$WORK/v_on1.txt" 2>&1
RIPWIRE_THETA11=0 "$BIN" --version >"$WORK/v_off.txt" 2>&1
if [ -n "${BASE_BIN:-}" ]; then
    ( cd "$FX" && "$BASE_BIN" "$FX" --no-cache "--for=$POS" 2>/dev/null ) >"$WORK/base_pos.xml"
    ( cd "$FX" && "$BASE_BIN" "$FX" --no-cache "--for=$NEG" 2>/dev/null ) >"$WORK/base_neg.xml"
fi
# Q11: a two-root workspace, run from $FX (a directory holding neither root, so a labelled path does not resolve against the cwd)
mkdir -p "$WORK/wsa" "$WORK/wsb"
printf 'int my_special_fn( int x ) { return x; }\n' >"$WORK/wsa/a.c"
printf 'v2.0\n* my_special_fn is documented here\n' >"$WORK/wsa/NEWS"
printf 'int caller( void ) { return my_special_fn( 1 ); }\n' >"$WORK/wsb/b.c"
( cd "$FX" && "$BIN" "$WORK/wsa" "$WORK/wsb" --no-cache '--for=why does `my_special_fn` return the wrong value' 2>/dev/null ) >"$WORK/ws.xml"
# Q12: 501 extensionless files (the crawl keeps 500 rows) -> every count a floor; an unreadable text file -> a floor
FL="$WORK/fl"; mkdir -p "$FL/src" "$FL/notes"
printf 'int my_special_fn( int x ) { return x; }\n' >"$FL/src/a.c"
for i in $( seq 0 500 ); do printf 'note %s\n' "$i" >"$FL/notes/n$i"; done
( cd "$FL" && "$BIN" "$FL" --no-cache '--for=why does `my_special_fn` return the wrong value' 2>/dev/null ) >"$WORK/floor_rows.xml"
UR="$WORK/ur"; mkdir -p "$UR/src"
printf 'int my_special_fn( int x ) { return x; }\n' >"$UR/src/a.c"
printf '* my_special_fn\n' >"$UR/NEWS"; chmod 000 "$UR/NEWS"
# CR #746: CAP_DAC_OVERRIDE (root on Linux) reads past chmod 000, so record whether the file is really unreadable
cat "$UR/NEWS" >/dev/null 2>&1 && : >"$WORK/ur_readable"
( cd "$UR" && "$BIN" "$UR" --no-cache '--for=why does `my_special_fn` return the wrong value' 2>/dev/null ) >"$WORK/floor_unread.xml"
chmod 600 "$UR/NEWS"
# Q12b (CR #746): a file the crawl drops over --max-file-size may hold a site -> every count a floor
OV="$WORK/ov"; mkdir -p "$OV/src"
printf 'int my_special_fn( int x ) { return x; }\n' >"$OV/src/a.c"
python3 -c "import sys; open(sys.argv[1], 'w').write('int pad[] = {' + '0,' * 3000 + '};\nint g( void ) { return my_special_fn( 2 ); }\n')" "$OV/src/big.c"
( cd "$OV" && "$BIN" "$OV" --no-cache --max-file-size=4K '--for=why does `my_special_fn` return the wrong value' 2>/dev/null ) >"$WORK/floor_oversize.xml"
# Q13: the match cap is spent on whole-word sites only
CP="$WORK/cap"; mkdir -p "$CP/src"
python3 -c "import sys; open(sys.argv[1], 'w').write('/* ' + 'z' * 4000003 + ' */\\nint zzz = 1;\\n')" "$CP/src/big.c"
printf 'int f( void ) { return zzz; }\n' >"$CP/src/f.c"
( cd "$CP" && "$BIN" "$CP" --no-cache '--for=why is `zzz` wrong' 2>/dev/null ) >"$WORK/cap.xml"
python3 - "$WORK" "$FX" "$BIN" "$POS" <<'PY' || fail=1
import json, os, re, subprocess, sys
W, FX, BIN, POS = sys.argv[1:5]; bad = 0
rd = lambda n: open(os.path.join(W, n), encoding='utf-8', errors='replace').read()
def P(m): print('  PASS  ' + m)
def F(m):
    global bad; bad = 1; print('  FAIL  ' + m)
on, off, neg_on, neg_off = rd('on.xml'), rd('off.xml'), rd('neg_on.xml'), rd('neg_off.xml')
QS = re.compile(r'<qs t="([^"]*)" n="(\d+)\+?">([^<]*)</qs>')
LEG = '<!-- qs:'
def strip(p): return p[len(FX) + 1:] if p.startswith(FX + '/') else p
def sites(body): return {(strip(p), int(l)) for p, ls in re.findall(r'(.+?):(\d+(?:,\d+)*)(?: |$)', body) for l in ls.split(',')}
def rows_of(doc): return {m.group(1): (int(m.group(2)), sites(m.group(3)), m.group(0)) for m in QS.finditer(doc)}
def inside_root(doc):
    """the block sits right before the answer's final </ctx>: the legend comment, then <qs> elements back to back, then </ctx>; no
    newline anywhere in it (G4: no newline outside CDATA)"""
    body = doc.rstrip('\n')
    if not body.endswith('</ctx>') or LEG not in body: return False
    tail = body[body.rfind(LEG):-len('</ctx>')]
    end = tail.find('-->') + 3
    if '\n' in tail or end < 3: return False
    elems = tail[end:]
    return bool(elems) and QS.sub('', elems) == ''
def g4(doc):
    """no newline outside CDATA (the trailing newline after the root aside)"""
    return '\n' not in re.sub(r'<!\[CDATA\[.*?\]\]>', '', doc.rstrip('\n'), flags=re.S)
rows = rows_of(on)
# Q1
r = rows.get('my_special_fn')
if not rows: F('(Q1) the default emitted no <qs> line at all (every arm below would be vacuous)')
elif r and {('src/a.c', 1), ('src/b.c', 3)} <= r[1] and ('src/b.c', 5) not in r[1] and inside_root(on):
    P(f'(Q1) my_special_fn: src/a.c:1 src/b.c:3 (my_special_fnx not a site); the block is inside the root, before </ctx>; {len(rows)} <qs> elements')
else: F(f'(Q1) my_special_fn row wrong or block not inside the root: {r and r[2]!r}; end {on[-200:]!r}')
# Q2
r = rows.get('--frob-level')
if r and ('src/b.c', 4) in r[1]: P(f'(Q2) --frob-level is a substring site at src/b.c:4 (n={r[0]})')
else: F(f'(Q2) --frob-level row wrong: {r and r[2]!r}')
# Q3
lb = sum(len(v[2].encode()) + 1 for v in rows.values())
if rows and 'TOO_MANY_HITS' not in rows and all(v[0] <= 150 for v in rows.values()) and lb <= 1000:
    P(f'(Q3) TOO_MANY_HITS (151 lines) not listed; max n={max(v[0] for v in rows.values())}; <qs> elements {lb} B <= 1000')
else: F(f'(Q3) caps broken: TOO_MANY_HITS listed={"TOO_MANY_HITS" in rows}, bytes={lb}')
# Q4
if not rows: F('(Q4) vacuous: the positive question emitted nothing, so an empty negative proves nothing')
elif '<qs' in neg_on or LEG in neg_on: F('(Q4) a question with no identifier-shaped token or rare word emitted a block')
elif neg_on != neg_off or '</ctx>' not in neg_on: F('(Q4) the negative answer differs from its RIPWIRE_THETA11=0 twin, or has no </ctx>')
else: P('(Q4) negative: no token kept -> no block; the default answer equals the =0 one byte for byte')
# Q5
if '</ctx>' not in off: F('(Q5) the RIPWIRE_THETA11=0 answer has no </ctx> (vacuous)')
elif '<qs' in off or LEG in off: F('(Q5) RIPWIRE_THETA11=0 still carries the block')
elif LEG not in on: F('(Q5) vacuous: the default answer carries no block to remove')
else:
    i = on.rfind(LEG); j = on.rfind('</ctx>')
    if off == on[:i] + on[j:]: P(f'(Q5) =0 carries no block ({len(off)} B); the default = the =0 answer + {len(on) - len(off)} B block')
    else: F('(Q5) the default answer less its block is not the RIPWIRE_THETA11=0 answer')
# D: the default is on, and equals =1
on1, neg_on1 = rd('on1.xml'), rd('neg_on1.xml')
if not rows or LEG not in on: F('(D) the default answer carries no block (the default is not on)')
elif on1 != on or neg_on1 != neg_on or '</ctx>' not in neg_on1: F(f'(D) the default differs from RIPWIRE_THETA11=1: pos same={on1 == on} neg same={neg_on1 == neg_on}')
else: P(f'(D) default on: a plain call carries {len(rows)} <qs> elements and equals RIPWIRE_THETA11=1 byte for byte (2 questions)')
# V: --version
vd, v1, v0 = rd('v_def.txt'), rd('v_on1.txt'), rd('v_off.txt')
vok = [('default', vd, 'qsites=on'), ('=1', v1, 'qsites=on'), ('=0', v0, 'qsites=off')]
vbad = [n for n, t, want in vok if not t.startswith('ripwire ') or len(re.findall(r'\bqsites=(on|off)\b', t)) != 1 or want not in t]
if vbad: F(f'(V) --version posture wrong for {vbad}: {vd.strip()!r} / {v0.strip()!r}')
else: P(f'(V) --version: qsites=on (default, =1), qsites=off (=0): {len(vok)} of {len(vok)}')
# I: =0 == a binary from before the block existed
if not os.path.exists(os.path.join(W, 'base_pos.xml')): print('  SKIP  (I) BASE_BIN unset')
else:
    bp, bn = rd('base_pos.xml'), rd('base_neg.xml')
    if '</ctx>' not in bp or '</ctx>' not in bn: F('(I) the BASE_BIN answers have no </ctx> (vacuous)')
    elif bp == off and bn == neg_off: P(f'(I) RIPWIRE_THETA11=0 == BASE_BIN byte for byte (2 of 2 questions, {len(bp)} + {len(bn)} B)')
    else: F(f'(I) RIPWIRE_THETA11=0 differs from BASE_BIN: pos same={bp == off} neg same={bn == neg_off}')
# Q6
if rd('on.xml') == rd('on2.xml') and rows: P('(Q6) two knob-on runs byte-identical')
else: F('(Q6) knob-on runs differ (or nothing emitted)')
# G: G4 holds with the block on (it once printed one <qs> per line, outside CDATA; test/actlinecheck.sh (H) caught it at the flip)
g4docs = [('default', on), ('=0', off), ('--token-budget', rd('budget.xml')), ('--legend=first', rd('lfirst.xml')), ('--page-bytes page 1', rd('page1.xml'))]
g4bad = [n for n, d in g4docs if '</ctx>' not in d or not g4(d)]
if not rows: F('(G) vacuous: the default answer carries no block')
elif g4bad: F(f'(G) a newline outside CDATA (G4) in: {g4bad}')
else: P(f'(G) no newline outside CDATA in {len(g4docs)} of {len(g4docs)} answers, {len(rows)} <qs> elements in the default one')
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
    if not env_on: env['RIPWIRE_THETA11'] = '0'
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
    P(f'(Q9) MCP `for`: the same {len(mr)} <qs> elements inside its root by default; RIPWIRE_THETA11=0 none')
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
FLR = re.compile(r'<qs t="[^"]*" n="\d+\+">')
fr_rows, fr_unread = rd('floor_rows.xml'), rd('floor_unread.xml')
n_rows, n_unread = len(QS.findall(fr_rows)), len(QS.findall(fr_unread))
plus_main = len(FLR.findall(on))
ur_readable = os.path.exists(os.path.join(W, 'ur_readable'))   # privileged reader: chmod 000 did not stop the read
unread_ok = ur_readable or (n_unread and len(FLR.findall(fr_unread)) == n_unread)
if ur_readable: print('  SKIP  (Q12) unreadable-NEWS arm: this user reads past chmod 000 (CAP_DAC_OVERRIDE), so the file is readable here')
if n_rows and len(FLR.findall(fr_rows)) == n_rows and unread_ok and rows and plus_main == 0:
    P(f'(Q12) floors: 501 counted extensionless rows -> {n_rows}/{n_rows} lines n="N+"; unreadable NEWS -> {n_unread}/{n_unread}; main fixture 0 of {len(rows)}')
else: F(f'(Q12) floors wrong: rows {len(FLR.findall(fr_rows))}/{n_rows}, unread {len(FLR.findall(fr_unread))}/{n_unread}, main + {plus_main} of {len(rows)}')
fr_ov = rd('floor_oversize.xml'); n_ov = len(QS.findall(fr_ov))
if n_ov and len(FLR.findall(fr_ov)) == n_ov:
    P(f'(Q12b) a file dropped over --max-file-size -> {n_ov}/{n_ov} lines n="N+"')
else: F(f'(Q12b) oversize drop not a floor: {len(FLR.findall(fr_ov))}/{n_ov} lines n="N+"')
# Q13 word-bounded before the cap
cr = rows_of(rd('cap.xml')).get('zzz')
if cr and ('src/big.c', 2) in cr[1] and ('src/f.c', 1) in cr[1] and ('src/big.c', 1) not in cr[1]:
    P(f'(Q13) word-bounded before the cap: big.c:2 found past ~4 M non-word matches on line 1; f.c:1 too (n={cr[0]})')
else: F(f'(Q13) the whole-word site past the cap was lost: {cr and cr[2]!r}')
sys.exit(bad)
PY
[ "$fail" = 0 ] && echo "forqsitescheck: PASS" || echo "forqsitescheck: FAIL"
exit "$fail"
