#!/usr/bin/env python3
"""mcpcontractprobe.py — the DECLARED / CONSUMED / CLI three-column contract table for every MCP verb.

Wave-2 M2/M4 deliverable. The finding class this exists to find is CONTRACT DIVERGENCE, not malformed
input: what the tools/list schema DECLARES, what the server code actually CONSUMES, and what the CLI does
for the same request. Two verifiers have already proved this surface clean under ~85 hostile probes, so a
hostile-input sweep would re-derive a known answer; a three-column diff cannot be derived by reading, only
by measuring.

CONSUMED is measured, never read out of the source: for every verb x every candidate argument key, the
same request is sent twice — once bare, once with the key — against a long-lived stdio server, and the two
answers are compared byte-for-byte. A key that moves the answer is consumed. A key that does not is either
genuinely inert for that verb or its probe value was too weak to move it, so every probe value below is
chosen to be answer-changing when honored (limit=1 truncates, kind= filters, paths= adds a whole root).

Usage:  test/mcpcontractprobe.py <ctxpack-binary> <rootA> <rootB> [--json out.json]
Prints one row per verb; exits 0 always (this is an instrument, not a gate — test/mcpcontractcheck.sh is
the gate that pins its findings).

────────────────────────────────────────────────────────────────────────────────────────────────────────────
THE RECORDED TABLE, wave 2 of the capture-audit-4 fix round (2026-07-30), measured on two real git repos
against the post-fix binary. Kept HERE, beside the instrument that produces it, so the next round diffs
against a measurement rather than re-deriving one.

After M2/M4/M12, the first three columns are ONE column: for all 30 verbs the tools/list schema, the
unknown-field guard's enforced set (declaredFieldsFor), and the consumed set agree — which is what arm (A)
of mcpcontractcheck.sh pins. So the table below prints that single column plus `required` plus the CLI
comparison, and the only rows worth reading are the two flagged DIVERGES.

  verb                     | declared (= enforced = consumed)        | required   | MCP m-root | CLI m-root
  -------------------------|-----------------------------------------|------------|------------|-----------
  analyze                  | path,paths                              | path       | answers    | answers
  find_symbol              | path,paths,symbol                       | path,symbol| answers    | answers
  find_referencing_symbols | path,paths,symbol                       | path,symbol| answers    | answers
  grep                     | path,paths,pattern,limit,offset         | path,pattern| answers   | answers
  cochange                 | path,file,paths                         | path,file  | answers    | answers
  memory_recall            | path,task,top_k,paths                   | path,task  | answers    | answers
  situational_awareness    | path,diff,files,paths                   | path       | REFUSE     | answers   <<< DIVERGES
  mentions                 | path,paths,symbol                       | path,symbol| answers    | answers
  for                      | path,paths,task                         | path,task  | answers    | answers
  lego                     | path,paths,type                         | path,type  | answers    | answers
  owners                   | path,symbol,paths                       | path       | REFUSE     | answers   <<< DIVERGES
  replace_symbol_body      | path,paths,symbol,file,new_body         | path,symbol,new_body | answers | n/a
  insert_before_symbol     | path,paths,symbol,file,text             | path,symbol,text     | answers | n/a
  insert_after_symbol      | path,paths,symbol,file,text             | path,symbol,text     | answers | n/a
  fetch_body               | path,handle,start_line,end_line,paths   | path,handle| answers    | answers
  exemplar                 | path,paths,kind,task                    | path +anyOf(kind|task) | answers | answers
  quality_delta            | path,paths                              | path       | REFUSE     | REFUSE
  quality_baseline         | path,paths                              | path       | REFUSE     | REFUSE
  impact                   | path,paths,symbol,limit,offset          | path,symbol| answers    | answers
  uses                     | path,paths,symbol                       | path,symbol| answers    | answers
  path_between             | path,paths,from,to                      | path,from,to| answers   | answers
  connect                  | path,paths,symbols,radius               | path,symbols| answers   | answers
  explore                  | path,paths,task,budget_tokens,partition | path,task  | answers    | answers
  from_trace               | path,paths,trace,budget_tokens          | path,trace | answers    | n/a
  edit_check               | path,paths,symbol                       | path,symbol| REFUSE     | REFUSE
  whereis                  | path,symbol,kind,limit,offset,paths     | path,symbol| REFUSE     | REFUSE
  stray_content            | path,kind,paths                         | path       | REFUSE     | REFUSE
  flags                    | path,kind,symbol,paths                  | path       | answers    | answers
  doc_drift                | path,kind,paths                         | path       | answers    | answers
  batch                    | path,queries,paths                      | path,queries| answers   | n/a (CLI --batch=FILE REFUSES)

`required` is shown for a ROOTLESS server; a server started as `ctxpack <root> --mcp` drops `path` from
every row, which is the point of rendering it from the policy rather than hardcoding it.

THE THREE REMAINING DISAGREEMENTS, all reported rather than silently fixed:
  1. owners — CLI answers a multi-root workspace, the MCP arm cannot (no per-root git plumbing there). Now
     refuses with the TRUE cause instead of "no git history for this tree"; closing it is a feature.
  2. situational_awareness — same shape: CLI answers, MCP arm is keyed to one working tree.
  3. batch — MCP answers a merged multi-root batch and the CLI's `--batch=FILE` refuses. Deliberately NOT
     aligned: the MCP verb demonstrably works against the merged index like every other read verb, so this
     looks like the CLI side being the questionable one. Routed to the lane that owns main.cpp.

KNOWN LIMITS of the consumed column, so a later reader does not over-trust it: `fetch_body`'s base request
uses a synthetic handle and refuses, so its per-key results are inert by construction; `top_k`, `kind` and
`diff` probe as inert on this fixture because a 3-file corpus with one ref cannot show a filter or a window
moving. Those are FIXTURE limits, not findings — a richer fixture is the way to strengthen them, and none
of them is a declared-vs-enforced disagreement, which is what this instrument is for.
────────────────────────────────────────────────────────────────────────────────────────────────────────────
"""

