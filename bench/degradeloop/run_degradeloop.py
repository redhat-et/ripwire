#!/usr/bin/env python3
"""run_degradeloop.py — orchestrates one arm of the iterative-improvement loop for one seed task.

UNTESTED. Scaffolding for docs/research/gate-vs-iterative-degradation.md §2.1/§2.4. Nobody has
run this — call_model() below raises NotImplementedError on purpose rather than faking a call
site that looks wired up. Filling that one function in is the only thing standing between this
script and a real run; everything else (git bookkeeping, measurement calls, trajectory recording)
is written to work once it is.

USAGE (once call_model() is implemented and RIPWIRE_BIN is set, per README.md):
    python3 run_degradeloop.py \\
        --seed-dir /path/to/seed/task/checkout \\
        --arm gated \\
        --iterations 10 \\
        --model-name "<name>" --model-version "<date/version>" \\
        --out trajectory_seed1_gated.jsonl

Arms (design doc §2.1/§2.4): ungated | gated | neutral-control | wrong-target. "wrong-target"
needs --wrong-target-report pointing at a previously recorded --quality-delta JSON report from a
DIFFERENT seed task, per the design doc's arm D.
"""

from __future__ import annotations

import argparse
import json
import shutil
import subprocess
import sys
import tempfile
import time
from pathlib import Path

import measure


IMPROVE_PROMPT = "Improve this code."   # deliberately the paper's own minimal prompt — see design doc §2.1


def call_model( prompt: str, current_code: str, *, model_name: str, model_version: str ) -> str:
    """THE seam. Takes a prompt and the current state of the seed task's code, returns the model's
    proposed new code. This is the only function in bench/degradeloop that this scaffolding does
    not and cannot implement — it needs real model access, which this environment does not have
    (see the design doc §2.6: "no model calls were made to produce this document").

    Contract for whoever fills this in: (1) deterministic sampling settings (fixed seed/temperature
    if the API supports it) recorded in the trajectory header, not just in code comments here —
    see main()'s header-writing below; (2) the SAME model_name/model_version across every arm and
    every iteration of one seed task's comparison, or the arms are not comparable; (3) return the
    FULL new code, not a diff — the measurement layer re-ingests the whole tree each iteration.
    """
    raise NotImplementedError(
        "call_model() is the one unimplemented seam in this harness — wire it to a real model "
        "before running. See this function's docstring and README.md."
    )


def build_prompt( arm: str, base_prompt: str, previous_report: dict | None, wrong_target_report: dict | None ) -> str:
    """Assemble the per-iteration prompt for the given arm. See design doc §2.1 (loop shape) and
    §2.4 (the neutral-text / wrong-target confound controls) for why each arm's prompt looks the
    way it does — this function is the literal implementation of that section, not a paraphrase of
    it, so a change here should be a change there too."""
    if arm == "ungated":
        return base_prompt
    if arm == "gated":
        if previous_report is None:
            return base_prompt   # iteration 1 has no prior report yet
        return (
            base_prompt
            + "\n\nThe deterministic quality gate reports the following about your PREVIOUS change "
              "to this code. Address what you can before proposing the next change:\n\n"
            + json.dumps( previous_report, indent=2 )
        )
    if arm == "neutral-control":
        # Matched-LENGTH neutral text, not matched-content — see design doc §2.4 arm C. Using the
        # tool's own --legend text (long, dense, describes the checker rather than this code) as
        # the filler is the design doc's suggestion; swap in whatever's pinned for the actual run.
        filler = _neutral_filler_text()
        return base_prompt + "\n\n" + filler
    if arm == "wrong-target":
        if wrong_target_report is None:
            raise ValueError( "arm=wrong-target requires --wrong-target-report" )
        return (
            base_prompt
            + "\n\nA deterministic quality gate reports the following (NOTE: about a DIFFERENT "
              "codebase, used here only as a matched-content control — see design doc §2.4 arm D):\n\n"
            + json.dumps( wrong_target_report, indent=2 )
        )
    raise ValueError( f"unknown arm {arm!r}" )


def _neutral_filler_text() -> str:
    """Returns the matched-length filler text for the neutral-control arm. Placeholder: a real run
    should call `ripwire --quality-delta --legend` (or any fixed, task-irrelevant, roughly
    report-length text) ONCE per run and reuse it, rather than regenerating it per iteration — the
    text must be IDENTICAL across iterations and across seed tasks within the control arm, or the
    control stops controlling for length and starts introducing its own variable content."""
    raise NotImplementedError(
        "pin a fixed neutral-text block before running the neutral-control arm — see design doc §2.4."
    )


