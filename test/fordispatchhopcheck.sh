#!/usr/bin/env bash
# fordispatchhopcheck.sh — THE DISPATCH HOP of a name-exact --for answer (lane mf1-nx wave 4; src/fordispatchhop.h).
#
# THE CONTRACT THIS PINS (arms tagged [P] are RED on the pre-change binary 12056c16; [G] arms are twins and near-miss negatives
# that hold on both binaries and must keep holding — PROCESS rule 4, no gate erosion):
#
#   TRIGGER  CLI --for (XML, compact and full legends) on the name-exact route, DEFAULT regime, when a body candidate (a function
#            or method) makes a call the resolver declined at an interface/trait receiver (gate="iface") AND the task names that
#            call as a member access (`recv->m`, `recv.m`) — not the caller's own name.
#   WHAT     <dispatch call= in= p=file:line cands= shown= [test=] capped= next="--whereis=NAME">: the non-test candidates as
#            <s t= n= p=file:line> rows, the callers of a candidate owner's constructor as <s … ctor=> rows, the one candidate's
#            body <b> when exactly one production candidate is left (test doubles counted in test=).
#   NOT      a task that does not name the call, a call the resolver bound, a wrapper calling its own name, a type subject, --json,
#            --signatures-only, --token-budget=N and RIPWIRE_NO_DISPATCH_HOP=1 carry none (byte-identical to the hop-off answer).
#
# Arms:
#   P1 [P] C++ field receiver (Loader::Load src_->Fetch): rows DiskSource::Fetch and NetSource::Fetch, cands="2" shown="2", no <b>
#   P2 [P] one production candidate + a test double (tests/loader_test.cc FakeSource): shown="1" test="1" and DiskSource::Fetch's body
#   P3 [P] Rust &dyn Trait parameter (build_book r.render): Html::render, Cmd::render and pick_renderers ctor="Cmd::new"
#   P4 [P] the clause rides in both legends when the element does, and defines every attribute the element carries
#   P5 [P] prefix identity: the answer minus <dispatch> and its clause, est_tokens masked, equals RIPWIRE_NO_DISPATCH_HOP=1
#   P6 [G] next= pasted (--whereis=Fetch) lists every candidate the element names
#   N1 [G] no element: the bare subject (build_book), the call as a bare word (Loader::Load the Fetch), a wrapper calling its own
#          name (CachedSource::Fetch inner_->Fetch), a member-access token naming another call (build_book out.push_str), a type subject (DiskSource src_->Fetch), a call declined for another
#          reason (Python job.run: the ladder tier, no gate — dispatch_job job.run)
#   N2 [G] no element, byte-identical to RIPWIRE_NO_DISPATCH_HOP=1: --json, --signatures-only, --token-budget=3000
#   M1 [P] MCP `for` parity: the same element (rows, no inline body — that surface serves bodies by handle) with its own clause;
#          the bare subject carries none
#   X1 [G] determinism  X2 [G] xmllint well-formed  X3 [P] the clause present, no "--" inside a legend comment
#
# Fix round 1 (rv-mf1-nx CHANGES blocking; every arm below is RED on lane head 04cbd504, GREEN after):
#   B1 [P] a production impl made by a FACTORY in its own file (MakePgStore in pg_store.cc) and named elsewhere only by a test is NOT
#          a test double: shown="2", no single body (fixture factory); B1b [G] twin: a type only *_test.cc names, in NON-test
#          paths (fixture double), IS a double: shown="1" test="1" + the other candidate's body (kills mutant RV1: demotion removed)
#   B2 [P] two same-name declined calls on different receivers: the receiver the task wrote picks the site (fixture recv:
#          cache_->Fetch -> the Cache impls, src_->Fetch -> the Source impls, both tokens -> both elements); a receiver no site
#          has (other_->Fetch) while the lists differ -> no element, never the wrong list
#   S1 [P] a C++ two-phase init() is not a constructor: no ctor= row (fixture initm); Rust `new` still is (P3)
#   S2 [P] a structurally typed language (TS) marks floor="1" and serves no single body (fixture ts); no legend says "in all"
#   S3 [P] every candidate a test double: no element and no reason=degraded clause, byte-identical to the hop-off answer (alltest)
#   S4 [P] MCP for: est_tokens prices the element
#
#   D1 [P] fix round 2: a task receiver bound by name (never declined) does not answer another receiver's declined call (fixture recvbound)
#   D2 [P] a non-test-file double named by tests and an uncalled helper stays demoted (fixture dumpfs)
#   F-A [P] an impl built only in an OS-run C/C++ entry (WinMain, wWinMain, DllMain, wmain, _tmain) stays shown; twin: a
#       non-entry name keeps D2's demotion (fixture osentry, entry name written at run time)
#
# CR pre-pass 42a (the honesty finding; C1 is RED on train head 76cd281a, the rest are controls and twins that hold on both):
#   C-pre [G] the fixture cuts as planned: _memory_stop on the cut call, the uncut control whole
#   C0 [G] control: the MCP `for` over the UNCUT index shows RealDisk and CachedDisk, FakeDisk (an atests/ definition) counted in test=1
#   C1 [P] MCP `for` over a MEMORY-CUT index (fixture cutmcp; RealDisk is built only in src/zmain.cc, which the crawl order cuts): a
#          candidate whose production evidence the cut dropped is NOT demoted to a test double from that absence (shown=2), and the
#          candidate that is a double by its OWN path (FakeDisk) stays in test=1 (kills a mutant that drops the demotion wholesale)
#   C3 [G] the CLI over the whole fixture is unchanged (the CLI refuses a cut index before --for runs)
#
# Usage:  bash test/fordispatchhopcheck.sh [BIN]   |   RIPWIRE_BIN=asan/ripwire bash test/fordispatchhopcheck.sh
# BIN is $1, else RIPWIRE_BIN, else build/ripwire; the first output line names the binary used. Exits non-zero on any failure.

