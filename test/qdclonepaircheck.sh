#!/usr/bin/env bash
# qdclonepaircheck.sh — QD-CLONE-FALSE-GATE gate: --quality-delta must not gate on a clone pair the baseline already held,
# only re-shaped by a small edit (quality.h pushExactGroupPairs, pushTwinWidenedPairs, cloneGroupHeldAtBaseline).
#
# Found by the P5 seeded-defect pilot (2026-11-10): 7/410 seeded runs exited 2 on a duplication row whose pair the edit did not
# create. Two identity re-shapes of ONE baseline duplication read as new member sets:
#   (1) SHRINK: exact {alpha,beta,gamma}; a one-line edit to alpha leaves exact {beta,gamma} (both untouched) and near {alpha,beta}.
#   (2) TWIN: exact {f1,f2} with g a near clone; Type-3 keeps one representative per token stream, so the baseline holds {f1,g}
#       only; an edit to f1 makes f2 its own stream and {f2,g} read as new.
#
#   (a) SHRINK edit: no duplication / new-clone-of-reused-helper row, exit 0.
#   (b) TWIN edit: no duplication row, exit 0.
#   (c) CONTROL, a third exact copy of a baseline group (a new member): duplication row, gating, exit 2.
#   (d) CONTROL, a new near clone of an UNTOUCHED function: duplication row, gating, exit 2.
#   (e) determinism: (a) twice is byte-identical.
#
# Usage: test/qdclonepaircheck.sh [BIN]   (default build/ripwire). Red before the fix: (a) and (b) fail.
set -u
ROOT="$( cd "$( dirname "$0" )/.." && pwd )"
. "$ROOT/test/lib/clean-env.sh"
BIN="${1:-${RIPWIRE_BIN:-$ROOT/build/ripwire}}"
[ "${BIN#/}" = "$BIN" ] && BIN="$ROOT/$BIN"
[ -x "$BIN" ] || { echo "no ripwire binary at $BIN — build first"; exit 2; }
TMP="$( mktemp -d )"; trap 'rm -rf "$TMP"' EXIT
export TMPDIR="$TMP/cache"; mkdir -p "$TMPDIR"
fail=0
ok(){ printf '  PASS  %s\n' "$*" || { fail=1; printf '  FAIL  could not write the PASS line for: %s\n' "$*"; }; return 0; }
no(){ printf '  FAIL  %s\n' "$*"; fail=1; }
echo "qdclonepaircheck: BIN=$BIN"
G=( git -c user.name=t -c user.email=t@t -c commit.gpgsign=false )

loader(){   # loader NAME — one 80-token CSV loader body
cat <<EOF
def $1(path, limit):
    rows = []
    with open(path) as fh:
        for line in fh:
            parts = line.strip().split(",")
            if len(parts) < 3:
                continue
            rows.append((parts[0], int(parts[1]), float(parts[2])))
            if len(rows) >= limit:
                break
    return rows


EOF
}
near(){     # near NAME — the loader with one extra statement and a different filter: a Type-3 near clone of it
cat <<EOF
def $1(path, limit):
    rows = []
    with open(path) as fh:
        for line in fh:
            parts = line.strip().split(",")
            if len(parts) < 4:
                continue
            rows.append((parts[0], int(parts[1]), float(parts[2])))
            if len(rows) >= limit:
                break
    rows.sort()
    return rows


EOF
}

tally(){    # tally NAME — a structurally different ~90-token body (a counting loop), so twin.py never pairs with ops.py
cat <<EOF
def $1(items, cap):
    seen = {}
    total = 0
    for item in items:
        key = item.lower()
        if key in seen:
            seen[key] += 1
        else:
            seen[key] = 1
        total = total + len(key)
        if total > cap:
            return seen, total
    return seen, total


EOF
}
tallynear(){
cat <<EOF
def $1(items, cap):
    seen = {}
    total = 0
    for item in items:
        key = item.upper()
        if key in seen:
            seen[key] += 2
        else:
            seen[key] = 1
        total = total + len(key)
        if total > cap:
            return seen, total
    print(total)
    return seen, total


EOF
}

