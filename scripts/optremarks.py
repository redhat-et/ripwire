#!/usr/bin/env python3
"""scripts/optremarks.py — triage clang's YAML optimization records into a short, ranked report.

A -DRIPWIRE_OPT_REMARKS=ON build drops one `<object>.opt.yaml` beside every object file. Those files
are large (tens of MB for src/main.cpp alone) and overwhelmingly noise: most remarks describe library
templates, cold one-shot setup code, or optimizer decisions that were correct. This script exists to
turn that pile into the two questions worth asking:

    which remark CLASSES fire at all, and how often   (--summary, the default)
    where does a given class fire in OUR hot code     (--pass/--name/--file, and --hot)

Design constraints, both deliberate:

  * ZERO DEPENDENCIES, like the tool it ships with — no PyYAML. Clang's opt-record is a strict,
    machine-generated YAML subset (one flow-style DebugLoc mapping, two-space Args entries, `...`
    terminators), so a line state machine reads it exactly and starts instantly. A general YAML
    parser on a 40 MB record is ~30 s; this is under 2 s.
  * third_party/ IS DROPPED, unconditionally. The vendored tree-sitter core and the sixteen grammars
    are C we do not own, and their remarks cannot become a change here. System and toolchain headers
    (the SDK, libc++) go with them: a failed-vectorization remark inside <algorithm> is a fact about
    libc++, not about this repo. `--keep-foreign` turns the filter off if you want to see the volume.

Usage:
    python3 scripts/optremarks.py                              # summary over build_remarks/
    python3 scripts/optremarks.py --hot                        # summary restricted to the hot set
    python3 scripts/optremarks.py --pass loop-vectorize --sites 40
    python3 scripts/optremarks.py --name NoDefinition --file src/clones.h
"""

import argparse
import collections
import os
import re
import sys

# ---- the hot set: where a remark is worth a bench run (G2 — the cache-locality guardrail) ----------
# MEMBERSHIP RULE. A file is hot when its code runs per FILE, per SYMBOL or per AST NODE on the default
# `ripwire <dir>` path — the path every verb pays for — and the profiler attributes measurable time to
# it. Everything else is CLI plumbing, serialization, one-shot per-run setup, or code gated behind a
# verb or a single language, where a vectorization or inlining remark cannot move a measured number.
# Kept as a literal list rather than a heuristic so the report's notion of "hot" is reviewable.
#
# A LITERAL LIST DOES NOT STAY HONEST ON ITS OWN — this one went stale silently, once, and stayed that
# way for as long as the ingest split has existed. The split moved ~18,000 lines out of src/ingest.cpp
# into fifteen src/ingest_*.h sections of the SAME translation unit. Every listed path still existed,
# so nothing failed and no gate fired; the remarks simply began naming the section headers instead.
# --hot went from covering the ingest family to covering 69 of its 33,957 first-party remarks — 0.2% —
# and the two hottest own-code phases in the tool were invisible to the triage the whole time.
#
# So the list is now gated against the tree by test/optremarkshotcheck.sh: every file the tree groups
# with a hot one must appear here, or in COLD_FILES with a reason. Adding a section and saying nothing
# is no longer possible. Growing this list without limit is also no longer possible — a hot set that is
# the whole tree narrows nothing, and the gate has a ceiling arm that says so.
#
# The shares below are from -DRIPWIRE_PROFILE=ON over this repository as its own corpus (~1,800 files,
# 19 threads); "cold" is --no-cache, "warm" is the steady state of repeated runs, NOT the first one.
# Re-derive them if you touch the pipeline — docs/OPTREMARKS.md §3 has the command.
HOT_FILES = (
    "src/pagerank.cpp",           # the power-iteration loop — G2's no-allocation scope
    "src/infra/radixSort.h",      # LSD radix entry points
    "src/infra/radixSort.inl",    # the counting/scatter kernels, incl. the SSE ones
    "src/infra/fastSort.h",
    "src/infra/sparseCsr.h",      # the CSR triple itself
    "src/infra/fastmath.h",       # fastmath:: — isFiniteFast and friends, inlined everywhere
    "src/infra/dynamic_map.hpp",
    "src/infra/sortutil.h",
    "src/clones.h",               # token-shingle scan over every file
    "src/lexical.h",              # tokenizer

    # ── the ingest translation unit ──────────────────────────────────────────────────────────────
    # One TU, seventeen files since the split. It is the overwhelming majority of both a cold and a
    # warm run, so most of its sections are hot — that is a fact about where this tool spends its
    # time, not a lapsed rule. The six that are NOT hot are in COLD_FILES, each with its number.
    "src/ingest.cpp",             # the TU anchor: the ingest() driver and its phase calls. Its own body is small now — the phases live in the sections below
    "src/ingest.h",               # isSkippedCrawlDir / looksBinary / isNonTextExtension — inline predicates run for EVERY crawled path
    "src/ingest_crawl.h",         # the crawl and its git-ignore probe (~26% warm), plus readFile's fopen+read (~4% cold) — both per path
    "src/ingest_parsepool.h",     # the parallel per-file parse pool; its pending-tag flush alone is 10.2% of a cold run
    "src/ingest_sidecap.h",       # captureTagsFacts + captureSideFacts, per query capture and per node — 23.7% + 5.6% cold, the hottest own code in the tool
    "src/ingest_names.h",         # the per-definition name / kind / gating decision, called from the capture loop above
    "src/ingest_binds.h",         # per-node binding and alias capture — 182 distinct ts_* NoDefinition sites, more than any other file
    "src/ingest_relations.h",     # captureIncludes and the relation captures — the densest LoadClobbered cluster in the family (1,120 in one function)
    "src/ingest_metrics.h",       # cc_walk / complexityOf — a per-symbol AST walk for the quality metrics
    "src/ingest_cache.h",         # loadCache / saveCache / readFileRecord, per file record — ~10% of a WARM run, which is the run an agent actually pays for
    "src/ingest_model.h",         # build-model: dedup, symbol-id assignment, the def-span index, the ref radix sort — per symbol and per reference, ~18% warm

    "src/resolve.h",              # reference resolution into the call graph
    "src/graph.h",
)

