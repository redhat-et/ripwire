#!/usr/bin/env bash
# binoverridecheck.sh — THE FALSE-GREEN gate for the binary-override convention itself.
#
# WHY THIS FILE EXISTS (wave-4 board item #10, flagged by the wave-3 verifier). test/pargates.py and
# test/regression.sh — the two ways this whole suite is actually invoked — select the binary under test
# with EXACTLY ONE mechanism: the RIPWIRE_BIN environment variable (pargates.py sets it per-subprocess,
# see `env = dict(os.environ, RIPWIRE_BIN=binp)`; regression.sh exports the same via `RIPWIRE_BIN="$BIN"
# bash ...`). Neither runner EVER passes the binary as $1. A gate that reads $1 for its binary and never
# falls back to RIPWIRE_BIN therefore silently tests the DEFAULT ./build/ripwire — not the binary the
# runner selected — while printing PASS the whole way. That is not hypothetical: test/lb3namecheck.sh did
# exactly this (`BIN="${1:-./build/ripwire}"`) until this round, and it is the reason this gate exists
# instead of a one-line fix. A verified misreport generator across ~430 scripts does not get another
# audit-by-eye; it gets a standing check that manufactures the failure and watches for it.
#
# THE FIX this round applied (same commit): every gate that resolves a binary now uses the ONE convention
#     BIN="${1:-${RIPWIRE_BIN:-<default>}}"
# — RIPWIRE_BIN first-class (so pargates.py / regression.sh always win), $1 as a compatible fallback for
# manual invocation (`bash test/foo.sh /path/to/other/ripwire`) that also works standing alone. This gate
# does not trust that the fix was applied correctly by re-reading the source; it proves it BEHAVIOURALLY:
# point RIPWIRE_BIN at a stub that fails LOUDLY on every invocation, run every gate that touches the binary
# under test, and assert each one actually turns red. A gate that stays green while pointed at a broken
# binary is exactly the false-green class this item exists to kill — this is that check, run for real.
#
# EXEMPTIONS (part below): a minority of gates never invoke the ripwire binary under test at all — they
# check CMake config text, compile an isolated harness from source (independent of build/ripwire), read
# git-tracked files, or check another gate's own source. Pointing RIPWIRE_BIN at a broken stub cannot make
# such a gate fail, so running it here would be noise, not signal. Each is PINNED below with why, the same
# discipline test/gateexitcheck.sh uses for its own FAILFAST table — a new gate that legitimately never
# invokes the binary must be added here by hand (with a reason), or it reds this gate for review, exactly
# the symmetry gateexitcheck's (C) enforces for exit-code propagation.
set -u
ROOT="$( cd "$( dirname "$0" )/.." && pwd )"
fail=0
ok(){ printf '  PASS  %s\n' "$*"; }
no(){ printf '  FAIL  %s\n' "$*"; fail=1; }

command -v python3 >/dev/null 2>&1 || { no "python3 is required by binoverridecheck"; echo "FAILURES ABOVE"; exit "$fail"; }

python3 - "$ROOT" <<'PY' || fail=1
import concurrent.futures as cf
import os, re, subprocess, sys, tempfile

ROOT = sys.argv[1]
T = os.path.join( ROOT, "test" )
SELF = "binoverridecheck.sh"

bad = 0
def ok( m ): print( "  PASS  %s" % m )
def no( m ):
    global bad; bad = 1; print( "  FAIL  %s" % m )

# ── the sentinel: an executable that IS a valid file (so every `[ -x "$BIN" ]` presence check the gates
#    run passes clean) but fails LOUDLY and immediately on every invocation — never hangs, never emits
#    anything a gate could mistake for real output. exit 77 is not a code any real ripwire path returns,
#    so it doubles as a tell in a failure log.
WORK = tempfile.mkdtemp( prefix="binoverridecheck." )
SENTINEL = os.path.join( WORK, "ripwire" )
with open( SENTINEL, "w" ) as fh:
    fh.write(
        "#!/bin/sh\n"
        "echo 'binoverridecheck SENTINEL: this is a deliberately-broken stub, not a real ripwire binary' >&2\n"
        "exit 77\n"
    )
os.chmod( SENTINEL, 0o755 )

