#!/usr/bin/env python3
# grade_answers.py — the ANSWER grader for the E1 scenario-efficiency bank.
#
# WHAT THIS IS, AND WHY IT IS NOT analyze.py. `analyze.py` scores a PATCH: it pairs (instance, seed)
# records and bootstraps a resolved-rate delta. The E1 bank does not produce patches — it poses 28
# self-contained QUESTIONS at pinned commits and grades the ANSWER an agent gave. That is a different
# instrument, and the E1 Phase-0 pricing memo names it as the binding constraint on the whole round:
# until it exists there is nothing to run into.
#
# THE PROTOCOL IS BINDING (e1-phase0/grading-protocol.md). Three of its rules are load-bearing here
# and are enforced mechanically rather than trusted:
#   §3  Ground truth is a COMMAND, not a list. This grader EXECUTES the row's `gt_command` at the
#       pinned sha and derives the key from its stdout. A frozen list is never read.
#   §3  NON-CIRCULARITY: no `gt_command` may invoke ripwire. A key produced by the instrument under
#       test is not a key. A row that invokes it is REFUSED, never scored. Note the precision this
#       requires: nine admitted rows legitimately name `ripwire/src` as a PATH argument to grep/ls.
#       Refusal keys on ripwire in COMMAND POSITION, which is what "invokes" means.
#   §3.2 A `gt_command` that needs judgement is only half a key. Where the judgement half must be
#       human-sealed, this grader takes a key FILE and REFUSES those rows without it. It never
#       improvises the judgement half — not from the answer, not from the notes, not from a heuristic.
#
# HONESTY POSTURE (CLAUDE.md non-negotiable 3). An `accept_rule` is prose written by a labeler. This
# grader parses a CLOSED grammar of clauses (see CLAUSE_RULES) and scores exactly those. Any clause it
# does not recognise is reported in `unparsed` and DEMOTES the verdict to PARTIAL. A row is never
# reported PASS on the strength of clauses that were silently skipped. `--audit` prints that coverage
# for a whole bank without needing a single transcript, so the gap is visible before anyone funds a run.
#
# INPUTS
#   --instances FILE   the graded TSV (instances_graded.tsv schema — 13 columns, header required)
#   --results FILE     a run's results JSON from run_agentloop.py (schema ripwire-agentloop-results-v3);
#                      each record's `events_path` is the retained transcript the answer is read from
#   --transcript FILE  a single raw transcript instead of --results (needs --instance-id)
#   --pin-root DIR     a directory holding one checkout per repo, each AT ITS PINNED SHA (verified)
#   --key FILE         the human-sealed judgement keys (JSON), required by V rows and by any row whose
#                      accept_rule carries a judgement half
#
# EXIT CODES  0 every row produced a verdict · 3 at least one row was REFUSED (owner action needed:
# a seal, or a non-circular gt_command) · 2 usage/precondition error.
#
# USAGE
#   python3 bench/agentloop/grade_answers.py --instances bank.tsv --audit
#   python3 bench/agentloop/grade_answers.py --instances bank.tsv --results run.json \
#       --pin-root /tmp/e1-pins --key sealed.json
import argparse, json, pathlib, re, subprocess, sys

SCHEMA_RESULTS = "ripwire-agentloop-results-v3"
COLUMNS = ( "id", "status", "repo", "pin_ref", "scenario_class", "tier", "cap_calls", "cap_wall_s",
            "grader", "question", "gt_command", "accept_rule", "notes" )
GRADERS = ( "F", "S", "E", "V", "O", "T" )
ANSWER_OPEN, ANSWER_CLOSE = "<<<ANSWER>>>", "<<<END ANSWER>>>"
# The unpinned escape hatch exists for GATE FIXTURES ONLY: a committed fixture cannot name a sha that
# the gate generates at run time. It is gated behind --allow-unpinned and disclosed in the header, so
# a real run cannot take this path by accident.
FIXTURE_PIN = "FIXTURE"

# A path is only a path if its extension is one this corpus actually uses. Without the whitelist,
# ordinary prose ("e.g.", "i.e.") parses as a filename and every answer scores as a hallucination.
SOURCE_EXT = frozenset( ( "c h cc cpp cxx hpp hh inc m mm py pyi ts tsx js jsx java rb sh go rs swift "
                          "cs cu cuh metal md txt json yaml yml toml xml lock cmake" ).split() )
