#!/usr/bin/env bash
# propcostcheck.sh — gate for Q5b: DSM propagation cost on --arch's <metrics> element.
#
# propagation_cost = density of the transitive closure of the file→file dependency graph
#   = ( Σ_i |reachable(i)| ) / N²   (reachable INCLUDES i itself — MacCormack's unit-diagonal visibility
#     matrix), the fraction of the system reachable from an average file. A VALIDATED coupling form.
#     Reported number on --arch, NEVER a gate (the arch exit code is owned
#     by the layer/path-rule violations, unaffected by this attribute).
#
# HAND-COMPUTED on test/archmetricsfix/ (9 files; resolveIncludeAdj resolves includes by unique basename):
#   file→file edges (adj[src] = files src includes):
#     app.cpp  → math.h, shape.h        math.cpp → math.h
#     a.cpp    → a.h, b.h               b.cpp    → b.h, a.h
#     (math.h, shape.h, util.cpp, a.h, b.h include nothing)
#   reachable-set sizes (incl. self):
#     app.cpp=3  math.cpp=2  math.h=1  shape.h=1  util.cpp=1  a.cpp=3  a.h=1  b.cpp=3  b.h=1
#   Σ = 16 ,  N=9 ,  N²=81  →  16/81 = 0.197531… → "0.198" at the serializer's fixed 3-decimal precision.
#   (Note: a.h/b.h include nothing, so the file graph is ACYCLIC even though the DIRECTORY projection has
#    the ringA↔ringB module cycle — propagation cost is a FILE-level closure, hence 0.198 not higher.)
#
# The fixed 3dp formatting makes the emitted string byte-identical run-to-run (a report value, not a rank
# input → no tolerance band; the det-gate holds on the exact string).
#
# Degenerate: N≤1 → the sole file reaches only itself → Σ=1, N²=1 → 1.000 (documented unit-diagonal).
#
# Usage:  RIPWIRE_BIN=build/ripwire bash test/propcostcheck.sh   |   RIPWIRE_BIN=asan/ripwire bash …
# Exits non-zero on any failure; prints PASS/FAIL per check, ALL PASS on success.

set -u
ROOT="$( cd "$( dirname "$0" )/.." && pwd )"
BIN="${1:-${RIPWIRE_BIN:-$ROOT/build/ripwire}}"
[ "${BIN#/}" = "$BIN" ] && BIN="$ROOT/$BIN"          # allow repo-relative RIPWIRE_BIN
FIX="$ROOT/test/archmetricsfix"
TMP="$( mktemp -d )"; trap 'rm -rf "$TMP"' EXIT
fail=0
ok(){ printf '  PASS  %s\n' "$*" || { fail=1; printf '  FAIL  could not write the PASS line for: %s\n' "$*"; }; return 0; }
no(){ printf '  FAIL  %s\n' "$*"; fail=1; }

[ -x "$BIN" ] || { echo "no ripwire binary at $BIN — build first"; exit 2; }
[ -d "$FIX" ] || { echo "no test/archmetricsfix dir — fixture missing"; exit 2; }
[ -f "$FIX/sibling.arch" ] || { echo "no test/archmetricsfix/sibling.arch — fixture config missing"; exit 2; }
cd "$ROOT"

echo "propcostcheck: BIN=$BIN  CORPUS=test/archmetricsfix"

# full --arch output; extract the propagation_cost attribute value from <metrics …>
arch(){ perl -e 'alarm 20; exec @ARGV' "$BIN" "$1" --arch="$2" --no-cache 2>/dev/null; }
pc(){ printf '%s' "$1" | tr '>' '\n' | grep '<metrics ' | grep -oE 'propagation_cost="[^"]*"' | head -1 | sed -E 's/.*"([^"]*)".*/\1/'; }

OUT="$( arch "$FIX" "$FIX/sibling.arch" )"
GOT="$( pc "$OUT" )"

