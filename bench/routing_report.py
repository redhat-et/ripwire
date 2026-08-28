#!/usr/bin/env python3
"""Summarize privacy-safe Codex routing feedback without reading prompt text."""

from __future__ import annotations

import argparse
import json
import os
import sys
from collections import defaultdict
from pathlib import Path
from typing import Any


MIN_COMPLETED = 30


def load_rows(path: Path) -> tuple[list[dict[str, Any]], int]:
    rows: list[dict[str, Any]] = []
    invalid = 0
    with path.open(encoding="utf-8") as handle:
        for line in handle:
            try:
                row = json.loads(line)
            except (json.JSONDecodeError, UnicodeDecodeError):
                invalid += 1
                continue
            if isinstance(row, dict):
                rows.append(row)
            else:
                invalid += 1
    return rows, invalid


def ratio(numerator: int, denominator: int) -> float | None:
    return round(numerator / denominator, 6) if denominator else None


def summarize(rows: list[dict[str, Any]], invalid: int) -> dict[str, Any]:
    decisions = [row for row in rows if row.get("event") == "UserPromptSubmit"]
    finals = [row for row in rows if row.get("event") == "RouteObservation" and row.get("outcome") in {"adopted", "missed"}]
    adopted = sum(row.get("outcome") == "adopted" for row in finals)
    by_intent: dict[str, list[dict[str, Any]]] = defaultdict(list)
    for row in finals:
        by_intent[str(row.get("intent") or "unknown")].append(row)

    intents = []
    for intent in sorted(by_intent):
        intent_rows = by_intent[intent]
        intent_adopted = sum(row.get("outcome") == "adopted" for row in intent_rows)
        intents.append({
            "intent": intent,
            "completed": len(intent_rows),
            "adopted": intent_adopted,
            "missed": len(intent_rows) - intent_adopted,
            "adoption_rate": ratio(intent_adopted, len(intent_rows)),
        })

    completed = len(finals)
    return {
        "schema": "ripwire.routing-feedback/v1",
        "decisions": len(decisions),
        "recommendations": sum(row.get("status") == "recommend" for row in decisions),
        "abstentions": sum(row.get("status") == "abstain" for row in decisions),
        "completed": completed,
        "adopted": adopted,
        "missed": completed - adopted,
        "adoption_rate": ratio(adopted, completed),
        "minimum_completed": MIN_COMPLETED,
        "underpowered": completed < MIN_COMPLETED,
        "invalid_rows": invalid,
        "intents": intents,
    }


def print_text(report: dict[str, Any]) -> None:
    rate = "n/a" if report["adoption_rate"] is None else f'{100 * report["adoption_rate"]:.1f}%'
    power = "underpowered" if report["underpowered"] else "readable"
    print(
        f'routing feedback: decisions={report["decisions"]} recommendations={report["recommendations"]} '
        f'abstentions={report["abstentions"]} completed={report["completed"]} adopted={report["adopted"]} '
        f'missed={report["missed"]} adoption={rate} evidence={power} '
        f'minimum={report["minimum_completed"]} invalid_rows={report["invalid_rows"]}'
    )
    for row in report["intents"]:
        intent_rate = "n/a" if row["adoption_rate"] is None else f'{100 * row["adoption_rate"]:.1f}%'
        print(
            f'  intent={row["intent"]} completed={row["completed"]} adopted={row["adopted"]} '
            f'missed={row["missed"]} adoption={intent_rate}'
        )


def main() -> int:
    default = Path(os.environ.get("RIPWIRE_HOME", str(Path.home() / ".ripwire"))) / "routing.jsonl"
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("log", nargs="?", type=Path, default=default)
    parser.add_argument("--json", action="store_true", help="emit the versioned report as compact JSON")
    args = parser.parse_args()
    if not args.log.is_file():
        print(f"routing_report.py: no routing telemetry at {args.log}", file=sys.stderr)
        return 2
    rows, invalid = load_rows(args.log)
    report = summarize(rows, invalid)
    if args.json:
        print(json.dumps(report, sort_keys=True, separators=(",", ":")))
    else:
        print_text(report)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