PATH_RE   = re.compile( r"(?<![\w/.\-])((?:[\w.+\-]+/)*[\w.+\-]+\.([A-Za-z][\w+]{0,5}))(?![\w/])" )
SYMBOL_RE = re.compile( r"^\s*[-*\d.)\s]*(?P<file>[\w./+\-]+\.\w{1,6})\s*:\s*(?P<sym>[A-Za-z_][\w:~]*)" )
VERDICT_RE = re.compile( r"^\s*[-*]?\s*(?P<claim>[^\s:][^:]{0,60}?)\s*:\s*"
                         r"(?P<verdict>TRUE|FALSE|DRIFTED|NOT[- ]DRIFTED)\b[^\w/]*"
                         r"(?P<cite>[\w./+\-]+\.\w{1,6}:\d+)?", re.I )
# ripwire in COMMAND POSITION — start of the command, or after a pipe/;/&&/||/backtick/$( — which is
# what protocol §3's "no gt_command invokes ripwire" actually forbids. `grep -rn X ripwire/src` names
# a directory and is fine; nine admitted rows depend on that distinction.
CIRCULAR_RE = re.compile( r"(?:^|[|;&`]|\$\(|&&|\|\|)\s*(?:[\w./\-]*/)?(ripwire|ctxpack)\b" )


# ── the bank ────────────────────────────────────────────────────────────────────────────────────────
def load_instances( path ):
    """Fail-closed TSV load: the header must be exactly the protocol's 13 columns, in order."""
    lines = pathlib.Path( path ).read_text().splitlines()
    if not lines:
        raise SystemExit( f"{path}: empty instances file" )
    header = tuple( lines[ 0 ].split( "\t" ) )
    if header != COLUMNS:
        raise SystemExit( f"{path}: unexpected header {header!r}; expected the graded-TSV schema "
                          f"{COLUMNS!r} — refusing (fail-closed, no silent column re-mapping)" )
    rows = []
    for line in lines[ 1: ]:
        if not line.strip():
            continue
        cells = line.split( "\t" )
        cells += [ "" ] * ( len( COLUMNS ) - len( cells ) )
        rows.append( dict( zip( COLUMNS, cells ) ) )
    return [ r for r in rows if r[ "status" ].strip().upper() == "GRADED" ]

def needs_seal( row ):
    """True when the row's accept_rule has a judgement half a command cannot supply (protocol §3.2).

    Deliberately CONSERVATIVE. A false positive costs the owner one sealed-key entry; a false negative
    would have the grader inventing the judgement half, which the protocol forbids outright. Every V
    row needs a seal by definition; the phrase list covers the E rows whose second half is a
    classification (I26's per-site operation classes, I19's switch/non-switch split, I18's indirect pins)."""
    if row[ "grader" ].strip().upper() == "V":
        return True
    text = row[ "accept_rule" ].lower()
    return any( phrase in text for phrase in
                ( "sealed", "scored separately", "split must be correct", "classification" ) )

def is_circular( gt_command ):
    return bool( CIRCULAR_RE.search( gt_command ) )


# ── the key: a COMMAND run at the pin (protocol §3) ─────────────────────────────────────────────────
def pin_pairs( row ):
    """[(repo_dir, sha)] for the row. `ctxpack@b5ac9f2 + ripwire@49f4d75` is the multi-root form."""
    pin = row[ "pin_ref" ].strip()
    if "@" not in pin:
        return [ ( row[ "repo" ].strip(), pin ) ]
    out = []
    for part in pin.split( "+" ):
        repo, _, sha = part.strip().partition( "@" )
        out.append( ( repo.strip(), sha.strip() ) )
    return out

def verify_pin( row, pin_root, allow_unpinned ):
    """None when the tree under pin_root is at the row's pinned sha; an error string otherwise."""
    if row[ "pin_ref" ].strip() == FIXTURE_PIN:
        return None if allow_unpinned else "pin_ref=FIXTURE requires --allow-unpinned (fixtures only)"
    for repo, sha in pin_pairs( row ):
        tree = pathlib.Path( pin_root ) / repo
        if not tree.is_dir():
            return f"no checkout at {tree}"
        head = subprocess.run( [ "git", "-C", str( tree ), "rev-parse", "HEAD" ],
                               capture_output=True, text=True )
        if head.returncode != 0:
            return f"{tree} is not a git checkout"
        if not head.stdout.strip().startswith( sha ):
            return f"{tree} is at {head.stdout.strip()[ :12 ]}, not the pinned {sha}"
    return None

_SHELL = []