def run_arm(
    seed_dir: Path,
    arm: str,
    iterations: int,
    model_name: str,
    model_version: str,
    wrong_target_report_path: Path | None,
) -> list[dict]:
    """Runs `iterations` rounds of the loop for one seed task under one arm, in a scratch git
    clone of seed_dir (never the original — see the warning in main()). Returns the list of
    per-iteration trajectory rows; does not write them (main() does, so a caller composing several
    arms in one process can hold them all before writing)."""
    scratch = Path( tempfile.mkdtemp( prefix=f"degradeloop-{arm}-" ) )
    tree = scratch / "tree"
    shutil.copytree( seed_dir, tree )
    subprocess.run( [ "git", "-C", str( tree ), "init", "-q" ], check=True )
    subprocess.run( [ "git", "-C", str( tree ), "add", "-A" ], check=True )
    subprocess.run(
        [ "git", "-C", str( tree ), "-c", "user.name=degradeloop", "-c", "user.email=degradeloop@invalid",
          "commit", "-q", "-m", "seed" ],
        check=True,
    )
    baseline_ref = subprocess.run(
        [ "git", "-C", str( tree ), "rev-parse", "HEAD" ], check=True, capture_output=True, text=True
    ).stdout.strip()

    wrong_target_report = None
    if wrong_target_report_path is not None:
        wrong_target_report = json.loads( wrong_target_report_path.read_text() )

    rows: list[dict] = []
    previous_report: dict | None = None
    current_code_dir = tree

    for i in range( 1, iterations + 1 ):
        prompt = build_prompt( arm, IMPROVE_PROMPT, previous_report, wrong_target_report )

        # NOTE: single-file-tree simplification. A real seed task with many files needs a real
        # (prompt, tree) -> tree contract instead of (prompt, one code string) -> one code string;
        # this scaffolding assumes call_model operates over a concatenated or single-entry-point
        # representation and that whoever implements call_model() handles multi-file state. Left
        # simple on purpose rather than guessing a serialization format nobody has asked for yet.
        current_code = "\n".join( p.read_text() for p in sorted( current_code_dir.rglob( "*" ) ) if p.is_file() )
        new_code = call_model( prompt, current_code, model_name=model_name, model_version=model_version )
        # Caller-side responsibility once call_model is real: write new_code back into tree,
        # respecting whatever multi-file contract was chosen above, before the commit below.
        raise NotImplementedError(
            "run_arm() cannot proceed past the first call_model() call in this environment — "
            "this RuntimeError is expected until call_model() and the write-back step are filled in."
        )

    return rows   # unreachable until the seam above is implemented; kept for the intended shape


def main() -> int:
    ap = argparse.ArgumentParser( description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter )
    ap.add_argument( "--seed-dir", required=True, type=Path, help="checkout of the seed task's starting code" )
    ap.add_argument( "--arm", required=True, choices=[ "ungated", "gated", "neutral-control", "wrong-target" ] )
    ap.add_argument( "--iterations", required=True, type=int )
    ap.add_argument( "--model-name", required=True )
    ap.add_argument( "--model-version", required=True, help="date or version string — recorded, not validated" )
    ap.add_argument( "--wrong-target-report", type=Path, default=None,
                      help="required for --arm=wrong-target; a --quality-delta --json report from a DIFFERENT seed task" )
    ap.add_argument( "--out", required=True, type=Path )
    args = ap.parse_args()

    if not args.seed_dir.is_dir():
        print( f"error: --seed-dir {args.seed_dir} is not a directory", file=sys.stderr )
        return 1
    print(
        "WARNING: this harness is scaffolding and has never been run end to end. "
        "call_model() will raise NotImplementedError. See README.md.",
        file=sys.stderr,
    )

    header = {
        "kind": "degradeloop-trajectory-header",
        "arm": args.arm,
        "seed_dir": str( args.seed_dir ),
        "iterations_requested": args.iterations,
        "model_name": args.model_name,
        "model_version": args.model_version,
        "recorded_at_unix": int( time.time() ),
        "ripwire_bin": measure._resolve_ripwire_bin(),   # fails fast if RIPWIRE_BIN unset — intentional
    }

    try:
        rows = run_arm(
            args.seed_dir, args.arm, args.iterations, args.model_name, args.model_version,
            args.wrong_target_report,
        )
    except NotImplementedError as e:
        print( f"stopped (expected, scaffolding-only): {e}", file=sys.stderr )
        return 2

    with args.out.open( "w" ) as f:
        f.write( json.dumps( header ) + "\n" )
        for row in rows:
            f.write( json.dumps( row ) + "\n" )
    return 0


if __name__ == "__main__":
    sys.exit( main() )