# ── (1) discover every gate the way pargates.py does: every test/*.sh but the driver itself, no dotfiles ──
gates = sorted( n for n in os.listdir( T ) if n.endswith( ".sh" ) and not n.startswith( "." ) )
gates = [ g for g in gates if g not in ( "regression.sh", SELF ) ]

# ── (2) the pinned exemption list — gates that never invoke the ripwire binary under test, so a broken
#    RIPWIRE_BIN cannot make them fail. Each reason was verified by reading the gate, not guessed from its
#    name. Committed and counted (this file's own header + (2b) below assert the count out loud).
EXEMPT = {
    "codexinstallhonestycheck.sh": "exercises skills/install.sh's jq/mv merge honesty inside hermetic temp HOMEs; the subject is the shell installer, so BIN is bound for interface uniformity and never executed (verified by reading the gate)",
    "meterdisclosurecheck.sh":   "runs skills/install.sh's --hook banner and asserts what it discloses about the substitution meter; the subject is banner TEXT, so BIN is bound for interface uniformity and never executed (verified by reading the gate)",
    "adaptivecutshapecheck.sh":  "compiles an isolated $CXX probe .cpp; never invokes build/ripwire",
    "aiderbytescheck.sh":        "pure-python test of bench/headtohead/r4-2026-08-06/r4_worker.py's aider byte-count wiring; no ripwire binary invocation",
    "argvdiffcheck.sh":          "sanctioned skip fires BEFORE the RIPWIRE_BIN guard, gated on a second env var (RIPWIRE_BASE) neither pargates.py nor regression.sh ever sets; independent of RIPWIRE_BIN/broken-binary state, and already asserted intentional by gateexitcheck.sh arm (D)",
    "nulbytecheck.sh":           "reads the SOURCE TREE (git ls-files), not the binary; BIN is bound for interface uniformity and explicitly documented as unused in the gate's own header",
    "agentloopfollowupcheck.sh": "pure-python test of bench/agentloop/followup_calls.py over a synthetic pilot json and the committed pilot-6run.json; BIN is bound for interface uniformity and never executed (verified by reading the gate)",
    "arisefollowupcheck.sh":     "pure-python test of bench/arise-h2h/followup_calls.py over synthetic SWE-agent .traj fixtures; BIN is bound for interface uniformity and never executed (verified by reading the gate)",
    "routingreportcheck.sh":     "pure-python test of bench/routing_ab_report.py over synthetic routing/substitution jsonl in a temp dir; BIN is bound (`: \"$BIN\"`) for interface uniformity and never executed (verified by reading the gate)",
    "agentloopcodexcheck.sh":    "pure-python test of bench/agentloop prompt-building; the path to build/ripwire is asserted as a STRING, never executed",
    "agentloopgradercheck.sh":   "pure-python test of the agentloop grader's circular-invocation detector; 'ripwire' appears only in fixture command strings, never executed",
    "agentlooplockcheck.sh":     "pure-python/schema test of tasks.lock partitioning; no CLI invocation",
    "clonebandcheck.sh":         "compiles an isolated $CXX probe .cpp; never invokes build/ripwire",
    "clonelexcheck.sh":          "builds its OWN standalone harness binary from src/*.cpp, independent of build/ripwire",
    "codexplugincheck.sh":       "pure-python/json check of a static MCP manifest file; 'ripwire' only appears as a string field",
    "columnarcommacheck.sh":     "compiles an isolated $CXX probe .cpp; never invokes build/ripwire",
    "connectcorecheck.sh":       "builds its OWN standalone harness binary, independent of build/ripwire",
    "dependencypincheck.sh":     "CMake-configure-level gate (checks CMakeLists.txt text + a throwaway cmake -S/-B configure); no ripwire binary",
    "dynmapsimdcheck.sh":        "builds its OWN standalone harness binaries per SIMD arm, independent of build/ripwire",
    "flagtablecheck.sh":         "pure file/doc-table check; no binary invocation",
    "g1configcheck.sh":          "greps CMakeLists.txt for the G1 sanitizer flag derivation; no binary invocation",
    "g1freshcheck.sh":           "checks asan/ripwire's mtime on disk against src/; never executes the binary",
    "gateexitcheck.sh":          "meta-check of other gates' own shell/exit-code conventions; no binary invocation",
    "infraportcheck.sh":         "greps source files for the literal string 'ripwire'; no binary invocation",
    "loopconservationcheck.sh":  "reads test/regression.sh's absorb loop via `git show REF:...` across HEAD and its merge parents (a pure git-history check); never invokes build/ripwire",
    "manifestcheck.sh":          "checks that every test/*check.sh is listed in test/regression.sh; pure file check",
    "optremarkscheck.sh":        "checks -DRIPWIRE_OPT_REMARKS/-DRIPWIRE_PGO CMake config text; no binary invocation",
    "pargatescheck.sh":          "meta-check of test/pargates.py's own source; pure file check",
    "pmccheck.sh":               "builds its OWN standalone harness binary, independent of build/ripwire",
    "portablebuildcheck.sh":     "CMake-configure-level gate only; the gate's own banner says 'no ripwire binary needed'",
    "qschemetripcheck.sh":       "greps src/quality.h's tripwire comment against the test/*.sh manifest; pure file check",
    "radixsimdcheck.sh":         "builds its OWN standalone harness binaries per SIMD arm, independent of build/ripwire",
    "releaseinstallcheck.sh":    "tests install.sh against a FABRICATED release asset/stub server; independent of build/ripwire",
    "reusefirstworkflowcheck.sh":"checks skills/ripwire-reuse-first/SKILL.md content; pure file check",
    "ripwirepubliccheck.sh":     "checks git-tracked files for leaked private content; pure file/grep check",
    "svectorcheck.sh":           "compiles isolated $CXX probes for the svector container; never invokes build/ripwire",
}