def globstar_shell():
    """The first bash on this machine that actually supports `**`, or None.

    NOT a detail. Protocol §4 records two derivations that returned a false ZERO purely from glob
    expansion, and macOS still ships bash 3.2 as /bin/bash — which has no globstar, so
    `repo/**/x.{h,cpp}` silently matches nothing and the key comes back empty. An empty key that
    looks like a legitimate 'no results' is the worst failure this grader can have, so the shell is
    probed once and a row that NEEDS `**` is REFUSED when no capable shell exists, never guessed at."""
    if not _SHELL:
        _SHELL.append( None )
        for candidate in ( "bash", "/opt/homebrew/bin/bash", "/usr/local/bin/bash", "/bin/bash" ):
            try:
                probe = subprocess.run( [ candidate, "-O", "globstar", "-c", "true" ],
                                        capture_output=True, text=True, timeout=30 )
            except ( OSError, subprocess.SubprocessError ):
                continue
            if probe.returncode == 0:
                _SHELL[ 0 ] = candidate
                break
    return _SHELL[ 0 ]

def run_gt( gt_command, pin_root, timeout_s=300 ):
    """Execute the derivation command at the pin, under bash (never the operator's zsh — §4)."""
    shell = globstar_shell()
    argv = ( [ shell, "-O", "globstar", "-O", "nullglob", "-c", gt_command ] if shell
             else [ "bash", "-c", gt_command ] )
    proc = subprocess.run( argv, capture_output=True, text=True, cwd=str( pin_root ), timeout=timeout_s )
    return proc.stdout, proc.stderr, proc.returncode

def derive_key( stdout ):
    """Turn a derivation command's stdout into the key: an ORDERED path list (ls / grep -rl / grep -rn),
    file:line citations (grep -n), and a bare count (grep -c / wc -l). Order is preserved because the
    O grader scores it."""
    paths, cites, seen = [], [], set()
    for line in stdout.splitlines():
        line = line.strip()
        if not line:
            continue
        head = line.split( ":", 2 )
        if len( head ) >= 2 and head[ 1 ].isdigit() and looks_like_path( head[ 0 ] ):
            cites.append( ( head[ 0 ], int( head[ 1 ] ) ) )
            candidate = head[ 0 ]
        else:
            candidate = line
        for m in PATH_RE.finditer( candidate ):
            p = m.group( 1 )
            if m.group( 2 ).lower() in SOURCE_EXT and p not in seen:
                seen.add( p ); paths.append( p )
    digits = [ ln.strip() for ln in stdout.splitlines() if ln.strip().isdigit() ]
    count = int( digits[ -1 ] ) if digits and not paths else None
    return dict( paths=paths, citations=cites, count=count )

def looks_like_path( text ):
    m = PATH_RE.fullmatch( text.strip() )
    return bool( m and m.group( 2 ).lower() in SOURCE_EXT )


# ── the answer: transcript -> text -> fenced block -> items ─────────────────────────────────────────
def transcript_answer_text( blob ):
    """Final agent message from any of the three harnesses' retained transcripts.

    `claude -p --output-format json` is one object with a `result` string; codex emits JSONL with
    item.completed/agent_message; opencode emits NDJSON text parts. Sniffed, not configured — a
    misconfigured parser would silently read the wrong turn."""
    blob = blob.decode( "utf-8", "replace" ) if isinstance( blob, bytes ) else ( blob or "" )
    try:
        payload = json.loads( blob )
        if isinstance( payload, dict ) and isinstance( payload.get( "result" ), str ):
            return payload[ "result" ]
    except ValueError:
        pass
    text = ""
    for line in blob.splitlines():
        try:
            event = json.loads( line )
        except ValueError:
            continue
        item = event.get( "item" ) or {}
        if event.get( "type" ) == "item.completed" and item.get( "type" ) == "agent_message":
            text = item.get( "text" ) or text
        part = event.get( "part" ) or {}
        if event.get( "type" ) == "text" and isinstance( part.get( "text" ), str ):
            text = part[ "text" ]
    return text

def fenced_answer( text ):
    """The terminal answer between the sentinels the question prompt mandates, or None.

    ONE contract, no fallback. Scraping a whole transcript for path-shaped tokens would score the
    agent's exploration rather than its answer, and would make groundedness meaningless."""
    start = text.find( ANSWER_OPEN )
    if start < 0:
        return None
    rest = text[ start + len( ANSWER_OPEN ): ]
    end = rest.find( ANSWER_CLOSE )
    return ( rest if end < 0 else rest[ :end ] ).strip()

def answer_paths( answer ):
    out, seen = [], set()
    for m in PATH_RE.finditer( answer ):
        p = m.group( 1 )
        if m.group( 2 ).lower() in SOURCE_EXT and p not in seen:
            seen.add( p ); out.append( p )
    return out

def answer_symbols( answer ):
    return [ ( m.group( "file" ), m.group( "sym" ) ) for m in
             ( SYMBOL_RE.match( line ) for line in answer.splitlines() ) if m ]

