#!/usr/bin/env bash
# planlanescheck.sh — gate for --plan-lanes (PLAN_planLanes_2026-07-27.md §6), the PRE-HOC lane plan.
#
# Six checks, and the plan is explicit about which one decides the feature:
#   G-A determinism — two runs of the same invocation are BYTE-IDENTICAL, in both modes, at N=2 and N=16,
#                     and with --no-cache as well as without. A committed plan is only REVIEWABLE if
#                     re-running the command reproduces it; this fails the moment anything iterates a hash
#                     map or reads a clock.
#   G-B JSON validity (the G4 analogue) — `python3 -m json.tool` parses stdout on every mode incl. the
#                     degenerate ones; at is null (never "" and never a fabricated sha) on a non-git root;
#                     no NaN/Inf reaches a float field.
#   G-C conflict prediction, POSITIVE — two lanes provably collide, the plan says so, names the right
#                     symbol, and the conflicting key appears in BOTH lanes' claims. Plus the overload
#                     fold: a scoped same-file overload pair claimed by a lane must report overloads=2,
#                     id_addressable=false, and a folded-claims warning with count>=1 — the fold must be
#                     VISIBLE, not merely correct.
#   G-D the NEGATIVE gate — THE ONE THAT DECIDES ADOPTION. A conflict tool dies on its second false
#                     positive. Two lanes with genuinely disjoint file sets must report conflict_count==0
#                     AND risk_count==0, and the fixture is the exact shape that fabricated a conflict in
#                     --merge-scout before its keying was fixed: two shell files each defining its own
#                     scope-less `ok()`. This gate goes red on day one if anyone "simplifies" the claim key
#                     back to id=. Second negative: two lanes whose BLAST RADII intersect but whose claims
#                     do not must report 0 conflicts, 0 risk and touch_count>0 — the signal lands in
#                     contract_touch and nowhere else.
#   G-E refusals — out-of-range N, a missing task/brief, both at once, an unreadable brief, a brief with
#                     the wrong line count, and a multi-root invocation all exit 1 and write NOTHING to
#                     stdout (a refusal must not ship a payload).
#   G-F schema stability — every documented top-level key, every documented key inside lanes[0] and
#                     pairs[0], and v==1. A schema that drifts silently is worse than no schema.
#
# Usage:
#   test/planlanescheck.sh                          # uses build/ctxpack
#   CTXPACK_BIN=asan/ctxpack test/planlanescheck.sh

set -u
ROOT="$( cd "$( dirname "$0" )/.." && pwd )"
BIN="${CTXPACK_BIN:-$ROOT/build/ctxpack}"
[ "${BIN#/}" = "$BIN" ] && BIN="$ROOT/$BIN"
TMP="$( mktemp -d )"; trap 'rm -rf "$TMP"' EXIT
fail=0

ok(){ printf '  PASS  %s\n' "$*"; }
no(){ printf '  FAIL  %s\n' "$*"; fail=1; }

[ -x "$BIN" ] || { echo "no ctxpack binary at $BIN — build first (cmake --build build -j)"; exit 2; }
command -v python3 >/dev/null 2>&1 || { echo "python3 not found — required to validate the plan JSON"; exit 2; }
echo "planlanescheck: BIN=$BIN"

# run the assertions on stdin against the JSON file named in $1; python prints PASS/FAIL rows itself
assert_json(){
    python3 - "$1" || fail=1
}

# ── fixtures ──────────────────────────────────────────────────────────────────────────────────────────
# Three purpose-built trees, one per question, because the answer depends on what the RANKER surfaces and a
# single shared corpus would let one scenario's symbols leak into another's top-K.

