#!/usr/bin/env bash
# bodyeditcheck.sh — THE EDIT-FILE FORM of a `--for` answer's first page (src/forbodyptr.h pointEditBodies; lane θ17, default OFF):
# with RIPWIRE_BODIES_EDIT set, an EDIT task's bodies in its top file (the act line's first path; a page without an act line is left as it is) become lean
# skip rows <skip p= n= l= e=/>, their P:L-E join <act read=>, and every other body stays inline.
# ARMS (every one NEW: on a binary without the knob the ON files equal the OFF files, so E2/E3/E6 fail)
#   (E0)  not vacuous: the OFF edit answer holds a <b> in its top file AND a <b> in another file
#   (E1)  DEFAULT UNCHANGED: the variable unset is the default; with RIPWIRE_PARENT_BIN set, the default is also the parent's answer
#         byte for byte (edit task, non-edit task, whole answer, page 2)
#   (E2)  ON, edit task: no <b> with the top file's p= left on page 1; one lean skip row per such body, in its place, with the body's
#         p= n= and an e=; the root says body_form="edit" and the clause is there exactly once
#   (E3)  each pointed range is on <act read=> (listed, or inside a listed range of that path)
#   (E4)  other-file bodies unchanged: every <b> element of the OFF page outside the top file is on the ON page byte for byte, in order
#   (E5)  NOT APPLIED: a non-edit task ("rank symbols ..."), page 2, --bodies=inline, and RIPWIRE_BODY_POINTERS=1 (the pointer form
#         decides) are byte-identical with and without the variable
#   (E6)  est_tokens= below the OFF page's; page smaller
#   (E7)  well formed (xmllint), no newline outside CDATA is checked by xmllint's parse of the minified root, deterministic (two runs)
#   (E8)  MUTATION NEGATIVE CONTROLS: E2's detector FAILS on the OFF page; E4's FAILS on an ON page with one other-file body removed
set -u
ROOT="$( cd "$( dirname "$0" )/.." && pwd )"
BIN="${RIPWIRE_BIN:-${1:-$ROOT/build/ripwire}}"
[ "${BIN#/}" = "$BIN" ] && BIN="$ROOT/$BIN"
[ -x "$BIN" ] || { echo "no ripwire binary at $BIN -- build first (cmake --build build -j)"; exit 2; }
command -v python3 >/dev/null 2>&1 || { echo "bodyeditcheck: python3 required"; exit 2; }
command -v xmllint >/dev/null 2>&1 || { echo "bodyeditcheck: xmllint required"; exit 2; }
PARENT="${RIPWIRE_PARENT_BIN:-}"
fail=0
ok(){ printf '  PASS  %s\n' "$*" || { fail=1; printf '  FAIL  could not write the PASS line for: %s\n' "$*"; }; return 0; }
no(){ printf '  FAIL  %s\n' "$*"; fail=1; }
WORK="$( mktemp -d )"; trap 'rm -rf "$WORK"' EXIT
echo "bodyeditcheck: BIN=$BIN${PARENT:+ PARENT=$PARENT}"
cd "$ROOT" || exit 2
unset RIPWIRE_BODY_POINTERS RIPWIRE_BODIES_EDIT
EDIT="fix the act line insertion in a for answer"   # its OFF page 1 folds bodies from verbs_for.h (the top file) and two other files
PLAIN="rank symbols by pagerank and serialize the map"
rw(){ "$BIN" src --no-cache "$@" 2>/dev/null; }
on(){ RIPWIRE_BODIES_EDIT=1 "$BIN" src --no-cache "$@" 2>/dev/null; }
rw --for="$EDIT" >"$WORK/edit.off";  on --for="$EDIT" >"$WORK/edit.on";  on --for="$EDIT" >"$WORK/edit.on2"
rw --for="$PLAIN" >"$WORK/plain.off"; on --for="$PLAIN" >"$WORK/plain.on"
rw --for="$EDIT" --page-bytes=12000:2 >"$WORK/p2.off"; on --for="$EDIT" --page-bytes=12000:2 >"$WORK/p2.on"
rw --for="$EDIT" --bodies=inline >"$WORK/il.off"; on --for="$EDIT" --bodies=inline >"$WORK/il.on"
RIPWIRE_BODY_POINTERS=1 rw --for="$EDIT" >"$WORK/pt.off"; RIPWIRE_BODY_POINTERS=1 on --for="$EDIT" >"$WORK/pt.on"
rw --for="$EDIT" --page-bytes=0 >"$WORK/whole.off"
if [ -n "$PARENT" ]; then
    pa(){ "$PARENT" src --no-cache "$@" 2>/dev/null; }
    pa --for="$EDIT" >"$WORK/edit.pa"; pa --for="$PLAIN" >"$WORK/plain.pa"
    pa --for="$EDIT" --page-bytes=12000:2 >"$WORK/p2.pa"; pa --for="$EDIT" --page-bytes=0 >"$WORK/whole.pa"
fi
same(){ [ -s "$1" ] && cmp -s "$1" "$2"; }
# The checker: prints one verdict word per arm for (OFF page, ON page). Mutation controls call it on swapped / damaged pages.
cat >"$WORK/judge.py" <<'PY'
import re, sys
off, on = open(sys.argv[1]).read(), open(sys.argv[2]).read()
B = re.compile(r'<b [^>]*>(?:<!\[CDATA\[.*?\]\]>|[^<])*?</b>|<b [^>]*>.*?</b>', re.S)
def outer(t):   # elements outside comments only
    return re.sub(r'<!--.*?-->', '', t, flags=re.S)
