#!/usr/bin/env bash
# ownerhopcheck.sh — the symbol a --for question is ABOUT gets a hop slot, first, with its callee names.
#
#   test/ownerhopcheck.sh                       # build/ripwire on test/ownerhopfix
#   test/ownerhopcheck.sh build_base/ripwire    # the RED run (a pre-change binary)
#   RIPWIRE_BASE_BIN=old/ripwire test/ownerhopcheck.sh   # adds the base-vs-head byte-identity arm (I)
#
# THE GAP (graded answers, round 1): the compact --for answer hop-expands only the first 6 positive-rank rows
# (packtask.h kPackTaskBodyCandidates, verbs_for.h buildForCompactHops) inside a ~1 KB hop budget. When the
# question names the function it is about ("How does the JWT middleware verify a token?" -> jwt(), rank 12;
# "How does Fastify validate a request ...?" -> validate(), rank 8), that function never gets a hop row, so its
# callees (getCookie, HTTPException, ctx.set, validateAsync*) — the gold items — are never named.
#
# THE CONTRACT (design note: $ORCH reports/owner-hop-068.md §Design).
#   OWNER. A ranked-head symbol is an OWNER of the question when (all of): its kind is callable (fn/method); it is a
#     DEFINITION (a C prototype and its body are ONE entity, the body's row); it is not a test symbol; its name, with
#     leading _ # $ @ removed and ASCII case folded, EQUALS a whole word of the question (length >= 3, not a route
#     stopword) — whole name only, never a substring ("log" never matches catalog/dialog); and that word has at
#     least one such definition inside the head tier (rank <= serialize.h kForDocExcerptRankCount = 24). Every
#     same-named definition of an owner word in the ranked pool is shown (never one picked silently), each as its own
#     row (entity identity: two classes' _notify are two rows).
#   SLOT. Owner rows come FIRST in <hops>, in rank order, regardless of the 6-candidate cap; each carries
#     qword="<the question word>". An owner that was already a hop candidate is moved, never duplicated. At most 3
#     owner rows; the rest are disclosed: <hops qword_cut="N" next="--callees=FILE:NAME"> (the first one cut).
#   EDGES. The hop-slot rule still applies (>= 1 proven callee edge, else counted in noedge=). An owner row lists ALL
#     its callee names (not the 16 a ranked hop shows) up to a runaway guard; past it: capped="1" + next=.
#     A callee bound by name alone keeps FE-B's via="name" hedge (a builtin method, a test-file def, an untyped
#     receiver) — never an unhedged claim.
#   BUDGET. Default regime: owner rows ride ON TOP of the hop budget (completeness first; the existing hop rows keep
#     their budget, so every pre-change <h> row is still served). Explicit --token-budget: owner rows are funded
#     first; anything cut is disclosed by the existing capped="1".
#   OFF. A question that names no owner is byte-identical to before; RIPWIRE_NO_OWNER_HOP=1 restores the pre-change
#     answer everywhere (the A/B handle the no-regression arms compare against). --json and the MCP `for` verb serve
#     no hop block today and stay byte-identical.
#
# ARMS (fixture roots under test/ownerhopfix/, each indexed on its own, --no-cache):
#   (P)  positive: TS gateway (rank 7..24, beyond the 6-cap) is the FIRST <h> row with qword="gateway" and names
#        readCookie + checkSessionToken; Python two _notify owners (Reactive, Signal) -> two rows, distinct l=;
#        C scan: ONE row, the table.c definition (the table.h prototype is not a second owner).
#   (F)  false-claim (needs FE-B; SKIP by name "expects FE-B" when the binary's own callee rows carry no via=):
#        gateway's remember (untyped receiver) and encode (a test-file def of a builtin method name) carry
#        via="name" inside the owner row; no unhedged <c> row of an owner names a test-file definition.
#   (Z)  zero proven callees: C collect (only an indirect call) gets no row and is counted in noedge=.
#   (N)  near misses: "the log" never makes catalog/dialog owners; a class (Reactive) is never an owner; a word
#        whose only definition is a test file (encode) is no owner; a non-code question carries no qword=.
#   (T)  tier: a word whose only definition ranks > 24 makes no owner (broadcast); a word with one head-tier
#        definition shows EVERY same-named definition in the pool (the second _notify ranks > 24, still a row).
#   (C)  cap: five owners -> 3 rows + qword_cut="2" + next="--callees=..." naming the first cut owner.
#   (G)  guard: dispatch (20 callees) lists all 20 names; broadcast (105 callees) lists the guard's worth with
#        capped="1" and next="--callees=pkg/broadcast.py:broadcast".
#   (R)  no-regression: every <h> row of the RIPWIRE_NO_OWNER_HOP=1 answer is still served, same <calls> content,
#        same relative order (owner rows removed); non-owner questions byte-identical to the A/B handle.
#   (B)  explicit --token-budget=4000 (hops fit): the owner row is first, est_tokens <= 4000 or over_ceiling="1";
#        --token-budget=1200 (ceiling spent, reason="budget"): byte-identical to the A/B handle.
#   (J)  --json --for and MCP `for` byte-identical to the A/B handle (no hop surface there).
#   (L)  legend: the qword clause is present iff a qword row is, and says "by name" (not a resolution claim).
#   (I)  optional: RIPWIRE_BASE_BIN set -> 12 out-of-scope argv byte-identical base vs head.
#
# Exit: 0 all PASS (named SKIPs allowed), 1 any FAIL, 2 missing prerequisite.

