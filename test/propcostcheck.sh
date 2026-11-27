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
. "$ROOT/test/lib/clean-env.sh"   # no inherited agent homes or GIT_* repository selection (the gate builds a repo)
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
# RIPWIRE_TEST_FILESET_CHUNK_BITS forces the fold's chunk size on EVERY fold (buildGraph's, and --deps' and --arch=FILE's own
# closure fold), so the multi-chunk read paths run here. Same numbers at every size; a knob that reached only one fold would move one.
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

# ── the --deps / --arch fold stops at the memory guard, disclosed ─────────────────────────────────────────────────
# fold:N is the memory guard's seam (memguard.h): the Nth fold of the process reads as over the hard limit at its first component.
# Since DEPS-NO-GRAPH, --deps and --arch=FILE build no call graph, so buildGraph's fold never runs for them and their own
# include-closure fold is the process's FIRST: fold:1 reaches it, and fold:2 finds no second fold (the verb answers, exit 0).
# A number from a stopped fold is never printed: exit 5, one stderr line, nothing on stdout. Without a seam the same run answers.
for mode in deps arch; do
    if [ "$mode" = deps ]; then args=( --deps ); else args=( --arch="$FIX/sibling.arch" ); fi
    RIPWIRE_TEST_MEMGUARD=fold:1 "$BIN" "$FIX" "${args[@]}" --no-cache >"$TMP/f2.out" 2>"$TMP/f2.err"; rc=$?
    if [ "$rc" = 5 ] && [ ! -s "$TMP/f2.out" ] && [ "$( grep -c '^ripwire:' "$TMP/f2.err" )" = 1 ] \
       && grep -q '^ripwire: memory limit reached during the include-closure fold' "$TMP/f2.err"; then
        ok "fold:1 on --$mode: its own closure fold (the only one) stops, exit 5, one stderr line, no number printed"
    else
        no "fold:1 on --$mode: rc=$rc stdout=$( wc -c <"$TMP/f2.out" ) bytes stderr: $( head -c 250 "$TMP/f2.err" )"
    fi
    RIPWIRE_TEST_MEMGUARD=fold:2 "$BIN" "$FIX" "${args[@]}" --no-cache >"$TMP/f2b.out" 2>"$TMP/f2b.err"; rc=$?
    if [ "$rc" != 5 ] && [ -s "$TMP/f2b.out" ] && ! grep -q '^ripwire: memory limit reached' "$TMP/f2b.err"; then
        ok "fold:2 on --$mode: no second fold (no graph built), the verb answers (exit $rc)"
    else
        no "fold:2 on --$mode: rc=$rc stdout=$( wc -c <"$TMP/f2b.out" ) bytes (want an answer: --$mode builds no graph, so there is no second fold)"
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
git -C "$FGS" -c user.name=t -c user.email=t@example.com commit -q -m one 2>/dev/null
echo '// two' >>"$FGS/lib.cpp"
git -C "$FGS" add -A 2>/dev/null
git -C "$FGS" -c user.name=t -c user.email=t@example.com commit -q -m two 2>/dev/null
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
# Each commit's tree in turn: loadRefTree's catch is what makes this a degrade, so exit 5 here would mean the catch is gone.
for seam in fold:1 fold:2; do
    rc="$( fgs_cli rg "$seam" --quality-delta=HEAD~1..HEAD --legend=compact )"
    if [ "$rc" = 6 ] && [ -s "$TMP/rg.out" ] && grep -q 'answered from the changed files only' "$TMP/rg.err"; then ok "--quality-delta=A..B $seam, a full tree's fold stopped: no score from it; the range form degrades to the changed files, disclosed (exit 6, the design of qd-memory-degrade)"
    else no "range form $seam: rc=$rc out=$( wc -c <"$TMP/rg.out" ) stderr: $( head -c 200 "$TMP/rg.err" )"; fi
