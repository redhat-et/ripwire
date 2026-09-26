#!/usr/bin/env python3
# run_mulocbench.py — UNTESTED adapter skeleton for MULocBench (arXiv:2509.25242), written against the
# design + pre-registration in docs/research/mulocbench-baseline.md — read that first, it is the
# contract this file implements, not the other way around.
#
# STATUS (2026-09-20): NEVER RUN. No MULocBench data is on this disk. This file exists so the mining
# and scoring logic is fixed in writing BEFORE any row is seen (docs/METHODOLOGY.md §9), the same
# discipline bench/multiswe/dataset.lock's content-hash freeze enforces after the fact. Every gold-field
# name below (file_loc/own_code_loc/ass_file_loc/other_rep_loc/loctype/analysis) is sourced from the
# public HuggingFace dataset card's prose (somethingone/MULocBench), NOT verified against one real row —
# see docs/research/mulocbench-baseline.md §4 step 1. EXPECT THIS FILE TO NEED FIXES the first time it
# sees a real row, and fix it in writing (this file + the design doc, same commit) rather than quietly
# reconciling a mismatch.
#
# Do NOT run this file's network path in this lane. The owner fetches raw rows via
# $ORCH/sim/mulocbench/1_fetch_rows.sh (JSON only, no dataset build); this file's own --refresh-dataset
# network path mirrors bench/multiswe/run_multiswe.py's shape for future symmetry, but has not been
# exercised this round. --offline is the only mode this file has ever been asked to run in, and it has
# not even been run in that mode yet (no fixture exists — bench/multiswe/README.md's offline-gate
# pattern, test/multiswecheck.sh's 3-row local fixture, is the template for that follow-up work, not
# done here).
#
# REUSE (not reinvention): run_ctx/sh/parse_candidates/ranked_files_from_candidates/file_ranks/
# acc_all_at/first_hit/norm_path all come from bench/locbench (imported, exactly as bench/multiswe
# already does — see its own header comment for the same reasoning); LOCAL_PATH_RE (the embedded-
# home-directory-path hygiene filter) comes from bench/cppbench, also re-imported rather than re-derived.
#
# NEW IN THIS FILE (does not exist anywhere else in the repo):
#   gold_from_mulocbench_row()  — reads dataset-native structured location fields, not a diff
#   class_ranks()               — class-level localization rank (k="cls"/"struct" candidates)
#   f1_at()                     — per-issue precision/recall/F1 over a gold location set
#   ARMS incl. "for-no-docmention" (RIPWIRE_NO_DOC_MENTION=1) — the ablation this benchmark's own
#                                  non-code gold set exists to exercise (R5's doc-mention boost,
#                                  src/mention.h::applyDocMentionBoost)
#
# See docs/research/mulocbench-baseline.md for: the verb-mapping table (§2.1), the metric definitions
# restated in our own words (§2.2), the eligibility/exclusion rules (§2.3), what we'd report/withhold
# (§2.4), the open questions for the benchmark's authors (§3), and the owner-run fetch steps (§4).
import argparse, json, os, pathlib, sys

HERE = pathlib.Path( __file__ ).resolve().parent
LOCBENCH_DIR = HERE.parent / "locbench"
CPPBENCH_DIR = HERE.parent / "cppbench"

sys.path.insert( 0, str( LOCBENCH_DIR ) )
import run_locbench as lb   # noqa: E402
sys.path.insert( 0, str( CPPBENCH_DIR ) )
import run_cppbench as cb   # noqa: E402  (cb.lb is the same run_locbench module, re-imported harmlessly)

DATASET_ID = "somethingone/MULocBench"
DATASET_URL = f"https://huggingface.co/datasets/{DATASET_ID}"
PAPER_URL = "https://arxiv.org/abs/2509.25242"