set -u
ROOT="$( cd "$( dirname "$0" )/.." && pwd )"
. "$ROOT/test/lib/clean-env.sh"
unset RIPWIRE_NO_DISPATCH_HOP
BIN="${1:-${RIPWIRE_BIN:-$ROOT/build/ripwire}}"
[ "${BIN#/}" = "$BIN" ] && BIN="$ROOT/$BIN"
echo "fordispatchhopcheck: BIN=$BIN"
fail=0
ok(){ printf '  PASS  %s\n' "$*" || { fail=1; printf '  FAIL  could not write the PASS line for: %s\n' "$*"; }; return 0; }
no(){ printf '  FAIL  %s\n' "$*"; fail=1; }
verdict(){ if [ "$1" -eq 0 ]; then ok "$2"; else no "$3"; fi; }   # rc, the PASS line, the FAIL line

[ -x "$BIN" ] || { echo "no ripwire binary at $BIN — build first"; exit 2; }
command -v python3 >/dev/null 2>&1 || { echo "python3 required"; exit 2; }
cd "$ROOT"
F="test/fordispatchhopfix"
[ -f "$F/cpp/loader.cc" ] && [ -f "$F/cpp1/tests/loader_test.cc" ] && [ -f "$F/rs/src/pick.rs" ] && [ -f "$F/cppwrap/cached.cc" ] && [ -f "$F/ladder/main.py" ] \
    && [ -f "$F/factory/pg_store.cc" ] && [ -f "$F/double/loader_test.cc" ] && [ -f "$F/recv/loader.cc" ] && [ -f "$F/initm/loader.cc" ] \
    && [ -f "$F/ts/src/loader.ts" ] && [ -f "$F/alltest/tests/fakes.cc" ] && [ -f "$F/recvbound/rc.cc" ] && [ -f "$F/dumpfs/src/test.cc" ] && [ -f "$F/osentry/src/disk.cc" ] && [ -f "$F/cutmcp/src/zmain.cc" ] || { echo "fixture $F missing"; exit 2; }

TMP="$( mktemp -d )"; trap 'rm -rf "$TMP"' EXIT
export HOME="$TMP/home"; mkdir -p "$HOME"

