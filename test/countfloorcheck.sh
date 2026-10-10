#!/usr/bin/env bash
# countfloorcheck.sh — a ZERO (or any count) the index cannot know is complete is printed as a FLOOR beside the
# number, with the call that finds the rest; a count the index CAN vouch for stays a plain total. Plus the
# call-site line on a --safe-delete caller row.
#
# WHY. Graded answers called eight of this tool's printed counts false claims, and every one of them was a
# number the graph really held, read as a total:
#   * `<enc n="Selection::tail" callers="0">` (grep) while six calls the resolver DECLINED to bind named it;
#   * `<enc n="BACKEND" callers="0">` (grep) about a module variable that another file READS — a variable is
#     never called, so a call count is blind to its every use;
#   * `--safe-delete=<a C struct>` answering callers="0" uses="0" risk="none-found" about a C struct whose type
#     mentions the index does not capture at all (thirty files use it);
#   * `<iface n="Router" implementors="1">` (the --for bundle) on a tree with six — the bundle printed the
#     number of rows it LISTED after narrowing to its own files, not how many implementors there are;
#   * and --safe-delete's caller rows carried the caller's DEFINITION line where the edit needs the CALL line.
# A root's counts_floor="1" and a legend's "a zero means none found" are blanket sentences far from the number;
# the reader takes the number. The marker now sits beside it, only where the index holds evidence of a miss.
#
# Arms (temp corpora, no git; every positive has a near-miss negative the new code could plausibly mishandle):
#   A  C struct, safe-delete: callers_floor + uses_floor + risk="unmodelled" + next= the literal grep;
#      and the clue LEADS to the uses (the grep names the file that declares a `struct cell`).
#   B  (negative) a static C function nobody calls: a provably complete zero stays callers="0" risk="none-found",
#      dead_code_candidate="1", no floor marker, no next=.
#   R  (negatives) recursion: a self-call is bound to the definition itself (C static fn, Python self.m() and module fn,
#      mutual recursion); (near miss) a recursive TS method with an outside same-named call bound nowhere still floors.
#   C  CALLSITE-LINE -> CALLSITE-AT (2026-10-09): --safe-delete=width_of rows carry sites_at= (the call sites as pasteable
#      file:line tokens; it was sites_l=, bare lines) beside p= (the definition line): a caller with three calls on three
#      lines lists all three; one call split over two lines lists its line. Twin: no safe-delete row carries sites_l= now.
#   D  (near-miss) a single-definition symbol called once still prints its call site (sites_at= present, one token).
#   E  grep <enc> on a Python module VARIABLE: callers_floor="1" floor_next="--uses=BACKEND", and --uses=BACKEND
#      (the clue) lists the reading file.
#   F  grep <enc> on a method whose only call the resolver DECLINED (two same-named defs in other dirs, an
#      untyped receiver): callers="0" callers_floor="1".
#   F2 the same, from a caller that also BINDS a same-named call elsewhere — the declined evidence alone floors it.
#   G  grep <enc> on a TS method whose only call is spelled like it and bound NOWHERE (unresolved, no decline).
#   H  grep <enc> on a C function stored in a table and never called directly (a value use).
#   I  (negative) grep <enc> on a C function with only direct, bound calls: callers="2", no marker.
#   J  (negative) grep <enc> on a markdown heading: callers="0" stays plain (nothing calls or reads a heading).
#   K  --for bundle <lego>: implementors= is the lego verb's own count (6) even when fewer rows are listed, with
#      implementors_shown= + implementors_next=; (negative) all rows listed => no shown/next attribute.
#   L  <lego> implementors_floor: an inherit clause naming the interface that bound nowhere (a cross-language base)
#      floors the count on the bundle AND the targeted verb; (negative) without it, no marker.
#   L2 (negatives) a bound Rust `impl Trait for T` and a twice-opened Ruby class do not floor (the graph re-keys
#      their derived type); (near miss) a Rust impl for a type the tree never defines still floors.
#   M  MCP twins: grep's `enclosing` JSON carries callers_floor/floor_next exactly where the CLI <enc> does; the MCP
#      `for` lego block equals the CLI's.
#   GO grep <enc> on the Go kinds honesty-small-068 added (t="type" `type N string`, t="functype"): read as a struct
#      is (a conversion is one call, a type mention is never counted) => callers_floor="1" + floor_next=, like the
#      Go struct beside them (the kinds' rows in countfloor.h kUseFormOfKind, train 26b).
#   N  legend: every new attribute is defined in the answer that carries it (compact and full dialects).
#   O  determinism (x2) + xmllint.
#
# Usage: bash test/countfloorcheck.sh [BIN]   |   RIPWIRE_BIN=asan/ripwire bash test/countfloorcheck.sh