done
# Every fold stops, the changed-files form's own too: its catch reports the phase, and the refusal is by name with nothing printed.
# The commit changes files that carry edges, or the changed-files graph has nothing to fold.
FGR="$TMP/fgr"; cp -R "$FGS" "$FGR"; git -C "$FGR" checkout -q -- . 2>/dev/null
for f in mid_a.h mid2_a.h use_a.cpp util_a.h; do echo '// three' >>"$FGR/$f"; done
git -C "$FGR" add -A 2>/dev/null; git -C "$FGR" -c user.name=t -c user.email=t@example.com commit -q -m three 2>/dev/null
mkdir -p "$TMP/xdg/rgall"
XDG_CACHE_HOME="$TMP/xdg/rgall" TMPDIR="$TMP/xdg/rgall" RIPWIRE_TEST_MEMGUARD=foldfrom:1 "$BIN" "$FGR" --no-cache --quality-delta=HEAD~1..HEAD --legend=compact >"$TMP/rgall.out" 2>"$TMP/rgall.err"; rc=$?
if [ "$rc" = 5 ] && [ ! -s "$TMP/rgall.out" ] && grep -q '^ripwire: memory limit reached during the include-closure fold.*the changed files alone were cut too' "$TMP/rgall.err"; then ok "--quality-delta=A..B, every fold stopped: refused by name, the changed-files form's phase on the line, nothing printed"
else no "range form foldfrom:1: rc=$rc out=$( wc -c <"$TMP/rgall.out" ) stderr: $( grep -a '^ripwire:' "$TMP/rgall.err" | head -c 240 )"; fi
# A stop while the grep prefetch worker runs: the unwind joins it first (a joinable thread would std::terminate, rc 134).
rc="$( fgs_cli gr fold:1 --grep=helper )"
if [ "$rc" = 5 ] && [ ! -s "$TMP/gr.out" ] && [ "$( stopline "$TMP/gr.err" )" = 1 ]; then ok "--grep over a stopped fold: exit 5, one line, nothing printed (the prefetch worker was joined on the unwind)"
else no "--grep fold:1: rc=$rc stdout=$( wc -c <"$TMP/gr.out" ) bytes stderr: $( head -c 200 "$TMP/gr.err" )"; fi
rc="$( fgs_cli grok "" --grep=helper )"
if [ "$rc" = 0 ] && grep -q helper "$TMP/grok.out"; then ok "--grep, no seam: answers (the positive twin)"; else no "--grep no seam: rc=$rc"; fi

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

