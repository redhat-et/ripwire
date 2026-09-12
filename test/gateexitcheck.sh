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
#   (F) THE PROBE COPY IS INVISIBLE TO `git status --porcelain` — (A)'s copies live in a mktemp dir
#       outside the checkout; (E)'s must sit beside the gate they copy (a gate finds its root from $0),
#       so they are named .gateprobe.*, which .gitignore hides. Every stamped verb reads that exact
#       command, from ANY crawl root inside the checkout, for its at="<sha>+dirty" bit — an untracked
#       probe flips every determinism arm running beside this gate under pargates -j N (CI run
#       34298150602: tokenbudgetcheck --for, est_tokens 3949 vs 3947, blamed on prbudgetcheck).
#       Asserted with a mutation control on the checkout's own .gitignore text, and per probe in (E).
#
# Own exit path: the canonical `exit "$fail"`, and this file is swept by its own arm (B) like any other.
set -u
ROOT="$( cd "$( dirname "$0" )/.." && pwd )"
fail=0
ok(){ printf '  PASS  %s\n' "$*" || { fail=1; printf '  FAIL  could not write the PASS line for: %s\n' "$*"; }; return 0; }
no(){ printf '  FAIL  %s\n' "$*"; fail=1; }

command -v python3 >/dev/null 2>&1 || { no "python3 is required by gateexitcheck"; echo "FAILURES ABOVE"; exit "$fail"; }

# ── (F) the probe copy is INVISIBLE to `git status --porcelain` ──────────────────────────────────────
# (E) writes its probe copy BESIDE the gate it copies (a real gate finds its repo root from $0), which
# puts an untracked file inside the shared checkout for as long as the probe runs. Every stamped verb
# (--for, --pr-context, --edit-check, --slice, --situ, --hotspots, --doctor, ...) reads
# `git status --porcelain` from ANY crawl root inside this checkout for the `+dirty` half of its
# at="<sha>[+dirty]" anchor (src/gitstamp.h stampAt), so that file flips every determinism arm running
# beside this gate. CI run 34298150602, macOS plain shard 2/2: tokenbudgetcheck's `--for` arm got
# est_tokens 3949 then 3947 -- "+dirty" is six bytes, two tokens at 2.5 B/tok -- while (A)'s
# .gateprobe.*.sh sat in test/gateexitfix/ three worker slots away; issue #71 blamed prbudgetcheck,
# which has never written outside its own mktemp. (A) now writes its copies to a mktemp dir (the
# fixtures never read $0). (E) cannot, so .gitignore names `.gateprobe.*`, and this arm asserts the
# hiding holds -- with a mutation control per CONTRIBUTING §2: the checkout's OWN .gitignore text is
# seeded into a scratch repo (real input), the identical extraction runs over it (git status
# --porcelain), and a twin file the pattern must NOT hide proves the extraction sees untracked files at
# all. Nothing is written into the real checkout to prove it; the in-situ answer is git's own
# check-ignore for the two paths (E) would write. test/pargates.py's tree tripwire is the runner-side
# half: it samples the same command while the suite runs and names whoever is in flight.
if command -v git >/dev/null 2>&1 && git -C "$ROOT" rev-parse --git-dir >/dev/null 2>&1; then
    CTRL="$( mktemp -d )"
    ( cd "$CTRL" && git init -q . && cp "$ROOT/.gitignore" .gitignore && mkdir -p test/gateexitfix \
      && : > test/.gateprobe.control.sh && : > test/gateexitfix/.gateprobe.control.sh && : > test/gateprobe.twin.sh ) \
      || no "(F control) could not seed a scratch repo with this checkout's .gitignore"
    SEEN="$( git -C "$CTRL" status --porcelain --untracked-files=all 2>/dev/null | sed -E 's/^\?\? //' | LC_ALL=C sort | tr '\n' ' ' )"
    rm -rf "$CTRL"
    case " $SEEN " in
        *" test/gateprobe.twin.sh "*) ok "(F control) git status lists the un-ignored twin in the seeded repo -- the extraction sees untracked files";;
        *)                            no "(F control) git status did not list the un-ignored twin (saw: '$SEEN') -- the extraction is blind, and the arm below proves nothing";;
    esac
    case " $SEEN " in
        *".gateprobe."*) no "(F) this checkout's .gitignore does NOT hide .gateprobe.* -- git status listed: $SEEN";;
        *)               ok "(F) this checkout's .gitignore hides .gateprobe.* in test/ and test/gateexitfix/ (the same text, the same command stampAt runs)";;
    esac
    for p in test/.gateprobe.control.sh test/gateexitfix/.gateprobe.control.sh; do
        git -C "$ROOT" check-ignore -q "$p" && ok "(F) git check-ignore: $p is ignored in this checkout" \
            || no "(F) git check-ignore: $p is NOT ignored in this checkout -- an (E) probe there would read as +dirty"
    done
