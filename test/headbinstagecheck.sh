#!/usr/bin/env bash
# headbinstagecheck.sh — the HEAD comparison binary is STAGED before the suite runs, never built inside a gate budget.
#
# WHY. Six gates (crossdirincludecheck, nestedimportcheck, preproccondcheck, pyimportprecisecheck,
# rustimportprecisecheck, tsimportprecisecheck — plus binoverridecheck, which re-runs them) compare today's binary
# against a second ripwire built from git HEAD, through test/lib/headbinlib.sh. Under test/pargates.py that build
# ran INSIDE whichever of them started first: a parallel cmake build inside a wall-clock-budgeted gate, competing
# with -j 3 neighbours. Its cost is super-linear in contention. Five draws of macos-14 Release shard 2/2, read
# against the xmlwellformed runner-speed probe (fixed work, no build):
#     probe 144.8 s -> crossdirincludecheck < 77.5 s        probe 585.8 s -> > 900 s, KILLED
#     probe 506.0 s -> crossdirincludecheck < 402 s         probe 663.8 s -> > 1200 s, KILLED with PR #109's floor
# The probe moved 4.6x and the gate more than 15x. No budget can be sized for that: the number that survives the
# next slow draw is not knowable from this one. So the build left the gates. .github/workflows/ci.yml stages the
# binary ONCE per job, in its own step before test/pargates.py, and exports RIPWIRE_HEADBIN; headbinlib.sh then
# runs in STAGED mode, where it never builds and never waits, and a declared binary that is missing, not
# executable, stamped +dirty, or built from another sha FAILS the gate that asked for it. With RIPWIRE_HEADBIN
# unset the library is the local developer path it always was: sha-keyed cache, one elected builder, the 240 s
# waiter and its private-build fallback.
#
# Four sections, each over the REAL source rather than a retyped rule, and each with a control that must go red:
#   (A) CI       — parse every workflow: a job that runs test/pargates.py, or a head-binary gate by name, stages the
#                  binary in an EARLIER and SEPARATE step after checkout, verifies it, and exports RIPWIRE_HEADBIN.
#                  Mutations: the same scan over a workflow with that step deleted, and with it moved after the suite.
#   (B) LIBRARY  — the real headbinlib.sh on a synthetic git corpus, with a logging `cmake` shim first on PATH, so
#                  "no build was attempted" is an observation. Staged refusals (missing, empty, not executable,
#                  another sha, +dirty, no stamp) return 3 with nothing built and no wait, even while a builder's
#                  lock is held. A HEAD-stamped binary comes back. UNSET still builds through the shim, honours
#                  RIPWIRE_HEADBIN_BUILD_LOG, then hits its cache. Mutation: the library with its staged dispatch
#                  line removed must build.
#   (C) CALLERS  — every test/*.sh that calls ripwire_head_binary sends the failure through headbin_refusal (rc 3
#                  FAILS, any other rc keeps the historic skip). One real caller, run end to end against a staged
#                  binary that does not exist, prints exactly one FAIL row naming RIPWIRE_HEADBIN, and its fixture
#                  arms still PASS. Mutation: that caller with the refusal reverted to a bare skip must be flagged.
#   (D) RUNNER   — test/pargates.py hands RIPWIRE_HEADBIN through to the gates it runs.
#
# Usage: bash test/headbinstagecheck.sh   |   RIPWIRE_BIN=asan/ripwire bash test/headbinstagecheck.sh
set -u
ROOT="$( cd "$( dirname "$0" )/.." && pwd )"
BIN="${1:-${RIPWIRE_BIN:-$ROOT/build/ripwire}}"
[ "${BIN#/}" = "$BIN" ] && BIN="$ROOT/$BIN"
LIB="$ROOT/test/lib/headbinlib.sh"
WORKFLOWS="$ROOT/.github/workflows"
fail=0
ok(){ printf '  PASS  %s\n' "$*" || { fail=1; printf '  FAIL  could not write the PASS line for: %s\n' "$*"; }; return 0; }
no(){ printf '  FAIL  %s\n' "$*"; fail=1; }