run(){ local dir="$1"; shift; "$BIN" "$dir" --no-cache "$@" 2>/dev/null </dev/null; }
off(){ local dir="$1"; shift; RIPWIRE_NO_DISPATCH_HOP=1 "$BIN" "$dir" --no-cache "$@" 2>/dev/null </dev/null; }
hop(){ python3 - "$1" <<'PY'
import re, sys
t = open(sys.argv[1], encoding="utf-8", errors="replace").read()
print("".join(re.findall(r'<dispatch [^>]*>.*?</dispatch>', t, re.S)))
PY
}
strip(){ python3 - "$1" <<'PY'
import re, sys
t = open(sys.argv[1], encoding="utf-8", errors="replace").read()
t = re.sub(r'<dispatch [^>]*>.*?</dispatch>', '', t, flags=re.S)
t = re.sub(r'; dispatch call=.*?every definition', '', t, flags=re.S)
t = re.sub(r' est_tokens="\d+"', '', t)
sys.stdout.write(t)
PY
}
has(){ printf '%s' "$1" | grep -qF -- "$2"; }

# ── P1 ────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────
run "$F/cpp" "--for=Loader::Load src_->Fetch" >"$TMP/p1"
H1="$( hop "$TMP/p1" )"
if grep -q 'route="name-exact(' "$TMP/p1"; then ok "(P1pre) the C++ subject routes name-exact"; else no "(P1pre) the C++ subject did not route name-exact — the fixture proves nothing"; fi
if has "$H1" 'in="Loader::Load"' && has "$H1" 'cands="2" shown="2"' && has "$H1" 'n="DiskSource::Fetch" p="loader.cc:14"' && has "$H1" 'n="NetSource::Fetch" p="loader.cc:15"' \
   && has "$H1" 'next="--whereis=Fetch"' && ! has "$H1" '<b '; then
    ok "(P1) the field-receiver call names both implementations, no body (two candidates)"
else no "(P1) expected DiskSource::Fetch + NetSource::Fetch rows, cands=2 shown=2, no <b>: [$H1]"; fi

# ── P2 ────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────
run "$F/cpp1" "--for=Loader::Load src_->Fetch" >"$TMP/p2"
H2="$( hop "$TMP/p2" )"
if has "$H2" 'cands="2" shown="1" test="1"' && has "$H2" 'n="DiskSource::Fetch"' && ! has "$H2" 'FakeSource' && has "$H2" 'int doubled = k * 2;'; then
    ok "(P2) one production candidate: the test double is counted (test=1), the candidate's body rides"
else no "(P2) expected shown=1 test=1, DiskSource::Fetch with its body, no FakeSource: [$H2]"; fi

# ── P3 ────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────
run "$F/rs" "--for=build_book r.render" >"$TMP/p3"
H3="$( hop "$TMP/p3" )"
if has "$H3" 'call="render" in="build_book"' && has "$H3" 'n="Html::render"' && has "$H3" 'n="Cmd::render"' && has "$H3" 'n="pick_renderers" p="src/pick.rs:22" ctor="Cmd::new"'; then
    ok "(P3) Rust &dyn Trait: both impls and the function constructing Cmd (ctor=Cmd::new)"
else no "(P3) expected Html::render, Cmd::render and pick_renderers ctor=Cmd::new: [$H3]"; fi

# ── P4 ────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────
run "$F/cpp" "--for=Loader::Load src_->Fetch" --legend=full >"$TMP/p4f"
if grep -q '; dispatch call=: the task names a call' "$TMP/p4f" && grep -q '; dispatch call= in= p=: a task-named call' "$TMP/p1" \
   && [ -n "$( hop "$TMP/p4f" )" ]; then ok "(P4) the clause rides in both legends with the element"
else no "(P4) the dispatch clause is missing from a legend that carries the element"; fi
for a in call in p cands shown test floor capped next ctor; do
    grep -qE "; dispatch ([^;]*[ (])?$a=" "$TMP/p4f" || no "(P4) full clause does not define $a="
    grep -qE "; dispatch ([^;]*[ (])?$a=" "$TMP/p1" || no "(P4) compact clause does not define $a="
done

