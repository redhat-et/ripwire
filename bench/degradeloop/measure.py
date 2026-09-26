#!/usr/bin/env python3
"""measure.py — deterministic per-iteration measurement layer for bench/degradeloop.

UNTESTED. Written alongside docs/research/gate-vs-iterative-degradation.md as scaffolding for
whoever runs the actual harness; no function in this file has been exercised against a real
ripwire binary or a real code tree. Read the design doc (../../docs/research/
gate-vs-iterative-degradation.md, sections 2.2 and 2.3) before changing what gets measured —
these functions exist to implement that section, not the other way around.

WHAT THIS DOES. Wraps two ripwire verbs as subprocess calls against a scratch working tree
(--quality-delta --json, --test-gate --json), both of which docs/COMMANDS.md's --json entry
confirms are on the JSON allow-list with keys mirroring the XML attribute names 1:1. Also holds
an unimplemented seam for a public security scanner (run_security_scanner) — deliberately not
guessed at here; see the design doc's "what we'd like help with" for why the choice is left open.

WHAT THIS DOES NOT DO. It does not interpret a --quality-delta exit code as "a real defect was
introduced." The design doc's Part 1 section 7 backtests --quality-delta against this project's
own commit history and finds it behaves as a debt ratchet (58% recall vs 40% false-alarm rate at
a 5-commit window) rather than a defect detector. Every function here reports counts, not
verdicts, and the analysis layer (analyze_trajectory.py) is responsible for any claim built on
top of them.
"""

from __future__ import annotations

import json
import os
import subprocess
import sys
from dataclasses import dataclass, field


def _resolve_ripwire_bin() -> str:
    """Refuse to fall back to a bare 'ripwire' on PATH — a stale system install would silently
    produce numbers from a different binary than the one the run's metadata claims. RIPWIRE_BIN
    must be set explicitly to a real build/ripwire; see README.md "before running any of this"."""
    bin_path = os.environ.get( "RIPWIRE_BIN" )
    if not bin_path:
        raise RuntimeError(
            "RIPWIRE_BIN is not set. Point it at a build/ripwire built from this repository's "
            "CLAUDE.md instructions — measure.py will not guess at a PATH install."
        )
    if not os.path.isfile( bin_path ) or not os.access( bin_path, os.X_OK ):
        raise RuntimeError( f"RIPWIRE_BIN={bin_path!r} is not an executable file." )
    return bin_path


def _run_ripwire_json( tree_dir: str, *verb_args: str ) -> dict:
    """Run one ripwire verb with --json against tree_dir and parse the result. Raises on a
    nonzero-but-unexpected exit rather than silently returning an empty dict — --quality-delta and
    --test-gate both use exit codes as part of their contract (exit 2 / exit 4 respectively are
    expected "gating" outcomes, not errors), so this only raises on exit codes neither verb
    documents (see docs/COMMANDS.md for the documented exit-code contract of each verb before
    changing the accepted set below)."""
    binp = _resolve_ripwire_bin()
    cmd = [ binp, tree_dir, *verb_args, "--json" ]
    proc = subprocess.run( cmd, capture_output=True, text=True )
    # --quality-delta: exit 0 (clean) or exit 2 (gating regressions). --test-gate: exit 0 or exit 4.
    if proc.returncode not in ( 0, 2, 4 ):
        raise RuntimeError(
            f"unexpected exit {proc.returncode} from {cmd!r}\nstdout={proc.stdout!r}\nstderr={proc.stderr!r}"
        )
    if not proc.stdout.strip():
        # An empty stdout on a documented-refusal exit path (see --json's ALLOW-list refusal
        # shape in docs/COMMANDS.md) is a real outcome, not a parse failure — but the caller needs
        # to know, so this is surfaced rather than coerced into {}.
        raise RuntimeError( f"empty stdout from {cmd!r} (exit {proc.returncode}); stderr={proc.stderr!r}" )
    return json.loads( proc.stdout )


@dataclass
class QualityDeltaSnapshot:
    """One --quality-delta --json reading, trimmed to the fields the design doc's instruments
    need. Field names mirror the XML attribute spellings from docs/COMMANDS.md's --quality-delta
    section verbatim (including the hyphens, carried as dict-style access below) rather than
    renaming them into Python convention — a mismatch between this dataclass and a future
    --quality-delta output change should be loud, not silently absorbed by a renamed field."""

    regressions: int
    gating: int
    minor: int
    acked: int
    per_kind_gating: dict = field( default_factory=dict )   # kind -> count, computed from the row list
    raw: dict = field( default_factory=dict )                # the full parsed JSON, for anything not modeled above


