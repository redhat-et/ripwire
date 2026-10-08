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
#     row (entity identity: two classes' _notify are two rows). Question words are split on every non-identifier
#     byte, so "GATEWAY", `gateway()`, "gateway's" and "gateway?" all name the word gateway.
#   SLOT. Owner rows come FIRST in <hops>, regardless of the 6-candidate cap; each carries qword="<the word, folded>".
#     An owner that was already a hop candidate is moved, never duplicated. At most 3 owner rows, in rank order —
#     except that a word on the small common-English list (get, then, write, …) ranks AFTER every other owner word,
#     so verbs the question merely USES never spend the slots before the function it is about. The rest are
#     disclosed: <hops qword_cut="N" next="--callees=…"> (the first one cut). A cut owner that was already one of the
#     six candidates stays where it was, a plain row (qword_cut counts owners not served as an OWNER row).
#   EDGES. The hop-slot rule still applies (>= 1 proven callee edge, else counted in noedge= — exactly once, and an
#     owner that is not an owner row never takes a slot). An owner row lists ALL its callee names (not the 16 a
#     ranked hop shows) up to a runaway guard of 100; past it, and whenever an explicit budget cuts it: capped="1" +
#     next= on its <calls>. A callee bound by name alone keeps FE-B's via="name" hedge — never an unhedged claim.
#   BUDGET. Default regime: owner rows ride ON TOP of the hop budget (completeness first; the existing hop rows keep
#     their budget, so every pre-change <h> row is still served). Explicit --token-budget: owner rows are funded
#     first; a cut is disclosed (capped="1" + next= on the row, or qword_cut + next= when no row fits).
#   OFF. A question that names no owner is byte-identical to the base binary; RIPWIRE_NO_OWNER_HOP=1 restores the
#     base answer byte for byte everywhere (the A/B handle). --json and the MCP `for` verb serve no hop block today
#     and stay byte-identical (MCP/JSON owner-hop parity is a named follow-up).
#
# ARMS (fixture roots under test/ownerhopfix/, each indexed on its own, --no-cache):
#   (P)  positive: TS gateway (rank 7..24, beyond the 6-cap) is the FIRST <h> row with qword="gateway" and names
#        readCookie + checkSessionToken; Python two _notify owners (Reactive, Signal) -> two rows, distinct l=;
#        C scan: ONE row, the table.c definition (the table.h prototype is not a second owner).
#        (P/case) "GATEWAY" and (P/punct) `gateway()`, gateway's, gateway? give the same first row.
#   (D)  every <hops> block the gate parses: no (p,n,l) appears in two <h> rows (moved, never duplicated).
#   (F)  false-claim (FE-B is in the base): gateway's remember (untyped receiver) and encode (a test-file def of a
#        builtin method name) carry via="name" inside the owner row; no unhedged <c> row of an owner names a
#        test-file definition. A binary without the FE-B hedge FAILs (it is a regression now, not a missing premise).
#   (Z)  zero proven callees: C collect (only an indirect call; definition r12 + prototype r13) gets no row and
#        noedge(head) == noedge(A/B) + 1 exactly. (Z2) an owner whose only edge is name-only (relay -> remember):
#        no row, never double-counted, byte-identical to the A/B handle.
#   (N)  near misses: "the log" never makes catalog/dialog owners; a class (Reactive) is never an owner and a
#        class-only question is byte-identical to the A/B handle; a word whose only definition is a test file
#        (encode, which has a proven callee) is no owner — byte-identical to the A/B handle; a non-code question carries
#        no qword=.
#   (T)  tier: a word whose only definition ranks > 24 makes no owner (broadcast); a word with one head-tier
#        definition shows EVERY same-named definition in the pool (the second _notify ranks > 24, still a row).
#   (C)  cap: five owners -> exactly Signal._notify, Reactive._notify, invoke_watcher (rank order) + qword_cut="2" +
#        next="--callees=pkg/reactive.py:schedule_refresh"; the two cut owners stay plain rows; (R) holds.
#   (V)  common verbs: get/then/write methods rank above gateway — gateway is still the first owner row; the verbs
#        fill the remaining two slots in rank order; qword_cut="1" next= names the third.
#   (G)  guard: dispatch (20 callees) lists all 20 names; broadcast (105 callees) lists exactly 100 (the guard) with
#        capped="1" and next="--callees=pkg/broadcast.py:broadcast".
#   (R)  no-regression: every <h> row of the RIPWIRE_NO_OWNER_HOP=1 answer is still served, in the same relative order
#        (owner rows removed), with EXACTLY the same <calls> on the five fixture questions; (R/prefix) only where a moved
#        owner frees budget (gain: fanout moves out of the ranked rows, push_batch 5 -> 12 names, premise >= 1 row gains)
#        the A/B row's <calls> are a strict PREFIX of the head row's (more names of the same walk, never fewer, never
#        others); and on every (R) question <sigs> and <tail> are byte-identical to the A/B handle. Non-owner questions
#        are byte-identical to the A/B handle.
#   (S)  sigs: where the owner rows ALONE switch on the header's via="name" clause (premise: the A/B answer has no via
#        clause, the head has it — gateway's remember/encode are name-only callees, no ranked hop has one), <sigs> and
#        <tail> are byte-identical to the A/B handle in both dialects, default and --token-budget=3000 (the clause is a
#        disclosure exempt from the sig trim, exactly as the qword clause is; charged, it cost a signature row).
#   (B)  explicit --token-budget=4500 (hops fit): the owner row is first, est_tokens <= 4500 or over_ceiling="1"; at 4000
#        (less room than the owner row needs) the owner is first or named by qword_cut + next=;
#        --token-budget=1200 (ceiling spent, reason="budget"): byte-identical to the A/B handle. (B3) a budget sweep
#        on broadcast: every owner row it serves is disclosed (capped="1" + next=), an absent one is disclosed
#        (qword_cut + next= or reason="budget"), and at least one budget funds the row only partly.
#   (J)  --json --for and MCP `for` byte-identical to the A/B handle (no hop surface there).
#   (L)  legend: the qword clause is present iff a qword row is, and says "by name" (not a resolution claim).
#   (I)  RIPWIRE_BASE_BIN set: head + RIPWIRE_NO_OWNER_HOP=1 vs base on the --for / --json / MCP / budget answers,
#        head (no knob) vs base on the no-owner questions, plus 12 out-of-scope argv — every binary's rc checked.
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
if cmd == 'hops':      # one JSON line: {hops attrs, rows:[{n,l,p,qword,calls:[{n,via}], ca}], dups:[(p,n,l) seen twice]}
    ha, rows = hops(x)
    keys = [(r['a'].get('p'), r['a'].get('n'), r['a'].get('l')) for r in rows]
    dups = sorted({k for k in keys if keys.count(k) > 1})
    print(json.dumps({'hops': ha, 'rows': [dict(r['a'], calls=r['calls'], ca=r['ca'], raw=r['raw']) for r in rows], 'dups': dups}))
