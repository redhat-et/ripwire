#!/usr/bin/env bash
# qdrenameidentitycheck.sh — gate for QD-RENAME-IDENTITY (quality.h ContentMoves): a renamed or moved function whose body is
# unchanged keeps its identity in --quality-delta, so a behaviour-neutral rename or move reads as nothing; a body that also got
# worse, and a genuinely new clone, still show.
#
# Measured problem (reports/qd-catch-fresh-2026-11-13.md, ADDENDUM 2026-11-14): renaming a function and its callers left a row on
# 13/45 seeded runs and GATED 4/45 (each renamed function was one member of an existing clone pair, whose member-set hash moved
# with the name); moving a function to a sibling file left a row on 5/30.
#
# Per language (Python, TypeScript, Go, C++, Rust), in git-backed temp repos (the auto-baseline-vs-HEAD path). Arms that share a
# repo share one diff, to keep the gate to five runs per language; a failing arm names every row it saw.
#   P. PREMISES, counted, each FAILS on zero: the clone pair is one clone group at the baseline (--clones names both members), and
#      the big function is over the bars (a COPY of it under a new name, the original kept, prints new-symbol rows).
#   A+B. rename one member of the clone pair AND the over-bar function (definitions and callers): no row, exit 0 (was: duplication
#      + new-clone-of-reused-helper, gating, and new-symbol / moved rows on the big function).
#   C. move the over-bar function to a new sibling file (Python, TypeScript, Go, C++; Rust as a module): no row, exit 0.
#   D+E. rename the over-bar function AND add a nested branch to it, rename one clone-pair member AND add a third copy: the
#      complexity row on the new name still prints, and the duplication row still prints and gates (exit 2).
#
# Usage:  bash test/qdrenameidentitycheck.sh [BIN]
set -u
ROOT="$( cd "$( dirname "$0" )/.." && pwd )"
. "$ROOT/test/lib/clean-env.sh"
BIN="${1:-${RIPWIRE_BIN:-$ROOT/build/ripwire}}"
[ "${BIN#/}" = "$BIN" ] && BIN="$ROOT/$BIN"
fail=0
ok(){ printf '  PASS  %s\n' "$*" || { fail=1; printf '  FAIL  could not write the PASS line for: %s\n' "$*"; }; return 0; }
no(){ printf '  FAIL  %s\n' "$*"; fail=1; }
[ -x "$BIN" ] || { echo "no ripwire binary at $BIN — build first"; exit 2; }
command -v git >/dev/null 2>&1 || { echo "  SKIP  qdrenameidentitycheck (git required for the HEAD-baseline fixtures)"; exit 0; }

WORK="$( mktemp -d )"; trap 'rm -rf "$WORK"' EXIT
export HOME="$WORK/home" TMPDIR="$WORK/tmp"; mkdir -p "$HOME" "$TMPDIR"
echo "qdrenameidentitycheck: BIN=$BIN  (temp git corpora)"

newrepo(){ mkdir -p "$1"; ( cd "$1" && git init -q && git config user.email t@t && git config user.name t ); }
commitall(){ ( cd "$1" && git add -A >/dev/null 2>&1 && git commit -qm "$2" >/dev/null 2>&1 ); }
run(){ OUT="$( cd "$1" && "$BIN" . --quality-delta --no-cache 2>"$WORK/err" )"; RC=$?; }
rows(){ printf '%s' "$1" | tr '>' '\n' | grep '<r kind="'; }
nrows(){ rows "$1" | grep -c . | tr -d ' '; }
crashed(){ case "$RC" in 0|2) return 1;; *) no "$1: ripwire exited rc=$RC (crash or refusal); stderr: $( head -c 300 "$WORK/err" )"; return 0;; esac; }
flat(){ rows "$1" | tr '\n' ' '; }