def answer_verdicts( answer ):
    out = []
    for line in answer.splitlines():
        m = VERDICT_RE.match( line )
        if m:
            out.append( ( m.group( "claim" ).strip(), m.group( "verdict" ).upper().replace( " ", "-" ),
                          m.group( "cite" ) ) )
    return out


# ── scoring primitives ──────────────────────────────────────────────────────────────────────────────
def basename_set( paths ):
    """Compare on basenames. The bank's keys are repo-relative (`ctxpack/src/x.h`) while an agent
    answering inside its checkout says `src/x.h`; scoring the prefix would fail every correct answer."""
    return { p.rsplit( "/", 1 )[ -1 ] for p in paths }

def recall_precision( answer_items, key_items ):
    a, k = basename_set( answer_items ), basename_set( key_items )
    if not k:
        return None, None
    hit = len( a & k )
    return hit / len( k ), ( hit / len( a ) if a else 0.0 )

def kendall_tau( answer_order, key_order ):
    """Tau over the items present in BOTH sequences; None when fewer than two are comparable."""
    a = [ p.rsplit( "/", 1 )[ -1 ] for p in answer_order ]
    k = [ p.rsplit( "/", 1 )[ -1 ] for p in key_order ]
    common = [ x for x in a if x in k ]
    if len( common ) < 2:
        return None
    rank = { name: i for i, name in enumerate( k ) }
    conc = disc = 0
    for i in range( len( common ) ):
        for j in range( i + 1, len( common ) ):
            if rank[ common[ i ] ] < rank[ common[ j ] ]: conc += 1
            else:                                        disc += 1
    return ( conc - disc ) / ( conc + disc ) if conc + disc else None

def at_pin( pin_root, row, rel_path ):
    """The real file for an answer's path, or None. Tried repo-relative AND under each pinned repo
    dir, because the key is written `repo/src/x.h` while an agent answering from inside its checkout
    says `src/x.h`; resolving only one of the two would score every correct answer as a fabrication."""
    for root in [ pathlib.Path( pin_root ) ] + [ pathlib.Path( pin_root ) / r for r, _ in pin_pairs( row ) ]:
        target = root / rel_path
        if target.exists():
            return target
    return None

def grounded( paths, pin_root, row ):
    """Protocol §10.10: any named path that does not exist at the pin is a hallucination, on EVERY grader."""
    return [ p for p in paths if at_pin( pin_root, row, p ) is None ]

def symbol_in_file( pin_root, row, file_path, symbol ):
    """Literal presence of the symbol in the named file at the pin.

    A DISCLOSED FLOOR, not a definition check: proving `defined in` needs a parser, and the only
    parser here is the instrument under test (protocol §3, non-circularity). Presence is strictly
    weaker, so it can only be generous to the agent — never falsely harsh."""
    target = at_pin( pin_root, row, file_path )
    try:
        return bool( target and target.is_file() and symbol in target.read_text( errors="replace" ) )
    except OSError:
        return False


# ── the accept rule: a CLOSED clause grammar (unrecognised clauses demote to PARTIAL) ───────────────
CLAUSE_RULES = (
    ( "recall",     re.compile( r"\brecall\b[^;.]{0,24}?(>=|=)\s*([\d.]+)", re.I ) ),
    ( "precision",  re.compile( r"\bprecision\b[^;.]{0,24}?(>=|=)\s*([\d.]+)", re.I ) ),
    ( "tau",        re.compile( r"tau\s*(=|>=)\s*([\d.]+)", re.I ) ),
    ( "core_of",    re.compile( r">=\s*(\d+)\s*of\s*(?:the\s*)?(?:\{([^}]*)\}|(\d+))", re.I ) ),
    ( "all_n",      re.compile( r"\ball\s+(\d+)\s+\w+\s+located", re.I ) ),
    ( "exact",      re.compile( r"\b(?:set )?exact(?:ly)?\b|precision AND recall\s*=\s*1", re.I ) ),
    ( "grounded",   re.compile( r"0 (?:non-existent|fabricated) paths|no fabricated filenames", re.I ) ),
    ( "sealed",     re.compile( r"sealed key|human-sealed", re.I ) ),
    ( "citation",   re.compile( r"\bcitations?\b[^;]{0,30}resolv", re.I ) ),
    ( "symbol_ok",  re.compile( r"named file must (?:actually )?contain", re.I ) ),
    ( "verbatim",   re.compile( r"\bverbatim\b", re.I ) ),
)