set -u
ROOT="$( cd "$( dirname "$0" )/.." && pwd )"
BIN="${1:-${RIPWIRE_BIN:-$ROOT/build/ripwire}}"
[ "${BIN#/}" = "$BIN" ] && BIN="$PWD/$BIN"
FIX="$ROOT/test/ownerhopfix"
fail=0
ok(){ printf '  PASS  %s\n' "$*" || { fail=1; printf '  FAIL  could not write the PASS line for: %s\n' "$*"; }; return 0; }
no(){ printf '  FAIL  %s\n' "$*"; fail=1; }
skip(){ printf '  SKIP  %s\n' "$*"; }
[ -x "$BIN" ] || { echo "ownerhopcheck: no ripwire binary at $BIN — build first"; exit 2; }
command -v python3 >/dev/null 2>&1 || { echo "ownerhopcheck: python3 required"; exit 2; }
echo "ownerhopcheck: BIN=$BIN"
TMP="$( mktemp -d )"; trap 'rm -rf "$TMP"' EXIT

# run ROOTNAME OUTFILE ARGS... — in the fixture root, --no-cache; records the binary's own rc next to the output
run(){ local r="$1" f="$2"; shift 2; ( cd "$FIX/$r" && "$BIN" . --no-cache "$@" >"$f" 2>"$f.err" ); printf '%s' "$?" >"$f.rc"; }
runoff(){ local r="$1" f="$2"; shift 2; ( cd "$FIX/$r" && RIPWIRE_NO_OWNER_HOP=1 "$BIN" . --no-cache "$@" >"$f" 2>"$f.err" ); printf '%s' "$?" >"$f.rc"; }
ran_ok(){ local rc; rc="$( cat "$1.rc" 2>/dev/null )"; [ "$rc" = 0 ] && [ -s "$1" ] && return 0; no "$2: the binary exited rc=${rc:-missing} or printed nothing"; return 1; }

cat >"$TMP/h.py" <<'PY'
import re, sys, html, json
def attrs(s): return {k: html.unescape(v) for k, v in re.findall(r'([\w:]+)="([^"]*)"', s)}
def hops(x):
    m = re.search(r'<hops([^>]*)>(.*?)</hops>', x, re.S)
    if not m: return None, []
    rows = []
    for h in re.finditer(r'<h ([^>]*)>(.*?)</h>', m.group(2), re.S):
        ca = re.search(r'<calls([^>]*)>', h.group(2))
        rows.append(dict(a=attrs(h.group(1)), raw=h.group(0), calls=[attrs(c.group(1)) for c in re.finditer(r'<c ([^>]*?)/?>', h.group(2))],
                         ca=attrs(ca.group(1)) if ca else {}))
    return attrs(m.group(1)), rows
def cands(x):
    return [attrs(m.group(1)) for m in re.finditer(r'<cand ([^>]*)>', x)]
cmd = sys.argv[1]
x = open(sys.argv[2]).read()
if cmd == 'hops':      # one JSON line: {hops attrs, rows:[{n,l,p,qword,calls:[{n,via}], ca}]}
    ha, rows = hops(x)
    print(json.dumps({'hops': ha, 'rows': [dict(r['a'], calls=r['calls'], ca=r['ca'], raw=r['raw']) for r in rows]}))
