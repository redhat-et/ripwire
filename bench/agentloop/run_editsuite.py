#!/usr/bin/env python3
"""run_editsuite.py — the EDIT-PATH terminality suite (terminality round A, 2026-09-05, lane E).

The question: after a ripwire edit verb returns its receipt, does the agent still Read the target file or
re-run a contract check? On Claude Code that question is confounded by the harness's Read-before-edit
policy, so the PRIMARY measurement runs on the agentloop runners that carry no such policy (codex exec,
opencode run). The band is pre-registered in docs/EVALS.md ("Terminality round A", lane E): the ripwire arm
must reach >= 80% of post-edit windows with ZERO reads of the target AND ZERO redundant checks, with task
pass not below the native arm.

Twelve tasks over editsuite/fixture (6 replace-body, 3 insert, 3 multi-edit plans), each with a
deterministic oracle (editsuite/expected + editsuite/oracle.sh: byte-equality). Two arms per task:
  ripwire_edit  — the agent is told to make the edit with the ripwire CLI edit verbs
                  (--replace-symbol-body / --insert-*-symbol / --edit-plan), and that the receipt already
                  carries the post-check and tests_to_run
  native_edit   — the agent uses the runner's own edit tool / apply_patch / sed
Arm ORDER alternates per task (task 1 ripwire first, task 2 native first, ...), the two arms of one task
run back to back in one worker so the order is real under --concurrency.

Everything about runner ISOLATION is reused from run_agentloop.py — prepare_environment() (ephemeral
HOME/XDG dirs, the logging ripwire shim first on PATH), build_harness_command(), sh() — so the suite cannot
drift from the harness it measures alongside. This file adds only what the edit question needs: the
fixture checkout, the two prompts, the ordered tool-call walk, the post-edit window classification, the
oracle, and the meter-row emission.

Recorded per run: every tool call after the edit call in order (classified), transcript bytes and tokens,
whether a Read/cat/sed of the TARGET followed the edit, whether an --edit-check on the same symbol
followed, the oracle verdict. Rows for bench/substitution_report.py's EDIT table are appended to
--meter-out as JSONL in the meter row shape (v, ts, seq, session, repo, tag, tool, class, family, agent,
surface, target, detail). Lane T's EDIT table reader was not visible when this was written; the fields are
the ones the round's prompt named, and the classes follow docs/EVALS.md's T2 definition (policy-read /
sweep / redundant-check / native-edit).

Usage (opencode, free hosted model, no credentials needed — this suite measures tool-call behaviour, not
answer quality; run_agentloop's model-substitution guard still records the model actually used):
    python3 bench/agentloop/run_editsuite.py --harness opencode --model opencode/big-pickle \
        --ripwire-bin ./build/ripwire --work-dir /tmp/editsuite --live --concurrency 2 \
        --results-out /tmp/editsuite/results.json --meter-out /tmp/editsuite/meter.jsonl
    python3 bench/agentloop/run_editsuite.py --summarize /tmp/editsuite/results.json
"""
import argparse, concurrent.futures, datetime, json, os, pathlib, re, shlex, shutil, subprocess, sys, threading, time

HERE = pathlib.Path( __file__ ).resolve().parent
sys.path.insert( 0, str( HERE ) )
import run_agentloop as R   # the runner isolation + command builders live there, and only there

SUITE    = HERE / "editsuite"
FIXTURE  = SUITE / "fixture"
TASKS    = SUITE / "tasks.json"
ORACLE   = SUITE / "oracle.sh"
ARMS     = ( "ripwire_edit", "native_edit" )
HARNESSES = ( "opencode", "codex-exec" )   # the runners WITHOUT a Read-before-edit policy
SCHEMA   = "ripwire.editsuite/v1"
METER_V  = 3
TERMINALITY_WINDOW = 5                       # docs/SUBSTITUTION_METER.md: the same 5-call window the FIND band uses
DEFAULT_TIMEOUT_S = 600

# ── tasks ─────────────────────────────────────────────────────────────────────────────────────────────
def load_tasks( path=TASKS ):
    return json.loads( pathlib.Path( path ).read_text() )["tasks"]

def task_ops( task ):
    return task["ops"] if task["kind"] == "plan" else [ dict( task, op=task["kind"] ) ]

def task_files( task ):
    """The target files, in first-touch order, deduplicated."""
    out = []
    for op in task_ops( task ):
        if op["file"] not in out:
            out.append( op["file"] )
    return out

