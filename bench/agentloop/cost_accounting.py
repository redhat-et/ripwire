#!/usr/bin/env python3
# cost_accounting.py — the four-way token split, tool-call count and model-call count of ONE agent run,
# read from that run's own transcript. Shared by run_agentloop.py (fills the record at run time) and
# analyze.py (re-derives it from events_path for records written before these fields existed), so the two
# sides cannot drift.
#
# WHY A SPLIT. Under prefix caching a token total does not price a run. A cache read bills at a fraction of
# an uncached input token, and a cache write at a premium, so two arms with equal tokens_in can differ in
# cost in either direction. "Context Has a Price ... under Prefix Caching" (arXiv 2611.22238) measured
# retrieved code that cut read/search commands by 18-34% and raised cost by 33-42% at a one-tenth cache
# price. The split is what lets a reader reprice a run under any schedule.
#
# THE FOUR CELLS, per harness, exactly as each harness's transcript labels them:
#   split_uncached_in  input tokens billed at the full input price
#   split_cache_write  input tokens written to the prompt cache
#   split_cache_read   input tokens served from the prompt cache
#   split_output       output tokens, reasoning included
#
#   claude-code-p  `claude -p --output-format json` trailer `usage`: input_tokens (already excludes the
#                  cache), cache_creation_input_tokens, cache_read_input_tokens, output_tokens. The trailer
#                  is the session total. model_calls = the trailer's num_turns.
#   codex-exec     `turn.completed` usage: input_tokens INCLUDES cached_input_tokens, so uncached is the
#                  difference. Codex reports no cache-write count, so split_cache_write is None ("not
#                  reported by this harness"), never 0. output_tokens already includes reasoning. Summed over
#                  every turn.completed. model_calls is None: codex exposes no per-request count.
#   opencode       `step_finish` part.tokens: input (opencode already subtracts cache read and write), output,
#                  reasoning, cache.read, cache.write. These are PER STEP: opencode 1.x adds each step's
#                  part.cost into the message total, so the run is the SUM over steps. model_calls = the
#                  number of step_finish events.
#
# tool_calls counts every tool the agent invoked, of any kind (shell, read, grep, edit, ...). It is wider
# than command_calls (shell commands only), which keeps its existing meaning.
#
# HONESTY. A cell the transcript does not carry is None, never 0: "unmeasured" and "zero" must not read the
# same. An unparseable line is skipped, never a crash; the retained transcript is the evidence of record.
import json, pathlib

SPLIT_FIELDS = ( "split_uncached_in", "split_cache_write", "split_cache_read", "split_output" )
ACCOUNTING_FIELDS = SPLIT_FIELDS + ( "tool_calls", "model_calls" )

def _empty():
    return dict.fromkeys( ACCOUNTING_FIELDS )

def _int_or_none( v ):
    return v if isinstance( v, int ) and not isinstance( v, bool ) else None

def _events( text ):
    for line in ( text or "" ).splitlines():
        try:
            event = json.loads( line )
        except ValueError:
            continue
        if isinstance( event, dict ):
            yield event

def _add( acc, key, v ):
    """Sum v into acc[key]; None stays None until a real number arrives."""
    if v is None:
        return
    acc[key] = v if acc[key] is None else acc[key] + v

def claude_trailer_accounting( trailer_text ):
    out = _empty()
    try:
        payload = json.loads( trailer_text or "" )
    except ValueError:
        return out
    if not isinstance( payload, dict ):
        return out
    usage = payload.get( "usage" ) or {}
    out.update( split_uncached_in=_int_or_none( usage.get( "input_tokens" ) ),
                split_cache_write=_int_or_none( usage.get( "cache_creation_input_tokens" ) ),
                split_cache_read=_int_or_none( usage.get( "cache_read_input_tokens" ) ),
                split_output=_int_or_none( usage.get( "output_tokens" ) ),
                model_calls=_int_or_none( payload.get( "num_turns" ) ) )
    return out

def claude_transcript_tool_calls( transcript_text ):
    """Every tool_use block in the session transcript's assistant messages; None if no line parsed."""
    count, seen = 0, False
    for event in _events( transcript_text ):
        seen = True
        if event.get( "type" ) != "assistant":
            continue
        message = event.get( "message" ) or {}
        content = message.get( "content" ) if isinstance( message, dict ) else None
        if isinstance( content, list ):
            count += sum( 1 for b in content if isinstance( b, dict ) and b.get( "type" ) == "tool_use" )
    return count if seen else None