# ─── per-language sources. pair NAME: a clone-pair member (under every bar); big NAME [worse]: over the params, nesting and
# complexity bars (worse = one more nested branch); call NAME: a caller line; file names per language. ─────────────────────
py_pair(){ cat <<EOF
def $1(items, limit):
    total = 0
    seen = set()
    for it in items:
        if it in seen:
            continue
        seen.add(it)
        if it > limit:
            total += it * 2
        else:
            total -= it
    return total + len(seen)

EOF
}
py_big(){ w=''; [ "${2:-}" = worse ] && w='
                            if f > 2:
                                s -= 1'
cat <<EOF
def $1(a, b, c, d, e, f):
    s = 0
    for x in a:
        if x > b:
            for y in c:
                if y > d:
                    while e > 0:
                        if f:
                            s += x * y$w
                        e -= 1
    return s

EOF
}
ts_pair(){ cat <<EOF
function $1(items: number[], limit: number): number {
  let total = 0;
  const seen = new Set<number>();
  for (const it of items) {
    if (seen.has(it)) {
      continue;
    }
    seen.add(it);
    if (it > limit) {
      total += it * 2;
    } else {
      total -= it;
    }
  }
  return total + seen.size;
}

EOF
}
ts_big(){ w=''; [ "${2:-}" = worse ] && w='
              if (f > 2) {
                s -= 1;
              }'
cat <<EOF
${3:-}function $1(a: number[], b: number, c: number[], d: number, e: number, f: number): number {
  let s = 0;
  for (const x of a) {
    if (x > b) {
      for (const y of c) {
        if (y > d) {
          while (e > 0) {
            if (f) {
              s += x * y;$w
            }
            e -= 1;
          }
        }
      }
    }
  }
  return s;
}

EOF
}
go_pair(){ cat <<EOF
func $1(items []int, limit int) int {
	total := 0
	seen := map[int]bool{}
	for _, it := range items {
		if seen[it] {
			continue
		}
		seen[it] = true
		if it > limit {
			total += it * 2
		} else {
			total -= it
		}
	}
	return total + len(seen)
}

EOF
}
go_big(){ w=''; [ "${2:-}" = worse ] && w='
							if f > 2 {
								s -= 1
							}'
cat <<EOF
func $1(a []int, b int, c []int, d int, e int, f int) int {
	s := 0
	for _, x := range a {
		if x > b {
			for _, y := range c {
				if y > d {
					for e > 0 {
						if f > 0 {
							s += x * y$w
						}
						e -= 1
					}
				}
			}
		}
	}
	return s
}

EOF
}
cpp_pair(){ cat <<EOF
int $1( const std::vector<int>& items, int limit )
{
    int total = 0;
    std::set<int> seen;
    for( int it : items )
    {
        if( seen.count( it ) )
        {
            continue;
        }
        seen.insert( it );
        if( it > limit )
        {
            total += it * 2;
        }
        else
        {
            total -= it;
        }
    }
    return total + int( seen.size() );
}

EOF
}
cpp_big(){ w=''; [ "${2:-}" = worse ] && w='
                            if( f > 2 )
                            {
                                s -= 1;
                            }'
cat <<EOF
int $1( const std::vector<int>& a, int b, const std::vector<int>& c, int d, int e, int f )
{
    int s = 0;
    for( int x : a )
    {
        if( x > b )
        {
            for( int y : c )
            {
                if( y > d )
                {
                    while( e > 0 )
                    {
                        if( f )
                        {
                            s += x * y;$w
                        }
                        e -= 1;
                    }
                }
            }
        }
    }
    return s;
}

EOF
}
rs_pair(){ cat <<EOF
fn $1(items: &[i64], limit: i64) -> i64 {
    let mut total = 0;
    let mut seen = std::collections::HashSet::new();
    for it in items {
        if seen.contains(it) {
            continue;
        }
        seen.insert(*it);
        if *it > limit {
            total += it * 2;
        } else {
            total -= it;
        }
    }
    total + seen.len() as i64
}

EOF
}
rs_big(){ w=''; [ "${2:-}" = worse ] && w='
                            if f > 2 {
                                s -= 1;
                            }'
cat <<EOF
${3:-}fn $1(a: &[i64], b: i64, c: &[i64], d: i64, mut e: i64, f: i64) -> i64 {
    let mut s = 0;
    for x in a {
        if *x > b {
            for y in c {
                if *y > d {
                    while e > 0 {
                        if f > 0 {
                            s += x * y;$w
                        }
                        e -= 1;
                    }
                }
            }
        }
    }
    s
}

EOF
}