elif cmd == 'rank':    # rank of name N (first def, optional path substring P) in --format=candidates output
    n = sys.argv[3]; p = sys.argv[4] if len(sys.argv) > 4 else ''
    rs = [int(a['r']) for a in cands(x) if a.get('n') == n and p in a.get('p', '')]
    print(rs[0] if rs else -1)
elif cmd == 'root':
    m = re.search(r'<ctx ([^>]*)>', x); print(json.dumps(attrs(m.group(1)) if m else {}))
PY
H(){ python3 "$TMP/h.py" "$@"; }
J(){ python3 -c "import json,sys; d=json.loads(sys.stdin.read()); print(eval(sys.argv[1]))" "$1"; }

# ── premises: the fixture still reproduces the gap (rank beyond the 6-cap, inside the head tier) ──────────────────────
QTS="How does the gateway check a session token?"
QPY="How does notify propagate a reactive change?"
QC="How does scan walk the process tables?"
premise(){ # root question name pathsub lo hi
    local f="$TMP/prem.$1.$3.xml"; run "$1" "$f" "--for=$2" --format=candidates
    ran_ok "$f" "premise $1/$3" || return 1
    local r; r="$( H rank "$f" "$3" "$4" )"
    if ! [[ "$r" =~ ^-?[0-9]+$ ]]; then no "premise $1/$3: rank not numeric ('$r')"; return 1; fi
    if [ "$r" -ge "$5" ] && [ "$r" -le "$6" ]; then ok "premise $1: $3 ranks $r (in $5..$6)"; else no "premise $1: $3 ranks $r, outside $5..$6 — the fixture no longer reproduces the gap; re-tune it"; fi
}
premise ts "$QTS" gateway src/middleware 7 24
premise py "$QPY" _notify pkg/reactive 7 24
premise c  "$QC"  scan table.c 7 24

# ── (P) positive ─────────────────────────────────────────────────────────────────────────────────────────────────────
f="$TMP/ts.p.xml"; run ts "$f" "--for=$QTS"
if ran_ok "$f" "(P/TS)"; then
    H hops "$f" >"$TMP/ts.p.json"
    first="$( J "(d['rows'][0]['n'], d['rows'][0].get('qword',''), d['rows'][0]['p']) if d['rows'] else None" <"$TMP/ts.p.json" )"
    if [ "$first" = "('gateway', 'gateway', 'src/middleware/gateway.ts')" ]; then ok "(P/TS) first <h> row is gateway with qword=\"gateway\""; else no "(P/TS) first <h> row is $first, want gateway / qword=gateway (rank-13 owner beyond the 6-cap)"; fi
    names="$( J "sorted(c['n'] for r in d['rows'] if r['n']=='gateway' for c in r['calls'])" <"$TMP/ts.p.json" )"
    case "$names" in *readCookie*checkSessionToken*|*checkSessionToken*readCookie*) ok "(P/TS) owner row names readCookie and checkSessionToken ($names)";;
        *) no "(P/TS) owner row callee names $names lack readCookie/checkSessionToken";; esac
    dup="$( J "sum(1 for r in d['rows'] if r['n']=='gateway')" <"$TMP/ts.p.json" )"
    if [ "$dup" = 1 ]; then ok "(P/TS) gateway appears in exactly one <h> row"; else no "(P/TS) gateway <h> rows: $dup (want 1)"; fi
fi
f="$TMP/py.p.xml"; run py "$f" "--for=$QPY"
if ran_ok "$f" "(P/PY)"; then
    H hops "$f" >"$TMP/py.p.json"
    got="$( J "[(r['n'], r.get('qword',''), r['l']) for r in d['rows'][:2]]" <"$TMP/py.p.json" )"
    want="[('_notify', 'notify', '11'), ('_notify', 'notify', '23')]"
    if [ "$got" = "$want" ]; then ok "(P/PY) two same-named owners (Reactive._notify l=11, Signal._notify l=23) are the first two rows"; else no "(P/PY) first two rows $got, want $want (show each same-named owner, never one, never merged)"; fi