# ---- the deliberate exclusions --------------------------------------------------------------------
# NOT "everything that is not hot" — that is 137 files and would say nothing. These are the files the
# grouping relations in test/optremarkshotcheck.sh would otherwise flag as undecided: the rest of a
# translation unit that has hot members, the name-family siblings of a hot file, and every TU in src/.
# Each states why it is out, because an exclusion nobody can argue with is an exclusion nobody
# reviewed. Argue with these — that is what they are for.
COLD_FILES = (
    # ── ingest sections that are not on the per-file / per-symbol default path ────────────────────
    ( "src/ingest_astquery.h",
      "the --match / --lint AST-query engine. It does not run at all on a plain `ripwire <dir>`, so a remark here cannot move the number every other verb pays." ),
    ( "src/ingest_prewarm.h",
      "grammar classification and tags.scm compile: ONE-SHOT per run, not per file, and already the subject of two landed optimizations. ~1.9% cold, ~1.1% warm; "
      "what remains is ts_query_new inside tree-sitter, which is third_party and dropped at triage by the same rule." ),
    ( "src/ingest_docs.h",
      "markdown / notebook / html / csv extraction, per doc file. 4.8 ms of an ~88 ms warm run and 0.07% cold — the same order as the build-model sorts D1 dismisses "
      "on arithmetic. The LoadClobbered cluster in extractMarkdown (447) is real, just cheap. Revisit if the doc pass grows." ),
    ( "src/ingest_docpass.h",
      "the driver of the doc extraction above, dismissed on the same measurement. Beware its FIRST warm run after a cold one, which costs ~30 ms rather than ~5: "
      "that is first-touch, not steady state, and it takes three repeats to see. A single run would have put this file in the hot set." ),
    ( "src/ingest_jsimports.h",
      "JS/TS import resolution. Per file, but for one language family, so a remark here cannot be validated against a general corpus. The same code SHAPE — a "
      "per-node tree-sitter walk — is covered by ingest_binds.h and ingest_relations.h, which run for every grammar." ),
    ( "src/ingest_elixir.h",
      "Elixir-specific capture helpers: per node, but for one grammar with a small corpus share. Same argument as ingest_jsimports.h above." ),

    # ── the other translation units under src/ ────────────────────────────────────────────────────
    ( "src/main.cpp",
      "argument parsing and verb dispatch: one-shot per run. It is also the largest opt-record in the tree by an order of magnitude (1.5 GB even narrowed) precisely "
      "BECAUSE it is thousands of cold functions — volume here measures function count, not heat. Its verbs_*.h sections are cold for the same reason." ),
    ( "src/tsprobe.cpp",
      "the ripwire_probe binary. Not linked into ripwire at all, so nothing in it runs when the tool runs." ),
    ( "src/alloccount.cpp",
      "the RIPWIRE_ALLOC_COUNT operator new/delete replacement: absent from every shipped build and from every gate by construction — see the honesty note at the "
      "top of the file." ),
    ( "src/infra/diagnostics.cpp",
      "the VERIFY / DEGRADED_PATH_ALERT handlers. They run on a degrade path: once, after something has already gone wrong." ),

    # ── name-family siblings of a hot file ────────────────────────────────────────────────────────
    ( "src/pagerank.h",
      "42 lines of PageRankConfig and the result struct — declarations, no loop. The power iteration is src/pagerank.cpp, which IS listed, and whose own remarks D1 "
      "dismisses on the profile: 2.2 ms of a 7.3 s cold run." ),
)