else
    ok "(F) no git repository around this checkout -- nothing reads +dirty here, so no probe can flip it"
fi

python3 - "$ROOT" <<'PY' || fail=1
import atexit, os, re, shutil, subprocess, sys, tempfile

ROOT = sys.argv[1]
T    = os.path.join( ROOT, "test" )
FIX  = os.path.join( T, "gateexitfix" )
FULL = os.environ.get( "GATEEXIT_FULL", "" ) == "1"
# (F) arm (A)'s probe copies live OUTSIDE the checkout: the fixtures never read $0, so nothing of theirs
# has to sit beside the original, and a file that is not inside the repository cannot read as +dirty to
# anyone. Only (E) writes beside a real gate -- see inject_and_run.
PROBEDIR = tempfile.mkdtemp( prefix="gateexit-probes-" )
atexit.register( shutil.rmtree, PROBEDIR, True )

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

def probe_is_invisible( d ):
    """(F) The in-place probe must not show in `git status --porcelain` -- the command every stamped verb
    runs, from ANY crawl root inside this checkout, for the `+dirty` half of its at= anchor. Asked of git
    about the REAL file just written, never inferred from the pattern text. Returns ( ok, detail )."""
    try:
        seen = subprocess.run( [ "git", "--no-optional-locks", "-C", ROOT, "status", "--porcelain", "--untracked-files=all", "--", d ],
                               capture_output=True, text=True, errors="replace", timeout=60 )
    except ( OSError, subprocess.TimeoutExpired ) as e:
        return True, "git unavailable (%s) -- nothing here reads +dirty either" % e
    if seen.returncode != 0:
        return True, "not a git checkout (rc=%s) -- nothing here reads +dirty either" % seen.returncode
    return not seen.stdout.strip(), seen.stdout.strip()

