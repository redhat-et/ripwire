#!/usr/bin/env python3
"""r3-headroom head-to-head harness. ONE metric implementation, called from every arm.

Arms:
  A  naive: grep -rn + whole-file reads until the answer criterion is satisfied
  B  A's transcript compressed by headroom compress() with DEFAULT config
  Bp same with the labeled non-default override (protect_analysis_context=False, protect_recent=0)
  C  ripwire verb ladder per pre-registered category spec (warm index)
  D  C's transcript through headroom compress() default (composition check)

Metric 1 tokens-to-correct-answer: tiktoken cl100k_base over the text an arm emitted
         until (all gold_files present as substrings) AND (all gold_symbols present).
Metric 2 gold survival (B/Bp): retained / recoverable-via-CCR-marker / lost.
         recoverable is charged marker + FULL original chunk (CCR retrieve returns the original).
         lost is charged a re-read of the original chunk (the miss message says re-read the file)
         and flagged.
Metric 3 wall time: median of N_TIMING runs per command.
Metric 4 determinism: byte-identity of two runs (both tools).

Run with the hrenv venv python. Env for headroom set in run_all.sh.
"""

import json
import os
import re
import statistics
import subprocess
import sys
import time
from pathlib import Path

HERE = Path(__file__).resolve().parent
CORPUS = Path(
    "/private/tmp/claude-501/-Users-qgames-AppDevelopLocal-project2-ripwire/"
    "8ebe7d31-1cf3-4a60-aa6c-cafea943c4df/scratchpad/repos/django__django"
)
RIPWIRE = Path("/Users/qgames/AppDevelopLocal/project2/ripwire/build/ripwire")
N_TIMING = 5
NAIVE_FILE_CAP = 15  # idealized-naive stops after this many whole-file reads per grep term

import tiktoken

ENC = tiktoken.get_encoding("cl100k_base")


def tokens(text: str) -> int:
    return len(ENC.encode(text, disallowed_special=()))


# ---------------------------------------------------------------- answer criterion


def _sym_present(emitted: str, name: str) -> bool:
    return re.search(r"\b" + re.escape(name) + r"\b", emitted) is not None


def satisfied(emitted: str, q: dict) -> bool:
    return not gold_missing(emitted, q)


def gold_missing(emitted: str, q: dict) -> list[str]:
    """gold_files: every path must appear (substring). gold_symbols: every name must
    appear on a word boundary. gold_any: each OR-group needs at least one member."""
    missing = [f for f in q["gold_files"] if f not in emitted]
    missing += [s for s in q["gold_symbols"] if not _sym_present(emitted, s)]
    for group in q.get("gold_any", []):
        if not any(_sym_present(emitted, s) for s in group):
            missing.append("any-of:" + "|".join(group))
    return missing


# ---------------------------------------------------------------- command running


def run_cmd(argv: list[str], cwd: Path | None = None) -> tuple[str, float]:
    t0 = time.perf_counter()
    p = subprocess.run(argv, capture_output=True, text=True, cwd=cwd, timeout=600)
    dt = time.perf_counter() - t0
    return (p.stdout + (p.stderr if p.returncode != 0 else ""), dt)


def timed_median(argv: list[str], cwd: Path | None = None) -> float:
    times = []
    for _ in range(N_TIMING):
        _, dt = run_cmd(argv, cwd)
        times.append(dt)
    return statistics.median(times)


# ---------------------------------------------------------------- arm A: naive


