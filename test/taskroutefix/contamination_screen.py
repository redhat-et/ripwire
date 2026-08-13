#!/usr/bin/env python3
"""Contamination screen + held-out split seal for test/taskroutefix/prompts.tsv.

The 2b-round method: a routing fixture is self-quotation if its prompts reuse the intent
cards' own vocabulary, so every HANDWRITTEN prompt's lowercased word-trigrams are flagged
when the same trigram occurs inside either reference corpus:
  (a) any double-quoted string literal in src/taskroute.h (the intent cards), or
  (b) the --help blocks of the 8 recommended verbs (--verify --connect --expand
      --from-trace --situ --pack-task --exemplar --for), read from the live binary.

Exempt as STRUCTURED SHAPE, not vocabulary (the machine or the claim grammar wrote them,
never the fixture author — surrounding prose is still screened):
  - closed claim expressions: calls(...) uses(...) unused(...) contains(...) defines(...) reaches(...)
  - the eval fixture repo's symbol names (make_repo in bench/taskroute_eval.py)
  - machine-emitted trace marker lines: sanitizer headers, the python traceback header,
    `File "..."` frames, and `#N 0x... in sym file:line` frames

Split seal (assigned BEFORE any scoring run, reproducible from content alone):
  sha256(prompt cell utf-8, exactly as stored in the TSV, escapes included);
  first digest byte < 0x4D -> dev, else test (~30/70).
Templated rows are pinned split=dev by the provenance rule (they are the contaminated
artifact and may not count toward held-out floors).

Modes:
  default        screen + verify splits + print the corpus seal; exit 0 clean, 1 dirty
  --print-splits print the hash-rule split per handwritten row and exit 0
"""

from __future__ import annotations

import hashlib
import re
import subprocess
import sys
from pathlib import Path

HERE = Path(__file__).resolve().parent
ROOT = HERE.parents[1]
TSV = HERE / "prompts.tsv"
CARDS = ROOT / "src" / "taskroute.h"

RECOMMENDED_FLAGS = ("--verify", "--connect", "--expand", "--from-trace", "--situ", "--pack-task", "--exemplar", "--for")
FIXTURE_SYMBOLS = ("alphaNode", "betaNode", "gammaNode", "targetSymbol", "CacheNode", "HttpClient",
                   "StorageDriver", "parseConfigValue", "renderXmlRow", "sendRequest", "cacheValue")
CLAIM_RE = re.compile(r"\b(?:calls|uses|unused|contains|defines|reaches)\s*\([^)]*\)")
TRACE_LINE_RES = (
    re.compile(r"^\s*#\d+\s+0x", re.IGNORECASE),
    re.compile(r"sanitizer:", re.IGNORECASE),
    re.compile(r"traceback \(most recent call last\)", re.IGNORECASE),
    re.compile(r'^\s*file "', re.IGNORECASE),
)
FLAG_LINE_RE = re.compile(r"^\s*(" + "|".join(re.escape(f) for f in RECOMMENDED_FLAGS) + r")(=|\[|\s|$)")


def words(text: str) -> list[str]:
    return re.findall(r"[a-z0-9]+", text.lower())


def trigrams(text: str) -> set[tuple[str, str, str]]:
    toks = words(text)
    return {(toks[i], toks[i + 1], toks[i + 2]) for i in range(len(toks) - 2)}


def card_literals() -> list[str]:
    source = CARDS.read_text(encoding="utf-8")
    return [m.group(1) for m in re.finditer(r'"((?:[^"\\]|\\.)*)"', source)]


def help_blocks(binary: Path) -> list[str]:
    proc = subprocess.run([str(binary), "--help"], text=True, stdout=subprocess.PIPE, stderr=subprocess.STDOUT, check=False)
    blocks: list[str] = []
    current: list[str] = []
    for line in proc.stdout.splitlines():
        stripped = line.lstrip()
        if FLAG_LINE_RE.match(line):
            if current:
                blocks.append("\n".join(current))
            current = [line]
        elif current and stripped and not stripped.startswith("--") and line.startswith(" " * 8):
            current.append(line)
        else:
            if current:
                blocks.append("\n".join(current))
            current = []
    if current:
        blocks.append("\n".join(current))
    return blocks


def strip_exempt(prompt: str) -> str:
    text = CLAIM_RE.sub(" ", prompt.replace("\\n", "\n"))
    for symbol in FIXTURE_SYMBOLS:
        text = text.replace(symbol, " ")
    kept = [line for line in text.split("\n") if not any(rx.search(line) for rx in TRACE_LINE_RES)]
    return "\n".join(kept)


def split_for(prompt_cell: str) -> str:
    return "dev" if hashlib.sha256(prompt_cell.encode("utf-8")).digest()[0] < 0x4D else "test"


def load_rows() -> tuple[list[str], list[dict[str, str]]]:
    lines = TSV.read_text(encoding="utf-8").splitlines()
    header = lines[0].split("\t")
    rows = [dict(zip(header, line.split("\t"))) for line in lines[1:] if line]
    return header, rows


def main() -> int:
    header, rows = load_rows()
    for column in ("split", "state", "permitted", "provenance", "prompt"):
        if column not in header:
            print(f"missing column: {column}")
            return 1
    handwritten = [(index + 2, row) for index, row in enumerate(rows) if row["provenance"].startswith("handwritten")]

    if "--print-splits" in sys.argv[1:]:
        for line_no, row in handwritten:
            print(f"line {line_no}\t{split_for(row['prompt'])}\t{row['prompt']}")
        return 0

    binary = Path(sys.argv[sys.argv.index("--bin") + 1]) if "--bin" in sys.argv else ROOT / "build" / "ripwire"
    reference: set[tuple[str, str, str]] = set()
    for literal in card_literals():
        reference |= trigrams(literal)
    for block in help_blocks(binary):
        reference |= trigrams(block)
    if not reference:
        print("reference corpus came back empty — refusing to declare a clean screen")
        return 1

    dirty = False
    for line_no, row in handwritten:
        hits = trigrams(strip_exempt(row["prompt"])) & reference
        for hit in sorted(hits):
            print(f"FLAGGED line {line_no}: trigram {' '.join(hit)!r} :: {row['prompt']}")
            dirty = True
        want = split_for(row["prompt"])
        if row["split"] != want:
            print(f"SPLIT MISMATCH line {line_no}: split={row['split']} hash-rule={want} :: {row['prompt']}")
            dirty = True
    for line_no, row in ((i + 2, r) for i, r in enumerate(rows) if r["provenance"] == "templated"):
        if row["split"] != "dev":
            print(f"TEMPLATED ROW NOT PINNED TO dev at line {line_no}: {row['prompt']}")
            dirty = True

    counts = {"handwritten": len(handwritten), "templated": len(rows) - len(handwritten),
              "test": sum(1 for r in rows if r["split"] == "test"), "dev": sum(1 for r in rows if r["split"] == "dev")}
    seal = hashlib.sha256(TSV.read_bytes()).hexdigest()
    print(f"rows={len(rows)} {counts} reference_trigrams={len(reference)}")
    print(("SCREEN DIRTY" if dirty else "SCREEN CLEAN") + f" seal sha256(prompts.tsv)={seal}")
    return 1 if dirty else 0


if __name__ == "__main__":
    raise SystemExit(main())