fi
f="$TMP/c.p.xml"; run c "$f" "--for=$QC"
if ran_ok "$f" "(P/C)"; then
    H hops "$f" >"$TMP/c.p.json"
    got="$( J "[(r['p'], r['l'], r.get('qword','')) for r in d['rows'] if r['n']=='scan']" <"$TMP/c.p.json" )"
    if [ "$got" = "[('table.c', '8', 'scan')]" ]; then ok "(P/C) scan: one owner row, the table.c definition (prototype not a second owner)"; else no "(P/C) scan rows $got, want [('table.c', '8', 'scan')]"; fi
    first="$( J "d['rows'][0]['n'] if d['rows'] else None" <"$TMP/c.p.json" )"
    if [ "$first" = scan ]; then ok "(P/C) scan is the first <h> row"; else no "(P/C) first <h> row is $first, want scan"; fi
fi

# ── (F) false-claim hedges (FE-B capability detected on the fixture's own name-only call) ─────────────────────────────
f="$TMP/ts.cl.xml"; run ts "$f" --callees=src/middleware/gateway.ts:gateway
if ran_ok "$f" "(F) capability probe"; then
    if grep -q 'n="remember"[^>]*via="name"' "$f"; then
        J "[(c['n'], c.get('via','')) for r in d['rows'] if r['n']=='gateway' for c in r['calls']]" <"$TMP/ts.p.json" >"$TMP/ts.f.txt" 2>/dev/null || echo "[]" >"$TMP/ts.f.txt"
        if grep -q "('remember', 'name')" "$TMP/ts.f.txt"; then ok "(F) owner row: remember (untyped receiver) carries via=\"name\""; else no "(F) owner row callee rows $(cat "$TMP/ts.f.txt"): remember must be present AND via=\"name\""; fi
        if grep -q "('encode', 'name')" "$TMP/ts.f.txt"; then ok "(F) owner row: encode (test-file def of a builtin method name) carries via=\"name\""; else no "(F) owner row callee rows $(cat "$TMP/ts.f.txt"): encode must be present AND via=\"name\""; fi
        if grep -q "('encode', '')\|('remember', '')" "$TMP/ts.f.txt"; then no "(F) an owner callee row asserts a name-only edge unhedged"
        else ok "(F) no unhedged name-only callee row under the owner"; fi
    else
        skip "(F) expects FE-B: this binary's --callees rows carry no via=\"name\" on the fixture's untyped receiver call"
    fi
fi

# ── (Z) zero proven callees ──────────────────────────────────────────────────────────────────────────────────────────
f="$TMP/c.z.xml"; run c "$f" "--for=How does collect gather the process tables?"
if ran_ok "$f" "(Z)"; then
    H hops "$f" >"$TMP/c.z.json"
    got="$( J "(sum(1 for r in d['rows'] if r['n']=='collect'), d['hops'].get('noedge','0') if d['hops'] is not None else 'nohops')" <"$TMP/c.z.json" )"
    case "$got" in "(0, '"[1-9]*) ok "(Z) collect (no resolvable callee) gets no <h> row and is counted in noedge ($got)";;
        *) no "(Z) collect rows/noedge = $got, want no row and noedge >= 1";; esac
fi

