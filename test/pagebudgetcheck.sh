#!/usr/bin/env bash
# pagebudgetcheck.sh — SIZE-PAGE (src/forpagebudgetswitch.h the switch, src/forpages.h the cut):
# page 1 of a default paged `--for` answer obeys the budget_bytes= its root states.
# Default ON; RIPWIRE_PAGE_BUDGET=0 is off (byte-identical to the answer before the switch existed); 1-100 = that percent of today's
# page 1, above 100 = a fixed byte cap (measurement arms).
# ARMS (each counts what it saw and FAILS on zero)
#   (C)  THE CAP: on this repo's own answers that page, page 1 as served (every byte, the legend and the question-sites block
#        included) is no larger than its root's budget_bytes= (today's page 1; stated only where the off answer states one), and no
#        larger than the off answer's page 1 but for the cap's own extra digits (budget_bytes="7500" -> "14468")
#   (Cn) NEGATIVE: the off answer's page 1 exceeds the budget_bytes= it states (the defect the cap fixes) on at least one question
#   (I)  NO ITEM LEAVES PAGE 1 FOR THE CAP (budget-serves-answers: optional attributes are shed before an item, and the default cap
#        sheds neither): the default page 1 is the off page 1 byte for byte but for the budget_bytes= and est_tokens= digits — the
#        same rows, the same withheld_bytes=, the same next=; overflow is on page 2 by that next=, never dropped
#   (In) NEGATIVE: the RIPWIRE_PAGE_BUDGET=50 arm's page 1 is NOT its off page 1 so masked (a cap that cuts moves rows) — (I) can fail
#   (P)  ROW IDENTITY: following the root next= chain, the pages' tail rows joined equal the --page-bytes=0 answer's tail rows, in
#        order, no row twice — the cut never loses or repeats a row
#   (W)  WHOLE: the --page-bytes=0 answer is not capped — the off one, byte for byte
#   (K)  ARMS: RIPWIRE_PAGE_BUDGET=50 serves a smaller page 1 that fits its budget_bytes=; =9000 states budget_bytes="9000" and fits it;
#        =101 (below any cut, CR #759) serves the first cut and states a budget_bytes= that page fits
#   (E)  --rows=elements: page 1 holds the default's pages and states the line form's budget_bytes= (a lossless re-spelling, rowlinescheck L1)
#   (R)  every run exited 0 (P: every continuation too), and (P) reaches the last page the chain declares
#   (O)  OFF: RIPWIRE_PAGE_BUDGET=0 carries none of the cap's clauses; its budget_bytes= is the payload target (7500)
#   (D)  deterministic: two default runs are byte-identical
#   (V)  --version names pagebudget=on by default and pagebudget=off under RIPWIRE_PAGE_BUDGET=0
#   (X)  every page served is well-formed (xmllint when present)
set -u
ROOT="$( cd "$( dirname "$0" )/.." && pwd )"
BIN="${RIPWIRE_BIN:-${1:-$ROOT/build/ripwire}}"
[ "${BIN#/}" = "$BIN" ] && BIN="$ROOT/$BIN"
[ -x "$BIN" ] || { echo "no ripwire binary at $BIN -- build first (cmake --build build -j)"; exit 2; }
command -v python3 >/dev/null 2>&1 || { echo "pagebudgetcheck: python3 required"; exit 2; }
WORK="$( mktemp -d )"; trap 'rm -rf "$WORK"' EXIT
echo "pagebudgetcheck: BIN=$BIN"
unset RIPWIRE_PAGE_BUDGET
cd "$ROOT" || exit 2
QS=( "how does the answer-first page cut decide where page 1 ends and what the legend says about it"
     "where is the question-sites block appended and how many bytes may it hold"
     "how is a --for answer priced in est_tokens and where is the token budget enforced" )