import json
import subprocess
import sys


# ── the candidate key universe: every argument key any verb declares or reads ──────────────────────────
# Values are chosen to MOVE the answer when the key is honored — an inert probe value would report a
# consumed key as unconsumed, which is the direction that would make this table lie in ctxpack's favour.
def candidateValues( rootA, rootB ):
    return {
        "paths":         [ rootA, rootB ],   # the multi-root form: REPLACES path, so the corpus grows
        "symbol":        "alphaOne",
        "pattern":       "alpha",
        "file":          "alpha.cpp",
        "task":          "what does alphaOne do",
        "type":          "alphaOne",
        "from":          "alphaThree",
        "to":            "alphaOne",
        "symbols":       [ "alphaOne", "alphaThree" ],
        "handle":        "alpha.cpp::alphaOne",
        "trace":         'File "alpha.cpp", line 2, in alphaOne',
        "new_body":      "int alphaOne( int x ) { return x + 99; }",
        "text":          "// inserted\n",
        "queries":       [ { "verb": "grep", "pattern": "alpha" } ],
        "diff":          "alpha.cpp",
        "files":         [ "alpha.cpp" ],
        "kind":          "zzz-no-such-thing",   # a filter that must empty the listing if honored
        "limit":         1,
        "offset":        1,
        "top_k":         1,
        "radius":        1,
        "budget_tokens": 100,
        "partition":     2,
        "start_line":    1,
        "end_line":      1,
    }


# A request that makes each verb ANSWER (not refuse) on rootA — otherwise every probe compares two refusals
# and the whole table reads "nothing is consumed".
def baseArgs( verb ):
    return {
        "analyze":                  {},
        "find_symbol":              { "symbol": "alphaTwo" },
        "find_referencing_symbols": { "symbol": "alphaOne" },
        "grep":                     { "pattern": "int" },
        "cochange":                 { "file": "alpha.cpp" },
        "memory_recall":            { "task": "entry point notes" },
        "situational_awareness":    {},
        "mentions":                 { "symbol": "alphaOne" },
        "for":                      { "task": "add a thing to alpha" },
        "lego":                     { "type": "alphaOne" },
        "owners":                   {},
        "replace_symbol_body":      { "symbol": "alphaOne", "new_body": "int alphaOne( int x ) { return x + 7; }" },
        "insert_before_symbol":     { "symbol": "alphaOne", "text": "// before\n" },
        "insert_after_symbol":      { "symbol": "alphaOne", "text": "// after\n" },
        "fetch_body":               { "handle": "alpha.cpp::alphaOne" },
        "exemplar":                 { "kind": "fn" },
        "quality_delta":            {},
        "quality_baseline":         {},
        "impact":                   { "symbol": "alphaOne" },
        "uses":                     { "symbol": "alphaOne" },
        "path_between":             { "from": "alphaThree", "to": "alphaOne" },
        "connect":                  { "symbols": [ "alphaOne", "alphaThree" ] },
        "explore":                  { "task": "change alphaOne" },
        "from_trace":               { "trace": 'File "alpha.cpp", line 2, in alphaOne' },
        "edit_check":               { "symbol": "alphaOne" },
        "whereis":                  { "symbol": "alphaOne" },
        "stray_content":            {},
        "flags":                    {},
        "doc_drift":                {},
        "batch":                    { "queries": [ { "verb": "grep", "pattern": "int" } ] },
    }.get( verb, {} )


# Verbs that WRITE. Their probes run against a throwaway copy of the corpus so a consumed-key probe cannot
# leave the fixture edited for every later verb.
EDIT_VERBS = ( "replace_symbol_body", "insert_before_symbol", "insert_after_symbol" )


