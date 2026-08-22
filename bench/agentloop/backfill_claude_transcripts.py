#!/usr/bin/env python3
"""Repair a claude-code-p results bundle produced before 2026-08-22: attach the real session
transcripts and populate the accounting fields the old harness left null.

WHY THIS EXISTS. Before 2026-08-22, run_agentloop.py's claude harness retained only the `claude -p`
result trailer under events/ — a 20-key summary object with no tool calls in it — while the REAL
per-message transcript (every assistant turn with its tool_use blocks) sat unretained in the
ephemeral run home at claude-home/<arm>/<instance>-<seed>/projects/<cwd-slug>/<session_id>.jsonl,
i.e. in /tmp state that dies on the next cycle. Every such record also carried
command_calls=None / native_read_calls=None — fields that look like they were meant to hold
tool-call accounting and never did, for this harness. Both halves are fixed in run_agentloop.py for
new runs (_claude_metrics + parse_claude_session_metrics); this script applies the same repair
retroactively to an ALREADY-ARCHIVED bundle while its /tmp run homes still exist.

WHAT IT DOES, per claude-code-p record in the results file:
  1. reads the archived trailer events/<instance>-<arm>-<seed>.json for its session_id;
  2. locates exactly claude-home/<arm>/<instance>-<seed>/projects/*/<session_id>.jsonl — the exact
     session only, never a guess: run homes are reused across lanes, and attaching another run's
     transcript would be worse than attaching none;
  3. copies it to events/<instance>-<arm>-<seed>.transcript.jsonl beside the trailer;
  4. populates command_calls / native_read_calls from it (only where currently null — a non-null
     value that disagrees is reported and left alone);
  5. cross-checks the shim-derived ripwire_calls against the transcript-parsed count (reported,
     never overwritten — the shim is authoritative);
  6. rewrites events_path to the RELATIVE form events/<name>.json, which grade_answers.py resolves
     against the results file's own directory — the bundle stops depending on /tmp paths at all.

The results file is rewritten in place; the pristine original is kept once at
<results>.pre-backfill. Exit 4 if any claude record could not be backfilled (missing trailer or
transcript) — a partial repair must be visible, not silent.
"""
import argparse, glob, json, pathlib, sys

sys.path.insert( 0, str( pathlib.Path( __file__ ).resolve().parent ) )
import run_agentloop as R


def backfill( results_path, claude_home, events_dir, ripwire_bin, dry_run ):
    results_path = pathlib.Path( results_path )
    data = json.loads( results_path.read_text() )
    if data.get( "schema" ) != R.SCHEMA:
        raise SystemExit( f"{results_path}: schema {data.get('schema')!r} != {R.SCHEMA!r}; refusing" )
    events_dir = pathlib.Path( events_dir ) if events_dir else results_path.resolve().parent / "events"
    claude_home = pathlib.Path( claude_home )

    done, skipped, missing, mismatched = 0, 0, [], []
    for rec in data.get( "records", [] ):
        if rec.get( "harness" ) != "claude-code-p":
            skipped += 1
            continue
        stem = f"{rec['instance_id']}-{rec['arm']}-{rec['seed']}"
        trailer = events_dir / f"{stem}.json"
        if not trailer.exists():
            missing.append( f"{stem}: no archived trailer at {trailer}" )
            continue
        try:
            session_id = json.loads( trailer.read_text() ).get( "session_id" )
        except ValueError:
            session_id = None
        if not session_id:
            missing.append( f"{stem}: trailer carries no session_id" )
            continue
        hits = glob.glob( str( claude_home / rec[ "arm" ] / f"{rec['instance_id']}-{rec['seed']}"
                               / "projects" / "*" / f"{session_id}.jsonl" ) )
        if not hits:
            # layout tolerance: same exact session_id, anywhere under the given home
            hits = glob.glob( str( claude_home / "**" / f"{session_id}.jsonl" ), recursive=True )
        if len( hits ) != 1:
            missing.append( f"{stem}: {len(hits)} transcript(s) match session {session_id} under {claude_home}" )
            continue

        text = pathlib.Path( hits[ 0 ] ).read_text( errors="replace" )
        ( command_calls, ripwire_calls,
          ripwire_commands, native_read_calls ) = R.parse_claude_session_metrics( text, ripwire_bin )
        if not dry_run:
            ( events_dir / f"{stem}.transcript.jsonl" ).write_text( text )
        for field, value in ( ( "command_calls", command_calls ), ( "native_read_calls", native_read_calls ) ):
            if rec.get( field ) is None:
                rec[ field ] = value
            elif rec[ field ] != value:
                mismatched.append( f"{stem}: recorded {field}={rec[field]} vs transcript {value} — left alone" )
        if rec.get( "ripwire_calls" ) is not None and rec[ "ripwire_calls" ] != ripwire_calls:
            mismatched.append( f"{stem}: shim ripwire_calls={rec['ripwire_calls']} vs transcript "
                               f"{ripwire_calls} ({ripwire_commands[:2]!r}) — shim kept (authoritative)" )
        rec[ "events_path" ] = f"events/{stem}.json"
        done += 1

    if not dry_run and done:
        backup = results_path.with_name( results_path.name + ".pre-backfill" )
        if not backup.exists():
            backup.write_text( results_path.read_text() )
        results_path.write_text( json.dumps( data, indent=2 ) )

    tag = "DRY RUN — " if dry_run else ""
    print( f"# {tag}{done} record(s) backfilled, {skipped} non-claude record(s) untouched, "
           f"{len(missing)} unrecoverable, {len(mismatched)} cross-check disagreement(s)" )
    for line in missing:
        print( f"MISSING    {line}" )
    for line in mismatched:
        print( f"CROSSCHECK {line}" )
    return 4 if missing else 0


def main():
    ap = argparse.ArgumentParser( description=( "attach real claude session transcripts to a pre-2026-08-22 "
                                                "results bundle and populate its null accounting fields" ) )
    ap.add_argument( "--results", required=True, help="run_agentloop.py results JSON (e.g. stage1.json)" )
    ap.add_argument( "--claude-home", required=True,
                     help="the run's claude-home root (work_dir/claude-home), holding <arm>/<instance>-<seed>/projects/" )
    ap.add_argument( "--events-dir", default="",
                     help="archived events/ dir holding the trailers (default: <results dir>/events)" )
    ap.add_argument( "--ripwire-bin", default=R.RIPWIRE_BIN_DEFAULT,
                     help="ripwire path/name for the transcript's ripwire-vs-native-read classification" )
    ap.add_argument( "--dry-run", action="store_true", help="report only; write nothing" )
    a = ap.parse_args()
    return backfill( a.results, a.claude_home, a.events_dir, a.ripwire_bin, a.dry_run )


if __name__ == "__main__":
    raise SystemExit( main() )