def measure_quality_delta( tree_dir: str, baseline_ref: str | None = None ) -> QualityDeltaSnapshot:
    """One snapshot of the ten kinds against tree_dir.

    baseline_ref, if given, is passed as --quality-delta=<ref>..HEAD (the ref-pair form) so the
    design doc's section 2.2 instruction — measure against the FIXED seed-state baseline, not
    against the previous iteration — can be honored without needing a .ripwire_quality_baseline
    sidecar dance on every iteration. If None, measures the bare working-tree-vs-HEAD form.
    """
    args = [ f"--quality-delta={baseline_ref}..HEAD" ] if baseline_ref else [ "--quality-delta" ]
    data = _run_ripwire_json( tree_dir, *args )
    # The JSON root mirrors the XML root's attributes; per-kind breakdown rides on the row list,
    # not the root, so it's folded here rather than assumed present at the top level.
    per_kind: dict = {}
    for row in data.get( "regressions_detail", data.get( "rows", [] ) ):
        k = row.get( "kind" )
        if k:
            per_kind[ k ] = per_kind.get( k, 0 ) + 1
    return QualityDeltaSnapshot(
        regressions=int( data.get( "regressions", 0 ) ),
        gating=int( data.get( "gating", 0 ) ),
        minor=int( data.get( "minor", 0 ) ),
        acked=int( data.get( "acked", 0 ) ),
        per_kind_gating=per_kind,
        raw=data,
    )


@dataclass
class TestGateSnapshot:
    tests: int
    untested: int
    raw: dict = field( default_factory=dict )


def measure_test_gate( tree_dir: str ) -> TestGateSnapshot:
    """--test-gate --json against the working tree (default = git diff, per docs/COMMANDS.md)."""
    data = _run_ripwire_json( tree_dir, "--test-gate" )
    return TestGateSnapshot(
        tests=int( data.get( "tests", 0 ) ),
        untested=int( data.get( "untested", 0 ) ),
        raw=data,
    )


def measure_subbar_growth( tree_dir: str, baseline_ref: str ) -> dict:
    """The design doc's §2.2/§2.3 instrument 3: raw ccx/LOC/nest/params growth per touched symbol,
    regardless of whether any single step crossed a --quality-delta bar. NOT part of
    --quality-delta's own reported kinds (which only fire on a bar crossing or, above the bar, a
    material-growth threshold — see src/quality.h's kMaterialGrowthPct/kSubBarGrowthPct) — this is
    exactly the accumulation a bar-gated report can be blind to, which is why the design doc treats
    it as a separate instrument.

    UNIMPLEMENTED. Computing this needs the per-symbol raw metrics for both trees, which
    --quality-delta's own JSON does not expose below its minor/major-severity rows (deliberately —
    it reports regressions, not a full metrics dump). The two ways to get it: (a) --metrics --json
    on both trees and a symbol-identity join done here, matching quality.h's own canonId scheme
    (path::scope::name — see docs/COMMANDS.md's --quality-delta LIMIT clause on renamed/moved
    symbols), or (b) a small ripwire patch that exposes sub-bar deltas directly. Left unimplemented
    rather than approximated, because an approximated version of exactly the instrument meant to
    catch quiet accumulation would be worth less than nothing.
    """
    raise NotImplementedError(
        "sub-bar growth needs a --metrics-based symbol join (or a ripwire-side addition) that "
        "this scaffolding does not implement — see the docstring above before filling this in."
    )


def run_security_scanner( tree_dir: str, language: str ) -> dict:
    """UNIMPLEMENTED — placeholder for the public, deterministic security scanner named in the
    design doc's §2.2 ("Semgrep's default ruleset, or a language-appropriate equivalent"). Left
    unimplemented because the choice needs pinning (tool version + ruleset hash) per language
    before it means anything as an instrument — see docs/research/gate-vs-iterative-degradation.md
    "what we would like help with". A caller that needs this today should pin its own scanner
    invocation here rather than treating this function's absence as "no scanner was run" silently:
    call sites MUST check for NotImplementedError and record scanner_ran=false in the trajectory
    row rather than defaulting a finding count to 0 (a 0 here must never be mistaken for "clean").
    """
    raise NotImplementedError(
        f"no security scanner pinned yet for language={language!r} — see README.md before running."
    )


if __name__ == "__main__":
    print( __doc__, file=sys.stderr )
    sys.exit( 1 )