# main LANG PAIR1 PAIR2 BIG [extra pair] [worse]: the whole one-file source of a fixture; the callers use every function.
src_of(){
    l=$1; p1=$2; p2=$3; bg=$4; p3=${5:-}; wz=${6:-}
    # the caller's argument lists, per language (built here: a brace inside ${x:+...} would end the expansion)
    case $l in
        py)  ap='[1], 2'; ab='[1], 2, [3], 4, 5, 6' ;;
        ts)  ap='[1], 2'; ab='[1], 2, [3], 4, 5, 6' ;;
        go)  ap='[]int{1}, 2'; ab='[]int{1}, 2, []int{3}, 4, 5, 6' ;;
        cpp) ap='{ 1 }, 2'; ab='{ 1 }, 2, { 3 }, 4, 5, 6' ;;
        rs)  ap='&[1], 2'; ab='&[1], 2, &[3], 4, 5, 6' ;;
    esac
    calls="$p1($ap) + $p2($ap)"
    [ -n "$p3" ] && calls="$calls + $p3($ap)"
    [ -n "$bg" ] && calls="$calls + $bg($ab)"
    [ "$l" = go ] && printf 'package lib\n\n'
    [ "$l" = cpp ] && printf '#include <set>\n#include <vector>\n\n'
    "${l}_pair" "$p1"; "${l}_pair" "$p2"; [ -n "$p3" ] && "${l}_pair" "$p3"; [ -n "$bg" ] && [ -z "${CALL_ONLY:-}" ] && "${l}_big" "$bg" "$wz"   # CALL_ONLY=1: the caller still calls it, its body lives elsewhere
    case $l in
        py)  printf 'def use_all():\n    return %s\n' "$calls" ;;
        ts)  printf 'export function useAll(): number {\n  return %s;\n}\n' "$calls" ;;
        go)  printf 'func UseAll() int {\n\treturn %s\n}\n' "$calls" ;;
        cpp) printf 'int useAll()\n{\n    return %s;\n}\n' "$calls" ;;
        rs)  printf 'pub fn use_all() -> i64 {\n    %s\n}\n' "$calls" ;;
    esac
}
mainfile(){ case $1 in py) echo lib/core.py;; ts) echo src/core.ts;; go) echo lib/core.go;; cpp) echo src/core.cpp;; rs) echo src/lib.rs;; esac; }

# fixture LANG DIR: the baseline (pair alpha/beta + big_fn) committed.
fixture(){
    newrepo "$2"; f="$2/$( mainfile "$1" )"; mkdir -p "$( dirname "$f" )"
    [ "$1" = py ] && : > "$( dirname "$f" )/__init__.py"
    src_of "$1" alpha beta big_fn > "$f"; commitall "$2" base
}

# move LANG DIR: big_fn leaves the main file for a sibling file, the caller reaches it as the language requires.
move_big(){
    l=$1; d=$2; f="$d/$( mainfile "$l" )"; dir="$( dirname "$f" )"
    case $l in
        py)  { printf 'from .moved import big_fn\n\n'; CALL_ONLY=1 src_of py alpha beta big_fn; } > "$f"
             py_big big_fn > "$dir/moved.py" ;;
        ts)  { printf 'import { big_fn } from "./moved";\n\n'; CALL_ONLY=1 src_of ts alpha beta big_fn; } > "$f"
             ts_big big_fn '' 'export ' > "$dir/moved.ts" ;;
        go)  CALL_ONLY=1 src_of go alpha beta big_fn > "$f"
             { printf 'package lib\n\n'; go_big big_fn; } > "$dir/moved.go" ;;
        cpp) CALL_ONLY=1 src_of cpp alpha beta big_fn | sed 's/^int useAll()$/int big_fn( const std::vector<int>\& a, int b, const std::vector<int>\& c, int d, int e, int f );\nint useAll()/' > "$f"
             { printf '#include <vector>\n\n'; cpp_big big_fn; } > "$dir/moved.cpp" ;;
        rs)  { printf 'mod moved;\nuse moved::big_fn;\n\n'; CALL_ONLY=1 src_of rs alpha beta big_fn; } > "$f"
             rs_big big_fn '' 'pub ' > "$dir/moved.rs" ;;
    esac
}