# A clause that is nothing but literal names ("answer names src/graphlegend.h", "BridgeRecipe") IS
# mechanically checkable: the named token must appear in the answer. The residue test is what keeps
# that honest — "the constant named must be kParserVer with both values stated" leaves "with both
# values stated" behind, so it stays UNPARSED rather than being scored as if the whole clause were met.
CLAUSE_STOPWORDS = frozenset( ( "answer answers names named name the a an of in on at file files list "
                                "plus and both must be is are it its" ).split() )
LITERAL_RE = re.compile( r"\b([A-Za-z_][\w./+\-]*\.[A-Za-z][\w+]{0,5}|[A-Za-z_]*[a-z][A-Z]\w*|k[A-Z]\w+)\b" )

def clause_literals( chunk ):
    """(literal tokens, leftover words). Brace groups and parentheticals are labeler annotation."""
    text = re.sub( r"\{[^}]*\}", " ", re.sub( r"\([^)]*\)", " ", chunk ) )
    tokens = [ m.group( 1 ) for m in LITERAL_RE.finditer( text ) ]
    residue = [ w for w in re.sub( LITERAL_RE, " ", text ).replace( "+", " " ).split()
                if w.strip( ".,:;" ).lower() not in CLAUSE_STOPWORDS and w.strip( ".,:;" ) ]
    return tokens, residue

def parse_clauses( accept_rule ):
    """(parsed, unparsed). Split on the four separators the bank actually uses: ';', ' AND ', ' and ',
    ' + '. Splitting finely matters: "names namesplit.h + naminglens.h + the splitting function" holds
    two checkable requirements and one that is not, and a coarse split would hide the third."""
    parsed, unparsed = [], []
    for chunk in re.split( r";|\s+AND\s+|\s+and\s+|\s+\+\s+", accept_rule ):
        chunk = chunk.strip()
        if not chunk:
            continue
        hit = next( ( ( name, rx.search( chunk ) ) for name, rx in CLAUSE_RULES if rx.search( chunk ) ), None )
        if hit:
            parsed.append( ( hit[ 0 ], hit[ 1 ], chunk ) ); continue
        tokens, residue = clause_literals( chunk )
        ( parsed.append( ( "literal", tokens, chunk ) ) if tokens and not residue
          else unparsed.append( chunk ) )
    return parsed, unparsed

def apply_clauses( parsed, scores ):
    """Mechanically decide each parsed clause against the measured scores. Returns (ok, [failures])."""
    failures = []
    for name, m, chunk in parsed:
        if name in ( "recall", "precision", "tau" ):
            got, want = scores.get( name ), float( m.group( 2 ) )
            if got is None or got + 1e-9 < want:
                failures.append( f"{name}={fmt(got)} < {want}" )
        elif name == "exact":
            for field in ( "recall", "precision" ):
                if scores.get( field ) is None or scores[ field ] < 1.0 - 1e-9:
                    failures.append( f"{field}={fmt(scores.get(field))} != 1.0 (exact)" )
        elif name in ( "core_of", "all_n" ):
            want = int( m.group( 1 ) )
            got = scores.get( "hits" )
            if got is None or got < want:
                failures.append( f"named {got} of the required {want}" )
        elif name == "grounded":
            if scores.get( "hallucinated" ):
                failures.append( f"{scores['hallucinated']} fabricated path(s)" )
        elif name == "sealed":
            if not scores.get( "sealed_ok" ):
                failures.append( "sealed-key comparison failed" )
        elif name == "citation":
            if scores.get( "hallucinated" ):
                failures.append( f"{scores['hallucinated']} citation(s) do not resolve at the pin" )
        elif name == "symbol_ok":
            if scores.get( "symbol_ok" ) is not True:
                failures.append( "a named symbol is not present in the file the answer named" )
        elif name == "verbatim":
            if scores.get( "verbatim_ok" ) is not True:
                failures.append( "no quoted span in the answer appears verbatim in a named file" )
        elif name == "literal":
            missing = [ t for t in m if t not in scores.get( "answer_text", "" ) ]
            if missing:
                failures.append( f"answer never names {', '.join( missing[ :3 ] )}" )
    return ( not failures ), failures

def fmt( x ):
    return "n/a" if x is None else ( f"{x:.2f}" if isinstance( x, float ) else str( x ) )