# ── a write verb whose fold stops AFTER its write answers its receipt, never a refusal (rv-file-graph-final F-W1) ──────────────
# The edit verbs write, then rebuild the index for the post-check, then the envelope stamps _index from it; quality_baseline writes
# its sidecar, then the stamp rebuilds. A stop in either rebuild refuses nothing: the write stands, so the call answers a RESULT
# with the write on it and the stop named (post_check "not run: ...", or _index "not rebuilt" plus _memory_stop). A refusal
# there makes an agent retry, and an insert retried inserts twice. fold:1 is the locate build, before any write: still refused.
mcp_full(){ python3 - "$1" "$2" <<'PY'
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
            if e:
                print( "ERR " + e.get( "message", "" ) )
            else:
                res = r.get( "result", {} )
                print( "OK " + "".join( c.get( "text", "" ) for c in res.get( "content", [] ) ) + " _index=" + res.get( "_index", "" ) + " _memory_stop=" + res.get( "_memory_stop", "" ) )
PY
}
mcp_write(){   # $1 = label, $2 = seam, $3 = tool, $4 = extra arguments JSON; a fresh copy of the fixture and a fresh cache per label
    local d="$TMP/w_$1"; rm -rf "$d" "$TMP/xdg/w_$1"; cp -R "$FGS" "$d"; mkdir -p "$TMP/xdg/w_$1"
    { printf '%s\n' '{"jsonrpc":"2.0","id":1,"method":"initialize"}'
      printf '%s\n' "{\"jsonrpc\":\"2.0\",\"id\":2,\"method\":\"tools/call\",\"params\":{\"name\":\"$3\",\"arguments\":{\"path\":\"$d\"$4}}}"; } \
        | ( cd "$d" && XDG_CACHE_HOME="$TMP/xdg/w_$1" TMPDIR="$TMP/xdg/w_$1" env ${2:+RIPWIRE_TEST_MEMGUARD="$2"} perl -e 'alarm shift; exec @ARGV' 60 "$BIN" --mcp 2>/dev/null ) >"$TMP/w_$1.out"
    mcp_full "$TMP/w_$1.out" 2
}
INS=',"symbol":"unrelated","file":"lib.cpp","text":"int added_fn(){ return 7; }\n"'
for seam in "" fold:1 fold:2 fold:3; do
    lab="ins${seam/:/}"; r="$( mcp_write "$lab" "$seam" insert_after_symbol "$INS" )"
    n="$( grep -c added_fn "$TMP/w_$lab/lib.cpp" 2>/dev/null )"
    case "$seam" in
    "")     case "$r" in OK*'"applied":"insert_after_symbol"'*'"edit_check"'*) if [ "$n" = 1 ]; then ok "MCP insert_after_symbol, no seam: applied with its post-check, the text once (the positive twin)"; else no "insert no seam: added_fn x$n"; fi;;
            *) no "MCP insert_after_symbol no seam: ${r:0:250}";; esac;;
    fold:1) case "$r" in "ERR memory limit reached during the include-closure fold"*) if [ "$n" = 0 ]; then ok "MCP insert_after_symbol fold:1 (the locate build, before the write): refused by name, file untouched"; else no "insert fold:1 refused but added_fn x$n"; fi;;
            *) no "MCP insert_after_symbol fold:1: ${r:0:250}";; esac;;
    *)      case "$r" in OK*'"applied":"insert_after_symbol"'*'"blob_sha"'*) ;; *) no "MCP insert_after_symbol $seam (a stop after the write): not a receipt: ${r:0:300}"; continue;; esac
            if [ "$n" = 1 ] && { printf '%s' "$r" | grep -q '"post_check":"not run: the post-edit check stopped in the include-closure fold' \
                                 || printf '%s' "$r" | grep -q '_index=\[index: not rebuilt.*_memory_stop=the index rebuild after this answer stopped'; }; then
                ok "MCP insert_after_symbol $seam: the stop after the write is on the receipt (applied, blob_sha, the stop named), the text once"
            else no "MCP insert_after_symbol $seam: added_fn x$n, no stop named: ${r:0:400}"; fi;;
    esac
done
# a neighbour the review did not run: replace_symbol_body, the other op through the same driver
r="$( mcp_write rep2 fold:2 replace_symbol_body ',"symbol":"unrelated","file":"lib.cpp","new_body":"int unrelated(){ return 9; }"' )"
case "$r" in OK*'"applied":"replace_symbol_body"'*'"post_check":"not run: '*) if grep -q 'return 9' "$TMP/w_rep2/lib.cpp"; then ok "MCP replace_symbol_body fold:2: applied, post_check not run, the stop named"; else no "replace fold:2: receipt but file not edited"; fi;;
*) no "MCP replace_symbol_body fold:2: ${r:0:300}";; esac
# quality_baseline: the sidecar is written, then the stamp's rebuild stops: the answer stands, the stamp and _memory_stop say so
r="$( mcp_write qb2 fold:2 quality_baseline '' )"
case "$r" in OK*'_index=[index: not rebuilt'*'_memory_stop=the index rebuild after this answer stopped in the include-closure fold'*)
    if [ -s "$TMP/w_qb2/.ripwire_quality_baseline" ]; then ok "MCP quality_baseline fold:2: the sidecar written, answered with the index stop named (_index not rebuilt, _memory_stop)"; else no "qb fold:2: answered but no sidecar"; fi;;
