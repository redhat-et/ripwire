#!/usr/bin/env bash
# deadcodescopecheck.sh — DEAD-CODE-SCOPE: --dead-code=PATH said count=0 about a file of public functions, because it lists only
# internal-linkage defs. Now the PUBLIC free functions of the filtered files that no non-test caller reaches print after the d and
# to rows as <exported linkage="exported" ...><e n= t= p= l= v= .../></exported>, honestly labelled: code outside the tree may call
# them, and v=/why= are the --for unused table's verdicts (forunused.h), so a name a string, registry, decorator, __all__ or
# re-export holds is never a bare candidate.
# Arms: A1 Python unused / test-only public defs listed with v=; A2 a used def, a private def, a method are not; A3 __all__ string,
# registry value, decorator: not listed, or listed with why=; A4 TS export listed, re-export labelled, non-exported not listed;
# A5 C++ extern def listed, static def stays a <d> row (count=1), string-named def labelled; A6 bare --dead-code carries no group
# (byte-identical shape); A7 the group is the last child, after d/to rows; A8 legend: compact reads linkage=, full carries the
# clause, and neither appears without the group; A9 second page has no group; A10 a filter whose files hold no such function
# prints no group; A11 files cap (files= of files_total=) and row cap (shown= of total=, capped=1) disclosed; A12 well-formed XML.
# Optional: RIPWIRE_BASE_BIN=<main binary> adds A13: with the group (and its legend clause) removed the answer is byte-identical.
#   RIPWIRE_BIN=build/ripwire bash test/deadcodescopecheck.sh     # red on a pre-DEAD-CODE-SCOPE binary (A1, A4, A5, A11)
set -u
ROOT="$( cd "$( dirname "$0" )/.." && pwd )"
BIN="${1:-${RIPWIRE_BIN:-$ROOT/build/ripwire}}"
[ "${BIN#/}" = "$BIN" ] && BIN="$ROOT/$BIN"
[ -x "$BIN" ] || { echo "no ripwire binary at $BIN — build first"; exit 2; }
TMP="$( mktemp -d )"; trap 'rm -rf "$TMP"' EXIT
fail=0
ok(){ printf '  PASS  %s\n' "$*" || { fail=1; printf '  FAIL  could not write the PASS line for: %s\n' "$*"; }; return 0; }
no(){ printf '  FAIL  %s\n' "$*"; fail=1; }
echo "deadcodescopecheck: BIN=$BIN"

F="$TMP/fx"; mkdir -p "$F/pkg" "$F/tests" "$F/web" "$F/cc" "$F/many"
cat > "$F/pkg/net.py" <<'P'
__all__ = ["listed_in_all"]


def used_fn(x):
    return x


def unused_fn(x):
    return x + 1


def tested_only_fn(x):
    return x + 2


def listed_in_all(x):
    return x + 3


def registered(x):
    return x + 4


REGISTRY = {"r": registered}


@app.route("/x")
def handler():
    return 5


def _private_unused(x):
    return x


class Box:
    def method_unused(self):
        return 6
P
cat > "$F/pkg/user.py" <<'P'
from pkg.net import used_fn


def run(v):
    return used_fn(v)
P
cat > "$F/tests/test_net.py" <<'P'
from pkg.net import tested_only_fn


def test_a():
    assert tested_only_fn(1) == 3
P
cat > "$F/web/path.ts" <<'T'
export function usedTs(a: number): number {
    return a;
}
export function unusedTs(a: number): number {
    return a + 1;
}
export function reexported(a: number): number {
    return a + 2;
}
function localOnly(a: number): number {
    return a + 3;
}
T
cat > "$F/web/main.ts" <<'T'
import { usedTs } from "./path";
console.log(usedTs(1));
T
cat > "$F/web/index.ts" <<'T'
export { reexported } from "./path";
T
cat > "$F/cc/lib.cpp" <<'C'
static int internal_dead(int x)
{
    return x;
}
int exported_dead(int x)
{
    return x + 1;
}
int exported_used(int x)
{
    return x + 2;
}
int by_string(int x)
{
    return x + 3;
}
C
cat > "$F/cc/main.cpp" <<'C'
int exported_used(int);
const char* kNames[] = { "by_string" };
int main()
{
    return exported_used(1);
}
C
cat > "$F/cc/only_static.cpp" <<'C'
static int lone_static(int x)
{
    return x;
}
C
for i in 1 2 3 4 5 6 7; do printf 'def lonely_%s(x):\n    return x\n' "$i" > "$F/many/m$i.py"; done
mkdir -p "$F/wide"; for i in $( seq 1 101 ); do printf 'def wide_%s(x):\n    return x\n\n' "$i"; done > "$F/wide/w.py"