set -u
ROOT="$( cd "$( dirname "$0" )/.." && pwd )"
BIN="${1:-${RIPWIRE_BIN:-$ROOT/build/ripwire}}"
[ "${BIN#/}" = "$BIN" ] && BIN="$ROOT/$BIN"
fail=0
ok(){ printf '  PASS  %s\n' "$*" || { fail=1; printf '  FAIL  could not write the PASS line for: %s\n' "$*"; }; return 0; }
no(){ printf '  FAIL  %s\n' "$*"; fail=1; }

[ -x "$BIN" ] || { echo "no ripwire binary at $BIN — build first"; exit 2; }
command -v python3 >/dev/null 2>&1 || { echo "countfloorcheck: SKIP — python3 not found (needed for the MCP JSON arm)"; exit 0; }
command -v perl >/dev/null 2>&1 || { echo "countfloorcheck: SKIP — perl not found (needed to read past legend comments)"; exit 0; }

W="$( mktemp -d )"; trap 'rm -rf "$W"' EXIT
mkdir -p "$W/c" "$W/py/pkg/css" "$W/py/pkg/other" "$W/ts" "$W/md"

# ── corpora ──────────────────────────────────────────────────────────────────────────────────────────────
cat > "$W/c/a.h" <<'EOF'
struct cell { int ch; int attr; };
int width_of(const char *s);
EOF
cat > "$W/c/a.c" <<'EOF'
#include "a.h"
static int helper_dead(int x) { return x + 1; }
int width_of(const char *s)
{
    int n = 0;
    while (*s) { n++; s++; }
    return n;
}
int pad(const char *s)
{
    int w = width_of(s);
    w += width_of("x");
    w += width_of("yz");
    return w;
}
static int twice(int v) { return v * 2; }
int user(void)
{
    struct cell c;
    c.ch = twice(1);
    return pad("a")
        + width_of("yy");
}
EOF
cat > "$W/c/ops.c" <<'EOF'
struct ops { int (*run)(int); };
static int run_fn(int v) { return v + 41; }
static const struct ops table = { .run = run_fn };
int dispatch(int v) { return table.run(v); }
EOF
cat > "$W/py/pkg/constants.py" <<'EOF'
import os
BACKEND = os.environ.get("APP_BACKEND_ENV", None)
EOF
cat > "$W/py/pkg/app.py" <<'EOF'
from . import constants

def get_backend():
    d = constants.BACKEND
    return d
EOF
cat > "$W/py/pkg/css/query.py" <<'EOF'
class Selection:
    def tail(self):
        raise ValueError("no items match last")
EOF
cat > "$W/py/pkg/other/cache.py" <<'EOF'
class LRU:
    def tail(self):
        return "lru tail"
EOF
cat > "$W/py/pkg/use.py" <<'EOF'
def use_param(q):
    return q.tail()
EOF
# F2: one caller binds a same-named call elsewhere (x = LRU(); x.head()) and has a second one DECLINED (q.head()):
# the unbound scan treats that caller as bound, so only the declined evidence can floor Selection.head
mkdir -p "$W/py2/pkg/css" "$W/py2/pkg/other"
printf 'class Selection:\n    def head(self):\n        raise ValueError("first item marker")\n' > "$W/py2/pkg/css/query.py"
printf 'class LRU:\n    def head(self):\n        return "lru head"\n' > "$W/py2/pkg/other/cache.py"
printf 'def mixed(q):\n    x = LRU()\n    x.head()\n    return q.head()\n' > "$W/py2/pkg/mix.py"
cat > "$W/ts/router.ts" <<'EOF'
export interface Router<T> { add(m: string): void; match(p: string): T | null }
EOF
for n in Alpha Beta Gamma Delta Epsilon Zeta; do
cat > "$W/ts/$n.ts" <<EOF
import { Router } from './router'
export class ${n}Router<T> implements Router<T> {
  add(m: string): void {}
  match(p: string): T | null { return null }
}
EOF
done
cat > "$W/ts/lonely.ts" <<'EOF'
export class Lonely { lonelyMatch(p: string): string { return "lonely marker " + p } }
export function onlyName() { return lonelyMatch('y') }
EOF
cat > "$W/md/notes.md" <<'EOF'
# Notes

## Added

- Added HEADING_MARKER environment variable
EOF

run(){ ( cd "$W/$1" && shift && "$BIN" . --no-cache "$@" 2>/dev/null ); }
root_tag(){ nocomment "$1" | grep -oE "<$2 [^>]*>" | head -1; }
attr(){ printf '%s' "$1" | grep -oE " $2=\"[^\"]*\"" | head -1 | sed -e "s/^ $2=\"//" -e 's/"$//'; }
nocomment(){ printf '%s' "$1" | perl -0pe 's/<!--.*?-->//gs'; }
comments(){ printf '%s' "$1" | perl -0ne 'print "$&\n" while /<!--.*?-->/gs'; }
first_iface(){ nocomment "$1" | grep -oE '<iface [^>]*>' | head -1; }
enc_row(){ printf '%s' "$1" | grep -oE "<enc n=\"$2\"[^>]*/>" | head -1; }