# every run's exit status is kept: a run that writes its answer and then exits non-zero fails (R), whatever its bytes say
ok() { "$@" || echo "rc=$? $*" >>"$WORK/rc_fail.txt"; }
i=0
for q in "${QS[@]}"; do
    ok "$BIN" . --for="$q" >"$WORK/on$i.xml" 2>/dev/null
    ok "$BIN" . --for="$q" >"$WORK/on${i}b.xml" 2>/dev/null
    ok env RIPWIRE_PAGE_BUDGET=0 "$BIN" . --for="$q" >"$WORK/off$i.xml" 2>/dev/null
    ok env RIPWIRE_PAGE_BUDGET=50 "$BIN" . --for="$q" >"$WORK/p50_$i.xml" 2>/dev/null
    ok env RIPWIRE_PAGE_BUDGET=9000 "$BIN" . --for="$q" >"$WORK/b9000_$i.xml" 2>/dev/null
    ok env RIPWIRE_PAGE_BUDGET=101 "$BIN" . --for="$q" --legend=last >"$WORK/b101_$i.xml" 2>/dev/null
    ok "$BIN" . --for="$q" --rows=elements >"$WORK/el$i.xml" 2>/dev/null
    ok "$BIN" . --for="$q" --page-bytes=0 >"$WORK/u$i.xml" 2>/dev/null
    ok env RIPWIRE_PAGE_BUDGET=0 "$BIN" . --for="$q" --page-bytes=0 >"$WORK/uoff$i.xml" 2>/dev/null
    printf '%s' "$q" >"$WORK/q$i.txt"
    i=$(( i + 1 ))
done
ok "$BIN" --version >"$WORK/ver_on.txt" 2>&1
ok env RIPWIRE_PAGE_BUDGET=0 "$BIN" --version >"$WORK/ver_off.txt" 2>&1
python3 - "$WORK" "$BIN" "${#QS[@]}" <<'PY'
import os, re, subprocess, sys
work, binp, n = sys.argv[1], sys.argv[2], int(sys.argv[3])
fails = 0
def say(ok, msg):
    global fails
    print(("  PASS  " if ok else "  FAIL  ") + msg)
    fails += 0 if ok else 1
def rd(f): return open(os.path.join(work, f), 'rb').read().decode('utf-8', 'replace')
def root(t): m = re.search(r'<ctx\b[^>]*>', t); return m.group(0) if m else ''
def attr(tag, a):
    m = re.search(r'\s' + a + r'="([^"]*)"', tag); return m.group(1) if m else None