# (1) COLLIDE — one contended symbol two brief lines both name, plus a scoped same-file overload pair.
COLL="$TMP/collide"
mkdir -p "$COLL"
cat >"$COLL/conflict.cpp" <<'EOF'
int contendedSymbolAaa() { return 7; }
int unrelatedPadOne() { return 1; }
int unrelatedPadTwo() { return 2; }
EOF
cat >"$COLL/overload.h" <<'EOF'
struct FoldHost
{
    int foldedTwin() { return 1; }
    int foldedTwin( int n ) { return n; }
};
EOF
# a committed field note on a symbol a lane will claim — the plan must carry it into that lane's notes[]
# (free: the index is already built for every run, and it is exactly the gotcha you would rediscover).
printf 'contendedSymbolAaa\t2026-07-27\tboth lanes want this one\n' >"$COLL/.ctxpack_notes"
cat >"$COLL/brief.txt" <<'EOF'
contendedSymbolAaa
rework contendedSymbolAaa now
foldedTwin
adjust the foldedTwin overload
EOF
git -C "$COLL" init -q
git -C "$COLL" config user.email "dev@x.com"
git -C "$COLL" config user.name  "Dev"
git -C "$COLL" add -A
GIT_AUTHOR_DATE="2026-06-01T12:00:00" GIT_COMMITTER_DATE="2026-06-01T12:00:00" git -C "$COLL" commit -qm init

# (2) BARE — the §1.2 repro shape, DELIBERATELY not a git repo (so at= must be null here too): two shell
#     files, each defining its own scope-less ok(). canonicalId folds both to the bare name "ok"; the claim
#     key must not. Each lane is steered onto ITS file by a marker token that only that file's body carries.
BARE="$TMP/bare"
mkdir -p "$BARE"
cat >"$BARE/a.sh" <<'EOF'
ok() { echo alphazebrasecret; }
alphaOther() { ok; }
EOF
cat >"$BARE/b.sh" <<'EOF'
ok() { echo betazebrasecret; }
betaOther() { ok; }
EOF
cat >"$BARE/brief.txt" <<'EOF'
the alphazebrasecret marker
the betazebrasecret marker
EOF

# (3) TOUCH — disjoint claims whose blast radii meet: upperCallerUnique CALLS deepBaseUnique, in another file.
TOUCH="$TMP/touch"
mkdir -p "$TOUCH"
cat >"$TOUCH/base.h" <<'EOF'
inline int deepBaseUnique() { return 41; }
EOF
cat >"$TOUCH/upper.cpp" <<'EOF'
#include "base.h"
int upperCallerUnique() { return deepBaseUnique() + 1; }
EOF
cat >"$TOUCH/brief.txt" <<'EOF'
deepBaseUnique
upperCallerUnique
EOF

# (4) WIDE — a corpus big enough to actually CARVE. test/fixture has 14 symbols, so its whole ranked surface
#     fits in the shared core and auto-carve honestly returns zero lanes; the schema and determinism checks
#     need a tree with more modules than lanes. 8 files x 7 functions, each file with an intra-file caller so
#     the call graph has real communities to carve along.
WIDE="$TMP/wide"
mkdir -p "$WIDE"
i=0
while [ "$i" -lt 8 ]; do
    {
        j=0
        while [ "$j" -lt 6 ]; do
            printf 'int paintTile%dx%d( int v ) { return v + %d; }\n' "$i" "$j" "$(( i * j ))"
            j=$(( j + 1 ))
        done
        printf 'int paintTileRoot%d() { return paintTile%dx0( 1 ) + paintTile%dx1( 2 ); }\n' "$i" "$i" "$i"
    } >"$WIDE/mod$i.cpp"
    i=$(( i + 1 ))
done

CORPUS="$ROOT/test/fixture"

# ── G-A determinism ───────────────────────────────────────────────────────────────────────────────────
det(){   # $1=label, rest=argv
    local label="$1"; shift
    "$BIN" "$@" >"$TMP/d1" 2>/dev/null
    "$BIN" "$@" >"$TMP/d2" 2>/dev/null
    if cmp -s "$TMP/d1" "$TMP/d2" && [ -s "$TMP/d1" ]; then ok "G-A determinism: $label byte-identical across two runs"
    else no "G-A determinism: $label DIFFERS run-to-run (or produced nothing)"; fi
}
det "auto-carve N=2"  "$WIDE" --plan-lanes=2  --task="paint the tile"
det "auto-carve N=16" "$WIDE" --plan-lanes=16 --task="paint the tile"
det "brief mode"      "$COLL" --plan-lanes    --brief="$COLL/brief.txt"