[ -x "$BIN" ] || { echo "no ripwire binary at $BIN — build first (cmake --build build -j)"; exit 2; }
command -v python3 >/dev/null 2>&1 || { echo "python3 required"; exit 2; }
command -v git     >/dev/null 2>&1 || { echo "git required"; exit 2; }
[ -f "$LIB" ] || { echo "no $LIB"; exit 2; }
[ -d "$WORKFLOWS" ] || { echo "no $WORKFLOWS"; exit 2; }
TMP="$( mktemp -d )"; trap 'rm -rf "$TMP"' EXIT
echo "headbinstagecheck: BIN=$BIN  LIB=$LIB  TMP=$TMP"

# ── (C, first half) the callers, derived from the tree — (A) needs their names ────────────────────────────────────
# A call is `ripwire_head_binary "` on a line that is not a comment; the statement is that line plus every line a
# trailing backslash continues onto. OK means its failure branch hands `$?` to headbin_refusal. BARE means it does
# not, and a bare `|| skip` is the silent hole: pargates counts a SKIP printed after the first 400 bytes as a PASS.
CALLSCAN="$TMP/callscan.py"
cat > "$CALLSCAN" <<'PYEOF'
import io, os, re, sys
for path in sys.argv[1:]:
    lines = io.open(path, encoding="utf-8", errors="replace").read().split("\n")
    i = 0
    while i < len(lines):
        if lines[i].lstrip().startswith("#") or 'ripwire_head_binary "' not in lines[i]:
            i += 1
            continue
        first = i
        stmt = [lines[i]]
        while lines[i].rstrip().endswith("\\") and i + 1 < len(lines):
            i += 1
            stmt.append(lines[i])
        text = " ".join(s.strip() for s in stmt)
        verdict = "OK" if re.search(r"\|\|\s*\{\s*headbin_refusal \$\? ", text) else "BARE"
        print("CALL %s %s:%d %s" % (verdict, os.path.basename(path), first + 1, text))
        i += 1
PYEOF
# This gate is left out: section (B) calls the library directly on purpose, to observe it, and is not a caller.
SELF="$( basename "$0" )"
GATE_FILES="$( cd "$ROOT/test" && ls ./*.sh 2>/dev/null | sed 's|^\./||' | grep -v -x -e 'regression\.sh' -e "$SELF" )"
callOut="$( cd "$ROOT/test" && printf '%s\n' "$GATE_FILES" | tr '\n' '\0' | xargs -0 python3 "$CALLSCAN" 2>&1 )"
CALLERS="$( printf '%s\n' "$callOut" | awk '/^CALL /{ split($3, a, ":"); print a[1] }' | LC_ALL=C sort -u )"
nCallers="$( printf '%s\n' "$CALLERS" | grep -c . || true )"

# ── (A) CI: the build happens in its own step, before the suite ─────────────────────────────────────────────────────
# Line-based on purpose: stdlib python has no YAML parser, and the workflows keep one shape (jobs at two spaces,
# steps as `- ` items at six). Comment lines are dropped before matching, because job and step comments name
# test/pargates.py in prose where no step runs it.
CISCAN="$TMP/ciscan.py"
cat > "$CISCAN" <<'PYEOF'
import io, re, sys

STAGE_KEYS = ("test/lib/headbinlib.sh", "ripwire_head_binary", "ripwire_headbin_verify", "RIPWIRE_HEADBIN=", "GITHUB_ENV")

def parse(lines):
    """[(job, [[line_index, ...] per step])] for the top-level jobs: mapping; comment lines excluded."""
    j0 = next((i for i, l in enumerate(lines) if l.rstrip() == "jobs:"), None)
    if j0 is None:
        return None
    jobs, cur, step = [], None, None
    for i in range(j0 + 1, len(lines)):
        l = lines[i]
        if re.match(r"^\S", l) and not l.startswith("#"):
            break
        m = re.match(r"^  ([A-Za-z0-9_-]+):\s*$", l)
        if m:
            cur = (m.group(1), [])
            jobs.append(cur)
            step = None
            continue
        if cur is None or re.match(r"^\s*#", l):
            continue
        if re.match(r"^      - ", l):
            step = [i]
            cur[1].append(step)
        elif step is not None and (l.startswith("       ") or not l.strip()):
            step.append(i)
        elif l.strip():
            step = None
    return jobs