elif cmd == 'rank':    # rank of name N (first def, optional path substring P) in --format=candidates output
    n = sys.argv[3]; p = sys.argv[4] if len(sys.argv) > 4 else ''
    rs = [int(a['r']) for a in cands(x) if a.get('n') == n and p in a.get('p', '')]
    print(rs[0] if rs else -1)
elif cmd == 'root':
    m = re.search(r'<ctx ([^>]*)>', x); print(json.dumps(attrs(m.group(1)) if m else {}))
PY
H(){ python3 "$TMP/h.py" "$@"; }
J(){ python3 -c "import json,sys; d=json.loads(sys.stdin.read()); print(eval(sys.argv[1]))" "$1"; }
# HJ XML JSON LABEL — parse the <hops> block AND assert (D): no (p,n,l) in two <h> rows (C2: moved, never duplicated)
ndup=0
HJ(){ H hops "$1" >"$2"; local d; d="$( J "d['dups']" <"$2" )"; ndup=$((ndup+1))
      if [ "$d" != "[]" ]; then no "(D) $3: an <h> row appears twice (owner moved AND left in place): $d"; fi; }

# ── premises: the fixture still reproduces the gap (rank beyond the 6-cap, inside the head tier) ──────────────────────
QTS="How does the gateway check a session token?"
QPY="How does notify propagate a reactive change?"
QC="How does scan walk the process tables?"
QCAP="How do invoke_watcher, schedule_refresh, record_signal and notify work?"
QV="How does the gateway get the session token, check it, then write it?"
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
premise ts "$QV"  gateway src/middleware 7 24

# ── (P) positive ─────────────────────────────────────────────────────────────────────────────────────────────────────
f="$TMP/ts.p.xml"; run ts "$f" "--for=$QTS"
if ran_ok "$f" "(P/TS)"; then
    HJ "$f" "$TMP/ts.p.json" "(P/TS)"
    first="$( J "(d['rows'][0]['n'], d['rows'][0].get('qword',''), d['rows'][0]['p']) if d['rows'] else None" <"$TMP/ts.p.json" )"
    if [ "$first" = "('gateway', 'gateway', 'src/middleware/gateway.ts')" ]; then ok "(P/TS) first <h> row is gateway with qword=\"gateway\""; else no "(P/TS) first <h> row is $first, want gateway / qword=gateway (rank-14 owner beyond the 6-cap)"; fi
    names="$( J "sorted(c['n'] for r in d['rows'] if r['n']=='gateway' for c in r['calls'])" <"$TMP/ts.p.json" )"
    case "$names" in *readCookie*checkSessionToken*|*checkSessionToken*readCookie*) ok "(P/TS) owner row names readCookie and checkSessionToken ($names)";;
        *) no "(P/TS) owner row callee names $names lack readCookie/checkSessionToken";; esac
    dup="$( J "sum(1 for r in d['rows'] if r['n']=='gateway')" <"$TMP/ts.p.json" )"
    if [ "$dup" = 1 ]; then ok "(P/TS) gateway appears in exactly one <h> row"; else no "(P/TS) gateway <h> rows: $dup (want 1)"; fi
fi
# (P/case, P/punct) the question's spelling of the word: case folded, punctuation splits (C4 — hono-13 is "JWT")
pq=0
for q in "How does the GATEWAY check a session token?" 'How does `gateway()` check a session token?' \
         "How does the gateway's check treat a session token?" "What does gateway? check in a session token"; do
    pq=$((pq+1)); f="$TMP/ts.pq$pq.xml"; run ts "$f" "--for=$q"
    ran_ok "$f" "(P/spelling $pq)" || continue
    HJ "$f" "$TMP/ts.pq$pq.json" "(P/spelling $pq)"
    first="$( J "(d['rows'][0]['n'], d['rows'][0].get('qword',''), d['rows'][0]['p']) if d['rows'] else None" <"$TMP/ts.pq$pq.json" )"
    if [ "$first" = "('gateway', 'gateway', 'src/middleware/gateway.ts')" ]; then ok "(P/spelling) '$q': first row gateway, qword=\"gateway\""
    else no "(P/spelling) '$q': first row $first, want gateway / qword=gateway"; fi