# SCHEMA-UNVERIFIED (design doc §4 step 1 fixes this against a real row): field names per the public
# HF dataset-card prose only. "file_loc"/"own_code_loc" are treated as in-scope (in-project) location
# sets; "other_rep_loc" (third-party-file) is excluded at mining time (design doc §2.3 rule 4);
# "ass_file_loc" ("runtime-file location") is retained on the row but withheld from scoring pending
# design doc §3 Q4.
IN_SCOPE_LOC_FIELDS = ( "file_loc", "own_code_loc" )
WITHHELD_LOC_FIELD = "ass_file_loc"
EXCLUDED_LOC_FIELD = "other_rep_loc"
LOCTYPE_CATEGORIES = ( "code", "test", "config", "doc", "asset" )   # paper's own taxonomy, §0

# class_ranks() below needs the `k=` (kind: fn/method/cls/struct/sec/var) attribute off each <cand>
# row, which no existing harness had ever needed — added directly to the shared
# bench/locbench/run_locbench.py::parse_candidates (one more dict key, `kind=`) rather than forked
# here: quality-delta flagged the fork as a new-clone-of-reused-helper on the first pass (gating), and
# the fix is to extend the one place every harness already imports, not add a second one. Callers use
# lb.parse_candidates(...) directly; there is no local wrapper.

def _location_records( row, field ):
    # SCHEMA-UNVERIFIED: assumes `row[field]` is a list of dicts, each carrying at least a file path
    # and optionally class/function/line — the shape the card's prose implies ("file path, class name
    # (if applicable), function name (if applicable), and line numbers (if applicable)"). Whatever the
    # real key names turn out to be, this is the ONE function that needs fixing — everything downstream
    # (gold_from_mulocbench_row, class_ranks, f1_at) consumes its normalized output, not the raw row.
    raw = row.get( field ) or []
    if isinstance( raw, dict ): raw = [ raw ]   # tolerate a single-record dict, not just a list
    out = []
    for r in raw:
        if not isinstance( r, dict ): continue
        path = r.get( "file" ) or r.get( "file_path" ) or r.get( "path" )
        if not path: continue
        out.append( dict( file=lb.norm_path( path ), cls=( r.get( "class" ) or r.get( "class_name" ) or "" ),
                          func=( r.get( "function" ) or r.get( "function_name" ) or "" ),
                          line=r.get( "line" ) or r.get( "line_number" ) ) )
    return out

def gold_from_mulocbench_row( row ):
    # returns dict( files, classes:list[(file,cls)], funcs:list[(file,cls,func)], withheld_count,
    #               excluded_count, loctype:dict ) — NEW, no diff involved (design doc §1 point 1).
    in_scope = []
    for field in IN_SCOPE_LOC_FIELDS: in_scope.extend( _location_records( row, field ) )
    withheld_count = len( _location_records( row, WITHHELD_LOC_FIELD ) )
    excluded_count = len( _location_records( row, EXCLUDED_LOC_FIELD ) )
    files = sorted( { r["file"] for r in in_scope } )
    classes = sorted( { ( r["file"], r["cls"] ) for r in in_scope if r["cls"] } )
    funcs = sorted( { ( r["file"], r["cls"], r["func"] ) for r in in_scope if r["func"] } )
    loctype = row.get( "loctype" ) or {}   # SCHEMA-UNVERIFIED: assumed dict of category -> bool/count
    return dict( files=files, classes=classes, funcs=funcs, withheld_count=withheld_count,
                excluded_count=excluded_count, loctype=loctype )

def eligible( row ):
    # design doc §2.3, rules 1-4 (rule 5 — ass_file_loc withheld-not-dropped — is handled by
    # gold_from_mulocbench_row returning it separately, not here).
    title = ( row.get( "title" ) or "" ).strip()
    body = ( row.get( "body" ) or "" ).strip()
    query = " ".join( ( title + "\n" + body ).split() )
    if not query or len( query.split() ) < 4: return None, "issue_too_short"
    if cb.LOCAL_PATH_RE.search( query ): return None, "embedded_local_path"
    if not ( row.get( "pr_html_url" ) or row.get( "commit_html_url" ) ): return None, "no_resolution_reference"
    if not row.get( "base_commit" ): return None, "no_base_commit"
    gold = gold_from_mulocbench_row( row )
    if not gold["files"]: return None, "other_repo_only"   # only other_rep_loc/ass_file_loc gold, or none
    return gold, "kept"

