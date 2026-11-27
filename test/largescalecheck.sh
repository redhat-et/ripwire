#!/usr/bin/env bash
# largescalecheck.sh — honesty gate for bench/largescale.py, the large-repo wall-clock / peak-RSS
# harness (added by lane/large-repo-perf, 2026-11-27).
#
# WHY A GATE ON A HARNESS. This harness is how the repo will decide where time goes at 80k files, and
# a measurement harness fails SILENTLY: every number it prints is plausible whether or not it read the
# right thing. Two specific ways it can lie, both of which have bitten this repo before, are what this
# gate pins:
#
#   (A) THE COUNTS PATTERN. The map prints its sizes UNQUOTED inside a trailing XML comment —
#       `files=103 symbols=612 edges=245` — not as attributes. A natural `files="([0-9]+)"` pattern
#       finds nothing, and the harness's x-axis then silently becomes zero for every corpus, which
#       renders as "?" and makes every slope unfittable. So this gate does not merely check that the
#       shipped pattern matches: it also proves the QUOTED pattern finds nothing in a header the gate
#       itself just produced. A pattern check that only shows the current pattern working cannot tell
#       a working pattern from a header that happens to contain anything at all.
#
#   (B) THE WARM CHECK. "I ran it twice, so the second run was warm" is an assumption. The harness
#       sets RIPWIRE_CACHE_STATS=1 on warm runs and reports `reparsed=`; this gate requires the warm
#       row to report exactly 0 AND the cold row to report something other than 0, so the column
#       cannot pass by being a constant. A column that reads 0 for every arm proves nothing.
#
# Both arms run against the binary under test, so they also fail if that binary stops emitting the
# counts comment or the cache-stats line at all.
#
# Usage:  bash test/largescalecheck.sh [path/to/ripwire]
#         RIPWIRE_BIN=/other/ripwire bash test/largescalecheck.sh

set -u
ROOT="$( cd "$( dirname "$0" )/.." && pwd )"
BIN="${1:-${RIPWIRE_BIN:-$ROOT/build/ripwire}}"
HARNESS="$ROOT/bench/largescale.py"
FIX="$ROOT/test/largescalefix"

echo "largescalecheck: BIN=$BIN $( "$BIN" --version 2>/dev/null | head -1 )"

fail=0
note() { echo "  FAIL  $*"; fail=1; }
ok()   { echo "  ok    $*"; }

if [ ! -x "$BIN" ]; then
    echo "  FAIL  no binary at $BIN"; exit 2
fi
if [ ! -f "$HARNESS" ]; then
    note "bench/largescale.py is missing — the large-repo harness this gate pins does not exist"
    exit 2
fi
if [ ! -d "$FIX" ]; then
    note "test/largescalefix is missing"; exit 2
fi

WORK="$( mktemp -d )"; trap 'rm -rf "$WORK"' EXIT

# ── Arm A: the counts pattern, proved against a header this gate just produced ──────────────────────
# A1: the shipped patterns find non-zero counts.  A2: the quoted spelling finds NOTHING, so A1 is a
# statement about the pattern and not about the header being permissive.
"$BIN" "$FIX" --top-k=1 > "$WORK/map.xml" 2> "$WORK/map.err"
if [ ! -s "$WORK/map.xml" ]; then
    note "arm A: the binary emitted no map for the fixture"; sed 's/^/    /' "$WORK/map.err"
fi

python3 - "$HARNESS" "$WORK/map.xml" <<'PY'
import importlib.util, re, sys
spec = importlib.util.spec_from_file_location("largescale", sys.argv[1])
mod  = importlib.util.module_from_spec(spec)
spec.loader.exec_module(mod)
text = open(sys.argv[2], errors="replace").read()

bad = 0
for name in ("FILES_ATTR_RE", "SYMS_ATTR_RE"):
    rx = getattr(mod, name, None)
    if rx is None:
        print(f"  FAIL  arm A1: bench/largescale.py has no {name}")
        bad = 1
        continue
    m = rx.search(text)
    if not m or int(m.group(1)) <= 0:
        print(f"  FAIL  arm A1: {name} = {rx.pattern!r} found "
              f"{m.group(1) if m else 'NOTHING'} in a map header the gate just produced")
        bad = 1
    else:
        print(f"  ok    arm A1: {name} found {m.group(1)}")

# A2 — the trap, proved to be a trap on this very header.
for quoted in (r'\bfiles="(\d+)"', r'\bsymbols="(\d+)"'):
    if re.search(quoted, text):
        print(f"  FAIL  arm A2: {quoted!r} matched — the counts are quoted attributes now, so arm A1 "
              f"no longer proves the harness reads the comment form and this gate needs rewriting")
        bad = 1
    else:
        print(f"  ok    arm A2: {quoted!r} finds nothing (the quoted spelling really is a trap)")
sys.exit(1 if bad else 0)
PY
[ $? -eq 0 ] || fail=1

# ── Arm B: the warm check discriminates ─────────────────────────────────────────────────────────────
# One harness run over the fixture, both modes, one rep. The rendered table must show reparsed 0 for
# the warm row and NOT 0 for the cold row.
OUT="$WORK/sweep"
if ! python3 "$HARNESS" --bin "$BIN" --corpus "fix=$FIX" --reps 1 --mode both \
        --out "$OUT" --window-label largescalecheck > "$WORK/sweep.log" 2>&1; then
    note "arm B: bench/largescale.py exited non-zero"; tail -25 "$WORK/sweep.log" | sed 's/^/    /'
fi

REPORT="$OUT/report.md"
if [ ! -f "$REPORT" ]; then
    note "arm B: the harness wrote no report.md"
else
    warm_rep="$( awk -F'|' '/^\| fix \|/ && $5 ~ /warm/ { gsub(/ /,"",$10); print $10 }' "$REPORT" | head -1 )"
    cold_rep="$( awk -F'|' '/^\| fix \|/ && $5 ~ /cold/ { gsub(/ /,"",$10); print $10 }' "$REPORT" | head -1 )"
    warm_files="$( awk -F'|' '/^\| fix \|/ && $5 ~ /warm/ { gsub(/ /,"",$3); print $3 }' "$REPORT" | head -1 )"

    if [ "$warm_rep" = "0" ]; then
        ok "arm B1: the warm row reports reparsed=0 (it really was warm)"
    else
        note "arm B1: the warm row reports reparsed='$warm_rep', not 0 — the warm cell is not warm"
    fi
    if [ -n "$cold_rep" ] && [ "$cold_rep" != "0" ]; then
        ok "arm B2: the cold row reports reparsed='$cold_rep', not 0 — the column discriminates"
    else
        note "arm B2: the cold row also reports '$cold_rep' — a reparsed column that is 0 on every arm proves nothing"
    fi
    case "$warm_files" in
        ''|*[!0-9]*) note "arm B3: the warm row's files column is '$warm_files', not an integer — the x-axis is unusable" ;;
        0)           note "arm B3: the warm row's files column is 0 — the x-axis is unusable" ;;
        *)           ok "arm B3: the warm row carries files=$warm_files for the x-axis" ;;
    esac
fi

if [ "$fail" -ne 0 ]; then
    echo "largescalecheck: FAIL"
    exit 1
fi
echo "largescalecheck: PASS"
