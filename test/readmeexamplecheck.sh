#!/usr/bin/env bash
# readmeexamplecheck.sh — the advertised callers example must match the current binary's paths.
#
# README-RESTRUCTURE (2026-11-17): the example used to live in README.md twice — once under "Real runs"
# and once in the reference guide's output-format section. The 0.7.0 front-page restructure moved both
# copies out, to docs/REAL_RUNS.md and docs/REFERENCE_GUIDE.md. The claim this gate holds is unchanged
# (WHICH callers exist and WHICH FILE each lives in); only the file publishing it moved, so the subject
# is now the SET of surfaces that publish it. Concatenating them, rather than re-pointing at one, is
# the widening: a stale row cannot escape by being the copy this gate was not aimed at. The presence
# guard below refuses a surface carrying no rows at all, so a rewrite that deletes the example fails
# loudly instead of passing vacuously.
set -u

ROOT="$( cd "$( dirname "$0" )/.." && pwd )"
BIN="${1:-${RIPWIRE_BIN:-$ROOT/build/ripwire}}"
[ "${BIN#/}" = "$BIN" ] && BIN="$ROOT/$BIN"
TMP="$( mktemp -d )"; trap 'rm -rf "$TMP"' EXIT

[ -x "$BIN" ] || { echo "readmeexamplecheck: no binary at $BIN — build first"; exit 2; }
SURFACES=( "$ROOT/README.md" "$ROOT/docs/REAL_RUNS.md" "$ROOT/docs/REFERENCE_GUIDE.md" )
for _s in "${SURFACES[@]}"; do
    [ -f "$_s" ] || { echo "readmeexamplecheck: missing published surface $_s"; exit 2; }
done
cat "${SURFACES[@]}" >"$TMP/surface.md"
( cd "$ROOT" && "$BIN" . --callers=rankGraphTeleport --no-cache ) >"$TMP/live"

python3 - "$TMP/surface.md" "$TMP/live" <<'PY'
import re
import sys

readme = open(sys.argv[1], encoding="utf-8").read()
live = open(sys.argv[2], encoding="utf-8").read()
# The `p=` attribute is `path:line`, so comparing it whole pinned README to LIVE LINE NUMBERS in
# src/graph.h — and this gate's own header says its subject is the binary's PATHS. Any insertion
# above a documented caller reddened it: it fired twice on 2026-09-09 alone, both times on two-line
# edits that had nothing to do with the documented rows. The example's claim is WHICH callers exist
# and WHICH FILE each lives in; a caller sliding down its own file is not a change to that claim, and
# a gate that cannot tell the two apart trains people to re-capture on reflex. The trailing `:N` is
# therefore stripped from BOTH sides before comparison — only a trailing colon-digits run, so a path
# that legitimately contains a colon is untouched. What still reds, and must: a caller that has
# vanished, been renamed, or MOVED TO A DIFFERENT FILE. README's printed line numbers are a capture
# and say so above the block; they are not asserted here because nothing can keep them true.
LINE_SUFFIX = re.compile(r":\d+$")

# CALLSITE-AT (2026-10-09): a caller row may carry attributes after p= (sites_at=, tested=, via=); the claim compared is
# still WHICH callers exist and in WHICH FILE, so the row pattern reads n= and p= and tolerates what follows.
rows = re.findall(r'<s t="[^"]+" n="([^"]+)" p="([^"]+)"[^>]*/>', live)
assert rows, "live callers command returned no rows"
readme_rows = { ( n, LINE_SUFFIX.sub( "", p ) )
                for n, p in re.findall(r'<s t="[^"]+" n="([^"]+)" p="([^"]+)"[^>]*/>', readme) }
# PRESENCE GUARD: an empty surface would make the comparison below vacuously true, so a deleted
# example is a red, not a pass.
assert readme_rows, "the published surfaces carry no <s ... n= p= /> rows at all — the callers example was deleted or reworded"
missing = []
for name, path in rows:
    if ( name, LINE_SUFFIX.sub( "", path ) ) not in readme_rows:
        missing.append(f'<s t="fn" n="{name}" p="{path}"/>')
assert not missing, "the advertised callers example has stale/missing rows (name+file compared, line ignored):\n" + "\n".join(missing)
print("readmeexamplecheck: ALL PASS")
PY