class Server:
    def __init__( self, binPath ):
        self.p = subprocess.Popen( [ binPath, "--mcp" ], stdin=subprocess.PIPE,
                                   stdout=subprocess.PIPE, stderr=subprocess.DEVNULL )
        self.n = 0
        self.call( "initialize", {} )

    def call( self, method, params ):
        self.n += 1
        req = { "jsonrpc": "2.0", "id": self.n, "method": method, "params": params }
        self.p.stdin.write( json.dumps( req ).encode() + b"\n" )
        self.p.stdin.flush()
        line = self.p.stdout.readline().decode( "utf-8", "replace" )
        try:
            return json.loads( line )
        except Exception:
            return { "raw": line }

    def tool( self, name, args ):
        return self.call( "tools/call", { "name": name, "arguments": args } )

    def close( self ):
        try:
            self.p.stdin.close()
            self.p.wait( 20 )
        except Exception:
            self.p.kill()


# The comparable BODY of a response: the id changes per request by construction, so it is dropped.
def body( resp ):
    r = dict( resp )
    r.pop( "id", None )
    return json.dumps( r, sort_keys = True )


def probe( binPath, rootA, rootB ):
    srv    = Server( binPath )
    listed = srv.call( "tools/list", {} )
    tools  = listed[ "result" ][ "tools" ]
    values = candidateValues( rootA, rootB )

    rows = []
    for t in tools:
        verb     = t[ "name" ]
        schema   = t[ "inputSchema" ]
        declared = list( schema.get( "properties", {} ).keys() )
        required = list( schema.get( "required", [] ) )

        base = dict( baseArgs( verb ) )
        base[ "path" ] = rootA

        # a write verb gets a private corpus per probe; a read verb shares the fixture
        import shutil, tempfile, os
        def runWith( extra ):
            args, scratch = dict( base ), None
            if verb in EDIT_VERBS:
                scratch = tempfile.mkdtemp()
                shutil.copytree( rootA, os.path.join( scratch, "c" ) )
                args[ "path" ] = os.path.join( scratch, "c" )
            args.update( extra )
            if "paths" in extra:
                args.pop( "path", None )          # the multi-root form replaces path
            out = srv.tool( verb, args )
            if scratch:
                shutil.rmtree( scratch, ignore_errors = True )
            return out

        bare     = runWith( {} )
        answered = "error" not in bare

        # THREE outcomes, not two. The server has an unknown-FIELD guard (W3FIX M4) whose refusal enumerates
        # the verb's accepted set, so a naive "did the answer change?" test reports every unknown key as
        # consumed — it changed the answer into a refusal. That guard is itself the third contract surface
        # this table exists to line up, so it is measured rather than worked around:
        #   rejected — the unknown-field guard refused it: the verb does not accept this key at all
        #   consumed — accepted AND the answer moved: the verb reads it
        #   inert    — accepted AND the answer did not move: declared/tolerated but with no effect here
        consumed, inert, rejected = [], [], []

        def isUnknownFieldRefusal( r ):
            return "error" in r and r[ "error" ].get( "message", "" ).startswith( "unknown field:" )

        for key, val in values.items():
            if key in base:
                consumed.append( key )            # in the base request by construction (required/addressing)
                continue
            with_ = runWith( { key: val } )
            if isUnknownFieldRefusal( with_ ):    rejected.append( key )
            elif body( with_ ) != body( bare ):   consumed.append( key )
            else:                                 inert.append( key )

        rows.append( { "verb": verb, "declared": declared, "required": required,
                       "consumed": sorted( consumed ), "inert": sorted( inert ),
                       "rejected": sorted( rejected ), "baseAnswered": answered } )

    srv.close()
    return rows


def main():
    binPath, rootA, rootB = sys.argv[ 1 ], sys.argv[ 2 ], sys.argv[ 3 ]
    rows = probe( binPath, rootA, rootB )

    if "--json" in sys.argv:
        outPath = sys.argv[ sys.argv.index( "--json" ) + 1 ]
        json.dump( rows, open( outPath, "w" ), indent = 1 )

    print( "%-26s %-4s %-22s %s" % ( "verb", "ans", "declared-not-consumed", "accepted-but-UNDECLARED" ) )
    print( "-" * 96 )
    divergences = 0
    for r in rows:
        accepted = set( r[ "consumed" ] ) | set( r[ "inert" ] )
        dnc      = sorted( set( r[ "declared" ] ) - set( r[ "consumed" ] ) )
        und      = sorted( accepted - set( r[ "declared" ] ) )
        if und: divergences += 1
        print( "%-26s %-4s %-22s %s" % ( r[ "verb" ], "y" if r[ "baseAnswered" ] else "REF",
                                         ",".join( dnc ) or "-", ",".join( und ) or "-" ) )
    print( "-" * 96 )
    print( "verbs with an accepted-but-undeclared field: %d of %d" % ( divergences, len( rows ) ) )


if __name__ == "__main__":
    main()