"$BIN" "$WIDE" --plan-lanes=3 --task="paint the tile"            >"$TMP/c1" 2>/dev/null
"$BIN" "$WIDE" --plan-lanes=3 --task="paint the tile" --no-cache >"$TMP/c2" 2>/dev/null
cmp -s "$TMP/c1" "$TMP/c2" && ok "G-A cache transparency: the plan is identical with and without --no-cache" \
                           || no "G-A cache transparency: --no-cache changed the plan"

# ── G-B JSON validity ─────────────────────────────────────────────────────────────────────────────────
parses(){   # $1=label, $2=file
    if python3 -m json.tool <"$2" >/dev/null 2>&1; then ok "G-B JSON validity: $1 parses"
    else no "G-B JSON validity: $1 does NOT parse"; fi
}
"$BIN" "$WIDE"   --plan-lanes=3 --task="paint the tile"     >"$TMP/auto.json"  2>/dev/null
"$BIN" "$COLL"   --plan-lanes   --brief="$COLL/brief.txt"   >"$TMP/coll.json"  2>/dev/null
"$BIN" "$BARE"   --plan-lanes   --brief="$BARE/brief.txt"   >"$TMP/bare.json"  2>/dev/null
"$BIN" "$TOUCH"  --plan-lanes   --brief="$TOUCH/brief.txt"  >"$TMP/touch.json" 2>/dev/null
"$BIN" "$CORPUS" --plan-lanes=2 --task=zzzznothingmatcheszzzz >"$TMP/empty.json" 2>/dev/null
parses "auto-carve"                "$TMP/auto.json"
parses "brief mode"                "$TMP/coll.json"
parses "a task that matches nothing" "$TMP/empty.json"

assert_json "$TMP/bare.json" <<'PY'
import json, sys, math
d = json.load( open( sys.argv[1] ) )
bad = 0
def check( cond, msg ):
    global bad
    print( ( "  PASS  " if cond else "  FAIL  " ) + msg )
    if not cond: bad = 1

check( d["at"] is None, "G-B at is null (never \"\", never a fabricated sha) on a non-git root" )
check( d["carve"] is None, "G-B carve is null in brief mode" )
check( d["task"] is None, "G-B task is null in brief mode" )
floats = []
for lane in d["lanes"]:
    floats += []
if d["carve"]:
    floats = [ d["carve"]["overlap_mean"], d["carve"]["overlap_max"], d["carve"]["core_overlap"] ]
check( all( math.isfinite( f ) for f in floats ), "G-B no NaN/Inf reaches a float field" )
sys.exit( bad )
PY

assert_json "$TMP/auto.json" <<'PY'
import json, sys, math
d = json.load( open( sys.argv[1] ) )
bad = 0
def check( cond, msg ):
    global bad
    print( ( "  PASS  " if cond else "  FAIL  " ) + msg )
    if not cond: bad = 1
c = d["carve"]
check( c is not None and all( math.isfinite( c[k] ) for k in ( "overlap_mean", "overlap_max", "core_overlap" ) ),
       "G-B auto-carve float fields are finite" )
check( d["at"] is None or isinstance( d["at"], str ), "G-B at is a string or null, never another type" )
sys.exit( bad )
PY

# ── G-C conflict prediction, positive + the visible overload fold ─────────────────────────────────────
assert_json "$TMP/coll.json" <<'PY'
import json, sys
d = json.load( open( sys.argv[1] ) )
bad = 0
def check( cond, msg ):
    global bad
    print( ( "  PASS  " if cond else "  FAIL  " ) + msg )
    if not cond: bad = 1

lanes  = { L["id"]: L for L in d["lanes"] }
claims = { L["id"]: { c["key"]: c for c in L["claims"]["symbols"] } for L in d["lanes"] }

# the contended symbol: some pair must report it as a conflict, by name and by key, and the key must be a
# real claim on BOTH sides of that pair (a conflict row nobody claims would be a fabricated row).
hit = None
for p in d["pairs"]:
    for cf in p["conflicts"]:
        if cf["n"] == "contendedSymbolAaa": hit = ( p, cf )