echo "countfloorcheck: BIN=$BIN"

# ── A: a C struct ──────────────────────────────────────────────────────────────────────────────────
echo "=== A: --safe-delete on a C struct: the zero is a floor, risk is no reading, next= finds its uses ==="
OUT_A="$( run c --safe-delete=cell )"; R_A="$( root_tag "$OUT_A" safe-delete )"
[ -n "$R_A" ] || no "(A) premise: no <safe-delete> root for cell"
[ "$( attr "$R_A" callers )" = 0 ] && [ "$( attr "$R_A" uses )" = 0 ] || no "(A) premise: callers/uses are not 0: $R_A"
if [ "$( attr "$R_A" callers_floor )" = 1 ]; then ok "(A) callers_floor=\"1\" beside callers=\"0\""; else no "(A) callers=\"0\" printed as a total: $R_A"; fi
if [ "$( attr "$R_A" uses_floor )" = 1 ]; then ok "(A) uses_floor=\"1\" beside uses=\"0\""; else no "(A) uses=\"0\" printed as a total: $R_A"; fi
if [ "$( attr "$R_A" risk )" = unmodelled ]; then ok "(A) risk=\"unmodelled\", never none-found"; else no "(A) risk=\"$( attr "$R_A" risk )\", expected unmodelled"; fi
NEXT_A="$( attr "$R_A" next )"
if [ "$NEXT_A" = "--grep=cell" ]; then ok "(A) next=\"--grep=cell\" (C reads are never indexed: the literal scan)"; else no "(A) next=\"$NEXT_A\", expected --grep=cell"; fi
FOLLOW_A="$( run c "$NEXT_A" )"
printf '%s' "$FOLLOW_A" | grep -q '<f p="a.c">' && ok "(A) the clue leads to the use: --grep=cell names a.c (struct cell c;)" \
    || no "(A) following next= did not reach a.c"

# ── B: a provably complete zero ──────────────────────────────────────────────────────────────────────────
echo "=== B: a static C function with no call anywhere keeps a plain zero ==="
R_B="$( root_tag "$( run c --safe-delete=helper_dead )" safe-delete )"
[ "$( attr "$R_B" callers )" = 0 ] && [ "$( attr "$R_B" risk )" = none-found ] && [ "$( attr "$R_B" dead_code_candidate )" = 1 ] \
    && ok "(B) callers=\"0\" risk=\"none-found\" dead_code_candidate=\"1\" (unchanged)" || no "(B) the complete zero changed: $R_B"
case "$R_B" in *callers_floor=*|*uses_floor=*|*' next='*) no "(B) a provably complete zero carries a floor marker: $R_B" ;; *) ok "(B) no floor marker, no next= on a complete zero" ;; esac