def classify(lines, steps, callers):
    txt = ["\n".join(lines[i] for i in s) for s in steps]
    checkout = next((k for k, t in enumerate(txt) if "actions/checkout@" in t), None)
    stage = [k for k, t in enumerate(txt) if all(key in t for key in STAGE_KEYS)]
    users = [k for k, t in enumerate(txt)
             if "test/pargates.py" in t or any(re.search(r"test/%s\b" % re.escape(c), t) for c in callers)]
    return checkout, stage, users

def scan(path, callers):
    lines = io.open(path, encoding="utf-8").read().split("\n")
    jobs = parse(lines)
    if jobs is None:
        print("NOJOBS %s" % path)
        return
    for name, steps in jobs:
        checkout, stage, users = classify(lines, steps, callers)
        if users:
            print("USERJOB %s:%s steps=%d users=%s stage=%s checkout=%s" % (path.rsplit("/", 1)[-1], name, len(steps), users, stage, checkout))
        for u in users:
            where = "%s:%s step %d" % (path.rsplit("/", 1)[-1], name, u)
            if u in stage:
                print("VIOLATION %s stages the HEAD binary in the SAME step that runs the gates, which is inside the gate budget again" % where)
            elif not [s for s in stage if s < u]:
                print("VIOLATION %s runs head-binary gates with no earlier step that stages, verifies and exports RIPWIRE_HEADBIN" % where)
            elif checkout is None or max(s for s in stage if s < u) < checkout:
                print("VIOLATION %s stages the HEAD binary before actions/checkout, where there is no tree to build" % where)

def mutate(path, out, mode, callers):
    lines = io.open(path, encoding="utf-8").read().split("\n")
    jobs = parse(lines) or []
    drop, moves = set(), []
    for name, steps in jobs:
        checkout, stage, users = classify(lines, steps, callers)
        if not stage or not users:
            continue
        for s in stage:
            drop.update(steps[s])
        if mode == "stage-after":
            moves.append((steps[max(users)][-1], [lines[i] for s in stage for i in steps[s]]))
    if not drop:
        print("NOSITE")
        return
    after = dict(moves)
    res = []
    for i, l in enumerate(lines):
        if i not in drop:
            res.append(l)
        if i in after:
            res.extend(after[i])
    io.open(out, "w", encoding="utf-8").write("\n".join(res))
    print("MUTATED %s %s lines=%d" % (mode, out, len(drop)))

cmd = sys.argv[1]
if cmd == "scan":
    callers = sys.argv[3].split(",") if len(sys.argv) > 3 and sys.argv[3] else []
    scan(sys.argv[2], callers)
else:
    callers = sys.argv[5].split(",") if len(sys.argv) > 5 and sys.argv[5] else []
    mutate(sys.argv[2], sys.argv[3], sys.argv[4], callers)
PYEOF

