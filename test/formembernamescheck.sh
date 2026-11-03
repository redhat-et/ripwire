#!/usr/bin/env bash
# formembernamescheck.sh — MEMBER NAMES on the owner rows of a compact-route --for answer (lane member-names, train 32;
# src/formembers.h).
#
# THE CONTRACT THIS PINS (arms tagged [P] are RED on the pre-change binary b112e8ac; [G] arms are twins and near-miss negatives
# that hold on both binaries and must keep holding — PROCESS rule 4, no gate erosion):
#
#   TRIGGER  CLI --for (XML, compact and full legends) on the compact route, in the DEFAULT regime. Not on: the name-exact
#            route, --signatures-only, --json, an explicit --token-budget=N, --expand, the map, the --for --limit=N file page,
#            RIPWIRE_NO_MEMBER_NAMES=1 (the A/B handle) — each byte-identical to the handle-off answer.
#   WHAT     a SHOWN class/struct/interface(trait) row gains mem="a,b,…" (<= 8 names of its DIRECT members by the index: sc= names
#            the owner, or the owner's span holds it; never one nested inside a member) and mem_more="N" (names not listed).
#            Not listed: a name already shown as a row, the owner's own name (a C++ constructor).
#   NOT ON   an owner whose body (or an enclosing body) the fold or the body slot serves, or whose member slice the fold served;
#            an ambiguous owner (another class of its name is indexed).
#   PRICE    the names ride on top of the chosen rows: the <d> rows are the handle-off rows, est_tokens prices the names.
#
# Arms (colour on b112e8ac in brackets):
#   A1 [P] JS class: TemplateCompiler's mem= is exactly its direct members less the names shown as rows (fold off)
#   A2 [P] Python class: JobScheduler likewise (fold off)
#   A3 [P] C++ struct with in-header member declarations and out-of-line definitions (one name each, never the constructor)
#   A4 [P] Rust `impl BookDriver` in another file (members by sc=) and a trait's default method (fold off)
#   B1 [G] a closure nested in a method (blockVisitor, wrap_job) is never a member name; B1 needs A1/A2's lists (non-vacuous)
#   C1 [P] the fold's posture: TemplateCompiler served whole by the fold carries no mem=; with the fold off it does
#   C2 [P] a class the fold serves as a member slice (LedgerBook, 6 KB) carries no mem=; with the fold off it does
#   D1 [P] two TaskWorker classes (amb): neither row carries mem=; the unique TaskQueue beside them does
#   E1 [P] the cap: LedgerBook's 30 members print 8 names and mem_more="22"
#   F1 [G] byte identity with RIPWIRE_NO_MEMBER_NAMES=1: name-exact --for, --expand, the map, the --limit=40 file page, --json,
#          --signatures-only, --token-budget=3000 — and none of them carries mem=
#   G1 [P] the ledger: est_tokens(on) > est_tokens(off) by the names' bytes at the markup rate (within 2 tokens); the <d> rows
#          (n, p, l, r) are the handle-off rows, one for one (a name never costs a row)
#   G2 [G] prefix identity: the answer minus mem=/mem_more= and the clause, est_tokens masked, equals the handle-off answer
#   L1 [P] the clause defines mem= and mem_more= in both dialects when a row carries mem=; L2 [G] absent when none does
#   X1 [G] determinism   X2 [G] xmllint well-formed   X3 [G] no "--" inside the legend comment
#   I1 [optional, RIPWIRE_BASE_BIN=<pre-change binary>] RIPWIRE_NO_MEMBER_NAMES=1 equals the base binary on every probe
#
# Usage:  bash test/formembernamescheck.sh [BIN]   |   RIPWIRE_BIN=asan/ripwire bash test/formembernamescheck.sh
# BIN is $1, else RIPWIRE_BIN, else build/ripwire; the first output line names the binary used. Exits non-zero on any failure.

set -u
ROOT="$( cd "$( dirname "$0" )/.." && pwd )"
. "$ROOT/test/lib/clean-env.sh"
unset RIPWIRE_NO_MEMBER_NAMES RIPWIRE_NO_BODY_FOLD RIPWIRE_NO_BODY_SLOT RIPWIRE_NO_OWNER_HOP
BIN="${1:-${RIPWIRE_BIN:-$ROOT/build/ripwire}}"
[ "${BIN#/}" = "$BIN" ] && BIN="$ROOT/$BIN"
echo "formembernamescheck: BIN=$BIN"
fail=0
ok(){ printf '  PASS  %s\n' "$*" || { fail=1; printf '  FAIL  could not write the PASS line for: %s\n' "$*"; }; return 0; }
no(){ printf '  FAIL  %s\n' "$*"; fail=1; }

