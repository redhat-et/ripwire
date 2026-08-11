#!/usr/bin/env bash
# gateexitcheck.sh — THE META-GATE: every gate script in test/ must propagate a recorded failure to its
# EXIT STATUS, because regression.sh's verdict is `if ... bash test/$g.sh; then ok`, nothing else.
#
# WHY THIS FILE EXISTS (CA4 trap #27 / §B15). `test/tracecheck.sh` ended with
#     [ "$fail" = 0 ] && echo "ALL PASS" || echo "FAILURES ABOVE"
# and nothing after it. `||`'s echo succeeds, so the script printed six real FAILs and exited 0, and
# every "suite green" for rounds was green including it. The round that found it prescribed the sweep
# `grep -L 'exit $fail' test/*.sh` and then fixed ONE file. The next verifier found two more siblings
# with the identical construct (editcheckcheck, notescheck) — and the behavioural sweep that produced
# this gate found a THIRD in a shape no grep on the exit line can see (g1freshcheck: the accumulator was
# written by `no()` and never read at all). Population: 3 real, out of 190 files the prescribed grep
# flags. The rule had to become a gate, or round five finds the fourth.
#
# WHAT IT ASSERTS, and how much of it is behaviour rather than pattern-matching:
#   (A) LIVENESS — test/gateexitfix/ holds the fixture gates, several deliberately un-failable in
#       DIFFERENT shapes (the counts are derived and printed by the arm, never asserted from this
#       comment). Each is classified AND actually run with a forced failure injected. The
#       classifier's verdict must match the observed exit status on every one. If the classifier ever
#       stops discriminating, (A) reds before (B) can quietly pass the whole tree.
#   (B) THE SWEEP — for every test/*.sh with a failure accumulator, the accumulator's last READ plus
#       everything after it is extracted and EXECUTED twice, once with the accumulator forced to 1 and
#       once to 0. Forced must exit non-zero; clean must exit zero. That is behaviour, not a grep: it
#       runs the gate's own terminal shell, and it costs ~1.5 s for the whole tree because it does not
#       run the gate's body.
#   (C) THE FAIL-FAST PIN — gates with no accumulator cannot exhibit trap #27's defect (there is nothing
#       to leave unread), and (B) has nothing to execute for them. Their membership is PINNED in the
#       table below, each row carrying why it has no accumulator and the exit status observed when its
#       own check was forced to fail by hand. A new gate landing in this family reds until someone
#       probes it and adds a row. The gate does not claim to have proved this family; it claims the set
#       cannot grow unnoticed.
#   (D) SKIP IS NOT PASS — a skip and a pass-with-failures both exit 0, and §B15 forbids conflating
#       them. The distinguisher is the printed vocabulary: a skip prints a skip marker and a reason and
#       NO failure marker. Asserted live on the tree's sanctioned skip (argvdiffcheck with no
#       RIPWIRE_BASE, 17 ms) and on the skip_honest fixture — and, statically, no gate may print
#       "ALL PASS" on a path that skipped, which is what g1freshcheck did before this round.
#   (E) GATEEXIT_FULL=1 — the ground truth, off by default. Copies every gate in place, injects a forced
#       failure before its terminal, RUNS IT, and reads the exit status. ~4 minutes; that is the sweep
#       that found all three defects. (B) is its cheap standing approximation, and the one thing (B)
#       cannot see is an accumulator lost in a subshell before it ever reaches the terminal — run (E)
#       when auditing this file, or after any change to how a gate records failures.
#
# Own exit path: the canonical `exit "$fail"`, and this file is swept by its own arm (B) like any other.
set -u
ROOT="$( cd "$( dirname "$0" )/.." && pwd )"
fail=0
ok(){ printf '  PASS  %s\n' "$*"; }
no(){ printf '  FAIL  %s\n' "$*"; fail=1; }

command -v python3 >/dev/null 2>&1 || { no "python3 is required by gateexitcheck"; echo "FAILURES ABOVE"; exit "$fail"; }