def inject_and_run( path, acc, probe_dir=None ):
    """The (E) machinery, used here on the fixtures: put a forced failure immediately before the
    terminal region and RUN the script for real.
    probe_dir: where the probe copy is written. (A) passes PROBEDIR, a mktemp dir outside the checkout.
    (E) passes None -- a REAL gate derives its repo root from $0, so its copy must sit beside it -- and
    the copy is then named .gateprobe.*, which .gitignore hides from `git status --porcelain`; that
    hiding is asserted on the real file, before the probe runs (arm F)."""
    lines = open( path, encoding="utf-8", errors="surrogateescape" ).read().split( "\n" )
    tail  = terminal_region( lines, acc )
    at    = len( lines ) - len( tail ) if tail else len( lines )
    out   = lines[ :at ] + [ 'printf "  FAIL  GATEPROBE forced failure (synthetic)\\n"', '%s=1' % acc ] + lines[ at: ]
    d     = os.path.join( probe_dir if probe_dir else os.path.dirname( path ), ".gateprobe." + os.path.basename( path ) )
    open( d, "w", encoding="utf-8", errors="surrogateescape" ).write( "\n".join( out ) )
    try:
        if probe_dir is None:
            hidden, detail = probe_is_invisible( d )
            if not hidden:
                no( "(F) the in-place probe %s is VISIBLE to `git status --porcelain` (%s) -- every stamped verb running beside this gate reads a dirty tree while it exists"
                    % ( os.path.relpath( d, ROOT ), detail ) )
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
    rc, _txt = inject_and_run( p, acc, PROBEDIR )
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
    "elixirsemanticcheck.sh":  ( "set -e and Python assertions; missing protocol and branch-scope probes observed exit 1", 1 ),
    "dartcheck.sh":            ( "set -e and Python assertions; pre-Dart HEAD binary probed to exit 1", 1 ),
    "elixircheck.sh":          ( "set -e and Python assertions; pre-Elixir HEAD binary probed to exit 1", 1 ),
    "agentloopcodexcheck.sh":  ( "trailing Python assertions make the interpreter rc the gate rc",     1 ),
    "clonebandcheck.sh":        ( "every check is `echo FAIL; exit 2` at the site",                      2 ),
    "clonelexcheck.sh":         ( "single terminal if/else on the harness binary, `exit 2` on failure",  2 ),
    "communitylabelcheck.sh":   ( "verdict is a TRAILING python3 heredoc; its rc IS the script's",       1 ),
    "connectcorecheck.sh":      ( "compile-and-run harness; `echo FAIL; exit 2` at the ASan run",        2 ),
    "deadprecisioncheck.sh":    ( "verdict is a TRAILING python3 heredoc; its rc IS the script's",       1 ),
    "isolateprovenancecheck.sh":( "verdict is a TRAILING python3 heredoc; its rc IS the script's",       1 ),
    "lintprecisioncheck.sh":    ( "verdict is a TRAILING python3 heredoc; its rc IS the script's",       1 ),
    "mcpattrparitycheck.sh":    ( "python3 heredoc's rc captured into `rc` and re-exited; FORCED by breaking one RENAME entry, rc read, not inferred", 1 ),
    "mcpcontractcheck.sh":      ( "python3 heredoc's rc captured into `rc`, propagated by a brace group", 1 ),
    "mcpmanifestcheck.sh":       ( "verdict is a TRAILING python3 heredoc (sys.exit); FORCED by appending a bogus routing-sentence pin, rc read, not inferred", 1 ),
    # type3clonecheck.sh was pinned here until 2026-08-11, when its PART 2 (clone grouping + duplication
    # %) gained a real accumulator (`p2fail`) so every drifted attribute is named in one run instead of
    # only the first. PART 1's cap_run arms are still fail-fast, but arm (B) now reaches the terminal
    # region and checks it forced and clean, which is strictly stronger than this pin was — so the row is
    # retired, not reworded (the deckclaimcheck precedent, one round earlier).
    "dynmapsimdcheck.sh":       ( "compile-and-run parity harness; every arm is `echo FAIL; exit 2`",    2 ),
    "pmccheck.sh":              ( "compile-and-run PMC harness; every arm is `echo FAIL; exit 2`",       2 ),
    "codexplugincheck.sh":      ( "trailing Python assertions make the interpreter rc the gate rc",     1 ),
    "codexwrapcheck.sh":        ( "each setup-contract assertion is fail-fast with explicit exit 1",    1 ),
    "impactpartitioncheck.sh":  ( "python3 heredoc: the sample-size and empty-output preflights are fail-fast sys.exit(1); the verdict arms accumulate into fail[] and sys.exit(fail[0]) is the rc — probed 2026-09-03 with a stub binary, forced failure exits 1", 1 ),
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

# ── (G) A VERDICT IS NOT A WRITE ──────────────────────────────────────────────────────────────────────
# Trap #27's family, one step further in. (A)-(F) ask whether a RECORDED failure reaches the exit status.
# This arm asks the question underneath it: can a gate record a failure that never happened?
#
# PR #126, CI run 34601131199, job 103268490365 (macos-14, Release, appleclang, shard 1/4) --
# tracehandoffcapcheck reported
#     L13:   FAIL  B4 crossing: packet lists 12 of the map's 25 symbols in wide.md (cap 12)
# whose own pass condition is `shown == cap and real > cap`. 12 == 12 and 25 > 12, so the arm PASSED and
# the gate said FAIL. Every other leg of that run passed it. The reporting was
#     [ "$verdict" = OK ] && ok "$tag $rest" || no "$tag $rest"
# and in `A && B || C`, C also runs when B fails (shellcheck SC2015). `ok` is a printf, and a printf to
# the harness's capture pipe CAN fail: pargates.py used to hand every gate a blocking PIPE, and bash
# installs its SIGCHLD handler WITHOUT SA_RESTART (sa_flags gets SA_RESTART only for sig != SIGCHLD), so
# when a stalled reader lets the pipe fill, a gate that forks -- every gate forks -- gets EINTR out of
# write(2). Measured, 2026-09-11, on a plain blocking pipe with a stalled reader: 600 arms, 600 PASS
# lines and 21 spurious FAILs, errno `Interrupted system call` every time. The buffered bytes survive in
# the FILE*, so the PASS line still appears and the transcript reads
#     PASS <arm>  /  printf: write error: Interrupted system call  /  FAIL <arm>
# which is exactly the 18-line transcript that run showed where a green one is 16 lines.
#
# The fix is a CONTRACT on the reporter, not a spelling: ok() can no longer return non-zero, so the `||`
# of any such chain cannot fire while the condition held. A failed write is still a failure -- it sets
# the accumulator -- but it says so in its own words instead of borrowing the arm's.
#
#   G1  THE CONTRACT, behaviourally: every distinct ok() definition in the suite is RUN with a stdout it
#       cannot write to. It must exit 0 and set its file's accumulator. Probed per distinct definition
#       text, not per file, so the sweep costs six subshells rather than six hundred.
#   G2  THE SPELLING: no gate reports a verdict through a single-line `… && ok … || no …` any more.
#
# Both carry a mutation control, because a probe that cannot see the defect proves nothing: G1 runs the
# pre-fix definition and requires it to FAIL the probe; G2 runs its sweep over a planted site and
# requires it to be found.
#
# What this arm deliberately does NOT assert: the same chain spelled across continuation lines
# (`cmd \` / `    && ok … \` / `    || no …`) is still how most of the suite reads. It is the identical
# construct and it is made safe by G1, not by its shape -- converting those thousands of sites was not
# part of the change that added this arm, and a rule that forbade the one-line spelling while tolerating
# the wrapped one would be a style pin wearing a correctness rule's clothes. G2 pins what the conversion
# actually achieved; the count of wrapped sites is PRINTED, never asserted, so it cannot serialise lanes.
python3 - "$ROOT" <<'PY' || fail=1
import glob, os, re, subprocess, sys