done
f="$TMP/py.p.xml"; run py "$f" "--for=$QPY"
if ran_ok "$f" "(P/PY)"; then
    HJ "$f" "$TMP/py.p.json" "(P/PY)"
    got="$( J "[(r['n'], r.get('qword',''), r['l']) for r in d['rows'][:2]]" <"$TMP/py.p.json" )"
    want="[('_notify', 'notify', '11'), ('_notify', 'notify', '23')]"
    if [ "$got" = "$want" ]; then ok "(P/PY) two same-named owners (Reactive._notify l=11, Signal._notify l=23) are the first two rows"; else no "(P/PY) first two rows $got, want $want (show each same-named owner, never one, never merged)"; fi
fi
f="$TMP/c.p.xml"; run c "$f" "--for=$QC"
if ran_ok "$f" "(P/C)"; then
    HJ "$f" "$TMP/c.p.json" "(P/C)"
    got="$( J "[(r['p'], r['l'], r.get('qword','')) for r in d['rows'] if r['n']=='scan']" <"$TMP/c.p.json" )"
    if [ "$got" = "[('table.c', '8', 'scan')]" ]; then ok "(P/C) scan: one owner row, the table.c definition (prototype not a second owner)"; else no "(P/C) scan rows $got, want [('table.c', '8', 'scan')]"; fi
    first="$( J "d['rows'][0]['n'] if d['rows'] else None" <"$TMP/c.p.json" )"
    if [ "$first" = scan ]; then ok "(P/C) scan is the first <h> row"; else no "(P/C) first <h> row is $first, want scan"; fi
fi

# ── (F) false-claim hedges — FE-B is in the base now: a missing hedge is a FAIL, never a SKIP (C9) ────────────────────
f="$TMP/ts.cl.xml"; run ts "$f" --callees=src/middleware/gateway.ts:gateway
if ran_ok "$f" "(F) capability probe"; then
    if grep -q 'n="remember"[^>]*via="name"' "$f"; then
        J "[(c['n'], c.get('via','')) for r in d['rows'] if r['n']=='gateway' for c in r['calls']]" <"$TMP/ts.p.json" >"$TMP/ts.f.txt" 2>/dev/null || echo "[]" >"$TMP/ts.f.txt"
        if grep -q "('remember', 'name')" "$TMP/ts.f.txt"; then ok "(F) owner row: remember (untyped receiver) carries via=\"name\""; else no "(F) owner row callee rows $(cat "$TMP/ts.f.txt"): remember must be present AND via=\"name\""; fi
        if grep -q "('encode', 'name')" "$TMP/ts.f.txt"; then ok "(F) owner row: encode (test-file def of a builtin method name) carries via=\"name\""; else no "(F) owner row callee rows $(cat "$TMP/ts.f.txt"): encode must be present AND via=\"name\""; fi
        if grep -q "('encode', '')\|('remember', '')" "$TMP/ts.f.txt"; then no "(F) an owner callee row asserts a name-only edge unhedged"
        else ok "(F) no unhedged name-only callee row under the owner"; fi
    else
        no "(F) FE-B hedge missing: --callees rows carry no via=\"name\" on the fixture's untyped receiver call (FE-B is in the base; this is a regression)"
    fi
fi

# ── (Z) zero proven callees: no row, noedge exactly +1 (a C prototype must not count twice) ─────────────────────────
qz="How does collect gather the process tables?"
f="$TMP/c.z.xml"; run c "$f" "--for=$qz"; fo="$TMP/c.z.off.xml"; runoff c "$fo" "--for=$qz"
if ran_ok "$f" "(Z)" && ran_ok "$fo" "(Z) A/B"; then
    HJ "$f" "$TMP/c.z.json" "(Z)"; HJ "$fo" "$TMP/c.z.off.json" "(Z) A/B"
    rows="$( J "sum(1 for r in d['rows'] if r['n']=='collect')" <"$TMP/c.z.json" )"
    ne="$( J "(d['hops'] or {}).get('noedge','0')" <"$TMP/c.z.json" )"; neo="$( J "(d['hops'] or {}).get('noedge','0')" <"$TMP/c.z.off.json" )"
    if [[ "$ne" =~ ^[0-9]+$ ]] && [[ "$neo" =~ ^[0-9]+$ ]]; then
        if [ "$rows" = 0 ] && [ "$ne" -eq $((neo+1)) ]; then ok "(Z) collect (no resolvable callee) gets no <h> row; noedge $neo -> $ne (exactly +1: definition and prototype are one owner)"
        else no "(Z) collect rows=$rows noedge head=$ne A/B=$neo, want rows=0 and noedge = A/B + 1"; fi
    else no "(Z) noedge not numeric (head '$ne', A/B '$neo')"; fi