FOREIGN_MARKERS = ( "third_party/", "/usr/include", "/usr/lib", ".sdk/", "/Applications/Xcode",
                    "/Library/Developer/", "_deps/" )

RECORD_START = re.compile( r"^--- !(Passed|Missed|Analysis|AnalysisFPCommute|AnalysisAliasing|Failure)\s*$" )
KEY_LINE     = re.compile( r"^(\w+):\s*(.*)$" )
ARG_LINE     = re.compile( r"^\s+-?\s*(\w+):\s*(.*)$" )
DEBUGLOC     = re.compile( r"File:\s*'((?:[^']|'')*)'\s*,\s*Line:\s*(\d+)" )


def unquote( value ):
    """Clang writes YAML single-quoted scalars with '' for a literal quote. Undo exactly that."""
    value = value.strip()
    if len( value ) >= 2 and value[ 0 ] == "'" and value[ -1 ] == "'":
        value = value[ 1 : -1 ]
    return value.replace( "''", "'" )


class Remark:
    __slots__ = ( "kind", "pass_", "name", "file", "line", "function", "detail" )

    def __init__( self ):
        self.kind = self.pass_ = self.name = self.function = self.detail = ""
        self.file = ""
        self.line = 0

    def set_location( self, flowMapping, repo_root ):
        m = DEBUGLOC.search( flowMapping )
        if not m:
            return
        pathText = m.group( 1 ).replace( "''", "'" )
        if repo_root and pathText.startswith( repo_root ):
            pathText = pathText[ len( repo_root ) : ].lstrip( "/" )
        self.file = pathText
        self.line = int( m.group( 2 ) )


def parse_record_file( path, repo_root ):
    """Return the Remarks in one .opt.yaml. Tolerates truncation: a partial trailing record is dropped.

    Two shapes of this format bite a naive line reader, and both are handled here rather than worked
    around later: a DebugLoc flow mapping WRAPS onto a continuation line when the path is long (the SDK
    paths always do), and the Args list nests its own DebugLoc mappings whose `Line:` key would
    otherwise read as a record-level key. `pending` tracks the unclosed brace across both.
    """
    out = []
    cur = None
    inArgs = False
    pending = ""       # a flow mapping whose closing brace has not been seen yet
    pendingIsRecordLoc = False
    with open( path, "r", errors = "replace" ) as fh:
        for raw in fh:
            line = raw.rstrip( "\n" )

            if pending:
                pending += " " + line.strip()
                if "}" not in line:
                    continue
                if pendingIsRecordLoc and cur is not None:
                    cur.set_location( pending, repo_root )
                pending = ""
                pendingIsRecordLoc = False
                continue

            start = RECORD_START.match( line )
            if start:
                cur = Remark()
                cur.kind = start.group( 1 )
                inArgs = False
                continue
            if cur is None:
                continue
            if line == "...":
                if cur.pass_:
                    cur.detail = cur.detail.strip()
                    out.append( cur )
                cur = None
                inArgs = False
                continue

            if line.startswith( " " ) or line.startswith( "-" ):
                if not inArgs:
                    continue
                arg = ARG_LINE.match( line )
                if not arg:
                    continue
                key, value = arg.group( 1 ), arg.group( 2 )
                if key == "DebugLoc":
                    if "}" not in value:
                        pending, pendingIsRecordLoc = value, False
                    continue
                # Clang builds the -Rpass message by concatenating every arg value in order; doing the
                # same here is what makes two remarks with the same Pass/Name distinguishable at a glance.
                cur.detail += unquote( value )
                continue

            kv = KEY_LINE.match( line )
            if not kv:
                continue
            key, value = kv.group( 1 ), kv.group( 2 ).strip()
            inArgs = ( key == "Args" )
            if key == "Pass":
                cur.pass_ = value
            elif key == "Name":
                cur.name = value
            elif key == "Function":
                cur.function = value
            elif key == "DebugLoc":
                if "}" in value:
                    cur.set_location( value, repo_root )
                else:
                    pending, pendingIsRecordLoc = value, True
    return out


def is_foreign( path ):
    if not path:
        return True   # a remark with no DebugLoc cannot be triaged to a site — treat as unusable
    if path.startswith( "/" ):
        return True
    return any( marker in path for marker in FOREIGN_MARKERS )