[ -x "$BIN" ] || { echo "no ripwire binary at $BIN — build first"; exit 2; }
command -v python3 >/dev/null 2>&1 || { echo "python3 required"; exit 2; }
FIX="$ROOT/test/formembernamesfix"
for d in js py cpp rust amb cap; do [ -d "$FIX/$d" ] || { echo "fixture $FIX/$d missing"; exit 2; }; done

TMP="$( mktemp -d )"; trap 'rm -rf "$TMP"' EXIT
export HOME="$TMP/home"; mkdir -p "$HOME"

Q_JS="How does the template compiler compile blocks?"
Q_PY="How are jobs scheduled onto workers?"
Q_CPP="How does the dependency scan decide an output is dirty?"
Q_RS="How does the book driver run each renderer backend?"
Q_AMB="How does a worker run tasks?"
Q_CAP="How does the ledger book record entries?"

# run NAME ROOT [ENV=V ...] -- ARGS... : one answer into $TMP/NAME.xml, a fresh cache per run, cwd = the fixture root
run(){
    local name="$1" root="$2"; shift 2
    local envs=()
    while [ "$#" -gt 0 ] && [ "$1" != "--" ]; do envs+=( "$1" ); shift; done
    shift
    ( cd "$root" || exit 1; env ${envs[@]+"${envs[@]}"} "$BIN" "$root" "$@" --cache="$TMP/$name.cache" >"$TMP/$name.xml" 2>"$TMP/$name.err" ) \
        || no "$name: ripwire exited non-zero ($( head -c 200 "$TMP/$name.err" | tr '\n' ' ' ))"
}

cat > "$TMP/chk.py" <<'PY'
import html, re, sys
cmd, args = sys.argv[1], sys.argv[2:]
def load(p):
    return open(p, "rb").read().decode("utf-8", "replace")
def attrs(s):
    return dict((k, html.unescape(v)) for k, v in re.findall(r'(\w+)="([^"]*)"', s))
def rows(t):
    return [attrs(m.group(1)) for m in re.finditer(r'<d ([^>]*)>', t)]
def legend(t):
    return " ".join(re.findall(r'<!--(.*?)-->', t, re.S))
CLAUSE = re.compile(r'; (d mem=|mem= on an owner d row:)[^;]*?mem_more= (names cut|the member names not listed)(?=;| ?-->|$)')
def strip(t):
    t = re.sub(r' mem="[^"]*"( mem_more="\d+")?', '', t)
    t = CLAUSE.sub('', t)
    return re.sub(r' est_tokens="\d+"', '', t)
def fail(msg):
    print(msg); sys.exit(1)
def row(t, name, path=None):   # path may be P@L (two rows of one name in one file: a C++ struct and its constructor)
    p, _, l = (path or "").partition("@")
    rs = [r for r in rows(t) if r.get("n") == name and (path is None or r.get("p") == p) and (not l or r.get("l") == l)]
    if len(rs) != 1: fail(f"{len(rs)} rows named {name} ({path})")
    return rs[0]
if cmd == "exact":            # FILE OWNER PATH MEMBER... : mem= == the direct members less the names shown as rows, none cut
    t = load(args[0]); r = row(t, args[1], args[2])
    # a member row prints Owner::name / Owner.name (QUALNAME-1); the product drops a member whose BARE name is shown as a row
    shown = {re.split(r"::|\.|#", x.get("n"))[-1] for x in rows(t)} | {x.get("n") for x in rows(t)}
    want = [m for m in args[3:] if m not in shown and m != args[1]]
    got = r.get("mem", "").split(",") if "mem" in r else []
    if not want: fail(f"vacuous: every member of {args[1]} is shown as a row")
    if sorted(got) != sorted(want) or "mem_more" in r: fail(f"{args[1]} mem={got} mem_more={r.get('mem_more')}, want exactly {sorted(want)}")
    if len(got) != len(set(got)): fail(f"a name rides twice: {got}")
    print(",".join(got))
elif cmd == "none":           # FILE OWNER [PATH] : that owner row carries no mem=/mem_more=
    t = load(args[0])
    rs = [r for r in rows(t) if r.get("n") == args[1] and (len(args) < 3 or r.get("p") == args[2])]
    if not rs: fail(f"no row named {args[1]} (the arm would be vacuous)")
    bad = [r for r in rs if "mem" in r or "mem_more" in r]
    if bad: fail(f"{args[1]} carries {bad[0].get('mem')!r} mem_more={bad[0].get('mem_more')}")