def arm_naive(q: dict) -> dict:
    """Idealized grep-first agent, rule fixed here:
    for each pre-registered term in order: emit full `grep -rn --include=*.py` output;
    then read whole files in order of first appearance in that output (cap NAIVE_FILE_CAP),
    stopping the moment the criterion is satisfied."""
    chunks: list[dict] = []  # {label, text}
    emitted = ""
    wall = 0.0

    def emit(label: str, text: str):
        nonlocal emitted
        chunks.append({"label": label, "text": text})
        emitted += "\n" + text

    for term in q["naive_grep_terms"]:
        argv = ["grep", "-rnF", "--include=*.py", term, "."]
        out, dt = run_cmd(argv, cwd=CORPUS)
        wall += dt
        emit(f"grep:{term}", out)
        if satisfied(emitted, q):
            break
        seen: list[str] = []
        for line in out.splitlines():
            m = re.match(r"^\./([^:]+\.py):", line)
            if m and m.group(1) not in seen:
                seen.append(m.group(1))
        for rel in seen[:NAIVE_FILE_CAP]:
            fp = CORPUS / rel
            if not fp.is_file():
                continue
            t0 = time.perf_counter()
            body = fp.read_text(errors="replace")
            wall += time.perf_counter() - t0
            emit(f"read:{rel}", f"=== {rel} ===\n{body}")
            if satisfied(emitted, q):
                break
        if satisfied(emitted, q):
            break

    return {
        "arm": "A",
        "chunks": chunks,
        "tokens": tokens(emitted),
        "satisfied": satisfied(emitted, q),
        "missing": gold_missing(emitted, q),
        "wall_s": round(wall, 4),
        "n_chunks": len(chunks),
    }


# ---------------------------------------------------------------- arms B/Bp: headroom


def to_messages(q: dict, chunks: list[dict]) -> list[dict]:
    msgs = [{"role": "user", "content": q["question"]}]
    for c in chunks:
        msgs.append({"role": "tool", "content": f"[tool result {c['label']}]\n{c['text']}"})
    return msgs


MARKER_RE = re.compile(r"hash=[0-9a-f]{6,}|Retrieve more|compressed to|items compressed", re.I)


def arm_headroom(q: dict, chunks: list[dict], override: bool) -> dict:
    from headroom import compress
    from headroom.compress import CompressConfig

    msgs = to_messages(q, chunks)
    cfg = None
    if override:
        cfg = CompressConfig(protect_analysis_context=False, protect_recent=0)

    t0 = time.perf_counter()
    res = compress(msgs, model="claude-sonnet-4-5-20250929", config=cfg)
    dt = time.perf_counter() - t0

    # scoring text excludes the user question (verifier finding H1: the question can
    # carry gold tokens, e.g. a symbol named in the question, under-charging this arm)
    comp_text = "\n".join(str(m.get("content", "")) for m in res.messages[1:])
    comp_tokens = tokens("\n".join(str(m.get("content", "")) for m in res.messages))

    def present(g: str, text: str) -> bool:
        return (g in text) if g in q["gold_files"] else _sym_present(text, g)

    # gold survival per original chunk (H2: same boundary rule as the criterion)
    survival = []
    charged = comp_tokens
    for c in chunks:
        lost_items = [
            g
            for g in (q["gold_files"] + q["gold_symbols"])
            if present(g, c["text"]) and not present(g, comp_text)
        ]
        if not lost_items:
            survival.append({"label": c["label"], "state": "retained"})
            continue
        has_marker = bool(MARKER_RE.search(comp_text))
        state = "recoverable" if has_marker else "lost"
        # CCR retrieve (or forced re-read) returns the FULL original chunk
        charged += tokens(c["text"])
        survival.append({"label": c["label"], "state": state, "lost": lost_items})

    final_text = comp_text + "".join(
        c["text"] for c, s in zip(chunks, survival) if s["state"] != "retained"
    )
    return {
        "arm": "Bp" if override else "B",
        "hr_tokens_before": res.tokens_before,
        "hr_tokens_after": res.tokens_after,
        "hr_ratio": res.compression_ratio,
        "transforms": res.transforms_applied,
        "compressed_tokens": comp_tokens,
        "charged_tokens": charged,
        "satisfied": satisfied(final_text, q),
        "survival": [s for s in survival if s["state"] != "retained"] or "all-retained",
        "n_lost_chunks": sum(1 for s in survival if s["state"] == "lost"),
        "n_recoverable_chunks": sum(1 for s in survival if s["state"] == "recoverable"),
        "compress_wall_s": round(dt, 4),
    }