# ── R: recursion — a self-call bound to the definition itself is not evidence of a miss ─────────────────
# graph.h drops self-loops (CallDisposition::Self), so a recursive call commits no edge: the unbound scan must still
# count it as bound (it bound to this very definition). Negatives: a static recursive C function with no other caller,
# a Python method recursing through self.m() and a recursive module function, mutual recursion (both edges bound).
# Near miss: a recursive TS method that ALSO has a same-named call bound nowhere still floors.
echo "=== R: a recursive function's own call keeps a plain count; an unbound outside call still floors ==="
mkdir -p "$W/crec" "$W/pyrec" "$W/tsrec"
printf 'static int fact(int n) { return n ? n * fact(n - 1) : 1; }\nstatic int pong(int n);\nstatic int ping(int n) { return n ? pong(n - 1) : 0; }\nstatic int pong(int n) { return n ? ping(n - 1) : 1; }\nint entry(void) { return ping(3); }\n' > "$W/crec/r.c"
printf 'class Walker:\n    def walk(self, n):\n        return self.walk(n - 1) if n else 0\n\ndef walk_tree(n):\n    return walk_tree(n - 1) if n else 0\n' > "$W/pyrec/w.py"
printf 'export class Tree { walkDown(n: number): number { return n ? this.walkDown(n - 1) : 0 } }\nexport function outside() { return walkDown(3) }\n' > "$W/tsrec/t.ts"
R_R1="$( root_tag "$( run crec --safe-delete=fact )" safe-delete )"
[ "$( attr "$R_R1" callers )" = 0 ] && [ "$( attr "$R_R1" dead_code_candidate )" = 1 ] || no "(R) premise: fact: $R_R1"
case "$R_R1" in *callers_floor=*|*' next='*) no "(R) a static recursive C function with no caller is floored: $R_R1" ;; *) ok "(R) --safe-delete=fact (self-call only): no callers_floor, no next=" ;; esac
ROW_R1="$( enc_row "$( run crec --grep='n - 1) : 1' )" fact )"
[ -n "$ROW_R1" ] || no "(R) premise: no <enc> row for fact"
case "$ROW_R1" in *callers_floor=*) no "(R) grep <enc> fact (self-call only) is floored: $ROW_R1" ;; *) ok "(R) grep <enc n=\"fact\"> stays a plain zero" ;; esac
OUT_R2="$( run pyrec --grep='if n else 0' )"
ROW_R2="$( enc_row "$OUT_R2" 'Walker::walk' )"; ROW_R3="$( enc_row "$OUT_R2" walk_tree )"
[ -n "$ROW_R2" ] && [ -n "$ROW_R3" ] || no "(R) premise: Python rows: [$ROW_R2] [$ROW_R3]"
case "$ROW_R2" in *callers_floor=*) no "(R) Python self.walk() recursion is floored: $ROW_R2" ;; *) ok "(R) Python method recursing via self.walk(): no callers_floor" ;; esac
case "$ROW_R3" in *callers_floor=*) no "(R) Python recursive module function is floored: $ROW_R3" ;; *) ok "(R) Python recursive module function walk_tree: no callers_floor" ;; esac
R_R3="$( root_tag "$( run pyrec --safe-delete=walk_tree )" safe-delete )"
case "$R_R3" in *callers_floor=*|*' next='*) no "(R) --safe-delete=walk_tree is floored: $R_R3" ;; *) ok "(R) --safe-delete=walk_tree: no callers_floor, no next=" ;; esac
OUT_RM="$( run crec --grep='n ? p' )"; ROW_PING="$( enc_row "$OUT_RM" pong )"; ROW_PONG="$( enc_row "$OUT_RM" ping )"
[ "$( attr "$ROW_PING" callers )" = 1 ] && [ "$( attr "$ROW_PONG" callers )" = 2 ] || no "(R) premise: mutual recursion counts: [$ROW_PING] [$ROW_PONG]"
case "$ROW_PING$ROW_PONG" in *callers_floor=*) no "(R) bound mutual recursion is floored: $ROW_PING $ROW_PONG" ;; *) ok "(R) mutual recursion ping<->pong (both bound): no callers_floor" ;; esac
ROW_R4="$( enc_row "$( run tsrec --grep='this.walkDown' )" walkDown )"
if [ "$( attr "$ROW_R4" callers_floor )" = 1 ]; then ok "(R) near miss: recursive walkDown with an outside call bound nowhere still floors"; else no "(R) near miss lost its floor: $ROW_R4"; fi

# ── C/D: the call-site line ──────────────────────────────────────────────────────────────────────────────
echo "=== C/D: --safe-delete caller rows carry the CALL lines beside the definition line ==="
OUT_C="$( run c --safe-delete=width_of )"
ROW_PAD="$( printf '%s' "$OUT_C" | grep -oE '<c n="pad"[^>]*/>' | head -1 )"
ROW_USER="$( printf '%s' "$OUT_C" | grep -oE '<c n="user"[^>]*/>' | head -1 )"
if [ "$( attr "$ROW_PAD" p )" = "a.c:9" ]; then ok "(C) p= still names the caller's definition line (a.c:9)"; else no "(C) p= changed on the pad row: $ROW_PAD"; fi
if [ "$( attr "$ROW_PAD" sites_at )" = "a.c:11 a.c:12 a.c:13" ]; then ok "(C) three calls on three lines: sites_at=\"a.c:11 a.c:12 a.c:13\""; else no "(C) pad row: $ROW_PAD"; fi
if [ "$( attr "$ROW_USER" sites_at )" = "a.c:22" ]; then ok "(C) a call continued onto its own line: sites_at=\"a.c:22\""; else no "(C) user row: $ROW_USER"; fi
printf '%s' "$OUT_C" | grep -q '<c [^>]*sites_l=' && no "(C-twin) a safe-delete row still carries the bare-line sites_l=" \
    || ok "(C-twin) safe-delete rows carry sites_at= only (the bare-line sites_l= stays on edit-check)"
ROW_TW="$( printf '%s' "$( run c --safe-delete=twice )" | grep -oE '<c n="user"[^>]*/>' | head -1 )"
if [ "$( attr "$ROW_TW" sites_at )" = "a.c:20" ]; then ok "(D) a single-definition callee called once still prints its call site (a.c:20)"; else no "(D) twice row: $ROW_TW"; fi
R_C="$( root_tag "$OUT_C" safe-delete )"
case "$R_C" in *callers_floor=*) no "(C) bound direct calls only, yet callers is floored: $R_C" ;; *) ok "(C) callers=\"2\" with no floor (every call bound)" ;; esac