T = os.path.join( sys.argv[1], "test" )
bad = 0
def ok( m ): print( "  PASS  %s" % m )
def no( m ):
    global bad; bad = 1; print( "  FAIL  %s" % m )

# ── the reader: heredoc bodies are DATA (a gate that writes a fixture gate keeps writing it verbatim),
#    and $( ) restarts quoting, so the scanner needs a stack rather than a quote-pair flag.
HD_START = re.compile( r'''(?<!<)<<-?(?=['"\\A-Za-z_])(?:(['"])([A-Za-z_][A-Za-z0-9_]*)\1|\\?([A-Za-z_][A-Za-z0-9_]*))''' )
AND_OK   = re.compile( r'&&\s*ok(?=\s)' )
OR_NO    = re.compile( r'\|\|\s*(?:no(?=\s)|\{\s*no(?=\s))' )
OKDEF    = re.compile( r'^\s*ok\(\)\s*\{\s*(?P<body>.*?)\s*\}\s*$' )
ACCSET   = re.compile( r'\|\|\s*\{\s*([A-Za-z_][A-Za-z0-9_]*)=' )     # the accumulator ok()'s recovery branch assigns

def spans( s ):
    """Index ranges of s that are top-level code: outside '..', "..", $( .. ) and ` .. `."""
    out = []; i = 0; n = len( s ); seg = 0; stack = []
    while i < n:
        c = s[i]; top = stack[-1] if stack else None
        if top is None:
            if c == "\\" and i + 1 < n: i += 2; continue
            if c in "'\"`" or ( c == "$" and i + 1 < n and s[i + 1] == "(" ):
                out.append( ( seg, i ) ); stack.append( ")" if c == "$" else c ); i += 2 if c == "$" else 1; continue
            i += 1; continue
        if top in "'`":
            if c == top:
                stack.pop()
                if not stack: seg = i + 1
            i += 1; continue
        if top == '"':
            if c == "\\" and i + 1 < n: i += 2; continue
            if c == "$" and i + 1 < n and s[i + 1] == "(": stack.append( ")" ); i += 2; continue
            if c == '"':
                stack.pop()
                if not stack: seg = i + 1
            i += 1; continue
        if c == "\\" and i + 1 < n: i += 2; continue
        if c in "'\"`": stack.append( c ); i += 1; continue
        if c == "$" and i + 1 < n and s[i + 1] == "(": stack.append( ")" ); i += 2; continue
        if c == "(": stack.append( "*" ); i += 1; continue
        if c == ")":
            stack.pop()
            if not stack: seg = i + 1
            i += 1; continue
        i += 1
    if stack: return None
    out.append( ( seg, n ) ); return out

def hit( line, pat, frm = 0 ):
    sp = spans( line )
    if sp is None: return None
    for a, b in sp:
        if b <= frm: continue
        m = pat.search( line, max( a, frm ), b )
        if m: return m
    return None