toRun = [ g for g in gates if g not in EXEMPT ]

# ── (2a) drift: a pinned exemption for a gate that no longer exists is stale — retire the row ───────────
stalePins = sorted( set( EXEMPT ) - set( gates ) )
if stalePins:
    no( "(2a) EXEMPT pins gate(s) that no longer exist on disk: %s — retire the row" % ", ".join( stalePins ) )
else:
    ok( "(2a) every pinned exemption names a gate that still exists (%d pins)" % len( EXEMPT ) )

# ── (2b) drift the other direction: an exempted gate that GREW a binary invocation is a stale exemption,
#    silently un-tested from here on. Cheap static tell: the gate now mentions RIPWIRE_BIN AND assigns a
#    $BIN it goes on to invoke. Not exhaustive (a gate could invoke the binary a stranger way), but it
#    catches the ordinary case — the same one every EXEMPT row above was verified against by hand.
#
#    Two rows are KNOWINGLY exempt from this static tell, not blind to it — their own EXEMPT reason
#    already names a real "$BIN" invocation in the file:
#      argvdiffcheck.sh — the invocation exists further down, behind a sanctioned skip (no RIPWIRE_BASE)
#                          that this file's own reason string explains fires first, every real run.
#      nulbytecheck.sh  — the file's own header says BIN is bound-but-unused in so many words; grepping
#                          "$BIN" finds that header sentence, not an invocation.
#      codexinstallhonestycheck.sh, meterdisclosurecheck.sh — same shape as nulbytecheck.sh. Both test
#                          skills/install.sh (a shell installer and its banner text), so they need no
#                          ripwire binary at all. Verified by reading every BIN occurrence in each file:
#      routingreportcheck.sh — same shape again: the shared BIN= convention line plus a `: "$BIN"` no-op
#                          annotated "unused"; the subject is bench/routing_ab_report.py, pure python.
#                          a usage comment, the shared BIN= convention line, and a `: "$BIN"` no-op whose
#                          trailing comment says it is unused. There is no invocation to find.
STATICALLY_UNREACHABLE = { "argvdiffcheck.sh", "nulbytecheck.sh",
                           "codexinstallhonestycheck.sh", "meterdisclosurecheck.sh", "routingreportcheck.sh" }
grown = []
for g in sorted( EXEMPT ):
    if g in STATICALLY_UNREACHABLE:
        continue
    path = os.path.join( T, g )
    if not os.path.isfile( path ):
        continue
    with open( path, errors="replace" ) as fh:
        text = fh.read()
    if re.search( r'RIPWIRE_BIN', text ) and re.search( r'\$BIN\b|\$\{BIN\}', text ):
        grown.append( g )