def task_symbols( task ):
    return sorted( { op["symbol"] for op in task_ops( task ) } )

def arm_order( task_index ):
    """Alternating: even task index -> ripwire first, odd -> native first."""
    return ARMS if task_index % 2 == 0 else tuple( reversed( ARMS ) )

def matrix( tasks, arms=ARMS ):
    """[(task, arm)] in RUN order — each task's arms adjacent, order alternating per task."""
    cells = []
    for i, task in enumerate( tasks ):
        for arm in arm_order( i ):
            if arm in arms:
                cells.append( ( task, arm ) )
    return cells

# ── the prompts ───────────────────────────────────────────────────────────────────────────────────────
def separator_words( rel ):
    return "two blank lines" if rel.endswith( ".py" ) else "one blank line"

def describe_op( op ):
    kind = op.get( "op", op.get( "kind" ) )
    if kind == "replace":
        return ( "Replace the ENTIRE definition of `%s` in `%s` (signature through closing brace / last body line) with exactly:\n"
                 "<<<NEW\n%s\nNEW>>>" % ( op["symbol"], op["file"], op["new_text"] ) )
    where = "immediately BEFORE" if kind == "insert_before" else "immediately AFTER"
    return ( "Insert the following new definition into `%s` %s the definition of `%s`, separated from it by %s "
             "(the file's convention), leaving every other byte of the file unchanged:\n<<<NEW\n%s\nNEW>>>"
             % ( op["file"], where, op["symbol"], separator_words( op["file"] ), op["new_text"] ) )

def task_prompt( task ):
    ops = task_ops( task )
    head = ( "You are editing a small repository in the current directory. Make the following %d edit%s EXACTLY as "
             "specified — the text between <<<NEW and NEW>>> must land byte-for-byte (same indentation, same blank "
             "lines around it). Do not change anything else. Do not run the tests.\n\n"
             % ( len( ops ), "" if len( ops ) == 1 else "s" ) )
    body = "\n\n".join( "EDIT %d: %s" % ( i + 1, describe_op( op ) ) for i, op in enumerate( ops ) )
    return head + body

def arm_instructions( arm, task, shim, rules_blurb="" ):
    if arm == "native_edit":
        return ( "\n\nTOOLS: use your own file-editing tool (edit / write / apply_patch / sed). Do not use ripwire or "
                 "ctxpack. Stop as soon as you are confident the edit is in place." )
    ops = task_ops( task )
    if task["kind"] == "plan":
        edits = ",\n    ".join( json.dumps( { "op": { "replace": "replace_symbol_body", "insert_before": "insert_before_symbol",
                                                   "insert_after": "insert_after_symbol" }[ op["op"] ],
                                            "target": op["symbol"], "file": op["file"], "payload": "%d.txt" % ( i + 1 ) } )
                                for i, op in enumerate( ops ) )
        how = ( "Write each payload to a file beside a plan file (e.g. under a scratch directory OUTSIDE this repository: "
                "payload files are confined to the plan's own directory), then apply every edit in ONE transaction:\n"
                "    %s . --edit-plan=/path/to/plan.json --apply\n"
                "where plan.json is:\n    {\"version\":1,\"edits\":[\n    %s\n    ]}\n"
                "(--dry-run previews the same plan without writing.)" % ( shim, edits ) )
    else:
        flag = { "replace": "--replace-symbol-body", "insert_before": "--insert-before-symbol",
                 "insert_after": "--insert-after-symbol" }[ task["kind"] ]
        op = ops[0]
        how = ( "    %s . %s=%s --edit-target-file=%s --edit-payload=PAYLOAD_FILE\n"
                "(or --edit-payload=- to read the payload from stdin). The payload is the exact bytes to %s."
                % ( shim, flag, op["symbol"], op["file"],
                    "write over the old definition" if task["kind"] == "replace" else "insert" ) )
    return ( "\n\nTOOLS: make the edit with the ripwire CLI edit verbs, invoked as `%s` (already on PATH as `ripwire`):\n%s\n"
             "The JSON receipt ripwire prints on success already carries the post-edit verification: `edit_check` "
             "(the contract check on the edited symbol) and `tests_to_run`. You do not need to read the file back or "
             "run --edit-check afterwards unless the receipt reports a problem. Stop as soon as the receipt reports "
             "the edit applied.%s" % ( shim, how, ( "\n\nRules for this tool:\n" + rules_blurb ) if rules_blurb else "" ) )