fi
# (Z2) an owner whose only out-edge is name-only (FE-B): the 26b hop-slot rule — no row, counted once, nothing else moves
qz2="How does relay forward a request?"
f="$TMP/ts.z2.xml"; run ts "$f" "--for=$qz2"; fo="$TMP/ts.z2.off.xml"; runoff ts "$fo" "--for=$qz2"
if ran_ok "$f" "(Z2)" && ran_ok "$fo" "(Z2) A/B"; then
    HJ "$f" "$TMP/ts.z2.json" "(Z2)"
    rows="$( J "sum(1 for r in d['rows'] if r['n']=='relay')" <"$TMP/ts.z2.json" )"
    ne="$( J "(d['hops'] or {}).get('noedge','0')" <"$TMP/ts.z2.json" )"
    if [ "$rows" = 0 ] && [[ "$ne" =~ ^[1-9][0-9]*$ ]] && cmp -s "$f" "$fo"; then ok "(Z2) relay (name-only edge only): no row, noedge=$ne, byte-identical to the A/B handle (counted once)"
    else no "(Z2) relay rows=$rows noedge=$ne identical=$( cmp -s "$f" "$fo" && echo 1 || echo 0 ), want 0 / >=1 / 1"; fi
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
qtf="How is a session token encoded with encode?"
f="$TMP/n.ts.tf.on.xml"; run ts "$f" "--for=$qtf"; fo="$TMP/n.ts.tf.off.xml"; runoff ts "$fo" "--for=$qtf"
if ran_ok "$f" "(N/test-file A/B)" && ran_ok "$fo" "(N/test-file A/B) knob"; then
    if cmp -s "$f" "$fo"; then ok "(N/test-file) the test-file encode (with a proven callee) is no owner: byte-identical to the A/B handle (no row, no noedge count)"
    else no "(N/test-file) '$qtf' differs from RIPWIRE_NO_OWNER_HOP=1 — a test-file definition became an owner"; fi
fi
nq ts "How does the team review pull requests?"          non-code-question
f="$TMP/n.py.cls.xml"; run py "$f" "--for=How does Reactive notify a change?"
if ran_ok "$f" "(N/class)"; then
    if grep -q '<h [^>]*n="Reactive"[^>]*qword=' "$f"; then no "(N/class) the class Reactive became an owner row"; else ok "(N/class) a class is never an owner row"; fi
fi
qcls="How does Reactive work?"
f="$TMP/n.py.cls2.xml"; run py "$f" "--for=$qcls"; fo="$TMP/n.py.cls2.off.xml"; runoff py "$fo" "--for=$qcls"
if ran_ok "$f" "(N/class-only)" && ran_ok "$fo" "(N/class-only) A/B"; then
    if cmp -s "$f" "$fo"; then ok "(N/class-only) a question whose only code word is a class is byte-identical to the A/B handle (no row, no noedge count)"
    else no "(N/class-only) '$qcls' differs from RIPWIRE_NO_OWNER_HOP=1 (a class became an owner, or a noedge count)"; fi
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
    HJ "$f" "$TMP/py.t2.json" "(T/each)"
    got="$( J "sorted(r['l'] for r in d['rows'] if r['n']=='_notify' and r.get('qword')=='notify')" <"$TMP/py.t2.json" )"
    case "$ranks" in "["[0-9]*", 2"[5-9]"]"|"["[0-9]*", "[3-4][0-9]"]")
        if [ "$got" = "['11', '23']" ]; then ok "(T/each) both _notify definitions are owner rows although one ranks in the tail ($ranks)"
        else no "(T/each) _notify owner rows l=$got, want ['11', '23'] (ranks $ranks): a same-named owner was picked silently"; fi;;
        *) no "(T/each) premise: _notify ranks $ranks, want one <= 24 and one > 24 — re-tune";; esac
fi

# ── (C) cap: which three, in which order, the exact next=, and a cut owner stays a plain row (C3) ───────────────────
f="$TMP/py.cap.xml"; run py "$f" "--for=$QCAP"
if ran_ok "$f" "(C)"; then
    HJ "$f" "$TMP/py.cap.json" "(C)"
    got="$( J "[(r['n'], r['l'], r.get('qword')) for r in d['rows'] if r.get('qword')]" <"$TMP/py.cap.json" )"
    want="[('_notify', '23', 'notify'), ('_notify', '11', 'notify'), ('invoke_watcher', '29', 'invoke_watcher')]"
    if [ "$got" = "$want" ]; then ok "(C) the 3 owner rows are Signal._notify, Reactive._notify, invoke_watcher (rank order)"; else no "(C) owner rows $got, want $want"; fi
    got="$( J "((d['hops'] or {}).get('qword_cut'), (d['hops'] or {}).get('next',''))" <"$TMP/py.cap.json" )"
    if [ "$got" = "('2', '--callees=pkg/reactive.py:schedule_refresh')" ]; then ok "(C) qword_cut=\"2\" next= names the first cut owner by rank (schedule_refresh)"
    else no "(C) (qword_cut, next) = $got, want ('2', '--callees=pkg/reactive.py:schedule_refresh')"; fi
    got="$( J "sorted((r['n'], r.get('qword','')) for r in d['rows'] if r['n'] in ('schedule_refresh','record_signal'))" <"$TMP/py.cap.json" )"
    if [ "$got" = "[('record_signal', ''), ('schedule_refresh', '')]" ]; then ok "(C) the two cut owners (already hop candidates) stay plain rows"
    else no "(C) cut owners' rows $got, want each once as a plain row (no qword)"; fi
fi