python3 - "$ROOT" <<'PY' || fail=1
import os, re, subprocess, sys, tempfile

ROOT = sys.argv[1]
T    = os.path.join( ROOT, "test" )
FIX  = os.path.join( T, "gateexitfix" )
FULL = os.environ.get( "GATEEXIT_FULL", "" ) == "1"

bad = 0
def ok( m ): print( "  PASS  %s" % m )
def no( m ):
    global bad; bad = 1; print( "  FAIL  %s" % m )

# ── the classifier ────────────────────────────────────────────────────────────────────────────────────
FAILWORD  = re.compile( r'FAIL|FAILURE|FAILED', re.I )
FNDEF     = re.compile( r'^\s*([A-Za-z_]\w*)\s*\(\)\s*\{' )
BUMP      = re.compile( r'\b([A-Za-z_]\w*)=(?:1\b|\$\(\(\s*\1\s*\+\s*1\s*\)\))' )
CTRLSTART = re.compile( r'^\s*(if\s|\[\s|\[\[\s|while\s|until\s)' )
OPENTOK   = { "if": "fi", "for": "done", "while": "done", "until": "done", "case": "esac" }
CLOSEOPEN = { "fi": "if :; then", "done": "while false; do", "esac": "case _ in _)" }
TOKENS    = re.compile( r'(?<![\w$.-])(if|for|while|until|case|fi|done|esac)(?![\w.-])' )

def recorder_var( lines ):
    """The variable a FAIL-printing helper assigns — i.e. the gate's failure accumulator."""
    i = 0
    while i < len( lines ):
        m = FNDEF.match( lines[i] )
        if m:
            depth = lines[i].count( "{" ) - lines[i].count( "}" )
            j, body = i, [ lines[i] ]
            while depth > 0 and j + 1 < len( lines ):
                j += 1; body.append( lines[j] )
                depth += lines[j].count( "{" ) - lines[j].count( "}" )
            txt = "\n".join( body )
            if FAILWORD.search( txt ):
                b = BUMP.search( txt )
                if b: return b.group( 1 ), "recorder %s()" % m.group( 1 )
            i = j
        i += 1
    body = "\n".join( lines )                      # no helper: an inline `X=0` … `X=1` next to a FAIL print
    for m in re.finditer( r'^\s*([A-Za-z_]\w*)=0\s*(?:#.*)?$', body, re.M ):
        v = m.group( 1 )
        for l in lines:
            if re.search( r'\b%s=1\b' % re.escape( v ), l ) and FAILWORD.search( l ):
                return v, "inline %s=" % v
    return None, None

def terminal_region( lines, acc ):
    """From the accumulator's LAST read to EOF, widened to the start of the construct that reads it.
    Returns None when the accumulator is never read — g1freshcheck's shape, a defect in itself."""
    read = re.compile( r'\$\{?%s\b' % re.escape( acc ) )
    hits = [ i for i, l in enumerate( lines ) if read.search( l ) ]
    if not hits: return None
    a = hits[-1]; s = a
    for j in range( a, max( -1, a - 10 ), -1 ):
        if CTRLSTART.match( lines[j] ): s = j; break
    return lines[ s: ]

def balance( tail ):
    """A terminal region sliced out of the middle of a block ends with orphan `fi`/`done`/`esac`
    (test/det-gate.sh). Re-open them so the region is a runnable script; never DROP them, because a
    dropped closer could hide the very statement under test."""
    stack, orphans = [], []
    for line in tail:
        if line.lstrip().startswith( "#" ): continue
        for tok in TOKENS.findall( line ):
            if tok in OPENTOK: stack.append( OPENTOK[tok] )
            elif stack and stack[-1] == tok: stack.pop()
            else: orphans.append( tok )
    if any( o not in CLOSEOPEN for o in orphans ): return None
    return [ CLOSEOPEN[o] for o in reversed( orphans ) ] + tail