# ---------------------------------------------------------------- arm C: ripwire


TOP1_RE = re.compile(r'<d [^>]*?n="([^"]+)"')


def arm_ripwire(q: dict, spec: dict) -> dict:
    """spec['ladder'] = list of ripwire argv suffixes (after binary+corpus), pre-registered.
    Runs with cwd=CORPUS and dir '.' so paths are relative, matching the naive arm's grep
    output (the root-neutralisation discipline of docs/EVALS.md §5, applied equally).
    The literal rung ["EXPAND_TOP1"] is a pre-registered dynamic rule: --expand of the
    first-ranked row (first <d n="..."> occurrence) of the previous rung's output.
    Stops at the first rung that satisfies. All emitted output is counted."""
    chunks = []
    emitted = ""
    wall = 0.0
    base_out = ""  # output of the FIRST rung; all dynamic rules resolve against it
    for rung in spec["ladder"]:
        if rung == ["EXPAND_TOP1"]:
            m = TOP1_RE.search(base_out)
            if not m:
                continue
            rung = [f"--expand={m.group(1)}"]
        elif rung == ["PATH_TOP2"]:
            names = TOP1_RE.findall(base_out)[:2]
            if len(names) < 2:
                continue
            rung = [f"--path={names[0]},{names[1]}"]
        elif rung == ["CONNECT_TOP3"]:
            names = TOP1_RE.findall(base_out)[:3]
            if len(names) < 2:
                continue
            rung = ["--connect=" + ",".join(names)]
        elif rung == ["USES_RAISED_EXC"]:
            m = re.search(r"\braise\s+([A-Z]\w+)", base_out)
            if not m:
                continue
            rung = [f"--uses={m.group(1)}"]
        argv = [str(RIPWIRE), "."] + rung
        out, dt = run_cmd(argv, cwd=CORPUS)
        wall += dt
        if not base_out:
            base_out = out
        chunks.append({"label": " ".join(rung), "text": out})
        emitted += "\n" + out
        if satisfied(emitted, q):
            break
    return {
        "arm": "C",
        "chunks": chunks,
        "tokens": tokens(emitted),
        "satisfied": satisfied(emitted, q),
        "missing": gold_missing(emitted, q),
        "wall_s": round(wall, 4),
        "rungs_used": len(chunks),
        "ladder": [" ".join(r) for r in spec["ladder"][: len(chunks)]],
    }


# ---------------------------------------------------------------- main


def main():
    qs = json.loads((HERE / "questions.json").read_text())
    specs = json.loads((HERE / "arms_spec.json").read_text())
    results = []
    for q in qs:
        spec = specs[q["id"]]
        a = arm_naive(q)
        b = arm_headroom(q, a["chunks"], override=False)
        bp = arm_headroom(q, a["chunks"], override=True)
        c = arm_ripwire(q, spec)
        d = arm_headroom(q, c["chunks"], override=False)
        for r in (a, c):
            r.pop("chunks")
        results.append({"id": q["id"], "category": q["category"], "A": a, "B": b, "Bp": bp, "C": c, "D": d})
        print(
            f"{q['id']} A={a['tokens']}t({'ok' if a['satisfied'] else 'MISS'}) "
            f"B={b['charged_tokens']}t B'={bp['charged_tokens']}t "
            f"C={c['tokens']}t({'ok' if c['satisfied'] else 'MISS'}) "
            f"D={d['charged_tokens']}t",
            flush=True,
        )
    (HERE / "results.json").write_text(json.dumps(results, indent=1))
    print("wrote", HERE / "results.json")


if __name__ == "__main__":
    main()