# ── (N) near misses ──────────────────────────────────────────────────────────────────────────────────────────────────
nq(){ # root question label — no qword= anywhere in the answer
    local f="$TMP/n.$1.$3.xml"; run "$1" "$f" "--for=$2"
    ran_ok "$f" "(N/$3)" || return
    grep -q '<hops' "$f" || { no "(N/$3) no <hops> block at all — the arm measured nothing"; return; }
    if grep -q 'qword=' "$f"; then no "(N/$3) carries qword= : $( grep -o '<h [^>]*qword="[^"]*"' "$f" | head -3 )"; else ok "(N/$3) no owner row"; fi
}
nq c  "How does the log walk the process tables?"        substring-log
nq ts "How is a session token encoded with encode?"      test-file-owner
nq ts "How does the team review pull requests?"          non-code-question
f="$TMP/n.py.cls.xml"; run py "$f" "--for=How does Reactive notify a change?"
if ran_ok "$f" "(N/class)"; then
    if grep -q '<h [^>]*n="Reactive"[^>]*qword=' "$f"; then no "(N/class) the class Reactive became an owner row"; else ok "(N/class) a class is never an owner row"; fi
fi

# ── (T) the head-tier gate is per WORD, never per definition ─────────────────────────────────────────────────────────
f="$TMP/py.t1.xml"; run py "$f" "--for=How does notify propagate a reactive change and broadcast?"
f2="$TMP/py.t1.cand"; run py "$f2" "--for=How does notify propagate a reactive change and broadcast?" --format=candidates
if ran_ok "$f" "(T/tail)" && ran_ok "$f2" "(T/tail) premise"; then
    r="$( H rank "$f2" broadcast )"
    if [[ "$r" =~ ^[0-9]+$ ]] && [ "$r" -gt 24 ]; then
        if grep -q '<h [^>]*n="broadcast"[^>]*qword=' "$f"; then no "(T/tail) broadcast (only definition ranks $r > 24) became an owner row"
        else ok "(T/tail) a word whose only definition ranks $r (> 24, the tail tier) makes no owner"; fi
    else no "(T/tail) premise: broadcast ranks '$r', want > 24 — re-tune the fixture"; fi
fi
q2="How does notify propagate a reactive change, then refresh and broadcast?"
f="$TMP/py.t2.xml"; run py "$f" "--for=$q2"; f2="$TMP/py.t2.cand"; run py "$f2" "--for=$q2" --format=candidates
if ran_ok "$f" "(T/each)" && ran_ok "$f2" "(T/each) premise"; then
    ranks="$( python3 -c "
import re,sys
x=open(sys.argv[1]).read()
print(sorted(int(r) for r,n in re.findall(r'<cand r=\"(\d+)\" s=\"[^\"]*\" n=\"([^\"]*)\"',x) if n=='_notify'))" "$f2" )"
    H hops "$f" >"$TMP/py.t2.json"
    got="$( J "sorted(r['l'] for r in d['rows'] if r['n']=='_notify' and r.get('qword')=='notify')" <"$TMP/py.t2.json" )"
    case "$ranks" in "["[0-9]*", 2"[5-9]"]"|"["[0-9]*", "[3-4][0-9]"]") 
        if [ "$got" = "['11', '23']" ]; then ok "(T/each) both _notify definitions are owner rows although one ranks in the tail ($ranks)"
        else no "(T/each) _notify owner rows l=$got, want ['11', '23'] (ranks $ranks): a same-named owner was picked silently"; fi;;
        *) no "(T/each) premise: _notify ranks $ranks, want one <= 24 and one > 24 — re-tune";; esac
fi

# ── (C) cap ──────────────────────────────────────────────────────────────────────────────────────────────────────────
f="$TMP/py.cap.xml"; run py "$f" "--for=How do invoke_watcher, schedule_refresh, record_signal and notify work?"
if ran_ok "$f" "(C)"; then
    H hops "$f" >"$TMP/py.cap.json"
    got="$( J "(sum(1 for r in d['rows'] if r.get('qword')), (d['hops'] or {}).get('qword_cut'), (d['hops'] or {}).get('next',''))" <"$TMP/py.cap.json" )"
    case "$got" in "(3, '2', '--callees="*) ok "(C) 3 owner rows, qword_cut=\"2\", next= names the first cut owner ($got)";;
        *) no "(C) owner rows / qword_cut / next = $got, want (3, '2', '--callees=FILE:NAME')";; esac
fi

# ── (G) all callee names up to the runaway guard ─────────────────────────────────────────────────────────────────────
f="$TMP/py.g1.xml"; run py "$f" "--for=How does dispatch route an event?"
if ran_ok "$f" "(G/20)"; then
    H hops "$f" >"$TMP/py.g1.json"
    got="$( J "[(len(r['calls']), r['ca'].get('capped','0')) for r in d['rows'] if r['n']=='dispatch']" <"$TMP/py.g1.json" )"
    if [ "$got" = "[(20, '0')]" ]; then ok "(G/20) dispatch's owner row lists all 20 callee names"; else no "(G/20) dispatch rows (names, capped) = $got, want [(20, '0')]"; fi
fi
f="$TMP/py.g2.xml"; run py "$f" "--for=How does broadcast send an event?"
if ran_ok "$f" "(G/guard)"; then
    H hops "$f" >"$TMP/py.g2.json"
    got="$( J "[(r['ca'].get('total'), r['ca'].get('capped'), r['ca'].get('next', r.get('next',''))) for r in d['rows'] if r['n']=='broadcast']" <"$TMP/py.g2.json" )"
    case "$got" in "[('105', '1', '--callees=pkg/broadcast.py:broadcast')]") ok "(G/guard) broadcast past the guard: capped=\"1\" + next= to the full list";;
        *) no "(G/guard) broadcast (total, capped, next) = $got, want [('105', '1', '--callees=pkg/broadcast.py:broadcast')]";; esac