def run_micro( acc, value, tail ):
    with tempfile.NamedTemporaryFile( "w", suffix=".sh", delete=False ) as fh:
        fh.write( "#!/usr/bin/env bash\n%s=%s\n%s\n" % ( acc, value, "\n".join( tail ) ) )
        p = fh.name
    try:
        return subprocess.run( [ "bash", p ], capture_output=True, timeout=30 ).returncode
    except subprocess.TimeoutExpired:
        return -99
    finally:
        os.unlink( p )

def classify( path ):
    """-> (verdict, detail).  verdict in {OK, BROKEN, NOACC, UNSYNTHESIZABLE}"""
    lines = open( path, encoding="utf-8", errors="surrogateescape" ).read().split( "\n" )
    acc, how = recorder_var( lines )
    if acc is None:
        return "NOACC", "no failure accumulator (fail-fast)"
    tail = terminal_region( lines, acc )
    if tail is None:
        return "BROKEN", "%s records into `%s` and NOTHING EVER READS IT — a `no` on any success path prints a failure and exits 0" % ( how, acc )
    tail = balance( tail )
    if tail is None:
        return "UNSYNTHESIZABLE", "terminal region has an orphan closer this gate cannot re-open"
    forced, clean = run_micro( acc, 1, tail ), run_micro( acc, 0, tail )
    if forced == 0:
        return "BROKEN", "terminal region exits 0 with `%s=1` — it prints the failure and returns success" % acc
    if clean != 0:
        return "UNSYNTHESIZABLE", "terminal region exits %s with `%s=0`; the extraction is not runnable in isolation" % ( clean, acc )
    return "OK", "acc=%s (%s), forced->%s clean->0" % ( acc, how, forced )

# ── (A) LIVENESS: the classifier must red on deliberately-broken fixture gates ─────────────────────────
# expectation, and the exit status the REAL script must show when a failure is forced into it.
FIXTURES = [
    ( "broken_summary.sh",       "BROKEN", 0 ),   # trap #27 verbatim
    ( "broken_unread.sh",        "BROKEN", 0 ),   # accumulator never read (g1freshcheck)
    ( "broken_trailing_echo.sh", "BROKEN", 0 ),   # failure path falls through to a bare echo
    ( "good_exitfail.sh",        "OK",     1 ),
    ( "good_ifelse.sh",          "OK",     1 ),
    ( "good_bracegroup.sh",      "OK",     1 ),
    ( "good_nested_fi.sh",       "OK",     1 ),
    ( "noacc_failfast.sh",       "NOACC",  None ),
    ( "skip_honest.sh",          "NOACC",  None ),
]

def inject_and_run( path, acc ):
    """The (E) machinery, used here on the fixtures: put a forced failure immediately before the
    terminal region and RUN the script for real."""
    lines = open( path, encoding="utf-8", errors="surrogateescape" ).read().split( "\n" )
    tail  = terminal_region( lines, acc )
    at    = len( lines ) - len( tail ) if tail else len( lines )
    out   = lines[ :at ] + [ 'printf "  FAIL  GATEPROBE forced failure (synthetic)\\n"', '%s=1' % acc ] + lines[ at: ]
    d     = os.path.join( os.path.dirname( path ), ".gateprobe." + os.path.basename( path ) )
    open( d, "w", encoding="utf-8", errors="surrogateescape" ).write( "\n".join( out ) )
    try:
        r = subprocess.run( [ "bash", d ], cwd=ROOT, capture_output=True, timeout=420, text=True, errors="replace" )
        return r.returncode, r.stdout + r.stderr
    except subprocess.TimeoutExpired:
        return -99, "TIMEOUT"
    finally:
        os.remove( d )