# ── (V) common English verbs never starve the owner the question is about (C8) ───────────────────────────────────────
f="$TMP/ts.v.xml"; run ts "$f" "--for=$QV"; f2="$TMP/ts.v.cand"; run ts "$f2" "--for=$QV" --format=candidates
if ran_ok "$f" "(V)" && ran_ok "$f2" "(V) premise"; then
    rg="$( H rank "$f2" get )"; rt="$( H rank "$f2" then )"; rw_="$( H rank "$f2" write )"; rgw="$( H rank "$f2" gateway src/middleware )"
    if [[ "$rg$rt$rw_$rgw" =~ ^[0-9]+$ ]] && [ "$rg" -lt "$rgw" ] && [ "$rt" -lt "$rgw" ] && [ "$rw_" -lt "$rgw" ]; then
        # the verbs in rank order: the first two fill the slots after gateway, the third is the one cut
        order="$( printf '%s get\n%s then\n%s write\n' "$rg" "$rt" "$rw_" | sort -n | awk '{print $2}' | tr '\n' ' ' )"
        set -- $order; v1="$1"; v2="$2"; v3="$3"
        HJ "$f" "$TMP/ts.v.json" "(V)"
        got="$( J "[(r['n'], r.get('qword')) for r in d['rows'] if r.get('qword')]" <"$TMP/ts.v.json" )"
        want="[('gateway', 'gateway'), ('$v1', '$v1'), ('$v2', '$v2')]"
        if [ "$got" = "$want" ]; then ok "(V) get/then/write rank $rg/$rt/$rw_ above gateway ($rgw); gateway is still the first owner row, the verbs follow in rank order"
        else no "(V) owner rows $got, want $want (a common verb spent the slot of the function the question is about)"; fi
        got="$( J "((d['hops'] or {}).get('qword_cut'), (d['hops'] or {}).get('next',''))" <"$TMP/ts.v.json" )"
        if [ "$got" = "('1', '--callees=src/util/io.ts:$v3')" ]; then ok "(V) qword_cut=\"1\" next= names the cut verb ($v3)"; else no "(V) (qword_cut, next) = $got, want ('1', '--callees=src/util/io.ts:$v3')"; fi
    else no "(V) premise: get/then/write ranks $rg/$rt/$rw_ must all be above gateway ($rgw) — re-tune the fixture"; fi
fi

# ── (G) all callee names up to the runaway guard; the guard's count pinned (C5) ─────────────────────────────────────
f="$TMP/py.g1.xml"; run py "$f" "--for=How does dispatch route an event?"
if ran_ok "$f" "(G/20)"; then
    HJ "$f" "$TMP/py.g1.json" "(G/20)"
    got="$( J "[(len(r['calls']), r['ca'].get('capped','0')) for r in d['rows'] if r['n']=='dispatch']" <"$TMP/py.g1.json" )"
    if [ "$got" = "[(20, '0')]" ]; then ok "(G/20) dispatch's owner row lists all 20 callee names"; else no "(G/20) dispatch rows (names, capped) = $got, want [(20, '0')]"; fi
fi
f="$TMP/py.g2.xml"; run py "$f" "--for=How does broadcast send an event?"
if ran_ok "$f" "(G/guard)"; then
    HJ "$f" "$TMP/py.g2.json" "(G/guard)"
    got="$( J "[(r['ca'].get('total'), r['ca'].get('capped'), r['ca'].get('next', r.get('next','')), len(r['calls']), r['ca'].get('shown')) for r in d['rows'] if r['n']=='broadcast']" <"$TMP/py.g2.json" )"
    case "$got" in "[('105', '1', '--callees=pkg/broadcast.py:broadcast', 100, '100')]") ok "(G/guard) broadcast past the guard: exactly 100 names, capped=\"1\" + next= to the full list";;
        *) no "(G/guard) broadcast (total, capped, next, names, shown) = $got, want [('105', '1', '--callees=pkg/broadcast.py:broadcast', 100, '100')]";; esac
fi

# ── (R) no-regression against the A/B handle ─────────────────────────────────────────────────────────────────────────
# SECTS XML — the <sigs> and <tail> sections verbatim (the parts an owner row must never change)
SECTS(){ python3 -c "import re,sys; x=open(sys.argv[1]).read(); print([m.group(0) for t in ('sigs','tail') for m in [re.search(r'<%s[ >].*?</%s>' % (t, t), x, re.S)] if m])" "$1"; }
# mode exact: the A/B rows' <calls> EXACTLY (the five fixture questions — no moved owner there frees a later row's budget);
# mode prefix: a PREFIX, and >= 1 row must actually gain names (else the widened branch is not exercised).
for spec in "exact|ts|$QTS" "exact|py|$QPY" "exact|c|$QC" "exact|py|$QCAP" "exact|ts|$QV" "prefix|gain|How does fanout deliver events?"; do
    mode="${spec%%|*}"; rest="${spec#*|}"; r="${rest%%|*}"; q="${rest#*|}"
    tag="$r.$( printf '%s' "$q" | cksum | cut -d' ' -f1 )"
    on="$TMP/r.$tag.on.xml"; off="$TMP/r.$tag.off.xml"; run "$r" "$on" "--for=$q"; runoff "$r" "$off" "--for=$q"
    ran_ok "$on" "(R/$r '$q') head" && ran_ok "$off" "(R/$r '$q') A/B" || continue
    HJ "$on" "$on.json" "(R/$r) head"; HJ "$off" "$off.json" "(R/$r) A/B"
    res="$( python3 - "$on.json" "$off.json" "$mode" <<'PY'