runin(){ local dir="$1"; shift; ( cd "$dir" || exit 1; "$BIN" "$dir" --no-cache "$@" 2>/dev/null ); }
run(){ runin "$F" "$@"; }
CHK=""
chk(){ local name="$1"; shift; CHK="$( run "$@" )"; local rc=$?
       if [ "$rc" != 0 ] || ! printf '%s' "$CHK" | grep -q '<dead-code'; then no "$name: the run did not answer (rc=$rc, no <dead-code root)"; return 1; fi; return 0; }
erow(){ printf '%s' "$1" | grep -o "<e n=\"$2\"[^>]*>"; }
group(){ printf '%s' "$1" | grep -o '<exported [^>]*>'; }

# ── A1/A2/A3 Python ───────────────────────────────────────────────────────────────────────────────────────────────────────
chk "A1 python run" --dead-code=pkg/net.py && PY="$CHK" || PY=""
if group "$PY" | grep -q 'linkage="exported"'; then ok "A1 the exported group prints, linkage=\"exported\""; else no "A1 no <exported linkage=\"exported\"> group"; fi
if erow "$PY" unused_fn | grep -q 'v="unused"'; then ok "A1 unused_fn listed v=unused"; else no "A1 unused_fn not v=unused: $( erow "$PY" unused_fn )"; fi
if erow "$PY" unused_fn | grep -q 'p="pkg/net.py"'; then ok "A1 the row names its file p="; else no "A1 unused_fn row has no p=pkg/net.py"; fi
if erow "$PY" tested_only_fn | grep -q 'v="test-only"' && erow "$PY" tested_only_fn | grep -q 'tests="'; then ok "A1 tested_only_fn listed v=test-only tests="; else no "A1 tested_only_fn: $( erow "$PY" tested_only_fn )"; fi
for n in used_fn _private_unused method_unused; do
    if [ -n "$( erow "$PY" "$n" )" ]; then no "A2 $n listed in the exported group"; else ok "A2 $n not listed (a caller / private / a method)"; fi
done
for pair in listed_in_all:string registered:value handler:framework; do
    n="${pair%%:*}"; w="${pair##*:}"; row="$( erow "$PY" "$n" )"
    if [ -z "$row" ]; then ok "A3 $n not listed"
    elif printf '%s' "$row" | grep -q 'v="unknown"' && printf '%s' "$row" | grep -q "why=\"[^\"]*$w"; then ok "A3 $n labelled v=unknown why=$w"
    else no "A3 $n listed without its why=$w: $row"; fi
done
if printf '%s' "$PY" | grep -q '<dead-code [^>]*count="0"'; then ok "A1 count= unchanged (exported rows are not in count=)"; else no "A1 count= is not 0"; fi

# ── A4 TypeScript ─────────────────────────────────────────────────────────────────────────────────────────────────────────
chk "A4 ts run" --dead-code=web/path.ts && TS="$CHK" || TS=""
if erow "$TS" unusedTs | grep -q 'v="unused"'; then ok "A4 exported unusedTs listed v=unused"; else no "A4 unusedTs: $( erow "$TS" unusedTs )"; fi
row="$( erow "$TS" reexported )"
if [ -z "$row" ] || printf '%s' "$row" | grep -q 'why="[^"]*import'; then ok "A4 a re-exported def is not listed or reads why=import"; else no "A4 reexported unlabelled: $row"; fi
if [ -n "$( erow "$TS" localOnly )" ]; then no "A4 a non-exported def listed as exported"; else ok "A4 a non-exported def is not in the exported group"; fi
if [ -n "$( erow "$TS" usedTs )" ]; then no "A4 usedTs (a caller) listed"; else ok "A4 a called export is not listed"; fi

# ── A5 C++ ────────────────────────────────────────────────────────────────────────────────────────────────────────────────
chk "A5 c++ run" --dead-code=cc/lib.cpp && CC="$CHK" || CC=""
if erow "$CC" exported_dead | grep -q 'v="unused"'; then ok "A5 extern exported_dead listed v=unused"; else no "A5 exported_dead: $( erow "$CC" exported_dead )"; fi
if printf '%s' "$CC" | grep -q '<d n="internal_dead"' && printf '%s' "$CC" | grep -q '<dead-code [^>]*count="1"'; then ok "A5 static internal_dead stays a <d> row, count=1"; else no "A5 internal_dead is not the one <d> row"; fi
if [ -n "$( erow "$CC" internal_dead )" ]; then no "A5 internal_dead also in the exported group"; else ok "A5 a <d> row is not repeated as <e>"; fi
row="$( erow "$CC" by_string )"
if [ -z "$row" ] || printf '%s' "$row" | grep -q 'why="[^"]*string'; then ok "A5 a string-named def is not listed or reads why=string"; else no "A5 by_string unlabelled: $row"; fi
if [ -n "$( erow "$CC" exported_used )" ]; then no "A5 exported_used (a caller) listed"; else ok "A5 a called extern def is not listed"; fi