seen = 0
for name, want, forced_rc in FIXTURES:
    p = os.path.join( FIX, name )
    if not os.path.exists( p ):
        no( "(A) fixture %s is missing — the meta-gate cannot prove itself live without it" % name ); continue
    seen += 1
    got, detail = classify( p )
    if got != want:
        no( "(A) fixture %s: classifier said %s, fixture declares %s — %s" % ( name, got, want, detail ) )
        continue
    rc_plain = subprocess.run( [ "bash", p ], cwd=ROOT, capture_output=True ).returncode
    if rc_plain != 0:
        no( "(A) fixture %s exits %s unforced; a fixture must be green until a failure is forced" % ( name, rc_plain ) )
        continue
    if forced_rc is None:
        ok( "(A) %-24s %-6s (no accumulator to force; unforced exit 0)" % ( name, got ) )
        continue
    acc, _ = recorder_var( open( p, encoding="utf-8" ).read().split( "\n" ) )
    rc, _txt = inject_and_run( p, acc )
    agree = ( rc == 0 ) == ( forced_rc == 0 )
    if not agree:
        no( "(A) fixture %s: forced-failure run exited %s, the fixture declares %s — classifier and behaviour disagree" % ( name, rc, forced_rc ) )
    else:
        ok( "(A) %-24s %-6s classified, and a forced failure really exits %s" % ( name, got, rc ) )
if seen == len( FIXTURES ):
    nbroken = sum( 1 for _n, w, _r in FIXTURES if w == "BROKEN" )
    ok( "(A) liveness: %d fixtures, %d of them un-failable in %d different shapes, all classified AND run" % ( seen, nbroken, nbroken ) )

# ── (C) the fail-fast pin ─────────────────────────────────────────────────────────────────────────────
# gate -> ( why it has no accumulator, the exit status OBSERVED when a failure was forced into its own
#           check by hand, 2026-07-30 ).
# Every rc below was RUN, not read. Four of these were first written from reading the source and TWO of the
# four were wrong (connectcorecheck and type3clonecheck exit 2, not 1) — in the commit whose entire subject
# is "a number that is printed but not checked". If you add a row, force the gate to fail and read the
# status; do not infer it from the `exit` literal you can see, because the one that fires may be another.
FAILFAST = {
    "agentloopcodexcheck.sh":  ( "trailing Python assertions make the interpreter rc the gate rc",     1 ),
    "clonebandcheck.sh":        ( "every check is `echo FAIL; exit 2` at the site",                      2 ),
    "clonelexcheck.sh":         ( "single terminal if/else on the harness binary, `exit 2` on failure",  2 ),
    "communitylabelcheck.sh":   ( "verdict is a TRAILING python3 heredoc; its rc IS the script's",       1 ),
    "connectcorecheck.sh":      ( "compile-and-run harness; `echo FAIL; exit 2` at the ASan run",        2 ),
    "deadprecisioncheck.sh":    ( "verdict is a TRAILING python3 heredoc; its rc IS the script's",       1 ),
    "isolateprovenancecheck.sh":( "verdict is a TRAILING python3 heredoc; its rc IS the script's",       1 ),
    "lintprecisioncheck.sh":    ( "verdict is a TRAILING python3 heredoc; its rc IS the script's",       1 ),
    "mcpcontractcheck.sh":      ( "python3 heredoc's rc captured into `rc`, propagated by a brace group", 1 ),
    "type3clonecheck.sh":       ( "cap_run helper; every assertion is `|| { echo FAIL; exit 2; }`",      2 ),
    "dynmapsimdcheck.sh":       ( "compile-and-run parity harness; every arm is `echo FAIL; exit 2`",    2 ),
    "pmccheck.sh":              ( "compile-and-run PMC harness; every arm is `echo FAIL; exit 2`",       2 ),
    "codexplugincheck.sh":      ( "trailing Python assertions make the interpreter rc the gate rc",     1 ),
    "codexwrapcheck.sh":        ( "each setup-contract assertion is fail-fast with explicit exit 1",    1 ),
    # deckclaimcheck.sh was pinned here until 2026-08-10, when its new slide-count arm gained a real
    # accumulator (`slideClaimFail`) so that EVERY drifted prose site is named in one run instead of
    # only the first. Arm (B) now checks it by running its terminal region forced and clean, which is
    # strictly stronger than this pin ever was — so the row is retired, not reworded.
    "docdriftcommentcheck.sh":  ( "shell/Python contract assertions fail fast and propagate rc 1",       1 ),
    "lintscopecheck.sh":        ( "fixture assertions fail fast and propagate their nonzero status",     1 ),
    "mcpcodexmetacheck.sh":     ( "trailing Python assertions make the interpreter rc the gate rc",     1 ),
    "readmeexamplecheck.sh":    ( "trailing Python assertions make the interpreter rc the gate rc",     1 ),
    "radixsimdcheck.sh":        ( "compile-and-run parity harness; every arm is `echo FAIL; exit 2`",    2 ),
}