# ── 1) hand-computed value: Σ|reachable(i)|/N² = 16/81 = 0.198 (3dp) ──────────────────────────────────
# To MUTATION-TEST this assertion, change EXPECT below to any other value (e.g. 0.199) → this check FAILS.
EXPECT="0.198"
[ "$GOT" = "$EXPECT" ] \
    && ok "propagation_cost = $EXPECT (hand-computed 16/81 transitive-closure density on archmetricsfix)" \
    || no "propagation_cost expected $EXPECT, got '$GOT' (closure density / formatting wrong)"

# ── 2) the attribute is PRESENT and well-formed (an emitted number, never a gate) ────────────────────
printf '%s' "$OUT" | grep -q 'propagation_cost="[0-9]\.[0-9][0-9][0-9]"' \
    && ok "propagation_cost present with fixed 3-decimal formatting" \
    || no "propagation_cost missing or not 3-decimal formatted"

# ── 3) determinism — the emitted value is byte-identical across two runs ──────────────────────────────
GOT2="$( pc "$( arch "$FIX" "$FIX/sibling.arch" )" )"
[ "$GOT" = "$GOT2" ] \
    && ok "deterministic (propagation_cost byte-identical across two runs)" \
    || no "non-deterministic propagation_cost ('$GOT' vs '$GOT2')"

# ── 4) N≤1 degenerate case → 1.000 (sole file reaches only itself; no divide-by-zero) ─────────────────
mkdir -p "$TMP/solo"
printf 'int main(){ return 0; }\n' > "$TMP/solo/only.cpp"
printf 'deny path nope -> nope\n' > "$TMP/degen.arch"
DGOT="$( pc "$( arch "$TMP/solo" "$TMP/degen.arch" )" )"
[ "$DGOT" = "1.000" ] \
    && ok "N==1 degenerate → propagation_cost=1.000 (unit-diagonal; no divide-by-zero)" \
    || no "N==1 case expected 1.000, got '$DGOT'"

# ── 5) it is NOT a gate: the arch exit code is owned by violations, not by this number ────────────────
# archmetricsfix + sibling.arch has 4 real violations → exit 2 regardless of propagation_cost.
perl -e 'alarm 20; exec @ARGV' "$BIN" "$FIX" --arch="$FIX/sibling.arch" --no-cache >/dev/null 2>&1; rc=$?
[ "$rc" = 2 ] \
    && ok "propagation_cost is descriptive only (arch exit still driven by violations: exit $rc)" \
    || no "unexpected arch exit $rc (propagation_cost must not affect the exit code)"

# ── 6) XML well-formed (G4) — the <metrics> element carrying the new attribute ────────────────────────
if command -v xmllint >/dev/null 2>&1; then
    if printf '%s' "$OUT" | xmllint --noout - 2>/dev/null; then ok "xml well-formed (arch + metrics + propagation_cost)"; else no "xml malformed"; fi
else
    printf '  SKIP  xml well-formed (no xmllint)\n'
fi

# ── §P9.4: files that CANNOT participate in the #include/import graph (.md/.json — no import syntax at ──
# all) must not dilute --deps <health>'s nccd/acd nor --arch's propagation_cost. Both must be computed
# over dependency-capable files only, with the SAME denominator.
# archmetricsfix (9 C-family files) has a hand-computed propagation_cost = 16/81 = 0.198 (see the header
# comment above) and a hand-computed CCD; copy it and add TWO non-capable files with no edges (a .md and a
# .json) — if they leaked into N, both numbers would be diluted toward a LARGER N (0.198 * 81/121 = 0.132,
# CCD/N would drop too). They must not move at all: excluding non-capable files means N stays 9.
#
# The .sh that used to be one of these two MOVED at kParserVer 81 — Bash `source`/`.` is now a captured
# directive and .sh is dependency-capable — so it is no longer a valid negative control and has become the
# POSITIVE one below. .md is still excluded on purpose (it mints doc→doc link edges but a README that
# links twelve designs is not twelve files of change amplification — see lintrules.h::dependencyCapable);
# .json has no file-level import at all.
DCAP="$TMP/depcap"
cp -R "$FIX" "$DCAP"
printf '# notes\n\nnothing to see here\n'  > "$DCAP/README.md"
printf '{ "note": "not a dependency" }\n'  > "$DCAP/data.json"