def main():
    ap = argparse.ArgumentParser( description = "triage clang optimization remarks" )
    ap.add_argument( "--build-dir", default = "build_remarks" )
    ap.add_argument( "--repo-root", default = os.path.abspath( os.path.join( os.path.dirname( __file__ ), ".." ) ) )
    ap.add_argument( "--hot", action = "store_true", help = "restrict to the hot-set files (see HOT_FILES)" )
    ap.add_argument( "--keep-foreign", action = "store_true", help = "do NOT drop third_party/ and toolchain headers" )
    ap.add_argument( "--kind", default = "", help = "Passed | Missed | Analysis (default: all)" )
    ap.add_argument( "--pass", dest = "pass_", default = "", help = "filter by optimizer pass, e.g. loop-vectorize" )
    ap.add_argument( "--name", default = "", help = "filter by remark Name, e.g. MissedDetails" )
    ap.add_argument( "--file", default = "", help = "filter by source path substring" )
    ap.add_argument( "--detail", default = "", help = "filter by message substring — '_ZN2rw' keeps only remarks about OUR symbols" )
    ap.add_argument( "--width", type = int, default = 110, help = "--sites message width" )
    ap.add_argument( "--sites", type = int, default = 0, help = "list this many individual sites instead of the summary" )
    ap.add_argument( "--top", type = int, default = 25 )
    args = ap.parse_args()

    repo_root = os.path.abspath( args.repo_root )
    build_dir = args.build_dir if os.path.isabs( args.build_dir ) else os.path.join( repo_root, args.build_dir )
    records = []
    for dirpath, _dirs, files in os.walk( build_dir ):
        for fname in files:
            if fname.endswith( ".opt.yaml" ):
                records.append( os.path.join( dirpath, fname ) )
    if not records:
        print( "no .opt.yaml under %s — configure with -DRIPWIRE_OPT_REMARKS=ON and build first" % build_dir, file = sys.stderr )
        return 2

    # ---- read + filter ----------------------------------------------------------------------------
    remarks = []
    per_tu = []
    for path in sorted( records ):
        got = parse_record_file( path, repo_root )
        per_tu.append( ( os.path.basename( path ), len( got ) ) )
        remarks.extend( got )
    rawCount = len( remarks )

    if not args.keep_foreign:
        remarks = [ r for r in remarks if not is_foreign( r.file ) ]
    ownCount = len( remarks )
    if args.hot:
        remarks = [ r for r in remarks if r.file in HOT_FILES ]
    if args.kind:
        remarks = [ r for r in remarks if r.kind == args.kind ]
    if args.pass_:
        remarks = [ r for r in remarks if r.pass_ == args.pass_ ]
    if args.name:
        remarks = [ r for r in remarks if r.name == args.name ]
    if args.file:
        remarks = [ r for r in remarks if args.file in r.file ]
    if args.detail:
        remarks = [ r for r in remarks if args.detail in r.detail ]

    print( "opt-record: %d TUs, %d remarks total, %d in first-party sources%s" %
           ( len( per_tu ), rawCount, ownCount, ", %d after filters" % len( remarks ) if len( remarks ) != ownCount else "" ) )
    for name, n in sorted( per_tu, key = lambda t: -t[ 1 ] ):
        print( "  %-28s %8d" % ( name, n ) )
    print()

    if args.sites:
        seen = collections.Counter()
        shown = 0
        for r in sorted( remarks, key = lambda r: ( r.file, r.line ) ):
            key = ( r.file, r.line, r.name )
            seen[ key ] += 1
            if seen[ key ] > 1:
                continue
            print( "%s:%d  [%s/%s/%s]  %s" % ( r.file, r.line, r.kind, r.pass_, r.name, r.detail[ : args.width ] ) )
            shown += 1
            if shown >= args.sites:
                break
        print( "\n%d distinct sites shown of %d matching remarks" % ( shown, len( remarks ) ) )
        return 0

    # ---- summary: remark class x volume, then the hot-file breakdown -------------------------------
    byClass = collections.Counter( ( r.kind, r.pass_, r.name ) for r in remarks )
    print( "remark classes (kind / pass / name):" )
    for ( kind, pass_, name ), n in byClass.most_common( args.top ):
        print( "  %7d  %-9s %-18s %s" % ( n, kind, pass_, name ) )
    print()

    byFile = collections.Counter( r.file for r in remarks )
    print( "top files:" )
    for path, n in byFile.most_common( args.top ):
        mark = "  HOT" if path in HOT_FILES else ""
        print( "  %7d  %s%s" % ( n, path, mark ) )
    return 0


if __name__ == "__main__":
    sys.exit( main() )