check( hit is not None, "G-C positive: contendedSymbolAaa is reported as a same-key conflict" )
if hit:
    p, cf = hit
    check( cf["key"] in claims[ p["a"] ] and cf["key"] in claims[ p["b"] ],
           "G-C positive: the conflicting key appears in BOTH lanes' claims.symbols" )
    check( p["conflict_count"] >= 1, "G-C positive: conflict_count >= 1 on that pair" )

noted = [ L for L in d["lanes"] if any( "both lanes want this one" in n for n in L["notes"] ) ]
check( len( noted ) >= 1, "G-C notes: a committed .ctxpack_notes entry on a claimed symbol reaches that lane's notes[]" )

order = d["landing_order"]
check( sorted( order ) == sorted( lanes.keys() ) and len( set( order ) ) == len( order ),
       "G-C landing_order is a total order over every lane id, no repeats" )

# the fold must be VISIBLE: the scoped same-file overload pair collapses to ONE claim that says so.
folded = [ c for L in d["lanes"] for c in L["claims"]["symbols"] if c["n"] == "foldedTwin" ]
check( len( folded ) > 0 and all( c["overloads"] == 2 for c in folded ),
       "G-C fold: the same-file overload pair reports overloads=2 on ONE folded claim" )
check( all( c["id_addressable"] is False for c in folded ),
       "G-C fold: a folded claim is not id_addressable" )
w = { x["code"]: x for x in d["warnings"] }
check( "folded-claims" in w and w["folded-claims"].get( "count", 0 ) >= 1,
       "G-C fold: the folded-claims warning carries a count >= 1 (the fold is in band, not silent)" )
check( "OVER-report" in w.get( "folded-claims", {} ).get( "text", "" ),
       "G-C fold: the warning names the DIRECTION of the error (over-reports, never hides)" )
sys.exit( bad )
PY

# ── G-D the negative gate ─────────────────────────────────────────────────────────────────────────────
assert_json "$TMP/bare.json" <<'PY'
import json, sys
d = json.load( open( sys.argv[1] ) )
bad = 0
def check( cond, msg ):
    global bad
    print( ( "  PASS  " if cond else "  FAIL  " ) + msg )
    if not cond: bad = 1

lanes = { L["id"]: L for L in d["lanes"] }
oks   = { lid: [ c for c in L["claims"]["symbols"] if c["n"] == "ok" ] for lid, L in lanes.items() }

# PRECONDITION, asserted rather than assumed: the fixture must actually have put ONE scope-less ok() on each
# lane, from a DIFFERENT file. Without that the clean pair below would prove nothing.
per = { lid: rows for lid, rows in oks.items() if rows }
check( len( per ) == 2 and all( len( rows ) == 1 for rows in per.values() ),
       "G-D fixture: each lane claims exactly one scope-less ok()" )
if len( per ) == 2:
    ( la, ra ), ( lb, rb ) = list( per.items() )
    check( ra[0]["p"] != rb[0]["p"], "G-D fixture: the two ok() claims are in DIFFERENT files" )
    check( ra[0]["scope"] == "" and rb[0]["scope"] == "",
           "G-D fixture: both ok() definitions are scope-less (the id= degradation case)" )
    check( ra[0]["id"] is None and rb[0]["id"] is None,
           "G-D fixture: both report id=null — canonicalId WOULD fold them to the bare name 'ok'" )
    check( ra[0]["key"] != rb[0]["key"],
           "G-D THE NEGATIVE GATE: two scope-less same-named helpers in different files have DIFFERENT claim keys" )
    pair = [ p for p in d["pairs"] if { p["a"], p["b"] } == { la, lb } ]
    check( len( pair ) == 1, "G-D the two lanes have a pair row" )
    if pair:
        check( pair[0]["conflict_count"] == 0,
               "G-D THE NEGATIVE GATE: disjoint-file lanes report ZERO conflicts (this is the shape that used to fabricate one)" )
        check( pair[0]["risk_count"] == 0,
               "G-D THE NEGATIVE GATE: disjoint-file lanes report ZERO same-file risk" )