import json, sys
on = json.load(open(sys.argv[1])); off = json.load(open(sys.argv[2])); mode = sys.argv[3]
owners = {(r['p'], r['n'], r['l']) for r in on['rows'] if r.get('qword')}
base = [r for r in off['rows'] if (r['p'], r['n'], r['l']) not in owners]
head = [r for r in on['rows'] if not r.get('qword')]
# exact: identity AND calls equal. prefix: a moved owner only frees budget, so a ranked row the A/B handle cut may name MORE
# of the same walk (measured: fzf-12 replacePlaceholder 0 -> 2 names), never fewer and never others (rows are walked in
# order against one cumulative budget, so every row the A/B handle printed starts at most as deep into it)
ident = lambda r: (r['p'], r['n'], r['l'])
calls = lambda r: [(c['n'], c.get('l'), c.get('via')) for c in r['calls']]
hd = {ident(r): r for r in head}
same = (lambda a, b: a == b) if mode == 'exact' else (lambda a, b: b[:len(a)] == a)
missing = [ident(r) for r in base if ident(r) not in hd or not same(calls(r), calls(hd[ident(r)]))]
gained = [r['n'] for r in base if ident(r) in hd and len(calls(hd[ident(r)])) > len(calls(r))]
moved = [r['n'] for r in off['rows'] if ident(r) in owners]
order_ok = [ident(r) for r in head if ident(r) in {ident(b) for b in base}] == [ident(r) for r in base if ident(r) in hd]
premise = bool(gained) and bool(moved) if mode == 'prefix' else True
print('OK' if not missing and order_ok and off['rows'] and premise
      else 'BAD missing=%s order_ok=%s base_rows=%d gained=%s moved=%s' % (missing[:3], order_ok, len(off['rows']), gained, moved))
PY
)"
    if [ "$res" = OK ]; then
        if [ "$mode" = exact ]; then ok "(R/$r) '$q': every A/B <h> row is still served, exactly the same calls, same order"
        else ok "(R/prefix) '$q': a moved owner frees budget — every A/B <h> row is still served, its calls a prefix, >= 1 row gains names"; fi
    else no "(R/$mode/$r) '$q': $res"; fi
    if [ "$( SECTS "$on" )" = "$( SECTS "$off" )" ] && [ "$( SECTS "$off" )" != "[]" ]; then ok "(R/sigs/$r) '$q': <sigs>/<tail> byte-identical to the A/B handle"
    else no "(R/sigs/$r) '$q': <sigs>/<tail> differ from the A/B handle (or are absent)"; fi
done
# ── (S) the via="name" clause the owner rows alone switch on never costs <sigs> a row (CHANGES 1 of the review) ──────────
# The header asks "may a <calls> row carry via=name?" over the hop ids AND the owner rows. When only an owner row answers
# yes, the clause is the owner rows' disclosure: exempt from the sig trim like the qword clause, so <sigs>/<tail> stay the
# A/B handle's. Red before the exemption: compact default 36 sigs with docs_dropped 10 -> 11, full at 3000 31 -> 29 rows.
for spec in "compact|$QTS|" "compact|$QV|" "full|$QTS|--legend=full" "compact|$QTS|--token-budget=3000" "full|$QTS|--legend=full --token-budget=3000"; do
    dia="${spec%%|*}"; rest="${spec#*|}"; q="${rest%%|*}"; extra="${rest#*|}"
    tag="s.$dia.$( printf '%s %s' "$q" "$extra" | cksum | cut -d' ' -f1 )"
    on="$TMP/$tag.on.xml"; off="$TMP/$tag.off.xml"
    # shellcheck disable=SC2086
    run ts "$on" "--for=$q" $extra; runoff ts "$off" "--for=$q" $extra
    ran_ok "$on" "(S/$dia '$q'${extra:+ $extra}) head" && ran_ok "$off" "(S/$dia '$q'${extra:+ $extra}) A/B" || continue
    if [ -z "$extra" ] || [ "$extra" = "--legend=full" ]; then   # premise: the owner rows alone switch the clause on
        if [ "$dia" = compact ]; then pat='c via=name:'; else pat='via="name" on a <c> row'; fi
        non="$( grep -cF "$pat" "$on" )"; noff="$( grep -cF "$pat" "$off" )"
        if [ "$non" -ge 1 ] && [ "$noff" = 0 ] && grep -q 'qword="gateway"' "$on"; then :
        else no "(S/$dia '$q'${extra:+ $extra}) premise: via clause head=$non A/B=$noff (want >=1 / 0) with the gateway owner row"; continue; fi
    fi
    if [ "$( SECTS "$on" )" = "$( SECTS "$off" )" ] && [ "$( SECTS "$off" )" != "[]" ]; then
        ok "(S/$dia '$q'${extra:+ $extra}) the owner rows' via=\"name\" clause costs <sigs>/<tail> nothing (byte-identical to the A/B handle)"
    else no "(S/$dia '$q'${extra:+ $extra}) <sigs>/<tail> differ from the A/B handle: $( grep -o '<sigs [^>]*>' "$on" ) vs $( grep -o '<sigs [^>]*>' "$off" )"; fi
done
for spec in "ts|How does the team review pull requests?" "c|How does the log walk the process tables?"; do
    r="${spec%%|*}"; q="${spec#*|}"
    on="$TMP/r2.$r.on.xml"; off="$TMP/r2.$r.off.xml"; run "$r" "$on" "--for=$q"; runoff "$r" "$off" "--for=$q"
    ran_ok "$on" "(R2/$r)" && ran_ok "$off" "(R2/$r) A/B" || continue
    if cmp -s "$on" "$off"; then ok "(R2/$r) a question with no owner is byte-identical to the A/B handle"; else no "(R2/$r) no-owner answer differs from RIPWIRE_NO_OWNER_HOP=1"; fi
done