def build_edit_prompt( task, arm, seed, shim, rules_blurb="" ):
    return task_prompt( task ) + arm_instructions( arm, task, shim, rules_blurb ) + "\n[run-seed:%d]" % seed

# ── the fixture checkout ──────────────────────────────────────────────────────────────────────────────
def checkout_fixture( work_dir, task_id, arm, seed, lane="" ):
    """A fresh copy of editsuite/fixture as a one-commit git repo (ripwire's HEAD baseline and the oracle's
    `git diff` both need a commit). Never the committed fixture itself — the edit verbs WRITE."""
    repo = pathlib.Path( work_dir ) / ( "repos%s" % lane ) / ( "%s-%s-%d" % ( task_id, arm, seed ) )
    if repo.exists():
        shutil.rmtree( repo )
    shutil.copytree( FIXTURE, repo )
    for cmd in ( [ "git", "init", "-q" ], [ "git", "add", "-A" ],
                 [ "git", "-c", "user.email=editsuite@ripwire", "-c", "user.name=editsuite", "commit", "-qm", "fixture" ] ):
        subprocess.run( cmd, cwd=repo, check=True, capture_output=True )
    return repo

# ── the ordered tool-call walk (both runners' self-logged streams) ─────────────────────────────────────
def walk_tool_calls( harness, stdout ):
    """[{tool, command, input}] in call order. opencode: every `tool_use` part (bash carries `command`,
    read/edit/write/grep/glob carry `filePath`/`pattern`). codex: every completed `command_execution` item —
    codex has no native read/edit tools, so every call is a shell command."""
    calls = []
    for line in ( stdout or "" ).splitlines():
        try:
            event = json.loads( line )
        except ValueError:
            continue
        if harness == "opencode":
            if event.get( "type" ) != "tool_use":
                continue
            part  = event.get( "part" ) or {}
            state = part.get( "state" ) or {}
            inp   = state.get( "input" ) or {}
            inp   = inp if isinstance( inp, dict ) else { "value": inp }
            command = inp.get( "command" )
            command = " ".join( map( str, command ) ) if isinstance( command, list ) else ( str( command ) if command else "" )
            calls.append( { "tool": str( part.get( "tool" ) or "" ), "command": command, "input": inp,
                            "status": str( state.get( "status" ) or "" ) } )
        else:
            item = event.get( "item" ) or {}
            if event.get( "type" ) != "item.completed" or item.get( "type" ) != "command_execution":
                continue
            command = shell_script_of( item.get( "command" ) or "" )
            calls.append( { "tool": "bash", "command": command, "input": { "command": command }, "status": "completed" } )
    return calls

# ── classification ────────────────────────────────────────────────────────────────────────────────────
EDIT_VERB_RE   = re.compile( r"--(replace-symbol-body|insert-before-symbol|insert-after-symbol|edit-plan)\b" )
EDIT_CHECK_RE  = re.compile( r"--edit-check=([^\s'\"]+)" )
NATIVE_EDIT_TOOLS = frozenset( { "edit", "write", "multiedit", "apply_patch", "patch", "notebookedit" } )
# a shell command that WRITES a file: sed -i, a redirect into it, tee, an inline python/perl writer, apply_patch
SHELL_WRITE_RE = re.compile( r"(?:^|[|;&]|&&|\|\|)\s*(?:sed\s+-i|tee\b|apply_patch\b|patch\b|(?:python3?|perl)\s+-c\b)|>\s*[^&\s]" )

def is_ripwire_command( cmd ):
    """run_agentloop's rule: a command word whose basename is `ripwire` — never a substring test (this
    checkout's path and the scratchpad both contain the word)."""
    return R.invokes_ripwire( cmd )

def shell_script_of( command ):
    """codex logs a command as argv; `["bash","-lc","sed -n 1,20p f"]` is the script, not a bash read."""
    if isinstance( command, list ) and len( command ) >= 3 and command[1] in ( "-c", "-lc", "-ec", "-lec" ) \
       and str( command[0] ).rsplit( "/", 1 )[-1] in ( "bash", "sh", "zsh", "dash" ):
        return str( command[2] )
    return " ".join( map( str, command ) ) if isinstance( command, list ) else str( command or "" )

def mentions_file( text, rel_files ):
    """The first target file a command/path names, or None. Matched on the basename too, because a runner
    may spell the path absolute (opencode's read tool does)."""
    for rel in rel_files:
        base = rel.rsplit( "/", 1 )[-1]
        if rel in text or re.search( r"(?:^|[/\s'\"=])" + re.escape( base ) + r"(?:$|[\s'\":])", text ):
            return rel
    return None

