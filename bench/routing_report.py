#!/usr/bin/env python3
"""Summarize privacy-safe Codex routing feedback without reading prompt text.

~/.ripwire/routing.jsonl is shared with hooks/ripwire-claude-route.sh, whose rows carry
agent="claude". This readout is Codex-only: rows are kept when their `agent` is "codex" — and a row
with no `agent` field predates that field and was written by the Codex router, so it reads as
"codex", the same convention hooks/ripwire-claude-route.sh applies. Excluded rows are counted and
disclosed as foreign_rows, never silently dropped.
"""

from __future__ import annotations

import argparse
import json
import os
import sys
from collections import defaultdict
from pathlib import Path
from typing import Any


MIN_COMPLETED = 30
AGENT = "codex"


def row_agent(row: dict[str, Any]) -> str:
    """A row without an `agent` field predates the field and belongs to the Codex router."""
    return str(row.get("agent") or AGENT)


def load_rows(path: Path, agent: str = AGENT) -> tuple[list[dict[str, Any]], int, int]:
    """Return (rows written by `agent`, invalid line count, well-formed rows written by other agents)."""
    rows: list[dict[str, Any]] = []
    invalid = 0
    foreign = 0
    with path.open(encoding="utf-8") as handle:
        for line in handle:
            try:
                row = json.loads(line)
            except (json.JSONDecodeError, UnicodeDecodeError):
                invalid += 1
                continue
            if not isinstance(row, dict):
                invalid += 1
            elif row_agent(row) != agent:
                foreign += 1
            else:
                rows.append(row)
    return rows, invalid, foreign


def ratio(numerator: int, denominator: int) -> float | None:
    return round(numerator / denominator, 6) if denominator else None


def summarize(rows: list[dict[str, Any]], invalid: int, foreign: int = 0, agent: str = AGENT) -> dict[str, Any]:
    # Re-filter here as well so a caller that hands summarize() raw rows cannot re-introduce the
    # cross-agent contamination load_rows() already removed.
    rows = [row for row in rows if row_agent(row) == agent]
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
        "agent": agent,
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
        "foreign_rows": foreign,
        "intents": intents,
    }


def print_text(report: dict[str, Any]) -> None:
    rate = "n/a" if report["adoption_rate"] is None else f'{100 * report["adoption_rate"]:.1f}%'
    power = "underpowered" if report["underpowered"] else "readable"
    print(
        f'routing feedback: agent={report["agent"]} decisions={report["decisions"]} recommendations={report["recommendations"]} '
        f'abstentions={report["abstentions"]} completed={report["completed"]} adopted={report["adopted"]} '
        f'missed={report["missed"]} adoption={rate} evidence={power} '
        f'minimum={report["minimum_completed"]} invalid_rows={report["invalid_rows"]} foreign_rows={report["foreign_rows"]}'
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
    rows, invalid, foreign = load_rows(args.log)
    report = summarize(rows, invalid, foreign)
    if args.json:
        print(json.dumps(report, sort_keys=True, separators=(",", ":")))
    else:
        print_text(report)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