if grown:
    no( "(2b) EXEMPT gate(s) now reference RIPWIRE_BIN/$BIN and may invoke the binary — re-verify and drop from EXEMPT if so: %s" % ", ".join( grown ) )
else:
    ok( "(2b) no pinned exemption shows a grown binary invocation (static check, %d rows exempted from the check itself by name — see comment)" % len( STATICALLY_UNREACHABLE ) )

# ── (3) per-gate timeout budget. Default is generous for a stub that fails in milliseconds; the six
#    headbinlib.sh gates (crossdirinclude/pyimportprecise/rustimportprecise/tsimportprecise/nestedimport/
#    preproccond) build a SECOND, real binary from git HEAD regardless of RIPWIRE_BIN (that build is what
#    they diff the broken stub against), so they need headroom for the one-time ~50s build even though
#    the sentinel side of the comparison fails instantly. hookcheck.sh / skillinstallcheck.sh /
#    agentloopclaudecheck.sh do enough fixture setup around their (few) real invocations to earn a little
#    more room too. vendorpatchcheck.sh's real cost is NOT the (instant) sentinel invocation — it's the
#    repo-wide patch/scanner static-analysis loops (arms A-E, H) that run regardless of binary state;
#    measured at 60s+ against the sentinel, given headroom rather than tuned to the edge. A gate that
#    still times out is reported, not silently retried.
DEFAULT_TIMEOUT = 60
BUDGET = {
    "crossdirincludecheck.sh":   300,
    "nestedimportcheck.sh":      300,
    "preproccondcheck.sh":       300,
    "pyimportprecisecheck.sh":   300,
    "rustimportprecisecheck.sh": 300,
    "tsimportprecisecheck.sh":   300,
    "hookcheck.sh":              120,
    "skillinstallcheck.sh":      120,
    "agentloopclaudecheck.sh":   120,
    "vendorpatchcheck.sh":       150,
}

def run_one( g ):
    env = dict( os.environ )
    env["RIPWIRE_BIN"] = SENTINEL
    limit = BUDGET.get( g, DEFAULT_TIMEOUT )
    try:
        p = subprocess.run(
            [ "bash", os.path.join( T, g ) ],
            cwd=ROOT, env=env, capture_output=True, timeout=limit,
        )
        rc, out = p.returncode, ( p.stdout + p.stderr ).decode( "utf-8", "replace" )
    except subprocess.TimeoutExpired:
        rc, out = 124, "TIMEOUT after %ds pointed at the sentinel" % limit
    return g, rc, out[-800:]

# ── (4) run every non-exempt gate pointed at the sentinel, modest parallelism (this gate is itself one
#    entry in test/pargates.py's own -j budget, competing with the rest of the suite for CPU) ────────────
results = {}
with cf.ThreadPoolExecutor( max_workers=6 ) as ex:
    for g, rc, out in ex.map( run_one, toRun ):
        results[g] = ( rc, out )

offenders = sorted( g for g, ( rc, _ ) in results.items() if rc == 0 )
timeouts  = sorted( g for g, ( rc, _ ) in results.items() if rc == 124 )

if offenders:
    no( "(4) %d gate(s) stayed GREEN while RIPWIRE_BIN pointed at a stub that fails on every invocation — false-green, the exact class this gate exists to kill:" % len( offenders ) )
    for g in offenders:
        rc, out = results[g]
        tail = out.strip().splitlines()
        tail = tail[-3:] if tail else []
        print( "    [%s] rc=0 — last output: %s" % ( g, " | ".join( tail ) ) )
else:
    ok( "(4) all %d non-exempt gates FAILED when pointed at the sentinel (0 false-greens)" % len( toRun ) )

if timeouts:
    print( "  NOTE  %d gate(s) timed out against the sentinel (counted as detecting the break, not as a false-green; budget may need raising): %s" % ( len( timeouts ), ", ".join( timeouts ) ) )

ok( "binoverridecheck: %d gates total, %d exempt (no binary invocation), %d run against the sentinel" % ( len( gates ), len( EXEMPT ), len( toRun ) ) )

sys.exit( bad )
PY

[ "$fail" = 0 ] && echo "ALL PASS" || echo "FAILURES ABOVE"
exit "$fail"