def classify_call( call, target_files, target_symbols ):
    """(class, family, target) for one tool call, in the meter's vocabulary plus EVALS T2's edit classes:
       ripwire-edit / ripwire-edit-check / ripwire-cli (family ripwire)
       read / grep / glob / find (family native) — with target= when the path is a TARGET file
       native-edit (family native) — the runner's own edit/write of a TARGET file (T2 sweep column)
       test-run / git-diff / script-run / shell-misc (family other|git)"""
    tool, cmd, inp = call["tool"].lower(), call.get( "command" ) or "", call.get( "input" ) or {}
    path_text = " ".join( str( v ) for v in inp.values() if isinstance( v, str ) )
    if is_ripwire_command( cmd ):
        if EDIT_VERB_RE.search( cmd ):
            return "ripwire-edit", "ripwire", mentions_file( cmd, target_files ) or ""
        m = EDIT_CHECK_RE.search( cmd )
        if m:
            sym = m.group( 1 ).split( ":" )[-1]
            return ( "ripwire-edit-check" if sym in target_symbols else "ripwire-cli" ), "ripwire", mentions_file( cmd, target_files ) or ""
        return "ripwire-cli", "ripwire", ""
    if tool in NATIVE_EDIT_TOOLS:
        return "native-edit", "native", mentions_file( path_text, target_files ) or ""
    if tool in ( "read", "grep", "glob", "list", "ls", "search", "find" ):
        cls = { "read": "read", "grep": "grep", "glob": "glob", "search": "grep" }.get( tool, "find" )
        return cls, "native", mentions_file( path_text, target_files ) or ""
    if tool in ( "bash", "shell", "command" ):
        if SHELL_WRITE_RE.search( cmd ) and mentions_file( cmd, target_files ):
            return "native-edit", "native", mentions_file( cmd, target_files )
        if re.search( r"\bgit\s+diff\b", cmd ):
            return "git-diff", "git", mentions_file( cmd, target_files ) or ""
        if re.search( r"\b(pytest|ctest|run_tests\.sh|make\s+test|npm\s+test)\b", cmd ):
            return "test-run", "other", ""
        if R.classify_native_read( command=cmd ):
            cls = "grep" if re.search( r"\b(rg|grep|egrep|fgrep|ag|ack)\b", cmd ) else ( "find" if re.search( r"\b(find|ls|tree)\b", cmd ) else "read" )
            return cls, "native", mentions_file( cmd, target_files ) or ""
        return "shell-misc", "other", ""
    return "unclassified", "other", ""

def edit_call_index( classified, arm, target_files, ops=1 ):
    """Index of THE edit call the window hangs off. A task of N ops is one edit either way: the ripwire arm
    lands it as one --edit-plan (one call) or N single verbs, the native arm as N edit-tool calls — so the
    window opens after the N-th edit call of the arm's own kind (or the last one, when fewer were made).
    Counting from the FIRST call would charge a multi-op task's own later edits as "re-edits". A single-op
    task is the N=1 case. None when the agent never edited."""
    want = "ripwire-edit" if arm == "ripwire_edit" else "native-edit"
    hits = [ i for i, c in enumerate( classified ) if c["class"] == want and ( arm == "ripwire_edit" or c["target"] ) ]
    if not hits:
        return None
    if arm == "ripwire_edit" and any( "--edit-plan" in classified[i]["detail"] for i in hits ):
        return hits[ [ "--edit-plan" in classified[i]["detail"] for i in hits ].index( True ) ]   # the plan IS the N ops
    return hits[ min( len( hits ), max( 1, ops ) ) - 1 ]