# and no lane may claim a file it never ranked into
for L in d["lanes"]:
    paths = { c["p"] for c in L["claims"]["symbols"] }
    check( { f["p"] for f in L["claims"]["files"] } == paths,
           "G-D " + L["id"] + ": claims.files is exactly the files of its claimed symbols (no third file appears)" )
sys.exit( bad )
PY

assert_json "$TMP/touch.json" <<'PY'
import json, sys
d = json.load( open( sys.argv[1] ) )
bad = 0
def check( cond, msg ):
    global bad
    print( ( "  PASS  " if cond else "  FAIL  " ) + msg )
    if not cond: bad = 1

check( len( d["pairs"] ) == 1, "G-D touch fixture: exactly one pair" )
if d["pairs"]:
    p = d["pairs"][0]
    check( p["conflict_count"] == 0, "G-D negative 2: intersecting BLAST RADII are not a conflict" )
    check( p["risk_count"] == 0,     "G-D negative 2: intersecting blast radii are not a same-file risk either" )
    check( p["touch_count"] > 0,     "G-D negative 2: the signal lands in contract_touch and nowhere else" )
    names = { t["n"] for t in p["contract_touch"] }
    check( "upperCallerUnique" in names,
           "G-D negative 2: contract_touch names the CALLER whose claim sits in the callee lane's blast radius" )
    for t in p["contract_touch"]:
        check( t["from"] != t["to"], "G-D negative 2: a contract_touch row is directional (from != to)" )
sys.exit( bad )
PY

# ── G-E refusals: exit 1, and NOTHING on stdout ───────────────────────────────────────────────────────
refuses(){   # $1=label, $2=expected stderr substring, rest=argv
    local label="$1" want="$2"; shift 2
    "$BIN" "$@" >"$TMP/r.out" 2>"$TMP/r.err"; local rc=$?
    if [ "$rc" != 1 ]; then no "G-E $label: exit $rc (want 1)"; return; fi
    if [ -s "$TMP/r.out" ]; then no "G-E $label: refusal wrote $(wc -c <"$TMP/r.out" | tr -d ' ') bytes to stdout"; return; fi
    if ! grep -qF -- "$want" "$TMP/r.err"; then no "G-E $label: stderr does not mention '$want'"; return; fi
    ok "G-E $label: exit 1, empty stdout, message names the fix"
}
refuses "N=1"               "2..16"        "$CORPUS" --plan-lanes=1  --task=x
refuses "N=17"              "2..16"        "$CORPUS" --plan-lanes=17 --task=x
refuses "no task, no brief" "--brief=FILE" "$CORPUS" --plan-lanes=3
refuses "bare flag"         "--brief=FILE" "$CORPUS" --plan-lanes
refuses "task AND brief"    "never both"   "$CORPUS" --plan-lanes=3 --task=x --brief="$COLL/brief.txt"
refuses "unreadable brief"  "cannot read"  "$CORPUS" --plan-lanes   --brief="$TMP/definitely-not-here.txt"
refuses "task without verb" "--plan-lanes" "$CORPUS" --task=x
refuses "brief without verb" "--plan-lanes" "$CORPUS" --brief="$COLL/brief.txt"
refuses "count with brief"  "contradiction" "$CORPUS" --plan-lanes=3 --brief="$COLL/brief.txt"
refuses "multi-root"        "single-root"  "$CORPUS" "$COLL" --plan-lanes=2 --task=x

printf 'only one line\n' >"$TMP/one.txt"
refuses "one-line brief"    "one line per lane" "$CORPUS" --plan-lanes --brief="$TMP/one.txt"
: >"$TMP/blank.txt"
refuses "empty brief"       "one line per lane" "$CORPUS" --plan-lanes --brief="$TMP/blank.txt"

# an empty corpus has nothing to split — a refusal, never a clean-looking empty plan
mkdir -p "$TMP/emptydir"
refuses "empty corpus"      "nothing to split" "$TMP/emptydir" --plan-lanes=2 --task=x

# ── G-F schema stability ──────────────────────────────────────────────────────────────────────────────
assert_json "$TMP/auto.json" <<'PY'
import json, sys
d = json.load( open( sys.argv[1] ) )
bad = 0
def check( cond, msg ):
    global bad
    print( ( "  PASS  " if cond else "  FAIL  " ) + msg )
    if not cond: bad = 1