# ── NEW: class-level ranking (neither run_locbench nor run_multiswe has ever scored this granularity).
#    Takes candidates from lb.parse_candidates(...) — its `kind=` field is what makes this possible.
def class_ranks( candidates, gold_classes ):
    # First candidate that IS the class itself (kind="cls"/"struct", name == class), else the
    # best-ranked member whose canonical id scope names the class (id contains "::<Class>::"). Flat
    # global rank, same convention lb.func_ranks uses for functions.
    out = []
    for gf, gc in gold_classes:
        ngf = lb.norm_path( gf ); r = None
        for i, c in enumerate( candidates ):
            if c["path"] != ngf: continue
            if c["kind"] in ( "cls", "struct" ) and c["name"] == gc:
                r = i; break
            if f"::{gc}::" in c["canon"]:
                if r is None: r = i   # keep scanning — an exact class-def row still wins if seen later
        out.append( r )
    return out

# ── NEW: per-issue F1 (design doc §2.2 — k fixed at 5, matching the paper's reported F1@5; an issue
#    with an empty gold set at this granularity is EXCLUDED from the average, never scored 0 or 1) ──
def f1_at( ranks, k ):
    if not ranks: return None   # empty gold set at this granularity — caller excludes from the average
    tp = sum( 1 for r in ranks if r is not None and r < k )
    fn = len( ranks ) - tp
    fp = max( 0, k - tp )   # predicted-but-not-gold, bounded by k — see design doc §2.2 for the two
                            # convention choices this line fixes; NOT yet confirmed against the paper.
    precision = tp / ( tp + fp ) if ( tp + fp ) else 0.0
    recall = tp / ( tp + fn ) if ( tp + fn ) else 0.0
    return 0.0 if ( precision + recall ) == 0 else 2 * precision * recall / ( precision + recall )

# ── arms (design doc §2.1) ───────────────────────────────────────────────────────────────────────────
ARMS = ( "for", "for-no-mention", "for-no-docmention", "query" )
def arm_flags_and_env( arm, query, top_k ):
    env = dict( os.environ )
    if arm == "for":                return [ f"--for={query}", f"--top-k={top_k}" ], env
    if arm == "for-no-mention":      return [ f"--for={query}", "--no-mention-boost", f"--top-k={top_k}" ], env
    if arm == "for-no-docmention":
        env = dict( env ); env["RIPWIRE_NO_DOC_MENTION"] = "1"
        return [ f"--for={query}", f"--top-k={top_k}" ], env
    if arm == "query":               return [ f"--query={query}", f"--top-k={top_k}" ], env
    raise ValueError( arm )

def main():
    ap = argparse.ArgumentParser( description="UNTESTED MULocBench adapter skeleton — see "
                                              "docs/research/mulocbench-baseline.md before running anything" )
    ap.add_argument( "--raw-jsonl", required=True, help="local JSONL of MULocBench rows, already fetched "
                     "by the OWNER via $ORCH/sim/mulocbench/1_fetch_rows.sh — this script never fetches it" )
    ap.add_argument( "--dataset-lock", default=str( HERE / "dataset.lock" ) )
    ap.add_argument( "--work-dir", required=True )
    ap.add_argument( "--top-k", type=int, default=200 )
    ap.add_argument( "--arms", default=",".join( ARMS ) )
    ap.add_argument( "--max-instances", type=int, default=0 )
    a = ap.parse_args()
    raise SystemExit(
        "run_mulocbench.py is a design-time skeleton (docs/research/mulocbench-baseline.md) — mining, "
        "checkout, and scoring wiring against real MULocBench rows have not been written or run yet. "
        "This refusal is deliberate (zero-silent-skip contract: an unfinished harness must say so loudly, "
        "never pretend to score). Extend main() once bench-assets/mulocbench/datasets/mulocbench_rows.jsonl "
        "exists and gold_from_mulocbench_row()'s field-name assumptions are checked against one real row." )

if __name__ == "__main__":
    sys.exit( main() )