def window_verdict( classified, edit_idx ):
    """The post-edit window, classified per docs/EVALS.md T2:
       policy_read      — a read/grep of the TARGET file (reported, never counted by the meter; COUNTED here,
                          because these runners have no policy and any target read is the receipt failing)
       sweep            — a read/grep of another file, or a native edit of the target (the edit did not land)
       redundant_check  — --edit-check on the same symbol after a receipt that carried it
    Two verdicts: `terminal_band` is lane E's registered band (zero target reads AND zero redundant checks
    inside the 5-call window); `terminal_t2` is the meter's TERMINAL (neither sweep nor redundant-check)."""
    post = classified[ edit_idx + 1: ] if edit_idx is not None else []
    win  = post[ :TERMINALITY_WINDOW ]
    def count( rows, pred ):
        return sum( 1 for c in rows if pred( c ) )
    is_target_read = lambda c: c["family"] == "native" and c["class"] in ( "read", "grep" ) and bool( c["target"] )
    is_other_read  = lambda c: c["family"] == "native" and c["class"] in ( "read", "grep", "glob", "find" ) and not c["target"]
    is_native_edit = lambda c: c["class"] == "native-edit"
    is_redundant   = lambda c: c["class"] == "ripwire-edit-check"
    v = {
        "post_edit_calls":       [ { "class": c["class"], "family": c["family"], "target": c["target"], "detail": c["detail"][:200] } for c in post ],
        "post_edit_count":       len( post ),
        "window_count":          len( win ),
        "policy_read_window":    count( win,  is_target_read ),
        "policy_read_total":     count( post, is_target_read ),
        "sweep_window":          count( win,  is_other_read ) + count( win, is_native_edit ),
        "sweep_total":           count( post, is_other_read ) + count( post, is_native_edit ),
        "native_edit_after":     count( post, is_native_edit ),
        "redundant_check_window": count( win,  is_redundant ),
        "redundant_check_total": count( post, is_redundant ),
        "git_diff_after":        count( post, lambda c: c["class"] == "git-diff" ),
    }
    v["terminal_band"] = edit_idx is not None and v["policy_read_window"] == 0 and v["redundant_check_window"] == 0
    v["terminal_t2"]   = edit_idx is not None and v["sweep_window"] == 0 and v["redundant_check_window"] == 0
    return v

def classify_all( calls, target_files, target_symbols ):
    out = []
    for c in calls:
        cls, fam, target = classify_call( c, target_files, target_symbols )
        detail = c.get( "command" ) or json.dumps( c.get( "input" ) or {}, sort_keys=True )
        out.append( { "tool": c["tool"], "class": cls, "family": fam, "target": target, "detail": detail } )
    return out

# ── the oracle ────────────────────────────────────────────────────────────────────────────────────────
def oracle( task_id, repo_dir ):
    p = subprocess.run( [ "bash", str( ORACLE ), task_id, str( repo_dir ) ], capture_output=True, text=True )
    return { 0: "pass", 2: "ws-only" }.get( p.returncode, "fail" ), ( p.stdout or "" ).strip()

# ── meter rows ────────────────────────────────────────────────────────────────────────────────────────
def meter_rows( record, classified ):
    """One row per tool call, in the meter row shape (bench/substitution_report.py): v, ts, seq, session,
    repo, tag, tool, class, family, agent, surface, target, detail. `agent` is the runner, `surface` is cli
    (these runners drive ripwire through the shell shim; no MCP)."""
    ts = datetime.datetime.fromtimestamp( record.get( "started_unix" ) or time.time(), datetime.timezone.utc ).strftime( "%Y-%m-%dT%H:%M:%SZ" )
    rows = []
    for seq, c in enumerate( classified, 1 ):
        rows.append( { "v": METER_V, "ts": ts, "seq": seq, "session": record["run_id"], "repo": record["repo_dir"],
                       "tag": "ripwire", "tool": c["tool"], "class": c["class"], "family": c["family"],
                       "agent": record["harness"], "surface": "cli", "target": c["target"], "arm": record["arm"],
                       "task": record["task_id"], "detail": c["detail"][:200] } )
    return rows

# ── one run ───────────────────────────────────────────────────────────────────────────────────────────
def make_record( task, arm, seed, harness, model, **kw ):
    rec = { "schema": SCHEMA, "run_id": "%s-%s-%d" % ( task["id"], arm, seed ), "task_id": task["id"],
            "kind": task["kind"], "arm": arm, "seed": seed, "harness": harness, "model": model,
            "target_files": task_files( task ), "target_symbols": task_symbols( task ),
            "status": "not_run", "error": None, "oracle": None, "oracle_note": "", "resolved_model": None,
            "tokens_in": None, "tokens_out": None, "transcript_bytes": None, "wall_seconds": None,
            "ripwire_calls": 0, "ripwire_commands": [], "edit_call_index": None, "tool_calls": 0,
            "started_unix": None, "finished_unix": None, "repo_dir": None, "events_path": None }
    rec.update( kw )
    return rec