*) no "MCP quality_baseline fold:2: ${r:0:300}";; esac
r="$( mcp_write qb0 "" quality_baseline '' )"
case "$r" in OK*'_index=[index: files='*) if [ -s "$TMP/w_qb0/.ripwire_quality_baseline" ]; then ok "MCP quality_baseline, no seam: the sidecar written, a whole stamp (the positive twin)"; else no "qb no seam: no sidecar"; fi;;
*) no "MCP quality_baseline no seam: ${r:0:300}";; esac
# the CLI twin of the edit driver: exit 0 with the receipt (the file is edited), the stop named on it and on the stderr line
d="$TMP/w_cli"; rm -rf "$d"; cp -R "$FGS" "$d"; printf 'int added_fn(){ return 7; }\n' >"$TMP/w_cli.payload"; mkdir -p "$TMP/xdg/w_cli"
( cd "$d" && XDG_CACHE_HOME="$TMP/xdg/w_cli" TMPDIR="$TMP/xdg/w_cli" RIPWIRE_TEST_MEMGUARD=fold:2 "$BIN" "$d" --insert-after-symbol=unrelated --edit-target-file=lib.cpp --edit-payload="$TMP/w_cli.payload" >"$TMP/w_cli.out" 2>"$TMP/w_cli.err" ); rc=$?
if [ "$rc" = 0 ] && grep -q '"post_check":"not run: ' "$TMP/w_cli.out" && grep -q 'post-check not run' "$TMP/w_cli.err" && [ "$( grep -c added_fn "$d/lib.cpp" )" = 1 ]; then
    ok "CLI --insert-after-symbol fold:2: exit 0, the receipt names the stopped post-check, the text once"
else no "CLI --insert-after-symbol fold:2: rc=$rc added_fn x$( grep -c added_fn "$d/lib.cpp" ) out: $( head -c 200 "$TMP/w_cli.out" ) err: $( head -c 200 "$TMP/w_cli.err" )"; fi

# the plan surface: each op's post-check and the receipt's count both rebuild after every file is written
d="$TMP/w_plan"; rm -rf "$d"; cp -R "$FGS" "$d"; mkdir -p "$d/plans" "$TMP/xdg/w_plan"; printf 'int added_fn(){ return 7; }\n' >"$d/plans/add.cpp"
printf '%s\n' '{"version":1,"edits":[{"op":"insert_after_symbol","target":"unrelated","file":"lib.cpp","payload":"add.cpp"}]}' >"$d/plans/p.json"
( cd "$d" && XDG_CACHE_HOME="$TMP/xdg/w_plan" TMPDIR="$TMP/xdg/w_plan" RIPWIRE_TEST_MEMGUARD=foldfrom:2 "$BIN" . --edit-plan=plans/p.json --apply >"$TMP/w_plan.out" 2>"$TMP/w_plan.err" ); rc=$?
if [ "$rc" = 0 ] && grep -q '"post_check":"not run: ' "$TMP/w_plan.out" && grep -q '"counts_floor_unavailable":"the post-apply index rebuild stopped' "$TMP/w_plan.out" && [ "$( grep -c added_fn "$d/lib.cpp" )" = 1 ]; then
    ok "CLI --edit-plan --apply, every fold after the locate stopped: exit 0, the op's post_check and the receipt's count name the stop, the text once"
else no "CLI --edit-plan --apply foldfrom:2: rc=$rc added_fn x$( grep -c added_fn "$d/lib.cpp" ) out: $( head -c 200 "$TMP/w_plan.out" ) err: $( head -c 200 "$TMP/w_plan.err" )"; fi