# ── E: a Python variable ─────────────────────────────────────────────────────────────────────────────────
echo "=== E: grep <enc> on a module variable ==="
OUT_E="$( run py --grep=APP_BACKEND_ENV )"; ROW_E="$( enc_row "$OUT_E" BACKEND )"
[ "$( attr "$ROW_E" callers )" = 0 ] || no "(E) premise: BACKEND row: $ROW_E"
if [ "$( attr "$ROW_E" callers_floor )" = 1 ]; then ok "(E) callers_floor=\"1\" on a variable's call count"; else no "(E) <enc BACKEND> printed callers=\"0\" as a total: $ROW_E"; fi
NEXT_E="$( attr "$ROW_E" floor_next )"
if [ "$NEXT_E" = "--uses=BACKEND" ]; then ok "(E) floor_next=\"--uses=BACKEND\""; else no "(E) floor_next=\"$NEXT_E\""; fi
if run py "$NEXT_E" | grep -q 'pkg/app.py:4'; then ok "(E) the clue leads to the reader: --uses=BACKEND lists pkg/app.py:4"; else no "(E) --uses=BACKEND did not list the reading line"; fi
R_ED="$( root_tag "$( run py --safe-delete=BACKEND )" safe-delete )"
[ "$( attr "$R_ED" uses_floor )" = 1 ] && [ "$( attr "$R_ED" risk )" = unmodelled ] && [ "$( attr "$R_ED" next )" = "--uses=BACKEND" ] \
    && ok "(E) --safe-delete=BACKEND: uses_floor=\"1\" risk=\"unmodelled\" next=\"--uses=BACKEND\" (Python reads ARE indexed by the uses verb)" \
    || no "(E) --safe-delete=BACKEND: $R_ED"

# ── F: a declined call ───────────────────────────────────────────────────────────────────────────────────
echo "=== F: grep <enc> on a method whose one call was declined ==="
OUT_F="$( run py --grep='no items match' )"; ROW_F="$( enc_row "$OUT_F" 'Selection::tail' )"
CALLERS_F="$( root_tag "$( run py --callers=Selection.tail )" callers )"
[ -n "$( attr "$CALLERS_F" declined_calls )" ] || no "(F) premise: the q.tail() call is not declined here: $CALLERS_F"
[ "$( attr "$ROW_F" callers )" = 0 ] && [ "$( attr "$ROW_F" callers_floor )" = 1 ] && [ "$( attr "$ROW_F" floor_next )" = "--uses=tail" ] \
    && ok "(F) callers=\"0\" callers_floor=\"1\" floor_next=\"--uses=tail\"" || no "(F) declined row: $ROW_F"

echo "=== F2: a declined call from a caller that ALSO binds the same name elsewhere — only the decline can floor it ==="
CALLERS_F2="$( root_tag "$( run py2 --callers=Selection.head )" callers )"
CALLERS_F2B="$( root_tag "$( run py2 --callers=LRU.head )" callers )"
[ -n "$( attr "$CALLERS_F2" declined_calls )" ] && [ "$( attr "$CALLERS_F2B" count )" = 1 ] || no "(F2) premise: want q.head() declined and x.head() bound: $CALLERS_F2 / $CALLERS_F2B"
ROW_F2="$( enc_row "$( run py2 --grep='first item marker' )" 'Selection::head' )"
if [ "$( attr "$ROW_F2" callers )" = 0 ] && [ "$( attr "$ROW_F2" callers_floor )" = 1 ]; then ok "(F2) declined-only evidence: callers_floor=\"1\""; else no "(F2) row: $ROW_F2"; fi

# ── G: an unbound call, no decline ───────────────────────────────────────────────────────────────────────
echo "=== G: grep <enc> on a TS method whose one call bound nowhere ==="
ROW_G="$( enc_row "$( run ts --grep='lonely marker' )" lonelyMatch )"
CALLERS_G="$( root_tag "$( run ts --callers=lonelyMatch )" callers )"
[ -z "$( attr "$CALLERS_G" declined_calls )" ] || no "(G) premise: this arm wants NO decline: $CALLERS_G"
if [ "$( attr "$ROW_G" callers )" = 0 ] && [ "$( attr "$ROW_G" callers_floor )" = 1 ]; then ok "(G) unbound same-name call: callers_floor=\"1\""; else no "(G) row: $ROW_G"; fi

# ── H: a value use ───────────────────────────────────────────────────────────────────────────────────────
echo "=== H: grep <enc> on a C function only a table holds ==="
ROW_H="$( enc_row "$( run c --grep='v + 41' )" run_fn )"
if [ "$( attr "$ROW_H" callers )" = 0 ] && [ "$( attr "$ROW_H" callers_floor )" = 1 ]; then ok "(H) value use: callers_floor=\"1\""; else no "(H) row: $ROW_H"; fi