def run_one_edit( task, arm, seed, harness, model, *, work_dir, ripwire_bin, timeout_s=DEFAULT_TIMEOUT_S, lane="" ):
    started = time.time()
    rec = make_record( task, arm, seed, harness, model, started_unix=started )
    if harness not in HARNESSES:
        rec.update( status="error", error="unsupported harness %r; the edit suite runs on %r" % ( harness, HARNESSES ) ); return rec, []
    if arm not in ARMS:
        rec.update( status="error", error="unknown arm %r" % arm ); return rec, []
    repo = checkout_fixture( work_dir, task["id"], arm, seed, lane )
    rec["repo_dir"] = str( repo )
    env, run_home, shim = R.prepare_environment( harness, work_dir, "edit-%s" % task["id"], arm, seed, ripwire_bin )
    shim_log = pathlib.Path( run_home ) / "shim" / "ripwire-calls.log"
    blurb = ""
    if arm == "ripwire_edit":
        wrapped = subprocess.run( [ str( ripwire_bin ), "wrap", { "opencode": "opencode", "codex-exec": "codex" }[ harness ], "--force" ],
                                  capture_output=True, text=True )
        blurb = R.extract_wrap_blurb( wrapped.stdout )
    prompt = build_edit_prompt( task, arm, seed, shim, blurb )
    cmd    = R.build_harness_command( harness, prompt, model, arm )
    t0 = time.perf_counter()
    try:
        proc = R.sh( cmd, cwd=repo, timeout=timeout_s, env=env )
        stdout, rc = proc.stdout, proc.returncode
        rec["status"] = "ok" if rc == 0 else "error"
        if rc != 0:
            rec["error"] = "%s exit %d: %s" % ( harness, rc, R._child_failure_detail( proc ) )
    except subprocess.TimeoutExpired as exc:
        stdout, rc = exc.stdout or b"", None
        rec.update( status="timeout", error="%s exceeded %ds" % ( harness, timeout_s ) )
    rec["wall_seconds"] = time.perf_counter() - t0
    if isinstance( stdout, bytes ):
        stdout = stdout.decode( "utf-8", errors="replace" )
    stdout = stdout or ""
    events = pathlib.Path( work_dir ) / "events"; events.mkdir( parents=True, exist_ok=True )
    ev = events / ( rec["run_id"] + ".jsonl" ); ev.write_text( stdout )
    rec["events_path"] = str( ev ); rec["transcript_bytes"] = len( stdout.encode( "utf-8" ) )
    if harness == "opencode":
        ti, to, _cost, model_id, _n, _rip, _cmds, _nat = R.parse_opencode_ndjson_metrics( stdout, ripwire_bin )
    else:
        ti, to, _n, _rip, _cmds, _nat = R.parse_codex_jsonl_metrics( stdout, ripwire_bin ); model_id = None
    rec.update( tokens_in=ti, tokens_out=to, resolved_model=model_id )
    if model and model_id and model_id not in model:
        rec.update( status="error", error="model substitution: asked for %r, harness used %r" % ( model, model_id ) )
    shim_calls, shim_cmds = R.read_shim_log( shim_log )
    rec.update( ripwire_calls=shim_calls, ripwire_commands=shim_cmds )
    calls      = walk_tool_calls( harness, stdout )
    classified = classify_all( calls, rec["target_files"], rec["target_symbols"] )
    idx        = edit_call_index( classified, arm, rec["target_files"], len( task_ops( task ) ) )
    rec["tool_calls"] = len( classified ); rec["edit_call_index"] = idx
    rec["window"] = window_verdict( classified, idx )
    if arm == "native_edit" and shim_calls:
        rec["contaminated"] = "native arm invoked ripwire %d time(s): %r" % ( shim_calls, shim_cmds[:2] )
    rec["oracle"], rec["oracle_note"] = oracle( task["id"], repo )
    rec["finished_unix"] = time.time()
    return rec, meter_rows( rec, classified )

def reclassify( records ):
    """Re-derive every record's window from its retained events with the classifier as it is NOW, so two
    result files produced under different versions of this script are read by ONE instrument. A record
    whose events file is gone keeps the window it recorded."""
    tasks = { t["id"]: t for t in load_tasks() }
    for rec in records:
        ev = rec.get( "events_path" )
        if not ev or not pathlib.Path( ev ).exists() or rec["task_id"] not in tasks:
            continue
        calls      = walk_tool_calls( rec["harness"], pathlib.Path( ev ).read_text() )
        classified = classify_all( calls, rec["target_files"], rec["target_symbols"] )
        idx        = edit_call_index( classified, rec["arm"], rec["target_files"], len( task_ops( tasks[ rec["task_id"] ] ) ) )
        rec["tool_calls"], rec["edit_call_index"], rec["window"] = len( classified ), idx, window_verdict( classified, idx )
    return records