def code_only( ln ):
    sp = spans( ln )
    if sp is None: return ln
    for a, b in sp:
        m = re.search( r'(?:(?<=\s)|^)#', ln[a:b] )
        if m: return ln[:a + m.start()]
    return ln

def heredoc_body( raw ):
    inside = set(); hd = None
    for i, ln in enumerate( raw ):
        if hd is not None:
            inside.add( i )
            if ln.strip() == hd: hd = None
            continue
        if not ln.lstrip().startswith( "#" ):
            m = HD_START.search( code_only( ln ) )
            if m: hd = m.group( 2 ) or m.group( 3 )
    return inside

# ── G1: the contract, run rather than read ────────────────────────────────────────────────────────────
PROBE = ( '%s=0; %s; exec 3>&1; exec 1>&- 2>&-; ok "gateexit probe"; rc=$?; '
          'printf "PROBE rc=%%s acc=%%s\\n" "$rc" "$%s" >&3' )

def probe( defn, acc ):
    """Run one ok() definition with a stdout (and stderr) it cannot write to -> (rc, accumulator after)."""
    p = subprocess.run( [ "bash", "-c", PROBE % ( acc, defn, acc ) ], capture_output=True, text=True, timeout=30 )
    m = re.search( r'PROBE rc=(\S+) acc=(\S+)', p.stdout )
    return ( m.group( 1 ), m.group( 2 ) ) if m else None

defs = {}               # definition text -> [ files carrying it ]
wrongacc = []           # ( file, name ): ok() records a failure somewhere the gate never reads
for path in sorted( glob.glob( os.path.join( T, "*.sh" ) ) ):
    src = open( path, encoding="utf-8", errors="surrogateescape" ).read()
    raw = src.split( "\n" )
    inside = heredoc_body( raw )
    for i, ln in enumerate( raw ):
        if i in inside: continue
        m = OKDEF.match( ln )
        if not m or "  PASS  " not in m.group( "body" ): continue
        defs.setdefault( ln.strip(), [] ).append( os.path.basename( path ) )
        # the accumulator is whatever the recovery branch ASSIGNS -- and it has to be the one this gate
        # actually reads. legendcostcheck.sh counts into FAILED and has a `fail` FUNCTION; an ok() that
        # set `fail=1` there would record the write failure into a variable nothing ever looks at, and
        # the gate would still exit 0. Caught by exactly this check, 2026-09-11.
        a = ACCSET.search( ln )
        if not a:
            wrongacc.append( ( os.path.basename( path ), "no accumulator is set when the write fails" ) ); continue
        name = a.group( 1 )
        rest = "\n".join( raw[:i] + raw[i + 1:] )
        if re.search( r'^\s*%s\s*\(\)' % re.escape( name ), rest, re.M ):
            wrongacc.append( ( os.path.basename( path ), "%s is a FUNCTION in this gate, not its accumulator" % name ) )
        elif not re.search( r'[$]\{?%s\b' % re.escape( name ), rest ):
            wrongacc.append( ( os.path.basename( path ), "%s is never read anywhere else in this gate" % name ) )

if not defs:
    no( "(G1) no ok() definition found anywhere in test/*.sh — the sweep is inert, which is not a pass" )
else:
    broken = []
    for defn, files in sorted( defs.items() ):
        a = ACCSET.search( defn )
        acc = a.group( 1 ) if a else "fail"
        r = probe( defn, acc )
        if r is None:
            broken.append( ( files[0], "the probe produced no verdict line", defn ) ); continue
        rc, after = r
        if rc != "0":
            broken.append( ( files[0], "returns %s when its write fails, so a `&& ok … || no …` chain "
                                       "reports the ARM as failed" % rc, defn ) )
        elif after in ( "0", "" ):
            broken.append( ( files[0], "leaves %s at %r when its write fails, so a lost PASS line is "
                                       "silent and the gate still exits 0" % ( acc, after ), defn ) )
    for f, why in wrongacc[:6]:
        no( "(G1) test/%s: ok() records a failed write where the gate cannot see it — %s" % ( f, why ) )
    if len( wrongacc ) > 6:
        no( "(G1) …and %d more gates whose ok() writes to the wrong accumulator" % ( len( wrongacc ) - 6 ) )
    if broken:
        for f, why, defn in broken[:6]:
            no( "(G1) test/%s: ok() %s — %s" % ( f, why, defn.strip() ) )
        if len( broken ) > 6:
            no( "(G1) …and %d more definitions with the same defect" % ( len( broken ) - 6 ) )
    elif not wrongacc:
        ok( "(G1) CONTRACT: %d distinct ok() definitions across %d gates each exit 0 and set the "
            "accumulator THIS gate reads when the write of the PASS line fails"
            % ( len( defs ), sum( len( f ) for f in defs.values() ) ) )