def paged(t): r = root(t); return attr(r, 'pages') not in (None, '1') and attr(r, 'page') == '1'
cap_seen = cap_neg = item_seen = item_neg = whole_seen = rows_seen = k_seen = e_seen = 0
for i in range(n):
    q = open(os.path.join(work, f'q{i}.txt')).read()
    on, off, u = rd(f'on{i}.xml'), rd(f'off{i}.xml'), rd(f'u{i}.xml')
    # (D)
    say(on == rd(f'on{i}b.xml'), f'(D) q{i}: two default runs byte-identical')
    # (C) / (Cn)
    ob = attr(root(off), 'budget_bytes')
    if paged(on):
        bb = attr(root(on), 'budget_bytes'); size = len(on.encode())
        stated = (bb is not None and size <= int(bb)) if ob is not None else bb is None   # the cap replaces a stated budget, adds none
        digits = max(0, len(bb) - len(ob)) if bb is not None and ob is not None else 0   # the cap's own extra digits: 7500 -> 14468
        say(stated and size <= len(off.encode()) + digits, f'(C) q{i}: page 1 {size} B <= budget_bytes="{bb}" (off states "{ob}") and no larger than the off page 1 ({len(off.encode())} B) + the cap\'s {digits} extra digit(s)')
        cap_seen += 1
    if ob is not None and len(off.encode()) > int(ob): cap_neg += 1
    # (I) / (In)
    digits = lambda t: re.sub(r'\sest_tokens="\d+"', ' est_tokens="#"', re.sub(r'\sbudget_bytes="\d+"', ' budget_bytes="#"', t, count=1), count=1)
    if paged(on):
        say(digits(on) == digits(off) and attr(root(on), 'next') == attr(root(off), 'next'),
            f'(I) q{i}: page 1 is the off page 1 but for the cap digits: no row leaves it, withheld_bytes="{attr(root(on), "withheld_bytes")}" == "{attr(root(off), "withheld_bytes")}", next= kept')
        item_seen += 1
        if digits(rd(f'p50_{i}.xml')) != digits(off): item_neg += 1
    # (W)
    say(u == rd(f'uoff{i}.xml'), f'(W) q{i}: the whole answer ({len(u.encode())} B) is the off one byte for byte'); whole_seen += 1
    # (P) follow the chain
    if paged(on):
        def tailrows(t):
            m = re.search(r'<tail\b[^>]*>(.*?)</tail>', t, re.S)
            return [l for l in (m.group(1).replace('<![CDATA[', '').replace(']]>', '').split('\n') if m else []) if l]
        got, page, k, rcs = tailrows(on), on, 1, []
        while paged(page) or (attr(root(page), 'page') not in (None,) and attr(root(page), 'page') != attr(root(page), 'pages')):
            nxt = attr(root(page), 'next')
            if not nxt or '--page-bytes=' not in nxt or k > 20: break   # a chain that ends early fails below: it never reached the last page
            pb = re.search(r"--page-bytes=(\d+:\d+)", nxt).group(1)
            run = subprocess.run([binp, '.', f'--for={q}', f'--page-bytes={pb}'], capture_output=True)
            rcs.append(run.returncode)
            page = run.stdout.decode('utf-8', 'replace')
            got += tailrows(page); k += 1
        reached = attr(root(page), 'page') == attr(root(page), 'pages') == attr(root(on), 'pages')
        want = tailrows(u)
        say(reached and not any(rcs) and got == want and len(set(got)) == len(got),
            f'(P) q{i}: {k} pages, the last (page {attr(root(page), "page")} of {attr(root(on), "pages")}) reached, exits {rcs}; {len(got)} tail rows joined == the whole answer\'s {len(want)}')
        rows_seen += 1
    # (K)
    p50, b9 = rd(f'p50_{i}.xml'), rd(f'b9000_{i}.xml')
    if paged(on):
        bb50 = attr(root(p50), 'budget_bytes'); bb9 = attr(root(b9), 'budget_bytes')
        say((bb50 is not None and len(p50.encode()) <= int(bb50) if ob is not None else bb50 is None) and len(p50.encode()) < len(on.encode()),
            f'(K) q{i}: RIPWIRE_PAGE_BUDGET=50 page 1 {len(p50.encode())} B <= budget_bytes="{bb50}", below the default {len(on.encode())} B')
        say((bb9 == '9000' if ob is not None else bb9 is None) and len(b9.encode()) <= 9000, f'(K) q{i}: RIPWIRE_PAGE_BUDGET=9000 states budget_bytes="{bb9}" and serves {len(b9.encode())} B')
        b1 = rd(f'b101_{i}.xml'); bb1 = attr(root(b1), 'budget_bytes')
        say((bb1 is not None and int(bb1) > 101 and len(b1.encode()) <= int(bb1)) if ob is not None else bb1 is None,
            f'(K) q{i}: RIPWIRE_PAGE_BUDGET=101 --legend=last: no cut fits, so the first cut is served and budget_bytes="{bb1}" states it ({len(b1.encode())} B)')
        k_seen += 1
    # (E)
    el = rd(f'el{i}.xml')
    if paged(el):
        be = attr(root(el), 'budget_bytes')
        say(be == attr(root(on), 'budget_bytes') and attr(root(el), 'pages') == attr(root(on), 'pages'),
            f'(E) q{i}: --rows=elements page 1 holds the default\'s {attr(root(el), "pages")} pages and states its budget_bytes="{be}" (the line form\'s; the row form is a lossless re-spelling, rowlinescheck (L1))')
        e_seen += 1
    # (O)
    say('caps every byte' not in off and 'budget_bytes=N' not in off and (ob in (None, '7500')),
        f'(O) q{i}: off carries no cap clause, budget_bytes="{ob}"')
    # (X)
    for name, t in (('on', on), ('off', off), ('p50', p50)):
        if subprocess.run(['sh', '-c', 'command -v xmllint'], capture_output=True).returncode == 0:
            r = subprocess.run(['xmllint', '--noout', '-'], input=t.encode(), capture_output=True)
            say(r.returncode == 0, f'(X) q{i} {name}: well-formed')
# counted arms fail on zero
for name, c in (('(C) capped pages', cap_seen), ('(Cn) off pages over their budget_bytes=', cap_neg), 
                ('(I) page 1s that keep every item', item_seen), ('(In) a 50 % cap moves rows', item_neg), ('(W) whole answers', whole_seen), ('(P) page chains', rows_seen), ('(K) arms', k_seen),
                ('(E) element-form pages', e_seen)):
    say(c > 0, f'{name}: {c} seen (an arm that saw nothing fails)')
rcf = os.path.join(work, 'rc_fail.txt')
say(not os.path.exists(rcf), '(R) every run exited 0' + ('' if not os.path.exists(rcf) else ': ' + open(rcf).read().strip().replace('\n', '; ')[:400]))
von, voff = open(os.path.join(work, 'ver_on.txt')).read(), open(os.path.join(work, 'ver_off.txt')).read()
say('pagebudget=on' in von and 'pagebudget=off' in voff, '(V) --version names pagebudget=on by default and pagebudget=off under RIPWIRE_PAGE_BUDGET=0')
print('pagebudgetcheck: ' + ('PASS' if fails == 0 else f'FAIL ({fails})'))
sys.exit(1 if fails else 0)
PY