# base: ops.py = an exact triple; twin.py = an exact pair (first in file order) + a near clone of it.
B="$TMP/base"; mkdir -p "$B"
{ loader load_alpha; loader load_beta; loader load_gamma
  echo 'def run(path):'; echo '    return load_alpha(path, 5) + load_beta(path, 6) + load_gamma(path, 7)'; } >"$B/ops.py"
{ tally read_first; tally read_second; tallynear read_near
  echo 'def drive(path):'; echo '    return read_first(path, 1) + read_second(path, 2) + read_near(path, 3)'; } >"$B/twin.py"
( cd "$B" && git init -q && git add -A && "${G[@]}" commit -qm base ) || { echo "git setup failed"; exit 2; }

# run_case NAME EDIT-PYTHON -> $TMP/NAME.out, $TMP/NAME.rc
run_case(){
    local d="$TMP/$1"
    git clone -q "$B" "$d" || { no "$1: clone failed"; return; }
    ( cd "$d" && python3 -c "$2" && git add -A && "${G[@]}" commit -qm "$1" ) || { no "$1: edit failed"; return; }
    "$BIN" "$d" --quality-delta=HEAD~1..HEAD --legend=compact >"$TMP/$1.out" 2>"$TMP/$1.err"; echo $? >"$TMP/$1.rc"
}
rows(){ tr '<' '\n' <"$TMP/$1.out" | grep -E '^r kind="(duplication|new-clone-of-reused-helper)"'; }

run_case shrink "s=open('ops.py').read(); open('ops.py','w').write(s.replace('def load_alpha(path, limit):\n    rows = []\n', 'def load_alpha(path, limit):\n    rows = []\n    print(\"loading\", path)\n', 1))"
run_case twin   "s=open('twin.py').read(); open('twin.py','w').write(s.replace('def read_first(items, cap):\n    seen = {}\n', 'def read_first(items, cap):\n    seen = {}\n    print(\"reading\", cap)\n', 1))"
run_case third  "import subprocess; open('ops.py','a').write('''
def load_delta(path, limit):
    rows = []
    with open(path) as fh:
        for line in fh:
            parts = line.strip().split(\",\")
            if len(parts) < 3:
                continue
            rows.append((parts[0], int(parts[1]), float(parts[2])))
            if len(rows) >= limit:
                break
    return rows
''')"
run_case newnear "open('ops.py','a').write('''
def load_omega(path, limit):
    rows = []
    with open(path) as fh:
        for line in fh:
            parts = line.strip().split(\",\")
            if len(parts) < 5:
                continue
            rows.append((parts[0], int(parts[1]), float(parts[2])))
            if len(rows) >= limit:
                break
    rows.reverse()
    return rows
''')"

if [ -z "$( rows shrink )" ] && [ "$( cat "$TMP/shrink.rc" )" = 0 ]; then ok "(a) shrink: no clone row, exit 0"
else no "(a) shrink: rc=$( cat "$TMP/shrink.rc" ) rows:"; rows shrink; fi
if [ -z "$( rows twin )" ] && [ "$( cat "$TMP/twin.rc" )" = 0 ]; then ok "(b) twin: no clone row, exit 0"
else no "(b) twin: rc=$( cat "$TMP/twin.rc" ) rows:"; rows twin; fi
if rows third | grep 'load_delta' | grep -q 'gating="1"' && [ "$( cat "$TMP/third.rc" )" = 2 ]; then ok "(c) third exact copy gates (exit 2)"
else no "(c) third copy: rc=$( cat "$TMP/third.rc" ) rows:"; rows third; fi
if rows newnear | grep 'load_omega' | grep -q 'gating="1"' && [ "$( cat "$TMP/newnear.rc" )" = 2 ]; then ok "(d) new near clone gates (exit 2)"
else no "(d) new near clone: rc=$( cat "$TMP/newnear.rc" ) rows:"; rows newnear; fi
"$BIN" "$TMP/shrink" --quality-delta=HEAD~1..HEAD --legend=compact >"$TMP/shrink2.out" 2>/dev/null
if cmp -s "$TMP/shrink.out" "$TMP/shrink2.out"; then ok "(e) deterministic"; else no "(e) shrink output differs across runs"; fi

echo
if [ "$fail" -eq 0 ]; then echo "ALL PASS"; exit 0; fi
echo "SOME CHECKS FAILED"; exit 1