# ── (B) the sweep ─────────────────────────────────────────────────────────────────────────────────────
# A probe copy left behind by an interrupted (E) run is itself a `test/*.sh`. os.listdir returns dotfiles
# where the shell glob would not, so a stale probe would be swept as a gate — and, being a copy of THIS
# file, would re-enter the sweep. Sweep the probe prefix out first, then never look at dotfiles.
for _stale in os.listdir( T ):
    if _stale.startswith( ".gateprobe." ):
        try: os.remove( os.path.join( T, _stale ) )
        except OSError: pass
gates = sorted( n for n in os.listdir( T ) if n.endswith( ".sh" ) and not n.startswith( "." ) )
counts, broken, noacc, unsynth = {}, [], [], []
for n in gates:
    v, d = classify( os.path.join( T, n ) )
    counts[v] = counts.get( v, 0 ) + 1
    if   v == "BROKEN":          broken.append( ( n, d ) )
    elif v == "NOACC":           noacc.append( n )
    elif v == "UNSYNTHESIZABLE": unsynth.append( ( n, d ) )

for n, d in broken:
    no( "(B) test/%s CANNOT FAIL: %s" % ( n, d ) )
for n, d in unsynth:
    no( "(B) test/%s could not be checked: %s — give it a house terminal form, or extend the classifier" % ( n, d ) )
if not broken and not unsynth:
    ok( "(B) sweep: %d of %d gates ran their own terminal region forced and clean — every one exits non-zero on a recorded failure and zero without" % ( counts.get( "OK", 0 ), len( gates ) ) )

missing = sorted( set( noacc ) - set( FAILFAST ) )
stale   = sorted( set( FAILFAST ) - set( noacc ) )
if missing:
    no( "(C) new fail-fast gate(s) with no accumulator and no pin: %s — probe each by hand (GATEEXIT_FULL=1 will not reach them) and add a row to FAILFAST" % ", ".join( missing ) )
if stale:
    no( "(C) FAILFAST pins a gate that no longer qualifies (it grew an accumulator, or was deleted): %s" % ", ".join( stale ) )
if not missing and not stale:
    ok( "(C) fail-fast pin: %d gates carry no accumulator, exactly the %d pinned with a reason" % ( len( noacc ), len( FAILFAST ) ) )

# ── (D) skip is not pass ──────────────────────────────────────────────────────────────────────────────
SKIPWORD = re.compile( r'\bskip', re.I )   # case-insensitive: g1freshcheck's helper was spelled `skip(...)`
ALLPASS  = re.compile( r'ALL PASS' )
offenders = []
for n in gates:
    lines = open( os.path.join( T, n ), encoding="utf-8", errors="surrogateescape" ).read().split( "\n" )
    for i, l in enumerate( lines ):
        if not re.match( r'^\s*exit\s+0\s*$', l ) or i == len( lines ) - 1: continue
        # comments only DESCRIBE the conflation — this file's own header does — so read code lines only
        window = [ w for w in lines[ max( 0, i - 3 ) : i ] if not w.lstrip().startswith( "#" ) ]
        if any( SKIPWORD.search( w ) for w in window ) and any( ALLPASS.search( w ) for w in window ):
            offenders.append( "test/%s:%d" % ( n, i + 1 ) )