TOP = { "v": int, "verb": str, "at": ( str, type( None ) ), "root": str, "task": ( str, type( None ) ),
        "source": str, "requested": int, "lane_count": int, "claim_key": str, "on_conflict": str,
        "corpus": dict, "carve": ( dict, type( None ) ), "core": dict, "lanes": list, "pairs": list,
        "landing_order": list, "landing_rule": str, "contract_touch_rule": str, "warnings": list }
for k, t in TOP.items():
    check( k in d and isinstance( d[k], t ), "G-F top-level key present and typed: " + k )
check( d["v"] == 1,                       "G-F v == 1" )
check( d["verb"] == "plan-lanes",         "G-F verb == plan-lanes" )
check( d["claim_key"] == "path+scope+name", "G-F claim_key names the key a consumer joins on" )
check( d["on_conflict"] == "producing-lane-rebases", "G-F on_conflict states the protocol" )
for k in ( "files", "symbols", "edges", "ambiguous", "unresolved" ):
    check( k in d["corpus"], "G-F corpus." + k )
for k in ( "surface", "modules", "split", "overlap_mean", "overlap_max", "shared_symbols",
           "union_symbols", "core_overlap", "overlap_surface", "overlap_is_ceiling" ):
    check( k in d["carve"], "G-F carve." + k )
check( set( d["core"] ) == { "files", "symbols" }, "G-F core is {files, symbols}" )

L = d["lanes"][0]
for k in ( "id", "task", "claims", "blast_radius", "tests_to_run", "tests_total", "tests_capped",
           "tests_granularity", "untested", "module_span", "notes" ):
    check( k in L, "G-F lanes[0]." + k )
for k in ( "symbols", "files" ): check( k in L["claims"], "G-F lanes[0].claims." + k )
for k in ( "reaches", "files_total", "capped", "files" ): check( k in L["blast_radius"], "G-F lanes[0].blast_radius." + k )
if L["claims"]["symbols"]:
    for k in ( "p", "n", "scope", "key", "id", "id_addressable", "id_collides_with", "l", "ord",
               "overloads", "amb", "cx", "ccx", "churn", "tested" ):
        check( k in L["claims"]["symbols"][0], "G-F claim row." + k )
    check( all( len( c["key"] ) == 16 for c in L["claims"]["symbols"] ), "G-F every claim key is 16 hex chars" )
if L["claims"]["files"]:
    for k in ( "p", "symbols", "churn", "ccx", "hotspot_rank" ):
        check( k in L["claims"]["files"][0], "G-F claim file row." + k )

P = d["pairs"][0]
for k in ( "a", "b", "conflicts", "conflict_count", "same_file_risk", "risk_count",
           "contract_touch", "touch_count" ):
    check( k in P, "G-F pairs[0]." + k )

# the honest limits are IN BAND, with stable codes — not only in --help
codes = { w["code"] for w in d["warnings"] }
for c in ( "name-based-callgraph", "bare-name-claims", "folded-claims", "id-collisions",
           "tests-are-symbol-granular", "test-surface-is-partial", "claims-are-advisory" ):
    check( c in codes, "G-F warnings always carry the code: " + c )
check( all( set( w ) >= { "code", "sev", "text" } for w in d["warnings"] ), "G-F every warning has code/sev/text" )
check( all( w["sev"] in ( "info", "warn" ) for w in d["warnings"] ), "G-F every warning sev is info|warn" )
sys.exit( bad )
PY

# the plan is exit 0 even WITH predicted conflicts — conflicts are data, not a CI failure
"$BIN" "$COLL" --plan-lanes --brief="$COLL/brief.txt" >"$TMP/x.json" 2>/dev/null
rc=$?
conf="$( python3 -c 'import json,sys; print(sum(p["conflict_count"] for p in json.load(open(sys.argv[1]))["pairs"]))' "$TMP/x.json" 2>/dev/null )"
if [ "$rc" = 0 ] && [ "${conf:-0}" -ge 1 ]; then ok "exit 0 with $conf predicted conflict(s) — conflicts are data, not a gate"
else no "expected exit 0 with >=1 predicted conflict (rc=$rc conflicts=${conf:-?})"; fi