for L in py ts go cpp rs; do
    echo "── $L"
    # ═══ P) PREMISES ══════════════════════════════════════════════════════════════════════════════════════════════
    R="$WORK/$L-p"; fixture "$L" "$R"
    PG="$( cd "$R" && "$BIN" . --clones --no-cache 2>/dev/null | tr -d '\n' | sed 's#</group>#\n#g' | grep '<group ' | grep 'n="alpha"' | grep 'n="beta"' )"   # status: output only — the premise FAILs when no group names both
    if [ -n "$PG" ]; then ok "P/$L: the baseline holds the alpha/beta clone pair"
    else no "P/$L: premise — --clones names no group holding both alpha and beta at the baseline"; fi
    f="$R/$( mainfile "$L" )"
    "${L}_big" big_copy >> "$f"
    [ "$L" = go ] && printf 'func useCopy() int { return big_copy([]int{1}, 2, []int{3}, 4, 5, 6) }\n' >> "$f"
    run "$R"
    if ! crashed "P/$L"; then
        N="$( rows "$OUT" | grep -c 'big_copy' | tr -d ' ' )"
        if [ "$N" -ge 2 ]; then ok "P/$L: the big function is over the bars ($N rows on a new COPY of it, the original kept)"
        else no "P/$L: premise — a new copy of big_fn prints $N rows, so the fixture is not over the bars: $( flat "$OUT" )"; fi
    fi

    # ═══ A+B) RENAME ONE MEMBER OF THE CLONE PAIR AND THE OVER-BAR FUNCTION ═══════════════════════════════════════════
    R="$WORK/$L-ab"; fixture "$L" "$R"; src_of "$L" alpha_renamed beta big_fn_renamed > "$R/$( mainfile "$L" )"
    run "$R"
    if ! crashed "A+B/$L"; then
        if [ "$RC" = 0 ] && [ "$( nrows "$OUT" )" = 0 ]; then ok "A+B/$L: renaming a clone-pair member and an over-bar function (and their callers) prints no row (exit 0)"
        else no "A+B/$L: a rename must not read as new code or a new clone (rc=$RC rows: $( flat "$OUT" ))"; fi
    fi

    # ═══ C) MOVE THE OVER-BAR FUNCTION TO A SIBLING FILE ═══════════════════════════════════════════════════════════
    R="$WORK/$L-c"; fixture "$L" "$R"; move_big "$L" "$R"
    MOVED="$( cd "$R" && "$BIN" . --metrics --no-cache 2>/dev/null | tr '>' '\n' | grep -c 'n="big_fn"' | tr -d ' ' )"   # status: output only — the premise FAILs on 0
    run "$R"
    if ! crashed "C/$L"; then
        if [ "$MOVED" -lt 1 ]; then no "C/$L: premise — big_fn is not indexed after the move ($MOVED)"
        elif [ "$RC" = 0 ] && [ "$( nrows "$OUT" )" = 0 ]; then ok "C/$L: moving an over-bar function to a sibling file prints no row (exit 0)"
        else no "C/$L: a move must not read as new code (rc=$RC rows: $( flat "$OUT" ))"; fi
    fi

    # ═══ D+E) RENAME + A REAL WORSENING STILL REPORTS; RENAME + A NEW REAL CLONE STILL GATES ═════════════════════════
    R="$WORK/$L-de"; fixture "$L" "$R"; src_of "$L" alpha_renamed beta big_fn_renamed gamma worse > "$R/$( mainfile "$L" )"
    run "$R"
    if ! crashed "D+E/$L"; then
        ROW="$( rows "$OUT" | grep 'kind="complexity"' | grep 'big_fn_renamed' )"
        if [ -n "$ROW" ]; then ok "D/$L: a renamed function whose body got worse still prints its complexity row"
        else no "D/$L: the worsening carried in with a rename vanished (rc=$RC rows: $( flat "$OUT" ))"; fi
        ROW="$( rows "$OUT" | grep 'kind="duplication"' | grep 'gamma' )"
        if [ "$RC" = 2 ] && [ -n "$ROW" ] && printf '%s' "$ROW" | grep -q 'gating="1"'; then ok "E/$L: a third copy beside the renamed member still gates as duplication (exit 2)"
        else no "E/$L: a new clone must still gate (rc=$RC rows: $( flat "$OUT" ))"; fi
    fi
done

[ "$fail" = 0 ] && echo "ALL PASS" || echo "FAILURES ABOVE"
exit $fail