# ── P5 ────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────
for leg in compact full; do
    run "$F/cpp1" "--for=Loader::Load src_->Fetch" --legend=$leg >"$TMP/p5a"
    off "$F/cpp1" "--for=Loader::Load src_->Fetch" --legend=$leg >"$TMP/p5b"
    strip "$TMP/p5a" >"$TMP/p5as"; strip "$TMP/p5b" >"$TMP/p5bs"
    if [ -n "$( hop "$TMP/p5a" )" ] && cmp -s "$TMP/p5as" "$TMP/p5bs" && [ -z "$( hop "$TMP/p5b" )" ]; then ok "(P5 $leg) the answer minus the element equals RIPWIRE_NO_DISPATCH_HOP=1"
    else no "(P5 $leg) prefix identity broken: $( diff "$TMP/p5as" "$TMP/p5bs" | head -c 400 )"; fi
done

# ── P6 ────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────
run "$F/cpp" --whereis=Fetch >"$TMP/p6"
if grep -q 'DiskSource::Fetch' "$TMP/p6" && grep -q 'NetSource::Fetch' "$TMP/p6"; then ok "(P6) next= --whereis=Fetch lists every candidate"
else no "(P6) --whereis=Fetch does not list both candidates"; fi

# ── N1 ────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────
n1(){ local dir="$1" task="$2" why="$3"
    run "$dir" "--for=$task" >"$TMP/n1"
    if [ -s "$TMP/n1" ] && [ -z "$( hop "$TMP/n1" )" ] && ! grep -q '; dispatch call=' "$TMP/n1"; then ok "(N1) no element: $why"
    else no "(N1) an element or clause rode on $why: [$( hop "$TMP/n1" )]"; fi
}
n1 "$F/rs" "build_book" "the bare subject (name-exact, its body makes the iface call)"
run "$F/rs" --for=build_book | grep -q 'route="name-exact(build_book)'
verdict $? "(N1pre) the bare subject routes name-exact (the task-names guard, not the route, holds it)" "(N1pre) build_book did not route name-exact"
n1 "$F/cpp" "Loader::Load the Fetch" "the call as a bare word"
n1 "$F/rs" "build_book out.push_str" "a member-access token naming a different call (push_str, not the declined render)"
n1 "$F/cppwrap" "CachedSource::Fetch inner_->Fetch" "a wrapper calling its own name"
n1 "$F/cpp" "DiskSource src_->Fetch" "a type subject"
n1 "$F/ladder" "dispatch_job job.run" "a call declined by the ladder tier (not gate=iface)"
if run "$F/ladder" "--for=dispatch_job job.run" | grep -q 'route="name-exact(' && run "$F/ladder" --callees=dispatch_job --legend=full | grep -q '<dc n="run"[^>]*cands="2"'; then
    ok "(N1pre) the ladder fixture routes name-exact and its job.run IS declined with 2 candidates (the gate=iface guard holds it)"
else no "(N1pre) the ladder fixture's premise failed"; fi
run "$F/cppwrap" "--for=CachedSource::Fetch inner_->Fetch" --legend=full >"$TMP/n1w"
grep -q 'route="name-exact(' "$TMP/n1w" && run "$F/cppwrap" --callees=CachedSource::Fetch --legend=full | grep -q 'gate="iface"'
verdict $? "(N1pre) the wrapper routes name-exact and its call IS iface-declined (the guard, not the premise, holds it)" "(N1pre) the wrapper fixture's premise failed (route or the iface decline)"

# ── N2 ────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────
for flag in --json --signatures-only --token-budget=3000; do
    run "$F/cpp" "--for=Loader::Load src_->Fetch" "$flag" >"$TMP/n2a"; off "$F/cpp" "--for=Loader::Load src_->Fetch" "$flag" >"$TMP/n2b"
    if [ -s "$TMP/n2a" ] && cmp -s "$TMP/n2a" "$TMP/n2b"; then ok "(N2) $flag: byte-identical to RIPWIRE_NO_DISPATCH_HOP=1"
    else no "(N2) $flag differs from the hop-off answer"; fi
done