if offenders:
    no( "(D) a SKIP path announces itself as ALL PASS, then exits 0 — a skip asserted nothing and must not claim to have passed: %s" % ", ".join( offenders ) )
else:
    ok( "(D) no gate prints ALL PASS on a path that skipped (%d gates scanned)" % len( gates ) )

AV = os.path.join( T, "argvdiffcheck.sh" )
if os.path.exists( AV ):
    env = { k: v for k, v in os.environ.items() if k != "RIPWIRE_BASE" }
    r = subprocess.run( [ "bash", AV ], cwd=ROOT, env=env, capture_output=True, text=True, timeout=120 )
    txt = r.stdout + r.stderr
    if r.returncode != 0:
        no( "(D) argvdiffcheck without RIPWIRE_BASE exited %s; the sanctioned skip must be exit 0" % r.returncode )
    elif not SKIPWORD.search( txt ):
        no( "(D) argvdiffcheck's skip exits 0 without printing a skip marker — indistinguishable from a pass" )
    elif re.search( r'\bFAIL\b', txt ):
        no( "(D) argvdiffcheck's skip printed a FAIL marker and still exited 0" )
    elif "RIPWIRE_BASE" not in txt:
        no( "(D) argvdiffcheck's skip does not say what would activate it" )
    else:
        ok( "(D) the tree's sanctioned skip (argvdiffcheck, no RIPWIRE_BASE) exits 0, prints SKIP + the reason, prints no FAIL" )

# ── (E) ground truth, opt-in ──────────────────────────────────────────────────────────────────────────
if FULL:
    import concurrent.futures
    jobs = int( os.environ.get( "GATEEXIT_JOBS", "10" ) )
    todo = []
    for n in gates:
        # gateexitcheck.sh IS the sweep (probing it re-enters this arm); regression.sh is the runner, and
        # probing it would run all 300 gates inside one gate. FAILFAST gates have no accumulator to force.
        if n in FAILFAST or n in ( "gateexitcheck.sh", "regression.sh" ): continue
        p = os.path.join( T, n )
        acc, _ = recorder_var( open( p, encoding="utf-8", errors="surrogateescape" ).read().split( "\n" ) )
        if acc is not None: todo.append( ( n, p, acc ) )
    def one( t ):
        n, p, acc = t
        rc, txt = inject_and_run( p, acc )
        return n, rc, txt
    real, skipped = 0, []
    with concurrent.futures.ThreadPoolExecutor( max_workers=jobs ) as ex:
        for n, rc, txt in ex.map( one, todo ):
            reached = "GATEPROBE forced failure" in txt
            if reached and rc != 0:
                real += 1
            elif reached:
                no( "(E) test/%s printed a forced failure and exited %s" % ( n, rc ) )
            # not reached: the gate exited before the injection point. That is a SKIP only if it exits 0
            # having printed a skip marker and NO failure marker — §B15's distinction, enforced not assumed.
            elif rc == 0 and SKIPWORD.search( txt ) and not re.search( r'\bFAIL\b', txt ):
                skipped.append( n )
            else:
                no( "(E) test/%s exited %s before reaching the injection point, and its output is not an honest skip (a skip prints a skip marker, a reason, and no FAIL)" % ( n, rc ) )
    ok( "(E) GROUND TRUTH: %d of %d gates run END TO END with a forced failure, every one exits non-zero%s"
        % ( real, len( todo ), ( "; %d skipped honestly before the injection point (%s)" % ( len( skipped ), ", ".join( skipped ) ) ) if skipped else "" ) )
else:
    print( "  SKIP  (E) ground-truth run not requested — nothing asserted by this arm. GATEEXIT_FULL=1 runs" )
    print( "        every gate for real with a forced failure (~4 min); (B) is its standing approximation," )
    print( "        and the one thing (B) cannot see is an accumulator lost in a subshell before the terminal." )

sys.exit( bad )
PY

[ "$fail" = 0 ] && echo "ALL PASS" || echo "FAILURES ABOVE"
exit "$fail"