DEPS_DCAP="$( "$BIN" "$DCAP" --deps --no-cache 2>/dev/null )"
printf '%s' "$DEPS_DCAP" | grep -qE '<health files="11"[^>]*\bdep_files="9"' \
    && ok "P9.4: <health> discloses BOTH files=11 (corpus, incl. .md/.json) and dep_files=9 (denominator)" \
    || no "P9.4: <health> files=/dep_files= wrong or missing: $( printf '%s' "$DEPS_DCAP" | grep -o '<health[^/]*/>' )"
printf '%s' "$DEPS_DCAP" | grep -qE '<health[^>]*\bnccd="0\.66"' \
    && ok "P9.4: --deps nccd unmoved by the two non-capable files (still computed over dep_files=9)" \
    || no "P9.4: --deps nccd shifted — non-capable files leaked into the denominator: $( printf '%s' "$DEPS_DCAP" | grep -o '<health[^/]*/>' )"

ARCH_DCAP="$( "$BIN" "$DCAP" --arch="$DCAP/sibling.arch" --no-cache 2>/dev/null )"
DCAP_PC="$( pc "$ARCH_DCAP" )"
[ "$DCAP_PC" = "$EXPECT" ] \
    && ok "P9.4: --arch propagation_cost unmoved by the two non-capable files (still $EXPECT, same N as --deps)" \
    || no "P9.4: --arch propagation_cost shifted to '$DCAP_PC' (expected unchanged $EXPECT) — denominators disagree"

# ── POSITIVE CONTROL for the same denominator (kParserVer 81) — without it, the three assertions above
# pass just as well on a build where dependencyCapable() returned false for EVERYTHING. Add ONE .sh with
# no edges to the same 9-file fixture: it must now COUNT, so dep_files goes 9 -> 10 and propagation_cost
# becomes 17/100 = 0.170 (the .sh seeds a root that reaches only itself: +1 numerator, +19 denominator).
# Both numbers moving together is the "same N" claim proven in the direction that can actually fail.
DCAPSH="$TMP/depcapsh"
cp -R "$FIX" "$DCAPSH"
printf '#!/usr/bin/env bash\necho hi\n' > "$DCAPSH/deploy.sh"

DEPS_SH="$( "$BIN" "$DCAPSH" --deps --no-cache 2>/dev/null )"
printf '%s' "$DEPS_SH" | grep -qE '<health files="10"[^>]*\bdep_files="10"' \
    && ok "P9.4 positive: a .sh is dependency-CAPABLE at parser version 81 — dep_files=10 of files=10" \
    || no "P9.4 positive: the .sh did not join the denominator: $( printf '%s' "$DEPS_SH" | grep -o '<health[^/]*/>' )"
SH_PC="$( pc "$( "$BIN" "$DCAPSH" --arch="$DCAPSH/sibling.arch" --no-cache 2>/dev/null )" )"
[ "$SH_PC" = "0.170" ] \
    && ok "P9.4 positive: --arch propagation_cost moved with it (17/100 = 0.170, same N as --deps)" \
    || no "P9.4 positive: propagation_cost is '$SH_PC', expected 0.170 — the two denominators disagree"

# ── the closure fold on a fixture that is too small to cross a 16-bit chunk ─────────────────────────────────────
# RIPWIRE_TEST_FILESET_CHUNK_BITS forces the fold's chunk size on EVERY fold (buildGraph's, --deps' and --arch=FILE's second
# one), so the multi-chunk read paths run here. Same numbers at every size; a knob that reached only one fold would move one.
DEPS_REF="$( "$BIN" "$FIX" --deps --no-cache 2>/dev/null | grep -o '<health[^/]*/>' )"
for bits in 1 2 4 8; do
    GOTB="$( pc "$( RIPWIRE_TEST_FILESET_CHUNK_BITS=$bits "$BIN" "$FIX" --arch="$FIX/sibling.arch" --no-cache 2>/dev/null )" )"
    DEPSB="$( RIPWIRE_TEST_FILESET_CHUNK_BITS=$bits "$BIN" "$FIX" --deps --no-cache 2>/dev/null | grep -o '<health[^/]*/>' )"
    if [ "$GOTB" = "$EXPECT" ] && [ -n "$DEPS_REF" ] && [ "$DEPSB" = "$DEPS_REF" ]; then
        ok "chunk bits forced to $bits: propagation_cost $EXPECT and --deps <health> unchanged"
    else
        no "chunk bits $bits: propagation_cost '$GOTB' (want $EXPECT), health '$DEPSB' (want '$DEPS_REF')"
    fi