# ── I/J: complete counts stay plain ──────────────────────────────────────────────────────────────────────
echo "=== I/J: counts the index can vouch for stay plain totals ==="
ROW_I="$( enc_row "$( run c --grep='n++' )" width_of )"
[ "$( attr "$ROW_I" callers )" = 2 ] || no "(I) premise: width_of row: $ROW_I"
case "$ROW_I" in *callers_floor=*|*floor_next=*) no "(I) a fully bound count carries a floor: $ROW_I" ;; *) ok "(I) callers=\"2\" stays a plain total" ;; esac
ROW_J="$( printf '%s' "$( run md --grep=HEADING_MARKER )" | grep -oE '<enc [^>]*/>' | head -1 )"
[ -n "$ROW_J" ] || no "(J) premise: no <enc> row for the heading"
case "$ROW_J" in *callers_floor=*) no "(J) a markdown heading's zero is floored: $ROW_J" ;; *) ok "(J) a heading's callers=\"0\" stays plain" ;; esac

# ── K: the --for lego count ──────────────────────────────────────────────────────────────────────────────
echo "=== K: the --for bundle's implementors= is the lego verb's count, a short list says so ==="
TOTAL_K="$( attr "$( first_iface "$( run ts --lego=Router )" )" implementors )"
[ "$TOTAL_K" = 6 ] || no "(K) premise: --lego=Router implementors=\"$TOTAL_K\", expected 6"
LEGO_ALL="$( run ts '--for=which router classes implement the Router interface' | grep -oE '<iface n="Router"[^>]*>' | head -1 )"
if [ "$( attr "$LEGO_ALL" implementors )" = 6 ]; then ok "(K) all six listed: implementors=\"6\""; else no "(K) $LEGO_ALL"; fi
case "$LEGO_ALL" in *implementors_shown=*|*implementors_next=*) no "(K) every row listed, yet a short-list marker: $LEGO_ALL" ;; *) ok "(K) no implementors_shown= when every row is listed" ;; esac
# the narrowed shape, built by construction: a task that reaches ONE implementor's file and the interface's
# file, so the bundle's rows are narrowed to the files its own sigs render (legobundlecheck rule 2) — one row of six
mkdir -p "$W/tsn"; cp "$W/ts/"[A-Z]*.ts "$W/ts/router.ts" "$W/tsn/"
printf 'export function routerDeltaDispatch(): number { return 1 }\n' >> "$W/tsn/router.ts"
cat > "$W/tsn/Delta.ts" <<'EOF'
import { Router } from './router'
export class DeltaRouter<T> implements Router<T> {
  add(m: string): void {}
  match(p: string): T | null { return null }
  deltaDispatch(p: string): number { return p.length }
}
EOF
LEGO_N="$( run tsn '--for=delta dispatch' | grep -oE '<iface n="Router"[^>]*>' | head -1 )"
if [ -z "$LEGO_N" ]; then
    no "(K) premise: no Router iface row in the narrowed bundle"
else
    IMPL_N="$( attr "$LEGO_N" implementors )"; SHOWN_N="$( attr "$LEGO_N" implementors_shown )"
    if [ "$IMPL_N" = 6 ]; then ok "(K) narrowed bundle still says implementors=\"6\""; else no "(K) narrowed bundle: $LEGO_N"; fi
    if [ -n "$SHOWN_N" ]; then
        [ "$SHOWN_N" -lt 6 ] && [ "$( attr "$LEGO_N" implementors_next )" = "--lego=router.ts:Router" ] \
            && ok "(K) implementors_shown=\"$SHOWN_N\" implementors_next=\"--lego=router.ts:Router\"" || no "(K) short-list marker: $LEGO_N"
        if run tsn --lego=router.ts:Router | grep -q 'implementors="6"'; then ok "(K) the clue lists all six"; else no "(K) implementors_next did not list six"; fi
    else
        no "(K) premise: the bundle was not narrowed (no implementors_shown=): $LEGO_N"
    fi
fi

# ── L: implementors floor ────────────────────────────────────────────────────────────────────────────────
echo "=== L: an inherit clause naming the interface that bound nowhere floors implementors= ==="
mkdir -p "$W/tsl"; cp "$W/ts/"*.ts "$W/tsl/"
printf 'class PyRouter(Router):\n    def add(self, m):\n        return m\n' > "$W/tsl/py_router.py"
IF_L="$( first_iface "$( run tsl --lego=Router )" )"
[ "$( attr "$IF_L" implementors )" = 6 ] || no "(L) premise: the Python class must not be counted: $IF_L"
[ "$( attr "$IF_L" implementors_floor )" = 1 ] && [ "$( attr "$IF_L" floor_next )" = "--uses=Router" ] \
    && ok "(L) --lego: implementors_floor=\"1\" floor_next=\"--uses=Router\"" || no "(L) --lego: $IF_L"