elif cmd == "has":            # FILE OWNER [PATH] : that owner row carries a mem=
    t = load(args[0]); r = row(t, args[1], args[2] if len(args) > 2 else None)
    if not r.get("mem"): fail(f"{args[1]} carries no mem=")
elif cmd == "never":          # FILE NAME... : no mem= list names any of these
    t = load(args[0])
    for r in rows(t):
        hit = set(r.get("mem", "").split(",")) & set(args[1:])
        if hit: fail(f"{r.get('n')} lists {sorted(hit)}")
elif cmd == "cap":            # FILE OWNER K MORE
    t = load(args[0]); r = row(t, args[1])
    got = r.get("mem", "").split(",")
    if len(got) != int(args[2]) or r.get("mem_more") != args[3]: fail(f"{len(got)} names, mem_more={r.get('mem_more')!r}; want {args[2]} and {args[3]}")
elif cmd == "nomem":          # FILE : no mem=/mem_more= anywhere, no clause
    t = load(args[0])
    if re.search(r' mem(_more)?="', t): fail("carries mem=")
    if CLAUSE.search(legend(t)): fail("carries the mem= clause with no mem= to define")
elif cmd == "ledger":         # ON OFF : rows one for one; est_tokens rise by the names' markup
    on, off = load(args[0]), load(args[1])
    key = lambda t: [(r.get("n"), r.get("p"), r.get("l"), r.get("r")) for r in rows(t)]
    if key(on) != key(off): fail("the <d> rows differ from the handle-off rows")
    eo = int(re.search(r' est_tokens="(\d+)"', on).group(1)); ef = int(re.search(r' est_tokens="(\d+)"', off).group(1))
    added = sum(len(m.group(0).encode()) for m in re.finditer(r' mem="[^"]*"( mem_more="\d+")?', on))
    added += sum(len(m.group(0).encode()) for m in CLAUSE.finditer(on))
    if added == 0: fail("no mem= on the answer: vacuous")
    if not eo > ef: fail(f"est_tokens {eo} vs {ef}: the names are not priced")
    want = added / 2.5   # the markup rate (kBytesPerTokenDefault); the header says "within 2 tokens"
    if abs( ( eo - ef ) - want ) > 2: fail(f"est_tokens rose {eo - ef}, want {want:.1f} (+/-2) for {added} B")
    print(f"est_tokens {ef} -> {eo} for {added} B")
elif cmd == "prefix":         # ON OFF
    a, b = strip(load(args[0])), strip(load(args[1]))
    if a != b:
        i = next((k for k in range(min(len(a), len(b))) if a[k] != b[k]), min(len(a), len(b)))
        fail(f"differs at {i}: {a[max(0, i - 60):i + 60]!r} vs {b[max(0, i - 60):i + 60]!r}")
elif cmd == "clause":         # FILE : the clause rides and defines mem= and mem_more=
    t = load(args[0])
    if not re.search(r' mem="', t): fail("no mem= on the answer: vacuous")
    m = CLAUSE.search(legend(t))
    if not m: fail("no mem= clause in the legend")
    if "mem=" not in m.group(0) or "mem_more=" not in m.group(0): fail(f"clause {m.group(0)!r} does not define both")
    if "--" in legend(t): fail("a legend comment holds --")
else:
    fail("unknown command " + cmd)
PY
chk(){ python3 "$TMP/chk.py" "$@" 2>&1; }
arm(){ local tag="$1"; shift; local out; if out="$( chk "$@" )"; then ok "$tag ${out:+($out)}"; else no "$tag: $out"; fi; }