# ── one instance ────────────────────────────────────────────────────────────────────────────────────
def grade_instance( row, answer, pin_root, keys, allow_unpinned ):
    """Verdict + measured scores for ONE instance. Never raises on a bad answer; refuses on a bad ROW."""
    out = dict( id=row[ "id" ], grader=row[ "grader" ].strip().upper(), tier=row[ "tier" ],
                scenario_class=row[ "scenario_class" ], recall=None, precision=None, tau=None,
                hits=None, hallucinated=0, unparsed=[], detail="" )

    if is_circular( row[ "gt_command" ] ):
        return dict( out, verdict="REFUSED_CIRCULAR",
                     detail="gt_command invokes the instrument under test (protocol §3)" )
    if out[ "grader" ] not in GRADERS:
        return dict( out, verdict="REFUSED_SCHEMA", detail=f"unknown grader type {out['grader']!r}" )
    if out[ "grader" ] == "T":
        return dict( out, verdict="UNSUPPORTED",
                     detail="T (edit) instances need a test run + --quality-delta + --edit-check, all "
                            "of which are the instrument under test; no admitted row uses T (protocol §2)" )
    if needs_seal( row ) and row[ "id" ] not in ( keys or {} ):
        return dict( out, verdict="REFUSED_NO_KEY",
                     detail="judgement half must be human-sealed before any run (protocol §3.2); "
                            "pass --key with an entry for this instance" )
    if "**" in row[ "gt_command" ] and globstar_shell() is None:
        return dict( out, verdict="REFUSED_SHELL",
                     detail="gt_command needs `**` but no bash on this machine supports globstar "
                            "(macOS ships 3.2); without it the derivation returns a false zero "
                            "(protocol §4) — install bash 4+ rather than scoring this row" )
    pin_error = verify_pin( row, pin_root, allow_unpinned )
    if pin_error:
        return dict( out, verdict="REFUSED_PIN", detail=pin_error )

    gt_out, gt_err, gt_rc = run_gt( row[ "gt_command" ], pin_root )
    key = derive_key( gt_out )
    if not key[ "paths" ] and key[ "count" ] is None:
        return dict( out, verdict="GT_EMPTY",
                     detail=f"gt_command yielded nothing at the pin (rc={gt_rc}); the instance is not "
                            f"gradeable — retire it, do not re-word the question (protocol §3.1). "
                            f"{( gt_err.strip().splitlines() or [ '' ] )[ 0 ][ :120 ]}" )
    out[ "key_n" ] = len( key[ "paths" ] ) or key[ "count" ]

    if answer is None:
        return dict( out, verdict="NO_ANSWER",
                     detail=f"no {ANSWER_OPEN} block in the transcript's final message" )

    scores = grade_by_type( out[ "grader" ], row, answer, key, pin_root, keys )
    out.update( { k: v for k, v in scores.items() if k in out or k in ( "key_n", ) } )
    parsed, unparsed = parse_clauses( row[ "accept_rule" ] )
    out[ "unparsed" ] = unparsed
    ok, failures = apply_clauses( parsed, scores )

    if scores.get( "hallucinated" ):
        return dict( out, verdict="HALLUCINATED",
                     detail=f"named {scores['hallucinated']} path(s) absent at the pin: "
                            f"{', '.join( scores.get( 'fabricated', [] )[ :3 ] )}" )
    if not ok:
        return dict( out, verdict="FAIL", detail="; ".join( failures ) )
    if unparsed:
        return dict( out, verdict="PARTIAL",
                     detail=f"{len(parsed)} clause(s) scored, {len(unparsed)} not mechanically "
                            f"checkable: {unparsed[ 0 ][ :90 ]}" )
    return dict( out, verdict="PASS", detail=f"{len(parsed)} clause(s) scored" )

def grade_by_type( grader, row, answer, key, pin_root, keys ):
    """Per-grader extraction + measurement. Protocol §2 defines the six types."""
    scores = dict( recall=None, precision=None, tau=None, hits=None, hallucinated=0, fabricated=[],
                   sealed_ok=None, symbol_ok=None, verbatim_ok=None, answer_text=answer )
    if grader == "V":
        sealed = ( keys or {} ).get( row[ "id" ], {} )
        want = { str( k ).strip().upper(): str( v ).strip().upper() for k, v in
                 ( sealed.get( "verdicts" ) or {} ).items() }
        got = answer_verdicts( answer )
        matched = sum( 1 for claim, verdict, _cite in got if want.get( claim.upper() ) == verdict )
        bad_cite = [ c for _cl, _v, c in got
                     if c and at_pin( pin_root, row, c.rsplit( ":", 1 )[ 0 ] ) is None ]
        missing_cite = [ cl for cl, _v, c in got if not c ]
        scores.update( sealed_ok=bool( want ) and matched == len( want ) and not bad_cite and not missing_cite,
                       hallucinated=len( bad_cite ), fabricated=bad_cite,
                       recall=( matched / len( want ) if want else None ), hits=matched )
        return scores

    paths = answer_paths( answer )
    fabricated = grounded( paths, pin_root, row )
    scores.update( hallucinated=len( fabricated ), fabricated=fabricated )
    recall, precision = recall_precision( paths, key[ "paths" ] )
    scores.update( recall=recall, precision=precision,
                   hits=len( basename_set( paths ) & basename_set( key[ "paths" ] ) ) )
    if grader == "S":
        pairs = answer_symbols( answer )
        good = [ ( f, s ) for f, s in pairs if symbol_in_file( pin_root, row, f, s ) ]
        # A right symbol in a wrong file scores zero for that item (protocol §2 S).
        scores.update( hits=len( good ), symbol_ok=bool( pairs ) and len( good ) == len( pairs ),
                       precision=( len( good ) / len( pairs ) ) if pairs else 0.0 )
    if grader == "O":
        scores[ "tau" ] = kendall_tau( paths, key[ "paths" ] )
    scores[ "verbatim_ok" ] = verbatim_ok( answer, paths, pin_root, row )
    return scores