fi

# ── (R) no-regression against the A/B handle ─────────────────────────────────────────────────────────────────────────
for spec in "ts|$QTS" "py|$QPY" "c|$QC"; do
    r="${spec%%|*}"; q="${spec#*|}"
    on="$TMP/r.$r.on.xml"; off="$TMP/r.$r.off.xml"; run "$r" "$on" "--for=$q"; runoff "$r" "$off" "--for=$q"
    ran_ok "$on" "(R/$r) head" && ran_ok "$off" "(R/$r) A/B" || continue
    H hops "$on" >"$on.json"; H hops "$off" >"$off.json"
    res="$( python3 - "$on.json" "$off.json" <<'PY'
import json, sys
on = json.load(open(sys.argv[1])); off = json.load(open(sys.argv[2]))
owners = {(r['p'], r['n'], r['l']) for r in on['rows'] if r.get('qword')}
base = [r for r in off['rows'] if (r['p'], r['n'], r['l']) not in owners]
head = [r for r in on['rows'] if not r.get('qword')]
key = lambda r: (r['p'], r['n'], r['l'], tuple((c['n'], c.get('l'), c.get('via')) for c in r['calls']))
missing = [k for k in map(key, base) if k not in set(map(key, head))]
order_ok = [key(r) for r in head if key(r) in set(map(key, base))] == [key(r) for r in base if key(r) in set(map(key, head))]
print('OK' if not missing and order_ok else 'BAD missing=%s order_ok=%s' % (missing[:3], order_ok))
PY
)"
    if [ "$res" = OK ]; then ok "(R/$r) every A/B <h> row is still served, same calls, same order"; else no "(R/$r) $res"; fi
done
for spec in "ts|How does the team review pull requests?" "c|How does the log walk the process tables?"; do
    r="${spec%%|*}"; q="${spec#*|}"
    on="$TMP/r2.$r.on.xml"; off="$TMP/r2.$r.off.xml"; run "$r" "$on" "--for=$q"; runoff "$r" "$off" "--for=$q"
    ran_ok "$on" "(R2/$r)" && ran_ok "$off" "(R2/$r) A/B" || continue
    if cmp -s "$on" "$off"; then ok "(R2/$r) a question with no owner is byte-identical to the A/B handle"; else no "(R2/$r) no-owner answer differs from RIPWIRE_NO_OWNER_HOP=1"; fi
done

# ── (B) explicit budget: owner funded first; an exhausted ceiling adds nothing ───────────────────────────────────────
f="$TMP/ts.b.xml"; run ts "$f" "--for=$QTS" --token-budget=4000
if ran_ok "$f" "(B1)"; then
    H hops "$f" >"$TMP/ts.b.json"; H root "$f" >"$TMP/ts.b.root"
    first="$( J "d['rows'][0]['n'] if d['rows'] else None" <"$TMP/ts.b.json" )"
    est="$( J "d.get('est_tokens','')" <"$TMP/ts.b.root" )"; over="$( J "d.get('over_ceiling','0')" <"$TMP/ts.b.root" )"
    if [ "$first" = gateway ]; then ok "(B1) under --token-budget=4000 the owner row is first"; else no "(B1) first row under --token-budget=4000 is $first, want gateway"; fi
    if [[ "$est" =~ ^[0-9]+$ ]]; then
        if { [ "$est" -le 4000 ] || [ "$over" = 1 ]; }; then ok "(B1) est_tokens=$est within 4000 (or over_ceiling disclosed)"; else no "(B1) est_tokens=$est > 4000 and no over_ceiling=\"1\""; fi
    else no "(B1) est_tokens missing or not numeric ('$est')"; fi