# ── M1 ────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────
mcp_for(){ printf '{"jsonrpc":"2.0","id":1,"method":"tools/call","params":{"name":"for","arguments":{"path":"%s","task":"%s"}}}\n' "$ROOT/$1" "$2" \
           | "$BIN" --mcp 2>/dev/null | python3 -c '
import sys, json
for l in sys.stdin:
    try: j = json.loads(l)
    except ValueError: continue
    sys.stdout.write("".join(c.get("text", "") for c in j.get("result", {}).get("content", [])))'; }
mcp_for "$F/rs" "build_book r.render" >"$TMP/m1"
mcp_for "$F/cpp" "Loader::Load" >"$TMP/m1n"
M1="$( hop "$TMP/m1" )"
if [ -n "$M1" ] && [ "$M1" = "$H3" ] && grep -q 'dispatch call=: the task names a call' "$TMP/m1" && [ -s "$TMP/m1n" ] && [ -z "$( hop "$TMP/m1n" )" ]; then
    ok "(M1) MCP for carries the CLI's element byte-for-byte (no body on this fixture) with its clause; the bare subject none"
else no "(M1) MCP for: [$M1] vs CLI [$H3]"; fi
H2M="$( mcp_for "$F/cpp1" "Loader::Load src_->Fetch" >"$TMP/m1b"; hop "$TMP/m1b" )"
if has "$H2M" 'shown="1" test="1"' && ! has "$H2M" '<b '; then ok "(M1b) MCP for: the one-candidate element carries no inline body"
else no "(M1b) MCP one-candidate element: [$H2M]"; fi

# ── B1 / B1b ──────────────────────────────────────────────────────────────────────────────────────────────────────────────────
run "$F/factory" "--for=Service::Lookup store_->Get" >"$TMP/b1"
HB1="$( hop "$TMP/b1" )"
if has "$HB1" 'cands="2" shown="2"' && has "$HB1" 'n="MemStore::Get"' && has "$HB1" 'n="PgStore::Get"' && ! has "$HB1" ' test="' && ! has "$HB1" '<b '; then
    ok "(B1) a factory-made production impl (MakePgStore in its own file) is not a test double: both candidates, no single body"
else no "(B1) expected MemStore::Get + PgStore::Get, shown=2, no test=, no <b>: [$HB1]"; fi
run "$F/double" "--for=Loader::Load src_->Fetch" >"$TMP/b1b"
HB1B="$( hop "$TMP/b1b" )"
if has "$HB1B" 'cands="2" shown="1" test="1"' && has "$HB1B" 'n="DiskSource::Fetch"' && ! has "$HB1B" 'ScriptedSource' && has "$HB1B" 'int doubled = k * 2;'; then
    ok "(B1b) a double in a non-test path that only *_test.cc names is demoted (test=1), the other candidate's body rides"
else no "(B1b) expected shown=1 test=1, DiskSource::Fetch + body, no ScriptedSource: [$HB1B]"; fi

# ── B2 ────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────
run "$F/recv" "--for=Loader::Load cache_->Fetch" >"$TMP/b2a"
HB2A="$( hop "$TMP/b2a" )"
if has "$HB2A" 'call="cache_-&gt;Fetch"' && has "$HB2A" 'n="LruCache::Fetch"' && has "$HB2A" 'n="ArcCache::Fetch"' && ! has "$HB2A" 'DiskSource' && ! has "$HB2A" 'NetSource'; then
    ok "(B2) cache_->Fetch answers the Cache implementations, not the Source ones"
else no "(B2) cache_->Fetch: [$HB2A]"; fi
run "$F/recv" "--for=Loader::Load src_->Fetch" >"$TMP/b2b"
HB2B="$( hop "$TMP/b2b" )"
if has "$HB2B" 'call="src_-&gt;Fetch"' && has "$HB2B" 'n="DiskSource::Fetch"' && has "$HB2B" 'n="NetSource::Fetch"' && ! has "$HB2B" 'LruCache' && ! has "$HB2B" 'ArcCache'; then
    ok "(B2) src_->Fetch answers the Source implementations, not the Cache ones"
else no "(B2) src_->Fetch: [$HB2B]"; fi
run "$F/recv" --callees=Loader::Load --legend=full >"$TMP/b2p"
if [ "$( grep -o '<dc n="Fetch"[^>]*gate="iface"' "$TMP/b2p" | wc -l | tr -d ' ' )" = "2" ]; then ok "(B2pre) both Fetch calls ARE iface-declined, with different lists (the receiver, not the premise, picks the site)"
else no "(B2pre) the recv fixture does not hold two iface-declined Fetch calls"; fi
run "$F/recv" "--for=Loader::Load other_->Fetch" >"$TMP/b2d"
if [ -s "$TMP/b2d" ] && [ -z "$( hop "$TMP/b2d" )" ] && ! grep -q '; dispatch call=' "$TMP/b2d"; then ok "(B2) a receiver no site has, with differing lists: no element (never the wrong site)"
else no "(B2) other_->Fetch carried an element: [$( hop "$TMP/b2d" )]"; fi

# ── S1 ────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────
run "$F/initm" "--for=Loader::Load src_->Fetch" >"$TMP/s1"
HS1="$( hop "$TMP/s1" )"
if has "$HS1" 'n="DiskSource::Fetch"' && ! has "$HS1" 'ctor=' && ! has "$HS1" 'ResetAllSources'; then ok "(S1) a C++ two-phase init() is not a constructor: no ctor= row"
else no "(S1) init() printed as a constructor: [$HS1]"; fi

# ── S2 ────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────
run "$F/ts" "--for=loadValue src.fetch" >"$TMP/s2"
HS2="$( hop "$TMP/s2" )"
if has "$HS2" 'floor="1"' && has "$HS2" 'n="DiskSource.fetch"' && ! has "$HS2" '<b '; then ok "(S2) a structurally typed language marks floor=1 and serves no single body"
else no "(S2) TS element: [$HS2]"; fi
run "$F/cpp1" "--for=Loader::Load src_->Fetch" --legend=full >"$TMP/s2n"
if ! grep -q 'cands= in all' "$TMP/p4f" && ! grep -q 'cands= in all' "$TMP/s2n" && ! has "$( hop "$TMP/s2n" )" 'floor='; then ok "(S2) no legend says cands= in all; a nominal language carries no floor="
else no "(S2) legend or floor= wrong"; fi

# ── S3 ────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────
run "$F/alltest" "--for=Loader::Load src_->Fetch" >"$TMP/s3a"; off "$F/alltest" "--for=Loader::Load src_->Fetch" >"$TMP/s3b"
if [ -s "$TMP/s3a" ] && cmp -s "$TMP/s3a" "$TMP/s3b" && ! grep -q 'reason=degraded' "$TMP/s3a"; then ok "(S3) every candidate a test double: byte-identical to the hop-off answer, no reason=degraded clause"
else no "(S3) all-doubles answer differs from hop-off or carries reason=degraded: $( diff "$TMP/s3a" "$TMP/s3b" | head -c 300 )"; fi
run "$F/alltest" --callees=Loader::Load --legend=full | grep -q 'gate="iface"'
verdict $? "(S3pre) the all-doubles fixture IS iface-declined (the demotion, not a missing premise, holds it)" "(S3pre) the all-doubles fixture's call is not iface-declined"

# ── D1 / D2 (fix round 2: rv-mf1nx-delta) ─────────────────────────────────────────────────────────────────────────────────────────
run "$F/recvbound" --callees=L::Load --legend=full >"$TMP/d1p"
if [ "$( grep -o '<dc n="F"[^>]*gate="iface"' "$TMP/d1p" | wc -l | tr -d ' ' )" = "1" ]; then ok "(D1pre) only y_->F is iface-declined; x_->F and h.get().F are bound by name"
else no "(D1pre) the recvbound fixture's premise failed (expected exactly one iface-declined F)"; fi
for tk in "this->x_->F" "x_->F"; do
    run "$F/recvbound" "--for=L::Load $tk" >"$TMP/d1"
    if [ -s "$TMP/d1" ] && [ -z "$( hop "$TMP/d1" )" ] && ! has "$( cat "$TMP/d1" )" 'k * 3' && ! grep -q '; dispatch call=' "$TMP/d1"; then ok "(D1) $tk (bound by name, never declined): another receiver's declined y_->F is not answered, no wrong body"
    else no "(D1) $tk answered another receiver's declined call: [$( hop "$TMP/d1" )]"; fi
done
run "$F/recvbound" "--for=L::Load y_->F" >"$TMP/d1y"
if has "$( hop "$TMP/d1y" )" 'call="y_-&gt;F"' && has "$( hop "$TMP/d1y" )" 'n="Lru::F"'; then ok "(D1) the declined receiver y_->F is still answered"
else no "(D1) y_->F lost its element: [$( hop "$TMP/d1y" )]"; fi
run "$F/dumpfs" "--for=Builder::Run disk_->ReadFile" >"$TMP/d2"
HD2="$( hop "$TMP/d2" )"
if has "$HD2" 'cands="2" shown="1" test="1"' && has "$HD2" 'n="RealDisk::ReadFile"' && ! has "$HD2" 'VirtualFS' && has "$HD2" 'p * 7 + 1'; then
    ok "(D2) a double in a non-test file named only by tests and an UNCALLED helper stays demoted (test=1), the other candidate's body rides"
else no "(D2) uncalled helper un-demoted the double: [$HD2]"; fi

# ── F-A (train 42a: rv-mf1nx-delta2 E1) ───────────────────────────────────────────────────────────────────────────────────────────
# An OS-run C/C++ entry (WinMain, wWinMain, DllMain, wmain, _tmain) is a caller-less root like main: a production impl built ONLY
# there, and named by tests, is NOT a test double (the other impl's body must not be printed as THE answer). The fixture's
# disk.cc spells ENTRY; each arm writes one name into a runtime copy. Twin: a non-entry name keeps D2's rule (uncalled = no evidence).
for en in WinMain wWinMain DllMain wmain _tmain NotAnEntry; do
    rm -rf "$TMP/osentry"; cp -R "$F/osentry" "$TMP/osentry"
    sed "s/int ENTRY()/int $en()/" "$F/osentry/src/disk.cc" >"$TMP/osentry/src/disk.cc"
    run "$TMP/osentry" "--for=Builder::Run disk_->ReadFile" >"$TMP/fa"
    HFA="$( hop "$TMP/fa" )"
    if [ "$en" = NotAnEntry ]; then
        if has "$HFA" 'cands="2" shown="1" test="1"'; then ok "(F-A twin) an uncalled $en() is not a root: RealDisk stays demoted (test=1)"
        else no "(F-A twin) a non-entry name became a root: [$HFA]"; fi
    elif has "$HFA" 'cands="2" shown="2"' && ! has "$HFA" 'test="1"' && ! has "$HFA" 'p * 11 + 5'; then
        ok "(F-A) $en() is a runtime root: RealDisk built there stays shown, no single other body printed"
    else no "(F-A) $en() counted as dead code: RealDisk demoted [$HFA]"; fi
done

# ── C (CR pre-pass 42a: the honesty finding) ─────────────────────────────────────────────────────────────────────────────────────
# The demotion of a candidate to a test double reads ABSENCE (no production code names its type). On a memory-guard-cut index the
# file that builds RealDisk may be exactly what the cut dropped, so absence proves nothing: the element must not call it a double.
# RIPWIRE_TEST_MEMGUARD=crawl:CUTAT stops the crawl before src/zmain.cc (entries by name: atests/, then src/); mcp_raw keeps the
# envelope (text + _memory_stop + _index), which mcp_for drops.
CUTAT=11
mcp_raw(){ local trip="$3"; printf '{"jsonrpc":"2.0","id":1,"method":"tools/call","params":{"name":"for","arguments":{"path":"%s","task":"%s"}}}\n' "$ROOT/$1" "$2" \
           | env ${trip:+RIPWIRE_TEST_MEMGUARD="$trip"} "$BIN" --mcp ${trip:+--max-memory=64M} 2>/dev/null | python3 -c '
import sys, json
for l in sys.stdin:
    try: j = json.loads(l)
    except ValueError: continue
    r = j.get("result", {})
    sys.stdout.write("".join(c.get("text", "") for c in r.get("content", [])))
    sys.stdout.write("\n@@STOP@@" + str(r.get("_memory_stop", "")) + "\n@@INDEX@@" + str(r.get("_index", "")) + "\n")'; }
CT="Builder::Run disk_->ReadFile"
mcp_raw "$F/cutmcp" "$CT" "crawl:$CUTAT" >"$TMP/c1"
mcp_raw "$F/cutmcp" "$CT" "" >"$TMP/c0"
HC1="$( hop "$TMP/c1" )"; HC0="$( hop "$TMP/c0" )"
if grep -q '@@STOP@@the memory guard stopped the crawl' "$TMP/c1" && grep -q '@@INDEX@@\[index: files=8 ' "$TMP/c1" && grep -q '^@@STOP@@$' "$TMP/c0"; then
    ok "(C-pre) the cut call is a cut index (_memory_stop, files=8) and the control is whole: the fixture proves something"
else no "(C-pre) the cut fixture did not cut as planned: $( grep -E '@@(STOP|INDEX)@@' "$TMP/c1" | cut -c1-160 )"; fi
if has "$HC0" 'cands="3" shown="2" test="1"' && has "$HC0" 'n="RealDisk::ReadFile"' && has "$HC0" 'n="CachedDisk::ReadFile"' && ! has "$HC0" 'FakeDisk'; then
    ok "(C0) uncut MCP for: RealDisk and CachedDisk shown, the atests/ FakeDisk counted (test=1)"
else no "(C0) control: [$HC0]"; fi
if has "$HC1" 'cands="3" shown="2" test="1"' && has "$HC1" 'n="RealDisk::ReadFile"' && has "$HC1" 'n="CachedDisk::ReadFile"' && ! has "$HC1" 'FakeDisk'; then
    ok "(C1) cut MCP for: RealDisk is not demoted from an absence the cut caused (shown=2); FakeDisk, a double by its own path, stays test=1"
else no "(C1) a cut index presented missing production evidence as a test double: [$HC1]"; fi
run "$F/cutmcp" "--for=$CT" >"$TMP/c3"
HC3="$( hop "$TMP/c3" )"
if has "$HC3" 'cands="3" shown="2" test="1"' && has "$HC3" 'n="RealDisk::ReadFile"'; then ok "(C3) CLI over the whole fixture: the same element as the uncut MCP call (the CLI refuses a cut index, so its rule is unchanged)"
else no "(C3) CLI answer: [$HC3]"; fi

# ── S4 ────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────
est(){ python3 -c 'import re,sys; m=re.search(r"est_tokens=\"(\d+)\"", sys.stdin.read()); print(m.group(1) if m else "")'; }
mcp_for "$F/rs" "build_book r.render" | est >"$TMP/s4a"
RIPWIRE_NO_DISPATCH_HOP=1 mcp_for "$F/rs" "build_book r.render" | est >"$TMP/s4b"
SA="$( cat "$TMP/s4a" )"; SB="$( cat "$TMP/s4b" )"
case "$SA$SB" in ''|*[!0-9]*) no "(S4) est_tokens missing or non-numeric: on=[$SA] off=[$SB]";;
    *) if [ "$SA" -gt "$SB" ]; then ok "(S4) MCP for prices the element: est_tokens $SB -> $SA"; else no "(S4) MCP est_tokens does not grow with the element: on=$SA off=$SB"; fi;; esac

# ── X ─────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────
run "$F/rs" "--for=build_book r.render" >"$TMP/x1"
cmp -s "$TMP/p3" "$TMP/x1"; verdict $? "(X1) deterministic" "(X1) two runs differ"
if command -v xmllint >/dev/null 2>&1; then
    for f in p1 p2 p3 p4f; do xmllint --noout "$TMP/$f" 2>/dev/null || no "(X2) $f is not well-formed XML"; done
    ok "(X2) xmllint checked"
else ok "(X2) xmllint absent — skipped"; fi
for f in p1 p4f; do
    python3 - "$TMP/$f" <<'PY' || no "(X3) a '--' inside the dispatch clause ($f)"
import re, sys
t = open(sys.argv[1], encoding="utf-8").read()
m = re.search(r'; dispatch call=[^;]*', t)
sys.exit(1 if m is None or "--" in m.group(0) else 0)
PY
done
ok "(X3) clause scanned"

exit "$fail"