QUOTED_RE = re.compile( r"`([^`\n]{8,})`|\"([^\"\n]{8,})\"|'([^'\n]{8,})'" )

def verbatim_ok( answer, paths, pin_root, row ):
    """True when a quoted span in the answer really appears in one of the files the answer named.

    None (not False) when the answer quoted nothing: an unmeasured claim must not read as a failed
    one. Every quoted span is tried against every named file, so an answer that quotes the right line
    but attributes it loosely still passes — the accept rules that use this ask for the LINE, not the
    attribution, and the attribution is what the S/F recall clauses already score."""
    spans = [ next( g for g in m.groups() if g ) for m in QUOTED_RE.finditer( answer ) ]
    if not spans:
        return None
    for path in paths:
        target = at_pin( pin_root, row, path )
        if target and target.is_file():
            try:
                body = target.read_text( errors="replace" )
            except OSError:
                continue
            if any( span.strip() in body for span in spans ):
                return True
    return False


# ── report ──────────────────────────────────────────────────────────────────────────────────────────
COST_FIELDS = ( "tokens_in", "tokens_out", "command_calls", "wall_seconds" )

def cap_hit( row, record ):
    """Protocol §8: a run that hits a cap is CENSORED, not failed — a flag beside the verdict."""
    calls, wall = ( record or {} ).get( "command_calls" ), ( record or {} ).get( "wall_seconds" )
    cap_c = int( row[ "cap_calls" ] ) if row[ "cap_calls" ].strip().isdigit() else None
    cap_w = int( row[ "cap_wall_s" ] ) if row[ "cap_wall_s" ].strip().isdigit() else None
    return int( bool( ( calls is not None and cap_c and calls >= cap_c )
                      or ( wall is not None and cap_w and wall >= cap_w ) ) )

def print_table( graded, header_notes ):
    for note in header_notes:
        print( f"# {note}" )
    cols = ( "id", "class", "tier", "g", "arm", "verdict", "recall", "prec", "tau", "halluc",
             "cap", "tok_in", "tok_out", "calls", "wall_s" )
    print( "\t".join( cols ) )
    for g in graded:
        rec = g.get( "record" ) or {}
        print( "\t".join( str( x ) for x in (
            g[ "id" ], g[ "scenario_class" ].split()[ 0 ], g[ "tier" ], g[ "grader" ],
            g.get( "arm", "-" ), g[ "verdict" ], fmt( g[ "recall" ] ), fmt( g[ "precision" ] ),
            fmt( g[ "tau" ] ), g[ "hallucinated" ], g.get( "cap_hit", 0 ),
            fmt( rec.get( "tokens_in" ) ), fmt( rec.get( "tokens_out" ) ),
            fmt( rec.get( "command_calls" ) ), fmt( rec.get( "wall_seconds" ) ) ) ) )
    tally = {}
    for g in graded:
        tally[ g[ "verdict" ] ] = tally.get( g[ "verdict" ], 0 ) + 1
    print( "# aggregate: " + " ".join( f"{k}={v}" for k, v in sorted( tally.items() ) ) )
    for g in graded:
        if g[ "detail" ]:
            print( f"#   {g['id']}: {g['detail']}" )
    return tally


# ── modes ───────────────────────────────────────────────────────────────────────────────────────────
def audit( rows ):
    """Bank readiness WITHOUT a transcript or a pin: circularity, seals owed, clause coverage."""
    print( "id\tgrader\ttier\tcircular\tseal_required\tclauses_parsed\tclauses_unparsed" )
    circular = seals = fully = 0
    for row in rows:
        parsed, unparsed = parse_clauses( row[ "accept_rule" ] )
        circ, seal = is_circular( row[ "gt_command" ] ), needs_seal( row )
        circular += circ; seals += seal; fully += ( not unparsed )
        print( f"{row['id']}\t{row['grader']}\t{row['tier']}\t{int(circ)}\t{int(seal)}\t"
               f"{len(parsed)}\t{len(unparsed)}" )
    print( f"# {len(rows)} graded rows: {circular} circular (REFUSED), {seals} need a human-sealed key, "
           f"{fully} fully clause-parsed, {len(rows)-fully} carry at least one clause that is not "
           f"mechanically checkable (those rows can only reach PARTIAL)" )
    return 0