done

# ── the second fold stops at the memory guard, disclosed ──────────────────────────────────────────────────────────
# fold:N is the memory guard's seam (memguard.h): the Nth fold of the process reads as over the hard limit at its first component.
# buildGraph's fold is the first, --deps' and --arch=FILE's the second, so fold:2 reaches ONLY the second. A number from a
# stopped fold is never printed: exit 5, one stderr line, nothing on stdout. Without a seam the same run answers.
for mode in deps arch; do
    if [ "$mode" = deps ]; then args=( --deps ); else args=( --arch="$FIX/sibling.arch" ); fi
    RIPWIRE_TEST_MEMGUARD=fold:2 "$BIN" "$FIX" "${args[@]}" --no-cache >"$TMP/f2.out" 2>"$TMP/f2.err"; rc=$?
    if [ "$rc" = 5 ] && [ ! -s "$TMP/f2.out" ] && [ "$( grep -c '^ripwire:' "$TMP/f2.err" )" = 1 ] \
       && grep -q '^ripwire: memory limit reached during the include-closure fold' "$TMP/f2.err"; then
        ok "fold:2 on --$mode: the second fold stops, exit 5, one stderr line, no number printed"
    else
        no "fold:2 on --$mode: rc=$rc stdout=$( wc -c <"$TMP/f2.out" ) bytes stderr: $( head -c 250 "$TMP/f2.err" )"
    fi
done
RIPWIRE_TEST_MEMGUARD=fold:1 "$BIN" "$FIX" --no-cache >"$TMP/f1.out" 2>"$TMP/f1.err"; rc=$?
if [ "$rc" = 5 ] && [ ! -s "$TMP/f1.out" ] && grep -q '^ripwire: memory limit reached during the include-closure fold' "$TMP/f1.err"; then
    ok "fold:1 on the bare map: buildGraph's fold stops at the hard line after the graph build (exit 5)"
else
    no "fold:1 on the bare map: rc=$rc stderr: $( head -c 250 "$TMP/f1.err" )"
fi
RIPWIRE_TEST_MEMGUARD=fold:2 "$BIN" "$FIX" --no-cache >/dev/null 2>&1; rc=$?
if [ "$rc" = 0 ]; then
    ok "fold:2 on the bare map: there is no second fold, the map answers (exit 0)"
else
    no "fold:2 on the bare map: rc=$rc"
fi