# ── summary ───────────────────────────────────────────────────────────────────────────────────────────
def summarize( records ):
    """Per arm (and per harness): n, windows terminal by the band, task pass, ws-only, policy-reads,
    redundant checks, native re-edits, mean transcript bytes / tokens. Printed as a table; returned as a dict."""
    out = {}
    for rec in records:
        key = ( rec["harness"], rec["arm"] )
        s = out.setdefault( key, { "n": 0, "ok": 0, "edited": 0, "terminal_band": 0, "terminal_t2": 0, "pass": 0, "ws_only": 0,
                                   "policy_reads": 0, "redundant_checks": 0, "native_edits_after": 0, "git_diffs": 0,
                                   "bytes": 0, "tokens_in": 0, "tokens_out": 0, "contaminated": 0, "errors": [] } )
        s["n"] += 1
        if rec["status"] != "ok":
            s["errors"].append( "%s: %s" % ( rec["run_id"], rec.get( "error" ) ) )
        else:
            s["ok"] += 1
        w = rec.get( "window" ) or {}
        if rec.get( "edit_call_index" ) is not None:
            s["edited"] += 1
        s["terminal_band"] += int( bool( w.get( "terminal_band" ) ) )
        s["terminal_t2"]   += int( bool( w.get( "terminal_t2" ) ) )
        s["policy_reads"]  += w.get( "policy_read_total", 0 )
        s["redundant_checks"] += w.get( "redundant_check_total", 0 )
        s["native_edits_after"] += w.get( "native_edit_after", 0 )
        s["git_diffs"] += w.get( "git_diff_after", 0 )
        s["pass"]    += int( rec.get( "oracle" ) == "pass" )
        s["ws_only"] += int( rec.get( "oracle" ) == "ws-only" )
        s["bytes"]   += rec.get( "transcript_bytes" ) or 0
        s["tokens_in"]  += rec.get( "tokens_in" ) or 0
        s["tokens_out"] += rec.get( "tokens_out" ) or 0
        s["contaminated"] += int( bool( rec.get( "contaminated" ) ) )
    return out

def print_summary( records ):
    summ = summarize( records )
    print( "editsuite summary — band: ripwire arm >= 80%% of post-edit windows with zero target reads AND zero redundant checks; task pass >= native" )
    print( "  %-10s %-13s %3s %3s %6s %8s %8s %5s %7s %7s %7s %7s %8s %8s" % ( "harness", "arm", "n", "ok", "edited", "term%band", "term%t2", "pass", "ws-only", "tgtread", "redchk", "reedit", "kB/run", "tok/run" ) )
    for ( harness, arm ), s in sorted( summ.items() ):
        n = max( s["n"], 1 )
        print( "  %-10s %-13s %3d %3d %6d %7.1f%% %7.1f%% %5d %7d %7d %7d %7d %8.1f %8.0f" % (
            harness, arm, s["n"], s["ok"], s["edited"], 100.0 * s["terminal_band"] / n, 100.0 * s["terminal_t2"] / n,
            s["pass"], s["ws_only"], s["policy_reads"], s["redundant_checks"], s["native_edits_after"],
            s["bytes"] / 1024.0 / n, ( s["tokens_in"] + s["tokens_out"] ) / n ) )
        for e in s["errors"]:
            print( "      error: %s" % e )
        if s["contaminated"]:
            print( "      contaminated native runs: %d" % s["contaminated"] )
    print( "  per task:" )
    for rec in sorted( records, key=lambda r: ( r["task_id"], r["arm"] ) ):
        w = rec.get( "window" ) or {}
        print( "    %-3s %-13s %-8s oracle=%-8s edit_idx=%-4s post=%-2s tgtread=%d redchk=%d reedit=%d term_band=%s  post-classes=%s" % (
            rec["task_id"], rec["arm"], rec["status"], rec.get( "oracle" ), rec.get( "edit_call_index" ),
            w.get( "post_edit_count", 0 ), w.get( "policy_read_total", 0 ), w.get( "redundant_check_total", 0 ),
            w.get( "native_edit_after", 0 ), w.get( "terminal_band" ), ",".join( c["class"] for c in w.get( "post_edit_calls", [] ) ) ) )
    return summ