# The call after a stop rebuilds: the envelope released the index even when the stop was a verb's own graph, not the index's.
rm -rf "$TMP/xdg/mcp"; mkdir -p "$TMP/xdg/mcp"
fr="{\"jsonrpc\":\"2.0\",\"id\":2,\"method\":\"tools/call\",\"params\":{\"name\":\"find_referencing_symbols\",\"arguments\":{\"path\":\"$FGS\",\"symbol\":\"helper\"}}}"
qb="{\"jsonrpc\":\"2.0\",\"id\":3,\"method\":\"tools/call\",\"params\":{\"name\":\"quality_delta\",\"arguments\":{\"path\":\"$FGS\"}}}"
printf '%s\n%s\n%s\n' "$fr" "$qb" "${fr/\"id\":2/\"id\":4}" \
    | { { printf '%s\n' '{"jsonrpc":"2.0","id":1,"method":"initialize"}'; cat; } | ( cd "$FGS" && XDG_CACHE_HOME="$TMP/xdg/mcp" TMPDIR="$TMP/xdg/mcp" RIPWIRE_MCP_TIMINGS=1 RIPWIRE_TEST_MEMGUARD=fold:2 perl -e 'alarm shift; exec @ARGV' 60 "$BIN" --mcp 2>"$TMP/rel.err" ) >"$TMP/rel.out"; }
r3="$( mcp_resp "$TMP/rel.out" 3 )"; r4="$( mcp_resp "$TMP/rel.out" 4 )"
last="$( grep 'ripwire-timing verb=find_referencing_symbols' "$TMP/rel.err" | tail -1 )"
case "$r3" in "ERR memory limit reached during the include-closure fold"*) ok "MCP: a verb's own fold stopped after the index was built, refused by name";; *) no "MCP own-fold premise: ${r3:0:200}";; esac
case "$r4$last" in OK*'"of_def":["1"]'*'rebuilt=1'*) ok "MCP: the call after it rebuilt the released index and answered whole (rebuilt=1)";; *) no "MCP after an own-fold stop: last='$last' ${r4:0:160}";; esac

# The HTTP server's warm-up: a stopped fold there leaves the server up with no index kept, and the first request builds whole.
WARMUP_PY="$TMP/warmup.py"
cat >"$WARMUP_PY" <<'PY'
import json, os, socket, subprocess, sys, time, urllib.request
bin_, root = sys.argv[1:3]
s = socket.socket(); s.bind( ( "127.0.0.1", 0 ) ); port = s.getsockname()[1]; s.close()
p = subprocess.Popen( [ bin_, root, f"--listen=127.0.0.1:{port}" ], cwd=root, env=dict( os.environ, RIPWIRE_TEST_MEMGUARD="fold:1" ), stdout=subprocess.DEVNULL, stderr=subprocess.PIPE, text=True )
try:
    for line in p.stderr:
        if "warm-up: memory limit reached during the include-closure fold" in line: break
    else:
        print( "no warm-up line, server rc", p.wait() ); sys.exit( 1 )
    time.sleep( 0.5 )
    if p.poll() is not None: print( "the server died, rc", p.returncode ); sys.exit( 1 )
    body = json.dumps( { "jsonrpc": "2.0", "id": 2, "method": "tools/call", "params": { "name": "find_referencing_symbols", "arguments": { "path": root, "symbol": "helper" } } } ).encode()
    r = urllib.request.urlopen( urllib.request.Request( f"http://127.0.0.1:{port}/mcp", data=body, headers={ "Content-Type": "application/json", "Accept": "application/json, text/event-stream" } ), timeout=60 ).read().decode().replace( '\\"', '"' )
    if '"of_def":["1"]' not in r: print( "first request not whole:", r[:200] ); sys.exit( 1 )
    print( "whole" )
finally:
    p.kill()
PY
XDG_CACHE_HOME="$TMP/xdg/mcp" TMPDIR="$TMP/xdg/mcp" perl -e 'alarm shift; exec @ARGV' 90 python3 "$WARMUP_PY" "$BIN" "$FGS" >"$TMP/warm.out" 2>&1; rc=$?
if [ "$rc" = 0 ] && [ "$( cat "$TMP/warm.out" )" = whole ]; then ok "--listen warm-up over a stopped fold: the server stays up, disclosed on stderr, and the first request answers whole"
else no "--listen warm-up: rc=$rc $( tail -c 240 "$TMP/warm.out" )"; fi