def attrs(tag): return dict(re.findall(r'(\w+)="([^"]*)"', tag))
def top(t):
    m = re.search(r'<act read="([^"]*)"', t)
    return m.group(1).split(',')[0].rsplit(':', 1)[0] if m else ''
def bodies(t): return [(attrs(x.group(0).split('>', 1)[0]), x.group(0)) for x in B.finditer(outer(t))]
T = top(off); ob = bodies(off); nb = bodies(on)
res = {}
res['E0'] = bool(T) and any(a.get('p') == T for a, _ in ob) and any(a.get('p') != T for a, _ in ob)
pointed = [a for a, _ in ob if a.get('p') == T]
skips = [attrs(x) for x in re.findall(r'<skip ([^>]*)/>', outer(on))]
lean = [s for s in skips if 'e' in s and 'next' not in s and 'bytes' not in s]
root = on.split('>', 1)[0]
res['E2'] = (not any(a.get('p') == T for a, _ in nb) and len(lean) == len(pointed) and
             all(s['p'] == a['p'] and s['n'] == a['n'] for s, a in zip(lean, pointed)) and
             ' body_form="edit"' in root and on.count('<!-- body_form=edit:') == 1)
act = re.search(r'<act read="([^"]*)"', on); vals = act.group(1).split(',') if act else []
def holds(r):
    p, le = r.rsplit(':', 1); l, e = map(int, le.split('-'))
    for v in vals:
        vp, vle = v.rsplit(':', 1); vl, ve = map(int, vle.split('-'))
        if vp == p and vl <= l and ve >= e: return True
    return False
res['E3'] = bool(lean) and all(holds(f"{s['p']}:{s['l']}-{s['e']}") for s in lean)
res['E4'] = [x for a, x in ob if a.get('p') != T] == [x for a, x in nb]
est = lambda t: int(re.search(r' est_tokens="(\d+)"', t.split('>', 1)[0]).group(1))
res['E6'] = est(on) < est(off) and len(on) < len(off)
print(' '.join(f'{k}={"1" if v else "0"}' for k, v in sorted(res.items())))
PY
judge(){ python3 "$WORK/judge.py" "$1" "$2" 2>/dev/null; }
J="$( judge "$WORK/edit.off" "$WORK/edit.on" )"; echo "  judge: $J"
arm(){ case " $J " in *" $1=1 "*) ok "$2";; *) no "$3";; esac; }
arm E0 "(E0) the OFF edit answer holds a body in its top file and one in another file" "(E0) vacuous: no top-file body or no other-file body on the OFF page"
if [ -n "$PARENT" ]; then
    for n in edit plain p2 whole; do if same "$WORK/$n.off" "$WORK/$n.pa"; then ok "(E1) $n: the default is the parent's answer byte for byte"; else no "(E1) $n: the default moved against the parent"; fi; done
else ok "(E1) no RIPWIRE_PARENT_BIN: parent comparison skipped (the lane runs it)"; fi
arm E2 "(E2) top-file bodies are lean skip rows in place; body_form=\"edit\"; one clause" "(E2) a top-file body is left, a skip row is wrong, or the root/clause is missing"
arm E3 "(E3) every pointed range is on act read=" "(E3) a pointed range is not on act read="
arm E4 "(E4) other-file bodies are unchanged, in order" "(E4) an other-file body moved or changed"
for n in plain p2 il; do if same "$WORK/$n.off" "$WORK/$n.on"; then ok "(E5) $n: byte-identical with the variable"; else no "(E5) $n: the variable changed it"; fi; done
if same "$WORK/pt.off" "$WORK/pt.on"; then ok "(E5) RIPWIRE_BODY_POINTERS=1 decides over RIPWIRE_BODIES_EDIT"; else no "(E5) the edit form overrode the pointer form"; fi
if [ -s "$WORK/pt.on" ] && grep -q 'body_form="pointer"' "$WORK/pt.on"; then ok "(E5) the pointer form is served under both variables"; else no "(E5) no pointer form under both variables"; fi
arm E6 "(E6) est_tokens= and the page are smaller than OFF" "(E6) est_tokens= or the page did not shrink"
if xmllint --noout "$WORK/edit.on" 2>/dev/null; then ok "(E7) well formed"; else no "(E7) xmllint rejects the ON page"; fi
if same "$WORK/edit.on" "$WORK/edit.on2"; then ok "(E7) two ON runs byte-identical"; else no "(E7) two ON runs differ"; fi
M="$( judge "$WORK/edit.off" "$WORK/edit.off" )"
case " $M " in *" E2=0 "*) ok "(E8) mutation: E2's detector fails on the OFF page";; *) no "(E8) E2's detector passed the OFF page";; esac
python3 - "$WORK/edit.on" "$WORK/edit.mut" <<'PY'
import re, sys
t = open(sys.argv[1]).read(); m = re.search(r'<b [^>]*>.*?</b>', t, re.S)
open(sys.argv[2], 'w').write(t[:m.start()] + t[m.end():] if m else t)
PY
M="$( judge "$WORK/edit.off" "$WORK/edit.mut" )"
case " $M " in *" E4=0 "*) ok "(E8) mutation: E4 fails with one other-file body removed";; *) no "(E8) E4 passed a page with a body removed";; esac
if [ "$fail" -eq 0 ]; then echo "bodyeditcheck: PASS"; exit 0; fi
echo "bodyeditcheck: FAIL"; exit 1