# ── A6/A7/A8 shape and legend ─────────────────────────────────────────────────────────────────────────────────────────────
chk "A6 bare run" --dead-code && BARE="$CHK" || BARE="<exported"
if printf '%s' "$BARE" | grep -q '<exported\|linkage='; then no "A6 bare --dead-code carries the group or its legend"; else ok "A6 bare --dead-code: no group, no linkage= term"; fi
if printf '%s' "$CC" | tr -d '\n' | grep -q '<d n="internal_dead"[^>]*/><exported '; then ok "A7 the group follows the d rows"; else no "A7 the group is not right after the d rows"; fi
if printf '%s' "$PY" | tr -d '\n' | grep -q '</exported></dead-code>'; then ok "A7 the group is the root's last child"; else no "A7 </exported></dead-code> missing"; fi
if printf '%s' "$PY" | grep -- '<!--' | grep -q 'linkage='; then ok "A8 the compact legend reads linkage="; else no "A8 compact legend lacks linkage="; fi
FULL="$( run --dead-code=pkg/net.py --legend=full )"
if printf '%s' "$FULL" | grep -q 'PUBLIC free functions of the filtered files' && printf '%s' "$FULL" | grep -q 'evidence=\\\?"no-non-test-caller'; then ok "A8 the full legend carries the exported clause"; else no "A8 full legend lacks the exported clause"; fi
FULLB="$( run --dead-code --legend=full )"
if printf '%s' "$FULLB" | grep -q 'PUBLIC free functions'; then no "A8 the clause rides an answer with no group"; else ok "A8 the clause is present-only"; fi

# ── A9/A10/A11 paging, empty filter, files cap ────────────────────────────────────────────────────────────────────────────
chk "A9 page 2" --dead-code=pkg/net.py --limit=1 --offset=1 && P2="$CHK" || P2="<exported"
if printf '%s' "$P2" | grep -q '<exported'; then no "A9 the group repeats past the first page"; else ok "A9 the group rides the first page only"; fi
chk "A10 static-only file" --dead-code=cc/only_static.cpp && ST="$CHK" || ST="<exported"
if printf '%s' "$ST" | grep -q '<exported'; then no "A10 a group on a file with no public free function"; else ok "A10 no public candidate, no group (byte-identical)"; fi
chk "A11 seven files" --dead-code=many && MANY="$CHK" || MANY=""
if group "$MANY" | grep -q 'files="6" files_total="7"' && group "$MANY" | grep -q 'total="6" shown="6"'; then ok "A11 files cap disclosed: files=6 of files_total=7"; else no "A11 cap not disclosed: $( group "$MANY" )"; fi

chk "A11 101 rows" --dead-code=wide && WIDE="$CHK" || WIDE=""
if group "$WIDE" | grep -q 'total="101" shown="100" files="1" files_total="1" capped="1"' && [ "$( printf '%s' "$WIDE" | grep -o '<e n=' | wc -l | tr -d ' ' )" = 100 ]; then ok "A11 row cap disclosed: shown=100 of total=101, capped=1"; else no "A11 row cap: $( group "$WIDE" )"; fi
if group "$PY" | grep -q 'capped='; then no "A11 capped= on an uncut group"; else ok "A11 capped= is present-only"; fi

# ── A12 well-formed ───────────────────────────────────────────────────────────────────────────────────────────────────────
if command -v xmllint >/dev/null 2>&1; then
    for doc in "$PY" "$TS" "$CC" "$FULL"; do
        if printf '%s' "$doc" | xmllint --noout - 2>/dev/null; then ok "A12 well-formed"; else no "A12 not well-formed"; fi
    done
else
    echo "  SKIP  A12 xmllint absent"
fi

# ── A13 optional: byte-identical to the base binary once the group is removed ─────────────────────────────────────────────
if [ -n "${RIPWIRE_BASE_BIN:-}" ] && [ -x "${RIPWIRE_BASE_BIN}" ]; then
    strip(){ python3 -c 'import re,sys; s=sys.stdin.read(); s=re.sub(r"<exported .*?</exported>","",s,flags=re.S); print(re.sub(r"<!--.*?-->","",s,flags=re.S))'; }
    for args in "--dead-code=pkg/net.py" "--dead-code=cc/lib.cpp" "--dead-code=web/path.ts" "--dead-code"; do
        a="$( run $args | strip )"; b="$( cd "$F" && "$RIPWIRE_BASE_BIN" "$F" --no-cache $args 2>/dev/null | strip )"
        if [ "$a" = "$b" ]; then ok "A13 $args: root and rows byte-identical to base"; else no "A13 $args differs from base beyond the group"; fi
    done
fi

[ "$fail" = 0 ] && echo "deadcodescopecheck: PASS" || echo "deadcodescopecheck: FAIL"
exit "$fail"