# G1 MUTATION CONTROL — the probe must fail the shape the suite carried before this contract existed.
PRE = """ok(){ printf '  PASS  %s\\n' "$*"; }"""
r = probe( PRE, "fail" )
if r is None:
    no( "(G1-control) the probe produced no verdict for the pre-fix definition — the sweep above proves nothing" )
elif r[0] == "0":
    no( "(G1-control) the pre-fix definition %s PASSES the probe (rc=0) — the probe cannot see the defect "
        "it exists to catch, so G1 is inert" % PRE )
else:
    ok( "(G1-control) the pre-fix definition still fails the probe (rc=%s, accumulator untouched) — G1 "
        "discriminates" % r[0] )

# ── G2: the spelling ──────────────────────────────────────────────────────────────────────────────────
def sites( raw ):
    """(single-line sites, wrapped sites) for one gate, over LOGICAL lines with heredoc bodies excluded.

    Counting physical lines undercounts badly: the suite's usual spelling puts `&& ok …` and `|| no …`
    on two different continuation lines, so neither line carries both operators and the site is invisible
    to a per-line scan. The wrapped figure is printed, so it has to be the real one."""
    inside = heredoc_body( raw ); one = []; wrapped = 0; i = 0
    while i < len( raw ):
        if i in inside: i += 1; continue
        start = i; parts = []
        while True:
            parts.append( raw[i] )
            more = raw[i].rstrip().endswith( "\\" )
            i += 1
            if not more or i >= len( raw ) or i in inside: break
        if parts[0].lstrip().startswith( "#" ): continue
        text = "\n".join( parts )
        a = hit( text, AND_OK )
        if not a or not hit( text, OR_NO, a.end() ): continue
        if len( parts ) == 1: one.append( ( start + 1, text.strip() ) )
        else: wrapped += 1
    return one, wrapped

found = []; wrapped_total = 0
for path in sorted( glob.glob( os.path.join( T, "*.sh" ) ) ):
    one, w = sites( open( path, encoding="utf-8", errors="surrogateescape" ).read().split( "\n" ) )
    wrapped_total += w
    for lineno, text in one: found.append( ( os.path.basename( path ), lineno, text ) )

if found:
    for f, n, t in found[:6]:
        no( "(G2) test/%s:%d reports a verdict through `… && ok … || no …` on one line — a failed write "
            "of the PASS line makes it print FAIL for an arm that passed: %s" % ( f, n, t[:120] ) )
    if len( found ) > 6:
        no( "(G2) …and %d more single-line sites" % ( len( found ) - 6 ) )
else:
    ok( "(G2) SPELLING: no gate reports a verdict through a single-line `… && ok … || no …` "
        "(%d wrapped sites remain, safe through G1's contract and deliberately not pinned here)" % wrapped_total )

# G2 MUTATION CONTROL — the sweep must find a planted site, or its silence above means nothing.
PLANT = [ '#!/usr/bin/env bash', 'fail=0', "cat > /dev/null <<'EOF'",
          '[ 1 = 1 ] && ok "inside a heredoc is DATA, never a site" || no "must not be found"', 'EOF',
          '[ "$verdict" = OK ] && ok "$tag $rest" || no "$tag $rest"',
          'cmd \\', '    && ok "wrapped: counted, not flagged" \\', '    || no "wrapped: counted, not flagged"' ]
one, w = sites( PLANT )
if [ n for n, _t in one ] == [ 6 ] and w == 1:
    ok( "(G2-control) the sweep finds the planted single-line site on line 6, counts the wrapped site on "
        "lines 7-9 as wrapped, and reads the heredoc body on line 4 as data — it discriminates" )
else:
    no( "(G2-control) the sweep found single=%r wrapped=%d on the planted fixture, wanted [6] and 1 — "
        "G2's silence above proves nothing" % ( [ n for n, _t in one ], w ) )

sys.exit( bad )
PY

[ "$fail" = 0 ] && echo "ALL PASS" || echo "FAILURES ABOVE"
exit "$fail"
