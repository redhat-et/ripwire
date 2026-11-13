#!/usr/bin/env bash
# qdconstructscheck.sh — gate for QD-CONSTRUCTS-AT-INGEST (src/ingest_astquery.h collectConstructHits, the v51 record family).
#
# --quality-delta's error-masking and placeholder hits (lintrules.h findQualityConstructs) are found in the parse
# worker from the tree ingest already built, ride the file's cache record, and are read back on a warm call instead
# of re-reading and re-parsing every file. RIPWIRE_QD_CONSTRUCTS_VERIFY=1 makes the binary compute the re-parsed list
# beside the carried one and print `qd-constructs-verify equal=…` with both lists' counts. This gate proves:
#
#   (C)  cold cache: the carried list equals the re-parsed one, and it is NOT EMPTY (the fixture plants every rule
#        family; a carried list of zero hits would make equal=1 vacuous, so zero FAILS);
#   (W)  warm cache (RIPWIRE_CACHE_STATS reparsed=0): the hits now come from the cache records, still equal, same counts;
#   (N)  --no-cache: equal, same counts;
#   (B)  the --quality-delta answer (stdout, stderr without the verify line, rc) is byte-identical across (C), (W), (N)
#        and A..B, and names the planted constructs (positive twin: a silent binary fails here);
#   (P)  a memory-cut parse (RIPWIRE_TEST_MEMGUARD=parse:1) claims no hits and --quality-delta refuses it (exit 5);
#   (R)  optional: QDC_REPOS="dir1 dir2 …" repeats (C)+(W) on real trees (the lane's envoy / cockroach / vscode run).
#
# Usage:  bash test/qdconstructscheck.sh          (BIN=build/ripwire)
#         RIPWIRE_BIN=asan/ripwire bash test/qdconstructscheck.sh
set -u
ROOT="$( cd "$( dirname "$0" )/.." && pwd )"
BIN="${RIPWIRE_BIN:-$ROOT/build/ripwire}"
case "$BIN" in /*) ;; *) BIN="$PWD/$BIN" ;; esac
WORK="$( mktemp -d )"; trap 'rm -rf "$WORK"' EXIT
fail=0
ok(){ printf '  PASS  %s\n' "$*"; }
no(){ printf '  FAIL  %s\n' "$*"; fail=1; }
echo "qdconstructscheck: BIN=$BIN"

# ── the fixture, generated here (never committed where a whole-repo run sees it) ─────────────────────────────────────
FX="$WORK/fx"; mkdir -p "$FX/src"
cat > "$FX/src/a.cpp" <<'EOF'
#include <stdexcept>
void risky();
void swallowBare() { try { risky(); } catch( ... ) {} }
void swallowComment() { try { risky(); } catch( const std::exception& ) { /* ignore */ } }
void handled() { try { risky(); } catch( ... ) { /* retry */ risky(); } }
void later() { // TODO: write this
    risky();
}
EOF
cat > "$FX/src/b.py" <<'EOF'
import logging
def quiet():
    try:
        work()
    except Exception:
        pass
def dots():
    try:
        work()
    except ValueError:
        ...
def stub():
    raise NotImplementedError
def logged():
    try:
        work()
    except Exception as e:
        logging.info("failed")
def work():
    return 1
EOF
cat > "$FX/src/c.js" <<'EOF'
function load(p) {
  p.catch(() => {});
  try { go(); } catch (e) {}
  // TODO: tidy
  return p.then(x => x, () => {});
}
function go() { return 1; }
EOF
cat > "$FX/src/d.go" <<'EOF'
package d

func f() (int, error) { return 0, nil }

func g() {
	if _, err := f(); err != nil {
	}
	x, err := f()
	if err != nil {
	}
	_ = x
}
EOF
cat > "$FX/src/e.rs" <<'EOF'
fn f() -> Result<i32, String> { Ok(1) }
fn g() {
    if let Err(_) = f() {}
    match f() { Ok(v) => { let _ = v; } Err(_) => {} }
    todo!()
}
EOF
cat > "$FX/src/F.java" <<'EOF'
class F {
  void run() { try { go(); } catch (Exception e) {} }
  void go() { throw new UnsupportedOperationException("not implemented"); }
}
EOF
printf '# Notes\n\nTODO: a markdown TODO is not a construct\n' > "$FX/README.md"
( cd "$FX" && git init -q && git -c user.name=t -c user.email=t@t add -A && git -c user.name=t -c user.email=t@t commit -qm base ) || no "fixture git init"
# HEAD~1..HEAD needs a second commit: one new swallow, so the delta has a row to name.
cat >> "$FX/src/b.py" <<'EOF'
def added():
    try:
        work()
    except Exception:
        pass
EOF
( cd "$FX" && git -c user.name=t -c user.email=t@t commit -qam grow ) || no "fixture second commit"

verifyline(){ grep '^ripwire: qd-constructs-verify ' "$1" | tail -n 1; }
field(){ sed -n 's/.* '"$2"'=\([0-9]*\).*/\1/p' <<< "$1"; }

