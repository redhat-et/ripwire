#!/usr/bin/env bash
# communitylabelcheck.sh — A5 semantic-label and bridge-display precision gate.

set -u
ROOT="$( cd "$( dirname "$0" )/.." && pwd )"
BIN="${CTXPACK_BIN:-$ROOT/build/ctxpack}"
[ "${BIN#/}" = "$BIN" ] && BIN="$ROOT/$BIN"
CORPUS="$ROOT/test/zoomfix"
TMP="$( mktemp -d )"; trap 'rm -rf "$TMP"' EXIT

[ -x "$BIN" ] || { echo "no ctxpack binary at $BIN — build first"; exit 2; }

run_pair()
{
    local verb="$1"
    "$BIN" "$CORPUS" "$verb" --no-cache >"$TMP/${verb#--}.a" 2>/dev/null
    "$BIN" "$CORPUS" "$verb" --no-cache >"$TMP/${verb#--}.b" 2>/dev/null
    diff -q "$TMP/${verb#--}.a" "$TMP/${verb#--}.b" >/dev/null
}

run_pair --communities || { echo "FAIL communities output is not deterministic"; exit 1; }
run_pair --report || { echo "FAIL report output is not deterministic"; exit 1; }

python3 - "$TMP/communities.a" "$TMP/report.a" <<'PY'
import re
import sys
import xml.etree.ElementTree as ET

community_path, report_path = sys.argv[1:]
root = ET.parse(community_path).getroot()
communities = root.findall(".//community")
if len(communities) < 6:
    raise SystemExit(f"FAIL expected at least 6 fixture communities, found {len(communities)}")

labels = [node.get("label", "") for node in communities]
if any("::" not in label for label in labels):
    raise SystemExit("FAIL every community label must contain directory and semantic anchor")
if len(labels) != len(set(labels)):
    raise SystemExit("FAIL community labels are not unique")
if any(re.search(r"(?:#|\bcommunity[-_ ]?)\d+$", label, re.I) for label in labels):
    raise SystemExit("FAIL community labels use an opaque community-id suffix")

# §P6.2: the anchor symbol (between "::" and "@") must not be a trivial accessor — a getter/setter or an
# STL-container-op name tells a reader nothing about a 5+-member module ("push_back@svector.h", "empty@notes.h"
# were the real-repo instances that motivated this). Mirrors main.cpp's isAccessorName() table; kept in sync by
# hand since the gate has no way to import the binary's constexpr table. test/zoomfix/core/engine.cpp plants an
# `empty()` helper with the highest fan-in in its cluster specifically to prove the picker skips it.
ACCESSOR_NAMES = {
    "empty", "size", "begin", "end", "cbegin", "cend", "push_back", "pop_back", "emplace_back",
    "data", "get", "set", "front", "back", "clear", "reserve", "resize", "at", "count", "length",
    "c_str", "insert", "erase", "find", "top", "push", "pop", "key", "value", "first", "second",
}
def is_accessor(name):
    if name in ACCESSOR_NAMES:
        return True
    if len(name) > 3 and name[:3] in ("get", "set") and name[3].isupper():
        return True
    return False

anchor_names = [re.search(r"::(.+?)@", label).group(1) for label in labels]
accessor_anchors = [n for n in anchor_names if is_accessor(n)]
if accessor_anchors:
    raise SystemExit(f"FAIL community label anchored to a trivial accessor: {accessor_anchors}")
if int(root.get("shown_modules", "-1")) != len(communities) or int(root.get("modules", "-1")) < len(communities):
    raise SystemExit("FAIL communities module cap does not disclose exact shown vs total")
bridges = root.findall("bridge")
if int(root.get("shown_bridges", "-1")) != len(bridges) or int(root.get("bridges", "-1")) < len(bridges):
    raise SystemExit("FAIL communities bridge cap does not disclose exact shown vs total")

# §P8 vocabulary (src/pageview.h, THE TRUNCATION VOCABULARY, rules 1+3): this root carries TWO independent
# listings, so it keeps the noun-prefixed shown_<noun>= form — but each shown_ needs its <noun>_capped="0|1"
# companion, which neither had. Without it a caller reading shown_modules="30" had to subtract against
# modules= itself to learn whether 30 was a cap; the bit is now always present and must AGREE with that
# subtraction, in both directions, so it can never become a decorative constant.
for noun in ("modules", "bridges"):
    bit = root.get(f"{noun}_capped")
    if bit not in ("0", "1"):
        raise SystemExit(f"FAIL communities {noun}_capped=\"{bit}\" is not the 0|1 truncation bit")
    if (int(root.get(f"shown_{noun}")) < int(root.get(noun))) != (bit == "1"):
        raise SystemExit(f"FAIL communities {noun}_capped disagrees with shown_{noun} vs {noun}")

report = open(report_path, encoding="utf-8").read()
module_labels = re.findall(r'^- \*\*(.+?)\*\* — \d+ symbols', report, re.M)
if len(module_labels) < 6 or len(module_labels) != len(set(module_labels)):
    raise SystemExit("FAIL report module labels must be present and unique")

for left, right in re.findall(r'^- (.+?) ↔ (.+?) \(\d+ edges\)$', report, re.M):
    if left == right:
        raise SystemExit("FAIL report rendered a distinct-ID bridge as X-to-X")

module_heading = re.search(r'^## Modules \(call-graph clusters; showing (\d+) of (\d+)\)$', report, re.M)
bridge_heading = re.search(r'^## Cross-module bridges \(showing (\d+) of (\d+)\)$', report, re.M)
report_bridges = re.findall(r'^- .+? ↔ .+? \(\d+ edges\)$', report, re.M)
if not module_heading or int(module_heading.group(1)) != len(module_labels) or int(module_heading.group(2)) < len(module_labels):
    raise SystemExit("FAIL report module cap does not disclose exact shown vs total")
if not bridge_heading or int(bridge_heading.group(1)) != len(report_bridges) or int(bridge_heading.group(2)) < len(report_bridges):
    raise SystemExit("FAIL report bridge cap does not disclose exact shown vs total")

fixed_caps = (
    (r'^## God files \(most depended-on; showing (\d+) of (\d+)\)$', 10, None),
    (r'^## Dependency cycles \(showing (\d+) of (\d+)\)$', 6, None),
    (r'^## Top symbols \(PageRank; showing (\d+) of (\d+)\)$', 10, int(root.get("symbols", "-1"))),
)
for pattern, cap, expected_total in fixed_caps:
    match = re.search(pattern, report, re.M)
    if not match:
        raise SystemExit("FAIL report fixed cap is missing shown-vs-total honesty")
    shown, total = map(int, match.groups())
    if shown != min(total, cap) or (expected_total is not None and total != expected_total):
        raise SystemExit("FAIL report fixed-cap shown/total values are dishonest")

print(f"PASS semantic unique labels={len(labels)} report_labels={len(module_labels)}")
PY