CODEX_TOOL_ITEMS = frozenset( { "command_execution", "file_change", "mcp_tool_call", "web_search" } )

def codex_accounting( jsonl_text ):
    out = _empty()
    tools, seen = 0, False
    for event in _events( jsonl_text ):
        seen = True
        if event.get( "type" ) == "turn.completed":
            usage = event.get( "usage" ) or {}
            total, cached = _int_or_none( usage.get( "input_tokens" ) ), _int_or_none( usage.get( "cached_input_tokens" ) )
            if total is not None and cached is not None:
                _add( out, "split_uncached_in", total - cached )
                _add( out, "split_cache_read", cached )
            _add( out, "split_output", _int_or_none( usage.get( "output_tokens" ) ) )
        item = event.get( "item" ) or {}
        if event.get( "type" ) == "item.completed" and isinstance( item, dict ) and item.get( "type" ) in CODEX_TOOL_ITEMS:
            tools += 1
    out["tool_calls"] = tools if seen else None
    return out

def opencode_accounting( ndjson_text ):
    out = _empty()
    tools = steps = 0
    seen = False
    for event in _events( ndjson_text ):
        seen = True
        part = event.get( "part" ) or {}
        if not isinstance( part, dict ):
            continue
        etype = event.get( "type" )
        if etype == "step_finish":
            steps += 1
            tokens = part.get( "tokens" ) or {}
            cache = tokens.get( "cache" ) or {}
            _add( out, "split_uncached_in", _int_or_none( tokens.get( "input" ) ) )
            _add( out, "split_cache_read", _int_or_none( cache.get( "read" ) ) )
            _add( out, "split_cache_write", _int_or_none( cache.get( "write" ) ) )
            output, reasoning = _int_or_none( tokens.get( "output" ) ), _int_or_none( tokens.get( "reasoning" ) )
            if output is not None:
                _add( out, "split_output", output + ( reasoning or 0 ) )
        elif etype == "tool_use":
            tools += 1
    if seen:
        out.update( tool_calls=tools, model_calls=steps )
    return out

def opencode_headline( ndjson_text ):
    """opencode's tokens_in / tokens_out / cost_usd: part.tokens.input, part.tokens.output and part.cost,
    SUMMED over every step_finish (each carries that step's usage only). Until 2026-11-26 the runner kept
    the LAST step, which undercounts every multi-step run. tokens_in is opencode's `input`, which already
    excludes cache read and write, so it equals split_uncached_in; uncached + cache_read + cache_write does
    NOT equal it. tokens_out excludes reasoning, which split_output includes. None until a step reports."""
    out = dict( tokens_in=None, tokens_out=None, cost_usd=None )
    for event in _events( ndjson_text ):
        part = event.get( "part" ) or {}
        if event.get( "type" ) != "step_finish" or not isinstance( part, dict ):
            continue
        tokens = part.get( "tokens" ) or {}
        _add( out, "tokens_in", _int_or_none( tokens.get( "input" ) ) )
        _add( out, "tokens_out", _int_or_none( tokens.get( "output" ) ) )
        cost = part.get( "cost" )
        _add( out, "cost_usd", cost if isinstance( cost, ( int, float ) ) and not isinstance( cost, bool ) else None )
    return out

def accounting_from_text( harness, text, transcript_text=None ):
    """The accounting fields for one run of `harness`, from its retained stdout (and, for claude, the
    session transcript beside the trailer)."""
    if harness == "codex-exec":
        return codex_accounting( text )
    if harness == "opencode":
        return opencode_accounting( text )
    if harness == "claude-code-p":
        out = claude_trailer_accounting( text )
        if transcript_text is not None:
            out["tool_calls"] = claude_transcript_tool_calls( transcript_text )
        return out
    return _empty()

def claude_transcript_path( events_path ):
    """_claude_metrics() retains the session stream as <trailer stem>.transcript.jsonl beside the trailer."""
    p = pathlib.Path( events_path )
    return p.parent / ( p.stem + ".transcript.jsonl" )

def accounting_from_events( harness, events_path ):
    """Re-derive the accounting from a retained events file; every field None if the file is unreadable."""
    if not events_path:
        return _empty()
    p = pathlib.Path( events_path )
    try:
        text = p.read_text( errors="replace" )
    except OSError:
        return _empty()
    transcript = None
    if harness == "claude-code-p":
        try:
            transcript = claude_transcript_path( p ).read_text( errors="replace" )
        except OSError:
            transcript = None
    return accounting_from_text( harness, text, transcript )
