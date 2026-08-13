#!/usr/bin/env python3
"""Held-out command-routing evaluator: precision, harm, specificity, and coverage stay separate."""

from __future__ import annotations

import argparse
import csv
import subprocess
import tempfile
import xml.etree.ElementTree as ET
from pathlib import Path


def run(cmd: list[str], cwd: Path | None = None) -> subprocess.CompletedProcess[str]:
    return subprocess.run(cmd, cwd=cwd, text=True, stdout=subprocess.PIPE, stderr=subprocess.PIPE, check=False)


def make_repo(base: Path) -> Path:
    repo = base / "route-eval-repo"
    repo.mkdir()
    run(["git", "init", "-q"], repo)
    run(["git", "config", "user.email", "ripwire@example.invalid"], repo)
    run(["git", "config", "user.name", "ripwire-eval"], repo)
    (repo / "router.cpp").write_text(
        """int alphaNode() { return 1; }
int betaNode() { return alphaNode(); }
int gammaNode() { return betaNode(); }
int targetSymbol() { return gammaNode(); }
int CacheNode() { return targetSymbol(); }
int HttpClient() { return CacheNode(); }
int StorageDriver() { return HttpClient(); }
int parseConfigValue() { return StorageDriver(); }
int renderXmlRow() { return parseConfigValue(); }
int sendRequest() { return renderXmlRow(); }
int cacheValue() { return sendRequest(); }
""",
        encoding="utf-8",
    )
    run(["git", "add", "router.cpp"], repo)
    run(["git", "commit", "-qm", "base"], repo)
    return repo


def set_state(repo: Path, dirty: bool) -> None:
    run(["git", "restore", "router.cpp"], repo)
    if dirty:
        with (repo / "router.cpp").open("a", encoding="utf-8") as out:
            out.write("\n// dirty route fixture\n")


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--bin", required=True, type=Path)
    parser.add_argument("--corpus", required=True, type=Path)
    parser.add_argument("--split", choices=("test", "dev", "all"), default="test")
    args = parser.parse_args()
    binary = args.bin.resolve()

    with args.corpus.open(encoding="utf-8", newline="") as src:
        rows = list(csv.DictReader(src, delimiter="\t"))
    if args.split != "all":
        rows = [row for row in rows if row["split"] == args.split]

    total = correct = recommended = recommended_correct = harmful = 0
    actionable = actionable_recommended = negatives = negative_abstained = 0
    confusion: dict[tuple[str, str], int] = {}
    with tempfile.TemporaryDirectory(prefix="ripwire-taskroute-") as temp:
        repo = make_repo(Path(temp))
        for row in rows:
            set_state(repo, row["state"] == "dirty")
            prompt = row["prompt"].replace("\\n", "\n")
            proc = run([str(binary), str(repo), "--no-cache", f"--help-task={prompt}"])
            if proc.returncode != 0:
                got = f"exit-{proc.returncode}"
                status = "error"
            else:
                root = ET.fromstring(proc.stdout)
                status = root.attrib["status"]
                choice = root.find("choice")
                got = choice.attrib["intent"] if choice is not None and status == "recommend" else status

            expected = set(row["permitted"].split(";"))
            is_negative = expected == {"abstain"}
            is_correct = (status == "abstain") if is_negative else (status == "recommend" and got in expected)
            total += 1
            correct += int(is_correct)
            confusion[(row["permitted"], got)] = confusion.get((row["permitted"], got), 0) + 1
            if is_negative:
                negatives += 1
                negative_abstained += int(status == "abstain")
            else:
                actionable += 1
                actionable_recommended += int(status == "recommend")
            if status == "recommend":
                recommended += 1
                recommended_correct += int(is_correct)
                harmful += int(not is_correct)

    precision = recommended_correct / recommended if recommended else 0.0
    harm = harmful / total if total else 1.0
    specificity = negative_abstained / negatives if negatives else 0.0
    coverage = actionable_recommended / actionable if actionable else 0.0
    accuracy = correct / total if total else 0.0
    print(f"taskroute-eval split={args.split} rows={total} accuracy={accuracy:.3f} precision={precision:.3f} "
          f"harmful={harm:.3f} negative_specificity={specificity:.3f} coverage={coverage:.3f}")
    for (want, got), count in sorted(confusion.items()):
        if want != got:
            print(f"  confusion want={want} got={got} n={count}")

    return 0 if precision >= 0.90 and harm <= 0.02 and specificity >= 0.90 else 1


if __name__ == "__main__":
    raise SystemExit(main())