# run <tag> <cache-mode> <extra env…> -- <args…>: stdout/stderr/rc under $WORK/<tag>.{out,err,rc}, private TMPDIR/HOME
run(){
    local tag="$1"; shift
    local envs=(); while [ "$1" != "--" ]; do envs+=( "$1" ); shift; done; shift
    ( cd "$FX" && env HOME="$WORK/home" TMPDIR="$WORK/tmp" RIPWIRE_QD_CONSTRUCTS_VERIFY=1 ${envs[@]+"${envs[@]}"} "$BIN" . "$@" \
        > "$WORK/$tag.out" 2> "$WORK/$tag.err" ); echo $? > "$WORK/$tag.rc"
}
mkdir -p "$WORK/home" "$WORK/tmp"

# (C) cold, then (W) warm, on one cache
run C RIPWIRE_CACHE_STATS=1 -- --quality-delta
run W RIPWIRE_CACHE_STATS=1 -- --quality-delta
run N -- --quality-delta --no-cache
run AB -- --quality-delta=HEAD~1..HEAD
for tag in C W N; do
    v="$( verifyline "$WORK/$tag.err" )"
    if [ -z "$v" ]; then no "($tag) no qd-constructs-verify line — the ingest made no whole-tree claim"; sed 's/^/    /' "$WORK/$tag.err" | head -20; continue; fi
    cm="$( field "$v" carried_mask )"; cp="$( field "$v" carried_placeholder )"
    if [ "$( field "$v" equal )" = 1 ]; then ok "($tag) carried == re-parsed: $v"; else no "($tag) carried != re-parsed: $v"; fi
    # premise: the fixture plants >= 12 masking hits and >= 4 placeholders; fewer means the pass went blind
    if [ "${cm:-0}" -ge 12 ] && [ "${cp:-0}" -ge 4 ]; then ok "($tag) premise: $cm masking + $cp placeholder hits counted"; else no "($tag) premise: only ${cm:-0} masking / ${cp:-0} placeholder hits — expected >= 12 / >= 4"; fi
    echo "$cm $cp" > "$WORK/$tag.counts"
done
if grep -q 'reparsed=0 ' "$WORK/W.err"; then ok "(W) the warm run is a real cache hit (reparsed=0)"; else no "(W) the warm run re-parsed: $( grep cache-stats "$WORK/W.err" | head -1 )"; fi
if cmp -s "$WORK/C.counts" "$WORK/W.counts" && cmp -s "$WORK/C.counts" "$WORK/N.counts"; then ok "(C/W/N) the same counts cold, warm and uncached"; else no "(C/W/N) counts differ: C=$( cat "$WORK/C.counts" ) W=$( cat "$WORK/W.counts" ) N=$( cat "$WORK/N.counts" )"; fi

# (B) the answer itself
strip(){ grep -v '^ripwire: qd-constructs-verify \|^ripwire: cache-stats ' "$1"; }
same=1
for tag in W N; do
    cmp -s "$WORK/C.out" "$WORK/$tag.out" || same=0
    [ "$( strip "$WORK/C.err" )" = "$( strip "$WORK/$tag.err" )" ] || same=0
    cmp -s "$WORK/C.rc" "$WORK/$tag.rc" || same=0
done
if [ "$same" = 1 ]; then ok "(B) working-tree answer byte-identical cold / warm / --no-cache (rc $( cat "$WORK/C.rc" ))"; else no "(B) working-tree answers differ"; fi
if v="$( verifyline "$WORK/AB.err" )" && [ "$( field "$v" equal )" = 1 ]; then ok "(B) A..B: carried == re-parsed: $v"; else no "(B) A..B verify: ${v:-missing}"; fi
if grep -q 'b.py' "$WORK/AB.out"; then ok "(B) A..B names the planted swallow (b.py)"; else no "(B) A..B does not name b.py"; sed 's/^/    /' "$WORK/AB.out" | head -20; fi

# (P) a memory-cut parse: ingest makes no whole-tree claim (constructHitsForFiles stays short), and --quality-delta refuses
#     the partial index (exit 5) before any construct pass, so a cut tree can never be read as "no hits"
run P RIPWIRE_TEST_MEMGUARD=parse:1 -- --quality-delta --no-cache
if [ "$( cat "$WORK/P.rc" )" = 5 ] && grep -q 'memory guard stopped the parse' "$WORK/P.err" && [ -z "$( verifyline "$WORK/P.err" )" ]; then
    ok "(P) a memory-cut parse is refused (exit 5) and claims no hits"
else
    no "(P) memory-cut run: rc $( cat "$WORK/P.rc" ), verify line '$( verifyline "$WORK/P.err" )'"; sed 's/^/    /' "$WORK/P.err" | head -10
fi

# (R) real trees, optional
for repo in ${QDC_REPOS:-}; do
    for pass in cold warm; do
        ( cd "$repo" && env HOME="$WORK/home" TMPDIR="$WORK/tmp-r" RIPWIRE_QD_CONSTRUCTS_VERIFY=1 "$BIN" . --quality-delta > /dev/null 2> "$WORK/r.err" )
        v="$( verifyline "$WORK/r.err" )"
        n=$(( $( field "$v" carried_mask || echo 0 ) + $( field "$v" carried_placeholder || echo 0 ) ))
        if [ "$( field "$v" equal )" = 1 ] && [ "$n" -gt 0 ]; then ok "(R) $repo $pass: $v"; else no "(R) $repo $pass: ${v:-no verify line}"; fi
    done
    rm -rf "$WORK/tmp-r"
done

[ "$fail" = 0 ] && echo "qdconstructscheck: PASS" || echo "qdconstructscheck: FAIL"
exit "$fail"