# ── (B) explicit budget: owner funded first; an exhausted ceiling adds nothing; a cut is disclosed (C7) ──────────────
f="$TMP/ts.b.xml"; run ts "$f" "--for=$QTS" --token-budget=4500
fo="$TMP/ts.b.off.xml"; runoff ts "$fo" "--for=$QTS" --token-budget=4500
if ran_ok "$fo" "(B1) A/B" && ! grep -q 'reason="compact-route"' "$fo"; then no "(B1) premise: --token-budget=4500 no longer leaves the hops a budget on the A/B handle — re-tune"; fi
if ran_ok "$f" "(B1)"; then
    HJ "$f" "$TMP/ts.b.json" "(B1)"; H root "$f" >"$TMP/ts.b.root"
    first="$( J "d['rows'][0]['n'] if d['rows'] else None" <"$TMP/ts.b.json" )"
    est="$( J "d.get('est_tokens','')" <"$TMP/ts.b.root" )"; over="$( J "d.get('over_ceiling','0')" <"$TMP/ts.b.root" )"
    if [ "$first" = gateway ]; then ok "(B1) under --token-budget=4500 the owner row is first"; else no "(B1) first row under --token-budget=4500 is $first, want gateway"; fi
    if [[ "$est" =~ ^[0-9]+$ ]]; then
        if { [ "$est" -le 4500 ] || [ "$over" = 1 ]; }; then ok "(B1) est_tokens=$est within 4500 (or over_ceiling disclosed)"; else no "(B1) est_tokens=$est > 4500 and no over_ceiling=\"1\""; fi
    else no "(B1) est_tokens missing or not numeric ('$est')"; fi
fi
# (B1b) a ceiling that leaves the owner less than its row: the owner is still first, or its cut is disclosed by name
f="$TMP/ts.b4.xml"; run ts "$f" "--for=$QTS" --token-budget=4000
if ran_ok "$f" "(B1b)"; then
    HJ "$f" "$TMP/ts.b4.json" "(B1b)"
    got="$( J "('row' if d['rows'] and d['rows'][0]['n']=='gateway' and d['rows'][0].get('qword')=='gateway' else 'cut' if (d['hops'] or {}).get('next')=='--callees=src/middleware/gateway.ts:gateway' and (d['hops'] or {}).get('qword_cut','0')!='0' else '')" <"$TMP/ts.b4.json" )"
    if [ "$got" = row ] || [ "$got" = cut ] || grep -q 'reason="budget"' "$f"; then ok "(B1b) --token-budget=4000: the owner is first or disclosed ($got)"
    else no "(B1b) --token-budget=4000: gateway neither the first owner row nor named by qword_cut/next= ($got)"; fi
fi
on="$TMP/b2.on.xml"; off="$TMP/b2.off.xml"; run ts "$on" "--for=$QTS" --token-budget=1200; runoff ts "$off" "--for=$QTS" --token-budget=1200
if ran_ok "$on" "(B2)" && ran_ok "$off" "(B2) A/B"; then
    grep -q 'reason="budget"' "$off" || no "(B2) premise: --token-budget=1200 no longer exhausts the ceiling (no reason=\"budget\") — re-tune"
    if cmp -s "$on" "$off"; then ok "(B2) exhausted ceiling: byte-identical to the A/B handle (owner rows add nothing)"; else no "(B2) exhausted-ceiling answer changed"; fi
fi
# (B3) a budget sweep on the 105-callee owner: no budget may drop callee names silently
qb3="How does broadcast send an event?"; partial=0; seen=0; bad=""
for tb in 1400 1600 1800 2000 2200 2400 2600 2800 3000 3500 4000 5000 6000; do
    f="$TMP/b3.$tb.xml"; run py "$f" "--for=$qb3" --token-budget=$tb
    ran_ok "$f" "(B3) budget $tb" || continue
    HJ "$f" "$f.json" "(B3) budget $tb"
    v="$( python3 - "$f" "$f.json" <<'PY'
import json, re, sys
x = open(sys.argv[1]).read(); d = json.load(open(sys.argv[2]))
nx = '--callees=pkg/broadcast.py:broadcast'
rows = [r for r in d['rows'] if r['n'] == 'broadcast']
if rows:
    r = rows[0]; ca = r['ca']; n = len(r['calls'])
    ok = ca.get('capped') == '1' and ca.get('next') == nx and ca.get('shown') == str(n) and ca.get('total') == '105'
    print(('row %d' % n) if ok else ('BAD row names=%d calls=%s' % (n, ca)))
else:
    h = d['hops'] or {}
    if h.get('qword_cut', '0') not in ('', '0') and h.get('next') == nx: print('cut')
    elif 'reason="budget"' in x: print('spent')
    else: print('BAD absent with no disclosure hops=%s' % h)
PY
)"
    case "$v" in "row "*) seen=$((seen+1)); n="${v#row }"; [ "$n" -gt 0 ] && [ "$n" -lt 100 ] && partial=$((partial+1));; cut|spent) ;; *) bad="$bad [$tb: $v]";; esac
done
if [ -z "$bad" ] && [ "$partial" -ge 1 ]; then ok "(B3) every explicit budget discloses the owner row's cut (capped=\"1\" + next=) or its absence; $partial budget(s) fund it only partly"
else no "(B3) bad=$bad partial=$partial seen=$seen (want no silent drop, and >= 1 partly funded row)"; fi

# ── (J) JSON and MCP twins: no hop surface, byte-identical ───────────────────────────────────────────────────────────
on="$TMP/j.on.json"; off="$TMP/j.off.json"; run ts "$on" "--for=$QTS" --json; runoff ts "$off" "--for=$QTS" --json
if ran_ok "$on" "(J/json)" && ran_ok "$off" "(J/json) A/B"; then
    if cmp -s "$on" "$off"; then ok "(J/json) --json --for byte-identical to the A/B handle"; else no "(J/json) --json --for changed"; fi
fi
mcp(){ printf '{"jsonrpc":"2.0","id":1,"method":"tools/call","params":{"name":"for","arguments":{"path":"%s","task":"%s"}}}\n' "$FIX/ts" "$QTS" \
       | env $1 "$2" --mcp --no-cache >"$3" 2>"$3.err"; printf '%s' "$?" >"$3.rc"; }