def answers_from_results( results_path ):
    """[(instance_id, arm, seed, answer|None, record)] from a run_agentloop.py results JSON."""
    data = json.loads( pathlib.Path( results_path ).read_text() )
    if data.get( "schema" ) != SCHEMA_RESULTS:
        raise SystemExit( f"{results_path}: schema {data.get('schema')!r} != {SCHEMA_RESULTS!r}; refusing" )
    out = []
    for rec in data.get( "records", [] ):
        blob = ""
        # A relative events_path resolves against the RESULTS FILE's own directory, not the caller's
        # cwd: a results bundle copied off the run machine keeps working, and a fixture is portable.
        events = rec.get( "events_path" )
        if events:
            path = pathlib.Path( events )
            if not path.is_absolute():
                path = pathlib.Path( results_path ).resolve().parent / path
            if path.exists():
                blob = path.read_text( errors="replace" )
        out.append( ( rec[ "instance_id" ], rec.get( "arm", "-" ), rec.get( "seed" ),
                      fenced_answer( transcript_answer_text( blob ) ), rec ) )
    return out

def main():
    ap = argparse.ArgumentParser( description="E1 answer grader (protocol-bound; never invokes ripwire)" )
    ap.add_argument( "--instances", required=True, help="graded TSV (instances_graded.tsv schema)" )
    ap.add_argument( "--results", default="", help="run_agentloop.py results JSON" )
    ap.add_argument( "--transcript", default="", help="one raw transcript instead of --results" )
    ap.add_argument( "--instance-id", default="", help="which instance --transcript answers" )
    ap.add_argument( "--pin-root", default="", help="dir holding one checkout per repo, at the pinned sha" )
    ap.add_argument( "--key", default="", help="human-sealed judgement keys (JSON, keyed by instance id)" )
    ap.add_argument( "--allow-unpinned", action="store_true",
                     help="permit pin_ref=FIXTURE rows — gate fixtures only; disclosed in the header" )
    ap.add_argument( "--audit", action="store_true",
                     help="report bank readiness (circularity / seals owed / clause coverage) and exit" )
    a = ap.parse_args()

    rows = { r[ "id" ]: r for r in load_instances( a.instances ) }
    if a.audit:
        return audit( list( rows.values() ) )
    if not a.pin_root:
        raise SystemExit( "--pin-root is required to grade: the key is DERIVED at the pin, never frozen" )
    keys = json.loads( pathlib.Path( a.key ).read_text() ) if a.key else {}

    if a.transcript:
        if not a.instance_id:
            raise SystemExit( "--transcript needs --instance-id" )
        blob = pathlib.Path( a.transcript ).read_text( errors="replace" )
        work = [ ( a.instance_id, "-", None, fenced_answer( transcript_answer_text( blob ) ), None ) ]
    elif a.results:
        work = answers_from_results( a.results )
    else:
        raise SystemExit( "one of --results or --transcript is required (or --audit)" )

    graded, unknown = [], []
    for instance_id, arm, seed, answer, record in work:
        row = rows.get( instance_id )
        if row is None:
            unknown.append( instance_id ); continue
        g = grade_instance( row, answer, a.pin_root, keys, a.allow_unpinned )
        g.update( arm=arm, seed=seed, record=record, cap_hit=cap_hit( row, record ) )
        graded.append( g )

    notes = [ f"instances={a.instances} n_graded={len(graded)} keys={len(keys)}",
              f"pin_root={a.pin_root}" + ( "  UNPINNED FIXTURE MODE" if a.allow_unpinned else "" ),
              f"derivation shell={globstar_shell() or 'bash (NO globstar — `**` rows are REFUSED)'}",
              "verdicts: PASS/FAIL scored · PARTIAL = a clause was not mechanically checkable · "
              "REFUSED_* = owner action needed · cap=1 is CENSORED, not failed (protocol §8)" ]
    if unknown:
        notes.append( f"WARNING {len(unknown)} record(s) name no bank row: {sorted(set(unknown))[:4]}" )
    tally = print_table( graded, notes )
    return 3 if any( k.startswith( "REFUSED" ) for k in tally ) else 0

if __name__ == "__main__":
    sys.exit( main() )