IF_LB="$( run tsl '--for=which router classes implement the Router interface' | grep -oE '<iface n="Router"[^>]*>' | head -1 )"
if [ "$( attr "$IF_LB" implementors_floor )" = 1 ]; then ok "(L) the --for bundle carries the same floor"; else no "(L) bundle: $IF_LB"; fi
case "$( first_iface "$( run ts --lego=Router )" )" in *implementors_floor=*) no "(L) a fully bound interface carries implementors_floor" ;; *) ok "(L) no floor when every inherit clause bound" ;; esac

# ── L2: the derived type is the one the GRAPH bound, not the reference's enclosing symbol ─────────────────
# graph.h's inheritance pass re-keys two languages' derived type: a Rust `impl Trait for T` header sits outside T's
# span (the ref carries T's NAME in `qualifier`; fromSymbol is whatever encloses the impl), and a reopened Ruby class
# is ONE implementor (rubyBases.canonicalClass), so the clause in the second `class Foo < Base` comes from a symbol id
# the implementor list does not hold. Both are BOUND clauses and must not floor; a Rust impl for a type the tree
# never defines is the near miss that still must.
echo "=== L2: a bound Rust impl / a reopened Ruby class is not evidence of a miss; an impl for an undefined type is ==="
mkdir -p "$W/rs" "$W/rsg" "$W/rb"
printf 'pub trait Shape { fn area(&self) -> u32; }\npub struct Widget { n: u32 }\nimpl Shape for Widget { fn area(&self) -> u32 { self.n } }\n' > "$W/rs/lib.rs"
cp "$W/rs/lib.rs" "$W/rsg/lib.rs"; printf 'impl Shape for Ghost { fn area(&self) -> u32 { 0 } }\n' >> "$W/rsg/lib.rs"
printf 'class Base\nend\nclass Foo < Base\n  def a; end\nend\nclass Foo < Base\n  def b; end\nend\n' > "$W/rb/a.rb"
IF_RS="$( first_iface "$( run rs --lego=Shape )" )"
[ "$( attr "$IF_RS" implementors )" = 1 ] || no "(L2) premise: Rust Shape must have its one implementor: $IF_RS"
case "$IF_RS" in *implementors_floor=*) no "(L2) a bound Rust impl floors implementors=: $IF_RS" ;; *) ok "(L2) Rust impl Shape for Widget (bound): no floor" ;; esac
IF_RB="$( first_iface "$( run rb --lego=Base )" )"
[ "$( attr "$IF_RB" implementors )" = 1 ] || no "(L2) premise: the reopened Ruby class must be one implementor: $IF_RB"
case "$IF_RB" in *implementors_floor=*) no "(L2) a reopened Ruby class floors implementors=: $IF_RB" ;; *) ok "(L2) Ruby class Foo < Base opened twice (bound): no floor" ;; esac
IF_RSG="$( first_iface "$( run rsg --lego=Shape )" )"
[ "$( attr "$IF_RSG" implementors )" = 1 ] && [ "$( attr "$IF_RSG" implementors_floor )" = 1 ] \
    && ok "(L2) Rust impl Shape for an undefined Ghost (unbound) still floors" || no "(L2) near miss: $IF_RSG"

# ── M: MCP twins ─────────────────────────────────────────────────────────────────────────────────────────
echo "=== M: the MCP grep and for twins say the same thing ==="
cat > "$W/mcptext.py" <<'PY'
import sys, json
for line in sys.stdin:
    line = line.strip()
    if not line: continue
    try: d = json.loads( line )
    except Exception: continue
    c = d.get( "result", {} ).get( "content" )
    if c: print( c[0].get( "text", "" ) )
PY
mcp_call(){ printf '{"jsonrpc":"2.0","id":1,"method":"tools/call","params":{"name":"%s","arguments":%s}}\n' "$1" "$2" \
            | "$BIN" --mcp 2>/dev/null | python3 "$W/mcptext.py"; }
MCP_G="$( mcp_call grep "{\"path\":\"$W/py\",\"pattern\":\"APP_BACKEND_ENV\"}" )"
printf '%s' "$MCP_G" | python3 -c '
import json, sys
d = json.loads( sys.stdin.read() )
rows = { r["n"]: r for r in d.get( "enclosing", [] ) }
r = rows.get( "BACKEND", {} )
sys.exit( 0 if r.get( "callers" ) == 0 and r.get( "callers_floor" ) == 1 and r.get( "floor_next" ) == "--uses=BACKEND" else 1 )' \
    && ok "(M) MCP grep enclosing BACKEND: callers 0, callers_floor 1, floor_next --uses=BACKEND" || no "(M) MCP grep: $MCP_G"
MCP_GI="$( mcp_call grep "{\"path\":\"$W/c\",\"pattern\":\"n++\"}" )"
printf '%s' "$MCP_GI" | python3 -c '
import json, sys
d = json.loads( sys.stdin.read() )
r = { x["n"]: x for x in d.get( "enclosing", [] ) }.get( "width_of", {} )
sys.exit( 0 if r.get( "callers" ) == 2 and "callers_floor" not in r and "floor_next" not in r else 1 )' \
    && ok "(M) MCP grep: a complete count carries no floor key (as on the CLI)" || no "(M) MCP grep negative: $MCP_GI"
