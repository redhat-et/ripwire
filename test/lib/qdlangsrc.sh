# qdlangsrc.sh — sourced: per-language fixture sources shared by the quality-delta identity gates
# (qdrenameidentitycheck.sh, qdgitrenamehealcheck.sh). Defines LANG_pair / LANG_big, src_of, mainfile; no side effects.

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