fi
on="$TMP/b2.on.xml"; off="$TMP/b2.off.xml"; run ts "$on" "--for=$QTS" --token-budget=1200; runoff ts "$off" "--for=$QTS" --token-budget=1200
if ran_ok "$on" "(B2)" && ran_ok "$off" "(B2) A/B"; then
    grep -q 'reason="budget"' "$off" || no "(B2) premise: --token-budget=1200 no longer exhausts the ceiling (no reason=\"budget\") — re-tune"
    if cmp -s "$on" "$off"; then ok "(B2) exhausted ceiling: byte-identical to the A/B handle (owner rows add nothing)"; else no "(B2) exhausted-ceiling answer changed"; fi
fi

# ── (J) JSON and MCP twins: no hop surface, byte-identical ───────────────────────────────────────────────────────────
on="$TMP/j.on.json"; off="$TMP/j.off.json"; run ts "$on" "--for=$QTS" --json; runoff ts "$off" "--for=$QTS" --json
if ran_ok "$on" "(J/json)" && ran_ok "$off" "(J/json) A/B"; then
    if cmp -s "$on" "$off"; then ok "(J/json) --json --for byte-identical to the A/B handle"; else no "(J/json) --json --for changed"; fi
fi
mcp(){ printf '{"jsonrpc":"2.0","id":1,"method":"tools/call","params":{"name":"for","arguments":{"path":"%s","task":"%s"}}}\n' "$FIX/ts" "$QTS" \
       | env $1 "$BIN" --mcp --no-cache >"$2" 2>"$2.err"; printf '%s' "$?" >"$2.rc"; }
mcp "RIPWIRE_X=0" "$TMP/m.on"; mcp "RIPWIRE_NO_OWNER_HOP=1" "$TMP/m.off"
if ran_ok "$TMP/m.on" "(J/mcp)" && ran_ok "$TMP/m.off" "(J/mcp) A/B"; then
    grep -q '"result"' "$TMP/m.on" || no "(J/mcp) no result object — the arm measured nothing"
    if cmp -s "$TMP/m.on" "$TMP/m.off"; then ok "(J/mcp) MCP for byte-identical to the A/B handle (signatures-only surface)"; else no "(J/mcp) MCP for changed"; fi
fi

# ── (L) legend ───────────────────────────────────────────────────────────────────────────────────────────────────────
if ! grep -q 'qword=' "$TMP/ts.p.xml" 2>/dev/null; then no "(L) no qword row on the positive answer — the legend arm measured nothing"
elif grep -q 'qword= [^;]*by name' "$TMP/ts.p.xml"; then ok "(L) qword legend clause present and says 'by name'"
else no "(L) qword row emitted without a legend clause that says it is by name"; fi
if grep -q 'qword' "$TMP/n.ts.non-code-question.xml" 2>/dev/null; then no "(L) qword legend clause on an answer with no owner row"; else ok "(L) no qword clause when no owner row"; fi

# ── (I) optional base-vs-head byte identity outside --for hop selection ──────────────────────────────────────────────
if [ -n "${RIPWIRE_BASE_BIN:-}" ] && [ -x "${RIPWIRE_BASE_BIN}" ]; then
    n=0; d=0
    while IFS='|' read -r r a; do
        [ -z "$r" ] && continue
        ( cd "$FIX/$r" && "$BIN" . --no-cache $a >"$TMP/i.h" 2>/dev/null; cd "$FIX/$r" && "$RIPWIRE_BASE_BIN" . --no-cache $a >"$TMP/i.b" 2>/dev/null )
        n=$((n+1)); cmp -s "$TMP/i.h" "$TMP/i.b" || { d=$((d+1)); echo "    differs: $r $a"; }
    done <<'ARGV'
ts|--callers=checkSessionToken
ts|--callees=src/middleware/gateway.ts:gateway
ts|--expand=gateway
ts|--top-k=20
py|--callers=invoke_watcher
py|--callees=dispatch
py|--expand=pkg/reactive.py:_notify
py|--top-k=20
c|--callers=Table_rowCount
c|--callees=scan
c|--expand=scan
c|--top-k=20
ARGV
    if [ "$d" = 0 ] && [ "$n" -gt 0 ]; then ok "(I) $n out-of-scope argv byte-identical base vs head"; else no "(I) $d of $n out-of-scope argv differ"; fi
else
    skip "(I) base-vs-head identity needs RIPWIRE_BASE_BIN"
fi

[ "$fail" = 0 ] && { echo "ownerhopcheck: OK"; exit 0; }
echo "ownerhopcheck: FAILURES ABOVE"; exit 1