echo "=== the answers ==="
run js_off   "$FIX/js"   RIPWIRE_NO_BODY_FOLD=1 -- --for="$Q_JS"
run js_on    "$FIX/js"   -- --for="$Q_JS"
run js_full  "$FIX/js"   RIPWIRE_NO_BODY_FOLD=1 -- --for="$Q_JS" --legend=full
run js_noff  "$FIX/js"   RIPWIRE_NO_BODY_FOLD=1 RIPWIRE_NO_MEMBER_NAMES=1 -- --for="$Q_JS"
run js_nofl  "$FIX/js"   RIPWIRE_NO_BODY_FOLD=1 RIPWIRE_NO_MEMBER_NAMES=1 -- --for="$Q_JS" --legend=full
run py_off   "$FIX/py"   RIPWIRE_NO_BODY_FOLD=1 -- --for="$Q_PY"
run cpp_off  "$FIX/cpp"  RIPWIRE_NO_BODY_FOLD=1 -- --for="$Q_CPP"
run rs_off   "$FIX/rust" RIPWIRE_NO_BODY_FOLD=1 -- --for="$Q_RS"
run amb_off  "$FIX/amb"  RIPWIRE_NO_BODY_FOLD=1 -- --for="$Q_AMB"
run cap_off  "$FIX/cap"  RIPWIRE_NO_BODY_FOLD=1 -- --for="$Q_CAP"
run cap_on   "$FIX/cap"  -- --for="$Q_CAP"
run cap_non  "$FIX/cap"  RIPWIRE_NO_MEMBER_NAMES=1 -- --for="$Q_CAP"
run cap_off2 "$FIX/cap"  RIPWIRE_NO_BODY_FOLD=1 -- --for="$Q_CAP"

echo "=== A: exactly the direct members ==="
arm "A1 JS TemplateCompiler"  exact "$TMP/js_off.xml"  TemplateCompiler src/compiler.js constructor compileBlock compileSuper emitLine flushOutput
arm "A2 Python JobScheduler"  exact "$TMP/py_off.xml"  JobScheduler sched/scheduler.py __init__ submit assign drain
arm "A3 C++ DependencyScan"   exact "$TMP/cpp_off.xml" DependencyScan scan/depscan.h@8 RecomputeDirty RecomputeOutputDirty LoadDepfile Reset Width
arm "A4 Rust BookDriver (impl in driver.rs)" exact "$TMP/rs_off.xml" BookDriver src/book.rs load execute_build build_dir_for source_dir theme_dir
arm "A4 Rust trait Renderer"  exact "$TMP/rs_off.xml"  Renderer src/book.rs supports

echo "=== B: a nested closure is not a member ==="
arm "B1 blockVisitor/wrap_job never listed (JS)" never "$TMP/js_off.xml" blockVisitor wrap_job helperClosure
arm "B1 blockVisitor/wrap_job never listed (Py)" never "$TMP/py_off.xml" blockVisitor wrap_job

echo "=== C: the fold already carries the owner's text ==="
arm "C1 fold serves TemplateCompiler whole: no mem=" none "$TMP/js_on.xml" TemplateCompiler
if grep -q '<fold [^>]*>.*<b [^>]*n="TemplateCompiler"' "$TMP/js_on.xml"; then ok "C1 (the fold does serve TemplateCompiler's body)"; else no "C1 the fold did not serve TemplateCompiler (the arm would be vacuous)"; fi
arm "C1 twin: fold off, TemplateCompiler carries mem=" has "$TMP/js_off.xml" TemplateCompiler
arm "C2 fold slices LedgerBook: no mem=" none "$TMP/cap_on.xml" LedgerBook
if grep -q '<slice [^>]*n="LedgerBook"' "$TMP/cap_on.xml"; then ok "C2 (the fold does slice LedgerBook)"; else no "C2 no LedgerBook slice (the arm would be vacuous)"; fi
arm "C2 twin: fold off, LedgerBook carries mem=" has "$TMP/cap_off.xml" LedgerBook

echo "=== D: an ambiguous owner gets no list ==="
arm "D1 TaskWorker (pool_a) no mem=" none "$TMP/amb_off.xml" TaskWorker pkg/pool_a.py
arm "D1 TaskWorker (pool_b) no mem=" none "$TMP/amb_off.xml" TaskWorker pkg/pool_b.py
arm "D1 twin: the unique TaskQueue lists put_task,take" exact "$TMP/amb_off.xml" TaskQueue pkg/pool_a.py put_task take

echo "=== E: the cap ==="
arm "E1 LedgerBook: 8 names + mem_more=22" cap "$TMP/cap_off.xml" LedgerBook 8 22