# binoverridecheck is not a caller, but it re-runs every caller against a sentinel binary, so a step that ran it by
# name would need the same staging. It is named here with that reason; the callers themselves are derived above.
USER_GATES="$( printf '%s\nbinoverridecheck.sh\n' "$CALLERS" | grep . | LC_ALL=C sort -u | tr '\n' ',' | sed 's/,$//' )"
ciOut=""
for wf in "$WORKFLOWS"/*.yml "$WORKFLOWS"/*.yaml; do
    [ -f "$wf" ] || continue
    ciOut="$ciOut$( python3 "$CISCAN" scan "$wf" "$USER_GATES" 2>&1 )
"
done
nUserJobs="$( printf '%s' "$ciOut" | grep -c '^USERJOB ' || true )"
nCiViol="$(   printf '%s' "$ciOut" | grep -c '^VIOLATION ' || true )"
if [ "$nUserJobs" -ge 1 ]; then
    ok "(A) $nUserJobs workflow job(s) run test/pargates.py or a head-binary gate by name: $( printf '%s' "$ciOut" | awk '/^USERJOB /{print $2}' | tr '\n' ' ')"
else
    no "(A) no workflow job runs test/pargates.py -- this scan found nothing to hold to the staging rule"
fi
if [ "$nCiViol" -eq 0 ] && [ "$nUserJobs" -ge 1 ]; then
    ok "(A) every such job stages, verifies and exports RIPWIRE_HEADBIN in an EARLIER, SEPARATE step after checkout -- the build is outside every gate budget"
else
    no "(A) $nCiViol job step(s) would build the HEAD binary inside a gate budget:"
    printf '%s' "$ciOut" | grep -E '^(VIOLATION|NOJOBS) ' | sed 's/^/    /'
fi

# mutations over ci.yml itself: without the staging step, and with it after the suite, the scan must go red
CI_YML="$WORKFLOWS/ci.yml"
for mode in drop stage-after; do
    case "$mode" in drop) what="deleted" ;; *) what="moved after the suite" ;; esac
    mutOut="$( python3 "$CISCAN" mutate "$CI_YML" "$TMP/ci.$mode.yml" "$mode" "$USER_GATES" 2>&1 )"
    if printf '%s' "$mutOut" | grep -q '^MUTATED '; then
        mutViol="$( python3 "$CISCAN" scan "$TMP/ci.$mode.yml" "$USER_GATES" 2>&1 | grep -c '^VIOLATION ' || true )"
        [ "$mutViol" -ge 1 ] \
            && ok "(A mutation: $mode) ci.yml with the staging step $what is caught ($mutViol violation(s)) -- the scan is not vacuous" \
            || no "(A mutation: $mode) ci.yml with the staging step $what produced NO violation -- the scan cannot see the defect it exists for"
    else
        no "(A mutation: $mode) ci.yml has no staging step to mutate: $mutOut"
    fi
done

# ── (B) LIBRARY: staged mode over the real headbinlib.sh ────────────────────────────────────────────────────────────
CORPUS="$TMP/corpus"; mkdir -p "$CORPUS"
( cd "$CORPUS" && git init -q . && git config user.email t@t && git config user.name t \
  && printf 'base\n' > f.txt && git add f.txt && git commit -qm base ) >/dev/null 2>&1 \
  || no "(B) could not initialise the synthetic git corpus at $CORPUS"
HEADSHA="$( git -C "$CORPUS" rev-parse HEAD 2>/dev/null )"
SHA9="$( printf '%s' "$HEADSHA" | cut -c1-9 )"
SHA12="$( printf '%s' "$HEADSHA" | cut -c1-12 )"
case "$SHA9" in 0*) OTHER9="1${SHA9#?}" ;; *) OTHER9="0${SHA9#?}" ;; esac
UIDN="$( id -u )"

# the cmake shim: records every invocation, and on --build writes a stub stamped from the tree it was configured on
SHIM="$TMP/shim"; mkdir -p "$SHIM"
cat > "$SHIM/cmake" <<'EOF'
#!/bin/sh
printf '%s\n' "$*" >> "$HB_SHIM_LOG"
echo "shim-cmake $*"
prev=""; src=""; bld=""; build=""
for a in "$@"; do
    [ "$prev" = "-S" ] && src="$a"
    [ "$prev" = "-B" ] && bld="$a"
    [ "$prev" = "--build" ] && build="$a"
    prev="$a"
done
if [ -n "$build" ]; then
    stamp="$( git -C "$( cat "$build/.shim-src" )" rev-parse --short=9 HEAD 2>/dev/null || echo unknown )"
    printf '#!/bin/sh\necho "ripwire 0.0.0 (dev, shim, built_from=%s)"\n' "$stamp" > "$build/ripwire"
    chmod +x "$build/ripwire"
else
    mkdir -p "$bld" && printf '%s' "$src" > "$bld/.shim-src"
fi
exit 0
EOF
chmod +x "$SHIM/cmake"

STUBS="$TMP/stubs"; mkdir -p "$STUBS"
mkstub(){ printf '#!/bin/sh\necho "%s"\n' "$2" > "$STUBS/$1"; chmod +x "$STUBS/$1"; }
mkstub other    "ripwire 0.0.0 (dev, stub, built_from=$OTHER9)"
mkstub dirty    "ripwire 0.0.0 (dev, stub, built_from=$SHA9+dirty)"
mkstub nostamp  "ripwire 0.0.0 (dev, stub)"
mkstub unknown  "ripwire 0.0.0 (dev, stub, built_from=unknown)"
mkstub head     "ripwire 0.0.0 (dev, stub, built_from=$SHA9)"
mkstub head12   "ripwire 0.0.0 (dev, stub, built_from=$SHA12)"
printf '#!/bin/sh\necho "ripwire 0.0.0 (dev, stub, built_from=%s)"\n' "$SHA9" > "$STUBS/noexec"   # right stamp, no +x

# hbrun DIR TAG VALUE [LIB] — one ripwire_head_binary call on a private TMPDIR. VALUE `--unset` unsets
# RIPWIRE_HEADBIN (the CI job exports it, so "unset" must be said out loud). A watchdog stops the call at 120 s,
# half the library's 240 s waiter: a call that reaches it has entered the waiter, which staged mode must never do.
# This is a hang tripwire, not a speed bar -- an honest call here is a git worktree and a shell script.
hbprep(){ mkdir -p "$1/tmpdir" "$1/fb"; : > "$1/shim.log"; }
hbrun(){
    local d="$1" t="$2" v="$3" lib="${4:-$LIB}" pid n=0
    (
        TMPDIR="$d/tmpdir"; HB_SHIM_LOG="$d/shim.log"; PATH="$SHIM:$PATH"; export TMPDIR HB_SHIM_LOG PATH
        if [ "$v" = "--unset" ]; then unset RIPWIRE_HEADBIN; else RIPWIRE_HEADBIN="$v"; export RIPWIRE_HEADBIN; fi
        . "$lib"
        s="$( date +%s )"
        ripwire_head_binary "$CORPUS" "$d/fb" >"$d/$t.out" 2>"$d/$t.err"
        echo "$?" >"$d/$t.rc"
        echo "$(( $( date +%s ) - s ))" >"$d/$t.secs"
    ) &
    pid=$!
    while kill -0 "$pid" 2>/dev/null; do
        if [ "$n" -ge 120 ]; then
            pkill -P "$pid" 2>/dev/null; kill "$pid" 2>/dev/null
            echo "killed-at-120s" >"$d/$t.rc"
            break
        fi
        sleep 1; n=$(( n + 1 ))
    done
    wait "$pid" 2>/dev/null
    return 0
}
rcOf(){ cat "$1.rc" 2>/dev/null || echo none; }
shimCalls(){ grep -c . "$1/shim.log" 2>/dev/null || true; }

# refusal cases: each must return 3, print nothing on stdout, and never reach cmake
refuse(){   # refuse LABEL VALUE [WITHLOCK] [ERRNEEDLE]
    local label="$1" v="$2" lock="${3:-}" needle="${4:-RIPWIRE_HEADBIN}" d="$TMP/B.$1" lockNote=""
    hbprep "$d"
    if [ -n "$lock" ]; then
        mkdir -p "$d/tmpdir/ripwire-headbin-$UIDN/$HEADSHA.lock"
        lockNote=", while a builder lock for this sha was held"
    fi
    hbrun "$d" call "$v"
    local rc out calls
    rc="$( rcOf "$d/call" )"; out="$( cat "$d/call.out" 2>/dev/null )"; calls="$( shimCalls "$d" )"
    if [ "$rc" = 3 ] && [ -z "$out" ] && [ "$calls" -eq 0 ] && grep -q -- "$needle" "$d/call.err" 2>/dev/null \
       && [ ! -e "$d/tmpdir/ripwire-headbin-$UIDN/$HEADSHA/ripwire" ]; then
        ok "(B) staged, $label: rc 3 in $( cat "$d/call.secs" )s, nothing on stdout, cmake never invoked$lockNote; the refusal names '$needle'"
    else
        no "(B) staged, $label: expected rc 3, empty stdout, 0 cmake calls and a stderr naming '$needle' -- got rc=$rc stdout='$out' cmake_calls=$calls stderr='$( head -c 300 "$d/call.err" 2>/dev/null )'"
    fi
}
refuse "missing binary"        "$TMP/no-such-dir/ripwire" lock
refuse "set but empty"         ""
refuse "not executable"        "$STUBS/noexec"
refuse "built from another sha" "$STUBS/other" "" "$OTHER9"
refuse "built from a +dirty tree" "$STUBS/dirty" "" "+dirty"
refuse "no built_from stamp"   "$STUBS/nostamp"
refuse "stamp 'unknown'"       "$STUBS/unknown"

accept(){   # accept LABEL STUB
    local d="$TMP/B.$1"
    hbprep "$d"
    hbrun "$d" call "$STUBS/$2"
    local rc out calls
    rc="$( rcOf "$d/call" )"; out="$( cat "$d/call.out" 2>/dev/null )"; calls="$( shimCalls "$d" )"
    if [ "$rc" = 0 ] && [ "$out" = "$STUBS/$2" ] && [ "$calls" -eq 0 ]; then
        ok "(B) staged, $1: rc 0 and the declared path comes back, cmake never invoked"
    else
        no "(B) staged, $1: expected rc 0 and stdout '$STUBS/$2' with 0 cmake calls -- got rc=$rc stdout='$out' cmake_calls=$calls stderr='$( head -c 300 "$d/call.err" 2>/dev/null )'"
    fi
}
accept "built from HEAD (9-char stamp)" head
accept "built from HEAD (git lengthened the stamp to 12)" head12

# unset: the developer path is unchanged -- elected builder, shim build, then the sha-keyed cache
d="$TMP/B.unset"; hbprep "$d"
CACHED="$d/tmpdir/ripwire-headbin-$UIDN/$HEADSHA/ripwire"
RIPWIRE_HEADBIN_BUILD_LOG="$d/build.log" hbrun "$d" first --unset
c1="$( shimCalls "$d" )"
if [ "$( rcOf "$d/first" )" = 0 ] && [ "$( cat "$d/first.out" 2>/dev/null )" = "$CACHED" ] && [ -x "$CACHED" ] \
   && grep -q -- '-DRIPWIRE_NATIVE=ON' "$d/shim.log" && grep -q -- '--build' "$d/shim.log"; then
    ok "(B) unset: the library configures (-DRIPWIRE_NATIVE=ON) and builds through cmake, and returns the sha-keyed cache path"
else
    no "(B) unset: expected rc 0, stdout '$CACHED' and a configure+build in the cmake log -- got rc=$( rcOf "$d/first" ) stdout='$( cat "$d/first.out" 2>/dev/null )' log='$( tr '\n' '|' < "$d/shim.log" )' stderr='$( head -c 300 "$d/first.err" 2>/dev/null )'"
fi
[ -x "$CACHED" ] && "$CACHED" --version 2>/dev/null | grep -q "built_from=$SHA9)" \
    && ok "(B) unset: the cached binary's --version says it was built from HEAD ($SHA9)" \
    || no "(B) unset: the cached binary does not report built_from=$SHA9: '$( "$CACHED" --version 2>&1 | head -1 )'"
grep -q 'shim-cmake' "$d/build.log" 2>/dev/null \
    && ok "(B) unset: RIPWIRE_HEADBIN_BUILD_LOG receives the build's output (what CI prints when the staging build fails)" \
    || no "(B) unset: RIPWIRE_HEADBIN_BUILD_LOG=$d/build.log received no build output"
hbrun "$d" second --unset
c2="$( shimCalls "$d" )"
[ "$( rcOf "$d/second" )" = 0 ] && [ "$( cat "$d/second.out" 2>/dev/null )" = "$CACHED" ] && [ "$c2" -eq "$c1" ] \
    && ok "(B) unset: a second call hits the cache ($c1 cmake call(s) before, $c2 after)" \
    || no "(B) unset: the second call did not come from the cache: rc=$( rcOf "$d/second" ) stdout='$( cat "$d/second.out" 2>/dev/null )' cmake calls $c1 -> $c2"
[ "$( git -C "$CORPUS" worktree list 2>/dev/null | grep -c . )" -eq 1 ] \
    && ok "(B) unset: the build registers no worktree in the corpus (its checkout is a private clone; test/worktreeleakcheck.sh kills it mid-build)" \
    || no "(B) unset: the build left a worktree registered in the corpus: $( git -C "$CORPUS" worktree list 2>&1 | tr '\n' '|' )"

# mutation: the library without its staged dispatch must go back to building, so the refusal arm above can go red
MUTLIB="$TMP/headbinlib.nostage.sh"
mutLine="$( python3 - "$LIB" "$MUTLIB" <<'PYEOF'
import io, sys
src, dst = sys.argv[1], sys.argv[2]
lines = io.open(src, encoding="utf-8").read().split("\n")
hits = [i for i, l in enumerate(lines) if '_headbin_staged "$_sha"' in l and not l.lstrip().startswith("#")]
if len(hits) != 1:
    print("SITES %d" % len(hits)); sys.exit(0)
io.open(dst, "w", encoding="utf-8").write("\n".join(l for i, l in enumerate(lines) if i != hits[0]))
print("MUTATED line %d" % (hits[0] + 1))
PYEOF
)"
if printf '%s' "$mutLine" | grep -q '^MUTATED '; then
    d="$TMP/B.mutant"; hbprep "$d"
    hbrun "$d" call "$TMP/no-such-dir/ripwire" "$MUTLIB"
    if [ "$( rcOf "$d/call" )" != 3 ] && [ "$( shimCalls "$d" )" -gt 0 ]; then
        ok "(B mutation) headbinlib.sh without its staged dispatch ($mutLine) builds instead of refusing (rc=$( rcOf "$d/call" ), $( shimCalls "$d" ) cmake call(s)) -- the refusal arms are not vacuous"
    else
        no "(B mutation) headbinlib.sh without its staged dispatch still refused (rc=$( rcOf "$d/call" ), $( shimCalls "$d" ) cmake calls) -- the arms above cannot tell staged mode from its absence"
    fi
else
    no "(B mutation) expected exactly one staged-dispatch line (_headbin_staged \"\$_sha\") in headbinlib.sh to remove: $mutLine"
fi

# ── (C) CALLERS ─────────────────────────────────────────────────────────────────────────────────────────────────────
nCalls="$( printf '%s\n' "$callOut" | grep -c '^CALL ' || true )"
nBare="$(  printf '%s\n' "$callOut" | grep -c '^CALL BARE ' || true )"
if [ "$nCallers" -ge 1 ]; then
    ok "(C) $nCallers gate(s) call ripwire_head_binary at $nCalls site(s): $( printf '%s' "$CALLERS" | tr '\n' ' ')"
else
    no "(C) no test/*.sh calls ripwire_head_binary -- the caller scan found nothing (renamed function, or the scan broke)"
fi
if [ "$nBare" -eq 0 ] && [ "$nCalls" -ge 1 ]; then
    ok "(C) every call site hands its failure to headbin_refusal -- a broken staged binary FAILS; only an unstaged build failure may skip"
else
    no "(C) $nBare call site(s) handle a failed ripwire_head_binary without headbin_refusal (a staged refusal would print a SKIP, which pargates counts as a pass):"
    printf '%s\n' "$callOut" | grep '^CALL BARE ' | sed 's/^/    /'
fi

refusal(){   # refusal RC -> the stub ok/no/skip transcript plus the accumulator, from the real library
    ( fail=0
      ok(){ echo "OK $*"; }; no(){ echo "NO $*"; fail=1; }; skip(){ echo "SKIP $*"; }
      RIPWIRE_HEADBIN="$TMP/no-such-dir/ripwire"; export RIPWIRE_HEADBIN
      . "$LIB" 2>/dev/null
      headbin_refusal "$1" "ctx$1" 2>&1
      echo "fail=$fail" ) 2>&1
}
r3="$( refusal 3 )"; r1="$( refusal 1 )"
printf '%s\n' "$r3" | grep -q '^NO ctx3: .*RIPWIRE_HEADBIN' && printf '%s\n' "$r3" | grep -q '^fail=1$' \
    && ok "(C) headbin_refusal 3 calls the gate's no() and sets its accumulator, naming RIPWIRE_HEADBIN" \
    || no "(C) headbin_refusal 3 did not FAIL the gate: $( printf '%s' "$r3" | tr '\n' '|' )"
printf '%s\n' "$r1" | grep -q '^SKIP ctx1: ' && printf '%s\n' "$r1" | grep -q '^fail=0$' && ! printf '%s\n' "$r1" | grep -q '^NO ' \
    && ok "(C) headbin_refusal 1 keeps the historic skip for an unstaged build failure, accumulator untouched" \
    || no "(C) headbin_refusal 1 is not the historic skip: $( printf '%s' "$r1" | tr '\n' '|' )"

# end to end through one REAL caller: the cheapest one (fixture-only, ~2 s idle). It must still be a caller.
E2E="pyimportprecisecheck.sh"
if printf '%s\n' "$CALLERS" | grep -qx "$E2E"; then
    e2eOut="$( RIPWIRE_BIN="$BIN" RIPWIRE_HEADBIN="$TMP/no-such-dir/ripwire" bash "$ROOT/test/$E2E" 2>&1 )"; e2eRc=$?
    nF="$( printf '%s\n' "$e2eOut" | grep -c '^  FAIL  ' || true )"
    nP="$( printf '%s\n' "$e2eOut" | grep -c '^  PASS  ' || true )"
    nS="$( printf '%s\n' "$e2eOut" | grep -c '^  SKIP  .*monoton' || true )"
    if [ "$e2eRc" -ne 0 ] && [ "$nF" -eq 1 ] && printf '%s\n' "$e2eOut" | grep '^  FAIL  ' | grep -q 'RIPWIRE_HEADBIN' \
       && [ "$nP" -ge 1 ] && [ "$nS" -eq 0 ]; then
        ok "(C) end to end: $E2E with a staged binary that does not exist exits $e2eRc with ONE FAIL row naming RIPWIRE_HEADBIN, beside $nP fixture arm(s) that PASS, and no monotonicity SKIP"
    else
        no "(C) end to end: $E2E with a missing staged binary -- expected rc != 0, exactly one FAIL naming RIPWIRE_HEADBIN, >= 1 PASS and no monotonicity SKIP; got rc=$e2eRc FAIL=$nF PASS=$nP SKIP(monotonicity)=$nS"
        printf '%s\n' "$e2eOut" | grep -E '^  (FAIL|SKIP)  |headbinlib' | head -8 | sed 's/^/    /'
    fi
    # mutation: the same caller with its refusal reverted to the historic bare skip must be flagged by the scan
    mkdir -p "$TMP/mutcaller"
    python3 - "$ROOT/test/$E2E" "$TMP/mutcaller/$E2E" <<'PYEOF' >"$TMP/mutcaller.log" 2>&1
import io, re, sys
t = io.open(sys.argv[1], encoding="utf-8").read()
m, n = re.subn(r'\|\|\s*\{\s*headbin_refusal \$\? "([^"]*)";', r'|| { skip "\1: pre-change build failed";', t)
io.open(sys.argv[2], "w", encoding="utf-8").write(m)
print("REPLACED %d" % n)
PYEOF
    if grep -q '^REPLACED [1-9]' "$TMP/mutcaller.log"; then
        python3 "$CALLSCAN" "$TMP/mutcaller/$E2E" | grep -q '^CALL BARE ' \
            && ok "(C mutation) $E2E with its refusal reverted to a bare skip is flagged BARE -- the caller scan is not vacuous" \
            || no "(C mutation) $E2E with a bare skip was NOT flagged by the caller scan"
    else
        no "(C mutation) no headbin_refusal site in $E2E to revert: $( cat "$TMP/mutcaller.log" )"
    fi
else
    no "(C) end to end: $E2E no longer calls ripwire_head_binary -- pick another caller from: $( printf '%s' "$CALLERS" | tr '\n' ' ')"
fi

# ── (D) RUNNER: pargates hands RIPWIRE_HEADBIN through ─────────────────────────────────────────────────────────────
PGC="$TMP/pgcorpus"; mkdir -p "$PGC/test"
cat > "$PGC/test/hbenvprobecheck.sh" <<'EOF'
#!/usr/bin/env bash
printf '%s' "${RIPWIRE_HEADBIN-<unset>}" > "$HB_ENV_PROBE_OUT"
echo "  PASS  recorded RIPWIRE_HEADBIN"
echo "ALL PASS"
exit 0
EOF
chmod +x "$PGC/test/hbenvprobecheck.sh"
printf '#!/bin/sh\nexit 0\n' > "$TMP/fakebin"; chmod +x "$TMP/fakebin"
WANT="$TMP/staged/ripwire-declared-by-the-job"
pgOut="$( HB_ENV_PROBE_OUT="$TMP/envprobe.out" RIPWIRE_HEADBIN="$WANT" python3 "$ROOT/test/pargates.py" "$PGC" "$TMP/fakebin" --only hbenvprobecheck 2>&1 )"
if printf '%s\n' "$pgOut" | grep -qE '^gates=1 pass=1 ' && [ "$( cat "$TMP/envprobe.out" 2>/dev/null )" = "$WANT" ]; then
    ok "(D) test/pargates.py hands the job's RIPWIRE_HEADBIN through to the gate it runs (gates=1)"
else
    no "(D) the gate under test/pargates.py saw RIPWIRE_HEADBIN='$( cat "$TMP/envprobe.out" 2>/dev/null )', not '$WANT': $( printf '%s\n' "$pgOut" | grep -E '^gates=' )"
fi

[ "$fail" -eq 0 ] && echo "headbinstagecheck: ALL PASS" || { echo "headbinstagecheck: SOME CHECKS FAILED"; exit 1; }