# --json is accepted and is a no-op (the output is already JSON) rather than a refusal
"$BIN" "$WIDE" --plan-lanes=3 --task="paint the tile" --json >"$TMP/j.json" 2>/dev/null
if [ $? = 0 ] && cmp -s "$TMP/j.json" "$TMP/auto.json"; then ok "--json is accepted and is a no-op on --plan-lanes"
else no "--json changed or refused --plan-lanes output"; fi

# ── G-G a degenerate carve must SAY it is degenerate ──────────────────────────────────────────────────
# When the ranked surface is smaller than the requested lane count, every lane can end up claiming the same
# symbols — and then the pair's "conflicts" are an artifact of the carve, not a property of the work. Found
# by running the verb on a 6-symbol corpus: both lanes claimed all 4 symbols and the pair reported 4
# conflicts with nothing saying why. Silence there is the false positive that kills adoption of a conflict
# tool, so the degenerate case must be labelled AND the healthy case must stay quiet.
printf 'make --recall honor --token-budget\nadd a default row cap to --owners output\n' > "$TMP/healthy_brief.txt"
echo "=== G-G degenerate carve is labelled, healthy carve is not ==="
GDIR="$TMP/degenerate"; mkdir -p "$GDIR"; cd "$GDIR"
git init -q .; git config user.email t@t; git config user.name t
printf 'static int ok( int a ) { return a; }\nint alphaMain( int n ) { return ok( n ); }\n'      > alpha.c
printf 'static int ok( int a ) { return a - 1; }\nint betaMain( int n ) { return ok( n ); }\n'   > beta.c
git add -A; git commit -qm base
printf 'change alphaMain in alpha.c\nchange betaMain in beta.c\n' > brief.txt
"$BIN" . --plan-lanes --brief=brief.txt >"$TMP/degen.json" 2>/dev/null
cd "$ROOT"
python3 - "$TMP/degen.json" <<'PYEOF'
import json,sys
d=json.load(open(sys.argv[1]))
fail=0
def check(c,m):
    global fail
    print(("  PASS  " if c else "  FAIL  ")+m)
    if not c: fail=1
w=[x for x in d["warnings"] if x["code"]=="lane-claims-coincide"]
lanes=d["lanes"]
if len(lanes) >= 2:
    keys=[set(c["key"] for c in L["claims"]["symbols"]) for L in lanes]
    coincide = keys[0] and keys[0] == keys[1]
    check(not coincide or bool(w),
          "G-G a carve whose lanes claim IDENTICAL symbol sets emits lane-claims-coincide")
    if w:
        check("artifact of the carve" in w[0]["text"],
              "G-G ...and says the conflicts are a carve artifact, not work")
        check(w[0]["sev"]=="warn", "G-G ...at sev=warn, not buried at info")
else:
    check(True, "G-G skipped: fixture produced <2 lanes (not a degenerate carve)")
sys.exit(fail)
PYEOF
[ $? -eq 0 ] || fail=1

# the healthy case: a real repo carve with disjoint claims must NOT raise it
"$BIN" . --plan-lanes --brief="$TMP/healthy_brief.txt" >"$TMP/healthy.json" 2>/dev/null || true
if [ -s "$TMP/healthy.json" ]; then
    if python3 -c "
import json,sys
d=json.load(open('$TMP/healthy.json'))
ks=[set(c['key'] for c in L['claims']['symbols']) for L in d['lanes']]
w=[x for x in d['warnings'] if x['code']=='lane-claims-coincide']
disjoint = len(ks)==2 and not (ks[0] & ks[1])
sys.exit(0 if (not disjoint or not w) else 1)
"; then ok "G-G disjoint-claim lanes do NOT raise lane-claims-coincide (no false alarm)"
    else no "G-G raised lane-claims-coincide on lanes with disjoint claims"; fi
fi

[ "$fail" = 0 ] && echo "ALL PASS" || echo "FAILURES ABOVE"
exit $fail