# --lsp: a request whose fold stops is answered -32803 RequestFailed with the stop line and the server keeps serving. initialize
# at fold:1 fails and the retried initialize serves; a rebuild mid-session (an edited file, then references) at fold:2 fails and
# the next references answers. The server exits 0 after shutdown/exit: never the crashed server a stop used to leave.
LSP_PY="$TMP/lspstop.py"
cat >"$LSP_PY" <<'PY'
import json, os, subprocess, sys
bin_, root, seam, mode = sys.argv[1:5]
p = subprocess.Popen( [ bin_, root, "--lsp" ], stdin=subprocess.PIPE, stdout=subprocess.PIPE, stderr=subprocess.DEVNULL, cwd=root, env=dict( os.environ, RIPWIRE_TEST_MEMGUARD=seam ) )
def send( o ):
    b = json.dumps( o ).encode(); p.stdin.write( b"Content-Length: %d\r\n\r\n" % len( b ) + b ); p.stdin.flush()
def recv():
    h = b""
    while not h.endswith( b"\r\n\r\n" ):
        c = p.stdout.read( 1 )
        if not c: return None
        h += c
    n = int( [ l for l in h.split( b"\r\n" ) if l.lower().startswith( b"content-length" ) ][0].split( b":" )[1] )
    return json.loads( p.stdout.read( n ) )
def tag( r ):
    if r is None: return "NONE"
    e = r.get( "error" )
    return "ERR%d:%s" % ( e[ "code" ], e[ "message" ][ :70 ] ) if e else "OK" + ( "[]" if r.get( "result" ) == [] else "" )
uri = "file://" + root
refs = { "textDocument": { "uri": uri + "/util_a.h" }, "position": { "line": 1, "character": 12 }, "context": { "includeDeclaration": True } }
out = []
send( { "jsonrpc": "2.0", "id": 1, "method": "initialize", "params": { "rootUri": uri } } ); out.append( tag( recv() ) )
if mode == "init":
    send( { "jsonrpc": "2.0", "id": 2, "method": "initialize", "params": { "rootUri": uri } } ); out.append( tag( recv() ) )
else:
    open( os.path.join( root, "use_a.cpp" ), "a" ).write( "// stale\n" )
    send( { "jsonrpc": "2.0", "id": 2, "method": "textDocument/references", "params": refs } ); out.append( tag( recv() ) )
send( { "jsonrpc": "2.0", "id": 3, "method": "textDocument/references", "params": refs } ); out.append( tag( recv() ) )
send( { "jsonrpc": "2.0", "id": 4, "method": "shutdown" } ); recv(); send( { "jsonrpc": "2.0", "method": "exit" } )
p.stdin.close(); p.wait()
print( " ".join( out ) + " rc=%d" % p.returncode )
PY
for shape in init:fold:1 mid:fold:2; do
    mode="${shape%%:*}"; seam="${shape#*:}"; d="$TMP/lsp_$mode"; rm -rf "$d" "$TMP/xdg/lsp_$mode"; cp -R "$FGS" "$d"; mkdir -p "$TMP/xdg/lsp_$mode"
    r="$( XDG_CACHE_HOME="$TMP/xdg/lsp_$mode" TMPDIR="$TMP/xdg/lsp_$mode" perl -e 'alarm shift; exec @ARGV' 60 python3 "$LSP_PY" "$BIN" "$d" "$seam" "$mode" 2>&1 )"
    case "$mode:$r" in
    "init:ERR-32803:ripwire --lsp: memory limit reached during the include-closure fold"*" OK OK rc=0") ok "--lsp initialize at fold:1: -32803 naming the stop, the retried initialize serves, references answer, exit 0";;
    "mid:OK ERR-32803:ripwire --lsp: memory limit reached during the include-closure fold"*" OK rc=0") ok "--lsp references after an edit at fold:2: -32803 naming the stop, the next references answers, exit 0";;
    *) no "--lsp $shape: $r";;
    esac
done

[ "$fail" = 0 ] && echo "ALL PASS" || echo "FAILURES ABOVE"
exit $fail