MCP_F="$( mcp_call for "{\"path\":\"$W/tsl\",\"task\":\"which router classes implement the Router interface\",\"sections\":\"lego\"}" | grep -oE '<lego>.*</lego>' | head -1 )"
CLI_F="$( run tsl '--for=which router classes implement the Router interface' --sections=lego | grep -oE '<lego>.*</lego>' | head -1 )"
if [ -n "$CLI_F" ] && [ "$MCP_F" = "$CLI_F" ]; then ok "(M) MCP for <lego> == CLI --for <lego> (implementors_floor included)"; else no "(M) lego twin differs: cli='$CLI_F' mcp='$MCP_F'"; fi

# ── GO: the Go named-type kinds floor as a struct does ──────────────────────────────────────────────────────
echo "=== GO: grep <enc> on Go t=\"type\" / t=\"functype\" floors like the Go struct ==="
mkdir -p "$W/go"
printf 'package m\n\ntype TestName string\n\ntype Pair struct{ a int }\n\ntype Handler func(int) int\n\nfunc Use(s string) int {\n\tn := TestName(s)\n\tvar p Pair\n\t_ = p\n\treturn len(n)\n}\n\nfunc Wrap(h Handler) int { return h(1) }\n' > "$W/go/m.go"
MAP_GO="$( run go )"
for kn in "type:TestName" "struct:Pair" "functype:Handler"; do
    printf '%s' "$MAP_GO" | grep -q "<s t=\"${kn%%:*}\" n=\"${kn#*:}\"" || no "(GO) premise: ${kn#*:} is not t=\"${kn%%:*}\" in the map"
done
for n in TestName Pair Handler; do
    E_GO="$( enc_row "$( run go "--grep=$n" )" "$n" )"
    [ -n "$E_GO" ] || { no "(GO) premise: no <enc n=\"$n\"> row"; continue; }
    if [ "$( attr "$E_GO" callers_floor )" = 1 ] && [ "$( attr "$E_GO" floor_next )" = "--grep=$n" ]; then
        ok "(GO) <enc n=\"$n\"> callers=\"$( attr "$E_GO" callers )\" carries callers_floor=\"1\" floor_next=\"--grep=$n\""
    else
        no "(GO) <enc n=\"$n\"> printed its count as a total: $E_GO"
    fi
done

# ── N: legend ────────────────────────────────────────────────────────────────────────────────────────────
echo "=== N: every new attribute is defined where it rides ==="
for dialect in compact full; do
    L_A="$( run c --safe-delete=cell --legend=$dialect )"; L_C="$( run c --safe-delete=width_of --legend=$dialect )"
    L_E="$( run py --grep=APP_BACKEND_ENV --legend=$dialect )"
    L_K="$( run tsl '--for=which router classes implement the Router interface' --legend=$dialect )"
    for pair in "L_A:callers_floor=" "L_A:uses_floor=" "L_A:unmodelled" "L_C:sites_at=" "L_E:callers_floor=" "L_E:floor_next=" \
                "L_K:implementors_floor=" "L_K:implementors_shown=" "L_K:floor_next="; do
        var="${pair%%:*}"; term="${pair#*:}"
        comments "${!var}" | grep -qF -- "$term" \
            && ok "(N/$dialect) $term defined in the legend of the $var answer" || no "(N/$dialect) $term is not defined in the $var legend"
    done
done
case "$( run c --safe-delete=helper_dead --legend=compact )" in *callers_floor*|*uses_floor*|*sites_l*|*sites_at*) no "(N) a legend defines a floor/sites term its answer does not carry" ;; *) ok "(N) present-only: no floor/sites term on an answer without them" ;; esac

# ── O: determinism + xmllint ─────────────────────────────────────────────────────────────────────────────
echo "=== O: determinism and well-formed XML ==="
for spec in "c --safe-delete=cell" "c --safe-delete=width_of" "py --grep=APP_BACKEND_ENV" "tsl --lego=Router"; do
    set -- $spec; a="$( run "$@" )"; b="$( run "$@" )"
    if [ -n "$a" ] && [ "$a" = "$b" ]; then ok "(O) deterministic: $spec"; else no "(O) not deterministic (or empty): $spec"; fi
    if command -v xmllint >/dev/null 2>&1; then
        if printf '%s' "$a" | xmllint --noout - 2>/dev/null; then ok "(O) well-formed: $spec"; else no "(O) xmllint rejects: $spec"; fi
    fi
done

if [ "$fail" -ne 0 ]; then echo "countfloorcheck: FAIL"; exit 1; fi
echo "countfloorcheck: PASS"
exit 0