mcp "RIPWIRE_X=0" "$BIN" "$TMP/m.on"; mcp "RIPWIRE_NO_OWNER_HOP=1" "$BIN" "$TMP/m.off"
if ran_ok "$TMP/m.on" "(J/mcp)" && ran_ok "$TMP/m.off" "(J/mcp) A/B"; then
    grep -q '"result"' "$TMP/m.on" || no "(J/mcp) no result object — the arm measured nothing"
    if cmp -s "$TMP/m.on" "$TMP/m.off"; then ok "(J/mcp) MCP for byte-identical to the A/B handle (signatures-only surface)"; else no "(J/mcp) MCP for changed"; fi
fi

# ── (L) legend ───────────────────────────────────────────────────────────────────────────────────────────────────────
if ! grep -q 'qword=' "$TMP/ts.p.xml" 2>/dev/null; then no "(L) no qword row on the positive answer — the legend arm measured nothing"
elif grep -q 'qword= [^;]*by name' "$TMP/ts.p.xml"; then ok "(L) qword legend clause present and says 'by name'"
else no "(L) qword row emitted without a legend clause that says it is by name"; fi
if grep -q 'qword' "$TMP/n.ts.non-code-question.xml" 2>/dev/null; then no "(L) qword legend clause on an answer with no owner row"; else ok "(L) no qword clause when no owner row"; fi

# (D) the duplicate check really ran on every parsed <hops> block
if [ "$ndup" -ge 20 ]; then ok "(D) $ndup <hops> blocks parsed, none with an <h> row twice (failures above if any)"; else no "(D) only $ndup <hops> blocks parsed — the duplicate arm measured too little"; fi

# ── (I) base vs head: the knob restores the BASE answer, and everything outside --for hop selection is unchanged (C1) ─
if [ -n "${RIPWIRE_BASE_BIN:-}" ] && [ -x "${RIPWIRE_BASE_BIN}" ]; then
    echo "  (I) RIPWIRE_BASE_BIN=$RIPWIRE_BASE_BIN"
    n=0; d=0; e=0
    # MODE|ROOT|ARG|ARG… — K: head with RIPWIRE_NO_OWNER_HOP=1 vs base; H: head as shipped vs base; M: MCP `for` (K form)
    while IFS= read -r line; do
        [ -z "$line" ] && continue
        IFS='|' read -r -a parts <<<"$line"
        mode="${parts[0]}"; r="${parts[1]}"; args=( ${parts[@]+"${parts[@]:2}"} ); shown="${args[*]-}"
        n=$((n+1)); hf="$TMP/i.$n.h"; bf="$TMP/i.$n.b"
        if [ "$mode" = M ]; then
            mcp "RIPWIRE_NO_OWNER_HOP=1" "$BIN" "$hf"; mcp "RIPWIRE_X=0" "$RIPWIRE_BASE_BIN" "$bf"
        else
            if [ "$mode" = K ]; then knob="RIPWIRE_NO_OWNER_HOP=1"; else knob="RIPWIRE_X=0"; fi
            ( cd "$FIX/$r" && env "$knob" "$BIN" . --no-cache ${args[@]+"${args[@]}"} >"$hf" 2>"$hf.err" ); printf '%s' "$?" >"$hf.rc"
            ( cd "$FIX/$r" && "$RIPWIRE_BASE_BIN" . --no-cache ${args[@]+"${args[@]}"} >"$bf" 2>"$bf.err" ); printf '%s' "$?" >"$bf.rc"
        fi
        if ! ran_ok "$hf" "(I) head $mode $r $shown" || ! ran_ok "$bf" "(I) base $mode $r $shown"; then e=$((e+1)); continue; fi
        cmp -s "$hf" "$bf" || { d=$((d+1)); echo "    differs: $mode $r $shown"; }
    done <<ARGV
K|ts|--for=$QTS
K|py|--for=$QPY
K|c|--for=$QC
K|py|--for=$QCAP
K|ts|--for=$QV
K|py|--for=How does broadcast send an event?
K|ts|--for=$QTS|--json
K|ts|--for=$QTS|--token-budget=1200
K|ts|--for=$QTS|--token-budget=4000
K|ts|--for=$QTS|--token-budget=4500
M|ts
H|ts|--for=How does the team review pull requests?
H|c|--for=How does the log walk the process tables?
H|py|--for=How does Reactive work?
H|ts|--for=How does relay forward a request?
H|ts|--callers=checkSessionToken
H|ts|--callees=src/middleware/gateway.ts:gateway
H|ts|--expand=gateway
H|ts|--top-k=20
H|py|--callers=invoke_watcher
H|py|--callees=dispatch
H|py|--expand=pkg/reactive.py:_notify
H|py|--top-k=20
H|c|--callers=Table_rowCount
H|c|--callees=scan
H|c|--expand=scan
H|c|--top-k=20
ARGV
    if [ "$d" = 0 ] && [ "$e" = 0 ] && [ "$n" -ge 26 ]; then ok "(I) $n argv byte-identical base vs head (knob on the owner questions, as shipped elsewhere), every rc=0"
    else no "(I) $d of $n argv differ, $e did not run cleanly"; fi
else
    skip "(I) base-vs-head identity needs RIPWIRE_BASE_BIN"
fi

[ "$fail" = 0 ] && { echo "ownerhopcheck: OK"; exit 0; }
echo "ownerhopcheck: FAILURES ABOVE"; exit 1