# ── main ──────────────────────────────────────────────────────────────────────────────────────────────
def main():
    ap = argparse.ArgumentParser( description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter )
    ap.add_argument( "--harness", default="opencode", choices=HARNESSES )
    ap.add_argument( "--model", default="" )
    ap.add_argument( "--arms", default=",".join( ARMS ) )
    ap.add_argument( "--tasks", default="", help="comma-separated task ids (default: all 12)" )
    ap.add_argument( "--seeds", type=int, default=1 )
    ap.add_argument( "--ripwire-bin", default=str( HERE.parents[1] / "build" / "ripwire" ) )
    ap.add_argument( "--work-dir", default="/tmp/editsuite" )
    ap.add_argument( "--timeout", type=int, default=DEFAULT_TIMEOUT_S )
    ap.add_argument( "--concurrency", type=int, default=1 )
    ap.add_argument( "--results-out", default="" )
    ap.add_argument( "--meter-out", default="" )
    ap.add_argument( "--live", action="store_true", help="actually invoke the runner (otherwise print the matrix)" )
    ap.add_argument( "--live-one", action="store_true", help="run exactly the first cell and print its record" )
    ap.add_argument( "--summarize", default="", help="print the summary table for an existing results file and exit" )
    a = ap.parse_args()

    if a.summarize:
        records = []
        for path in a.summarize.split( "," ):   # a matrix run in chunks: several results files, one table
            records.extend( json.loads( pathlib.Path( path ).read_text() )["records"] )
        print_summary( reclassify( records ) )
        return 0

    tasks = load_tasks()
    if a.tasks:
        want = set( a.tasks.split( "," ) ); tasks = [ t for t in tasks if t["id"] in want ]
    arms  = tuple( x for x in a.arms.split( "," ) if x )
    cells = matrix( tasks, arms )
    if a.live_one:
        cells = cells[ :1 ]
    if not ( a.live or a.live_one ):
        print( "editsuite matrix (%d cells; --live to run): harness=%s model=%r" % ( len( cells ), a.harness, a.model ) )
        for task, arm in cells:
            print( "  %-3s %-13s %-8s files=%s symbols=%s" % ( task["id"], arm, task["kind"], ",".join( task_files( task ) ), ",".join( task_symbols( task ) ) ) )
        return 0

    ripwire_bin = str( pathlib.Path( a.ripwire_bin ).resolve() )
    work_dir    = pathlib.Path( a.work_dir ); work_dir.mkdir( parents=True, exist_ok=True )
    records, rows, lock = [], [], threading.Lock()

    # a task's two arms run back to back in one worker, in the alternating order — concurrency is across tasks
    by_task = []
    for task, arm in cells:
        if by_task and by_task[-1][0]["id"] == task["id"]:
            by_task[-1][1].append( arm )
        else:
            by_task.append( ( task, [ arm ] ) )

    def run_task( slot, task, arm_list ):
        lane = "-w%d" % slot
        for seed in range( 1, a.seeds + 1 ):
            for arm in arm_list:
                rec, rrows = run_one_edit( task, arm, seed, a.harness, a.model, work_dir=str( work_dir ),
                                           ripwire_bin=ripwire_bin, timeout_s=a.timeout, lane=lane )
                with lock:
                    records.append( rec ); rows.extend( rrows )
                    print( "  done %-3s %-13s status=%-7s oracle=%-8s post=%s tgtread=%s redchk=%s" % (
                        task["id"], arm, rec["status"], rec["oracle"], ( rec.get( "window" ) or {} ).get( "post_edit_count" ),
                        ( rec.get( "window" ) or {} ).get( "policy_read_total" ), ( rec.get( "window" ) or {} ).get( "redundant_check_total" ) ), flush=True )

    with concurrent.futures.ThreadPoolExecutor( max_workers=max( 1, a.concurrency ) ) as pool:
        futures = [ pool.submit( run_task, i % max( 1, a.concurrency ), task, arm_list ) for i, ( task, arm_list ) in enumerate( by_task ) ]
        for f in futures:
            f.result()

    if a.results_out:
        pathlib.Path( a.results_out ).write_text( json.dumps( { "schema": SCHEMA, "harness": a.harness, "model": a.model,
                                                                 "ripwire_bin": ripwire_bin, "records": records }, indent=1 ) )
    if a.meter_out:
        with open( a.meter_out, "a" ) as fh:
            for r in rows:
                fh.write( json.dumps( r, sort_keys=True ) + "\n" )
    if a.live_one:
        print( json.dumps( records[0], indent=1 ) )
    print_summary( records )
    return 0

if __name__ == "__main__":
    sys.exit( main() )