echo "=== F: no mem= outside the compact --for route, byte-identical to the handle-off answer ==="
fpair(){   # TAG ROOT ARGS... : head == RIPWIRE_NO_MEMBER_NAMES=1, and no mem=
    local tag="$1" root="$2"; shift 2
    run "f_$tag"  "$root" RIPWIRE_NO_BODY_FOLD=1 -- "$@"
    run "fn_$tag" "$root" RIPWIRE_NO_BODY_FOLD=1 RIPWIRE_NO_MEMBER_NAMES=1 -- "$@"
    if ! cmp -s "$TMP/f_$tag.xml" "$TMP/fn_$tag.xml"; then no "F1 $tag differs from RIPWIRE_NO_MEMBER_NAMES=1"; return; fi
    [ -s "$TMP/f_$tag.xml" ] || { no "F1 $tag empty answer (vacuous)"; return; }
    if grep -q ' mem="' "$TMP/f_$tag.xml"; then no "F1 $tag carries mem="; else ok "F1 $tag identical, no mem= ($( wc -c <"$TMP/f_$tag.xml" | tr -d ' ' ) B)"; fi
}
fpair name-exact "$FIX/js"  --for=TemplateCompiler
fpair expand     "$FIX/js"  --expand=src/compiler.js:TemplateCompiler
fpair map        "$FIX/cap"
fpair filepage   "$FIX/cap" --for="$Q_CAP" --limit=40
fpair json       "$FIX/cap" --for="$Q_CAP" --json
fpair sigsonly   "$FIX/cap" --for="$Q_CAP" --signatures-only
fpair budget     "$FIX/cap" --for="$Q_CAP" --token-budget=3000

echo "=== G: the ledger ==="
run cap_noff "$FIX/cap" RIPWIRE_NO_BODY_FOLD=1 RIPWIRE_NO_MEMBER_NAMES=1 -- --for="$Q_CAP"
arm "G1 cap: rows one for one, est_tokens priced"   ledger "$TMP/cap_off2.xml" "$TMP/cap_noff.xml"
arm "G1 JS: rows one for one, est_tokens priced"    ledger "$TMP/js_off.xml" "$TMP/js_noff.xml"
arm "G2 cap prefix identity (compact)" prefix "$TMP/cap_off2.xml" "$TMP/cap_noff.xml"
arm "G2 JS prefix identity (compact)"  prefix "$TMP/js_off.xml" "$TMP/js_noff.xml"
arm "G2 JS prefix identity (full)"     prefix "$TMP/js_full.xml" "$TMP/js_nofl.xml"
arm "G2 fold on: cap prefix identity"  prefix "$TMP/cap_on.xml" "$TMP/cap_non.xml"

echo "=== L: the legend ==="
arm "L1 compact clause defines mem= mem_more=" clause "$TMP/js_off.xml"
arm "L1 full clause defines mem= mem_more="    clause "$TMP/js_full.xml"
arm "L2 no mem=, no clause (fold-sliced cap)"  nomem "$TMP/cap_on.xml"

echo "=== X: determinism, well-formedness ==="
run js_off_b "$FIX/js" RIPWIRE_NO_BODY_FOLD=1 -- --for="$Q_JS"
if cmp -s "$TMP/js_off.xml" "$TMP/js_off_b.xml"; then ok "X1 deterministic"; else no "X1 two runs differ"; fi
if command -v xmllint >/dev/null 2>&1; then
    for f in js_off js_full cap_off cpp_off rs_off; do
        if xmllint --noout "$TMP/$f.xml" 2>/dev/null; then ok "X2 $f well-formed"; else no "X2 $f not well-formed"; fi
    done
else
    echo "  SKIP  X2 xmllint not installed"
fi

if [ -n "${RIPWIRE_BASE_BIN:-}" ]; then
    echo "=== I: RIPWIRE_NO_MEMBER_NAMES=1 equals the base binary ==="
    for spec in "js|$Q_JS" "py|$Q_PY" "cpp|$Q_CPP" "rust|$Q_RS" "amb|$Q_AMB" "cap|$Q_CAP"; do
        d="${spec%%|*}"; q="${spec#*|}"
        ( cd "$FIX/$d" || exit 1; RIPWIRE_NO_MEMBER_NAMES=1 "$BIN" "$FIX/$d" --for="$q" --cache="$TMP/i1h.$d" >"$TMP/i1h.$d.xml" 2>/dev/null )
        ( cd "$FIX/$d" || exit 1; "$RIPWIRE_BASE_BIN" "$FIX/$d" --for="$q" --cache="$TMP/i1b.$d" >"$TMP/i1b.$d.xml" 2>/dev/null )
        if cmp -s "$TMP/i1h.$d.xml" "$TMP/i1b.$d.xml"; then ok "I1 $d: handle off == base"; else no "I1 $d: handle off differs from the base binary"; fi
    done
fi

echo
if [ "$fail" = "0" ]; then echo "formembernamescheck: ALL PASS"; else echo "formembernamescheck: FAILURES ABOVE"; fi
exit "$fail"