# ── a stopped fold is a FAILED BUILD: nothing answers from it, nothing is written from it (rv-file-graph-delta F1) ─────────────
# test/filegraphstopfix: util_a.h and util_b.h each define `helper`; use_a.cpp reaches only util_a.h through two includes, so the
# include closure decides which `helper` the call is. A partial closure splits the call and strands util_b.h's `helper`, which
# --quality-delta reads as a NEW dead symbol: exit 2 and a persisted false floor. Every surface that builds a graph must refuse
# instead. fold:N trips the Nth fold of the process, so a seam on the path's OWN graph reaches the site under test.
FGS="$TMP/fgs"; mkdir -p "$FGS" "$TMP/xdg"; cp "$ROOT"/test/filegraphstopfix/* "$FGS"/
git -C "$FGS" init -q 2>/dev/null
git -C "$FGS" add -A 2>/dev/null
git -C "$FGS" -c user.name=t -c user.email=t@example.invalid commit -q -m one 2>/dev/null
echo '// two' >>"$FGS/lib.cpp"
git -C "$FGS" add -A 2>/dev/null
git -C "$FGS" -c user.name=t -c user.email=t@example.invalid commit -q -m two 2>/dev/null
echo '// edit' >>"$FGS/lib.cpp"
stopline(){ grep -c '^ripwire: memory limit reached during the include-closure fold' "$1"; }
fgs_cli(){   # $1 = label, $2 = seam, $3.. = argv; a fresh cache per label, kept for the "not poisoned" re-run
    local label="$1" seam="$2"; shift 2
    mkdir -p "$TMP/xdg/$label"
    XDG_CACHE_HOME="$TMP/xdg/$label" TMPDIR="$TMP/xdg/$label" RIPWIRE_TEST_MEMGUARD="$seam" "$BIN" "$FGS" "$@" >"$TMP/$label.out" 2>"$TMP/$label.err"; echo $?
}
rc="$( fgs_cli qd fold:2 --quality-delta --legend=compact )"
if [ "$rc" = 5 ] && [ ! -s "$TMP/qd.out" ] && [ "$( stopline "$TMP/qd.err" )" = 1 ] && [ "$( grep -c '^ripwire:' "$TMP/qd.err" )" = 1 ]; then
    ok "--quality-delta, HEAD snapshot's fold stopped: exit 5, one line, nothing on stdout"
else
    no "--quality-delta fold:2: rc=$rc stdout=$( wc -c <"$TMP/qd.out" ) bytes stderr: $( head -c 250 "$TMP/qd.err" )"
fi
rc="$( XDG_CACHE_HOME="$TMP/xdg/qd" TMPDIR="$TMP/xdg/qd" "$BIN" "$FGS" --quality-delta --legend=compact >"$TMP/qd2.out" 2>/dev/null; echo $? )"
if [ "$rc" = 0 ] && grep -q 'regressions="0"' "$TMP/qd2.out"; then
    ok "--quality-delta again on that cache, no seam: exit 0, regressions=0 (the stop persisted no snapshot)"
else
    no "--quality-delta after a stopped fold, same cache: rc=$rc out: $( head -c 300 "$TMP/qd2.out" )"
fi
rc="$( fgs_cli ec fold:2 --edit-check=use_a --legend=compact )"
if [ "$rc" = 5 ] && [ ! -s "$TMP/ec.out" ] && [ "$( stopline "$TMP/ec.err" )" = 1 ]; then
    ok "--edit-check, HEAD snapshot's fold stopped: exit 5, one line, nothing on stdout"
else
    no "--edit-check=use_a fold:2: rc=$rc stdout=$( wc -c <"$TMP/ec.out" ) bytes stderr: $( head -c 250 "$TMP/ec.err" )"
fi
rc="$( fgs_cli rg fold:2 --quality-delta=HEAD~1..HEAD --legend=compact )"
if [ "$rc" = 6 ] && grep -q 'answered from the changed files only' "$TMP/rg.err"; then ok "--quality-delta=A..B, a full tree's fold stopped: no score from it; the range form degrades to the changed files, disclosed (exit 6, the design of qd-memory-degrade)"
elif [ "$rc" = 5 ] && [ ! -s "$TMP/rg.out" ]; then ok "--quality-delta=A..B, a stopped fold: exit 5, nothing printed"
else no "range form fold:2: rc=$rc out=$( wc -c <"$TMP/rg.out" ) stderr: $( head -c 200 "$TMP/rg.err" )"; fi

# the MCP envelope: the call that hit the stop is refused by name; the server is NOT stuck — the next call is served, and from a
# whole index (the `of_def` of the call is one definition, not the split ["1~s","2~s"] a partial closure gives)
mcp_fgs(){   # $1 = seam, stdin = tool lines (ids 2..); stdout = responses
    { printf '%s\n' '{"jsonrpc":"2.0","id":1,"method":"initialize"}'; cat; } \
        | ( cd "$FGS" && XDG_CACHE_HOME="$TMP/xdg/mcp" TMPDIR="$TMP/xdg/mcp" RIPWIRE_TEST_MEMGUARD="$1" perl -e 'alarm shift; exec @ARGV' 60 "$BIN" --mcp 2>/dev/null )
}
mkdir -p "$TMP/xdg/mcp"
mcp_resp(){ python3 - "$1" "$2" <<'PY'
import json, sys
for line in open( sys.argv[1], encoding="utf-8", errors="replace" ):
    line = line.strip()
    if line.startswith( "{" ):
        try:
            r = json.loads( line )
        except ValueError:
            continue
        if r.get( "id" ) == int( sys.argv[2] ):
            e = r.get( "error" )
            print( "ERR " + e.get( "message", "" ) if e else "OK " + "".join( c.get( "text", "" ) for c in r.get( "result", {} ).get( "content", [] ) ) )
PY
}
printf '%s\n%s\n' \
    "{\"jsonrpc\":\"2.0\",\"id\":2,\"method\":\"tools/call\",\"params\":{\"name\":\"find_referencing_symbols\",\"arguments\":{\"path\":\"$FGS\",\"symbol\":\"helper\"}}}" \
    "{\"jsonrpc\":\"2.0\",\"id\":3,\"method\":\"tools/call\",\"params\":{\"name\":\"find_referencing_symbols\",\"arguments\":{\"path\":\"$FGS\",\"symbol\":\"helper\"}}}" \
    | mcp_fgs fold:1 >"$TMP/m1.out"
r2="$( mcp_resp "$TMP/m1.out" 2 )"; r3="$( mcp_resp "$TMP/m1.out" 3 )"
case "$r2" in "ERR memory limit reached during the include-closure fold"*) ok "MCP first call, index build's fold stopped: refused by name, no answer";; *) no "MCP fold:1 id=2: ${r2:0:250}";; esac
case "$r3" in OK*'"of_def":["1"]'*) ok "MCP next call: served, whole index (the stop is not sticky; mcp.h's promise holds)";; *) no "MCP fold:1 id=3: ${r3:0:300}";; esac
find "$FGS" "$TMP/xdg/mcp" -name '.ripwire_quality_baseline*' 2>/dev/null | head -1 | grep -q . && no "a baseline sidecar exists before any quality_baseline call"
for verb in quality_baseline quality_delta edit_check; do
    case "$verb" in edit_check) a=",\"symbol\":\"use_a\"";; *) a="";; esac
    rm -rf "$TMP/xdg/mcp"; mkdir -p "$TMP/xdg/mcp"
    printf '%s\n' "{\"jsonrpc\":\"2.0\",\"id\":2,\"method\":\"tools/call\",\"params\":{\"name\":\"$verb\",\"arguments\":{\"path\":\"$FGS\"$a}}}" | mcp_fgs fold:1 >"$TMP/mv.out"
    r="$( mcp_resp "$TMP/mv.out" 2 )"
    case "$r" in "ERR memory limit reached during the include-closure fold"*) ok "MCP $verb: its own graph's fold stopped, refused by name";; *) no "MCP $verb fold:1: ${r:0:250}";; esac
    if [ "$verb" = quality_baseline ]; then
        if find "$FGS" "$TMP/xdg/mcp" -name '.ripwire_quality_baseline*' 2>/dev/null | grep -q .; then no "MCP quality_baseline wrote a sidecar from a stopped fold"; else ok "MCP quality_baseline: no sidecar written from a stopped fold"; fi
    fi
done
rm -f "$FGS"/.ripwire_quality_baseline*   # an old binary's sidecar would stand in for the HEAD snapshot below
rm -rf "$TMP/xdg/mcp"; mkdir -p "$TMP/xdg/mcp"
printf '%s\n' "{\"jsonrpc\":\"2.0\",\"id\":2,\"method\":\"tools/call\",\"params\":{\"name\":\"quality_delta\",\"arguments\":{\"path\":\"$FGS\"}}}" | mcp_fgs fold:2 >"$TMP/mq.out"
r="$( mcp_resp "$TMP/mq.out" 2 )"
case "$r" in "ERR memory limit reached during the include-closure fold"*) ok "MCP quality_delta: the HEAD snapshot's fold stopped, refused, no false regression";; *) no "MCP quality_delta fold:2: ${r:0:250}";; esac

[ "$fail" = 0 ] && echo "ALL PASS" || echo "FAILURES ABOVE"
exit $fail
