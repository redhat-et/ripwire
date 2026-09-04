#!/usr/bin/env bash
# rootrelemitcheck.sh — the ROOT-RELATIVE EMISSION contract: no emitted document may carry the corpus
# checkout's absolute path anywhere except the ONE envelope attribute that declares the root.
#
#   test/rootrelemitcheck.sh
#   RIPWIRE_BIN=asan/ripwire test/rootrelemitcheck.sh
#
# WHY THIS EXISTS. ing.files[] holds each path exactly as derived from the run's OWN root argument, so an
# absolute root ("ripwire /abs/repo") makes every emitted p=/id= carry the checkout prefix verbatim. That is
# a per-ROW cost against a per-DOCUMENT fact: a peer session measured ~4.8 B of bundle per character of
# checkout depth (26 absolute-path occurrences in one --partition core bundle — 21 path-qualified id= keys
# plus 5 root echoes), which is how two byte-ceiling gates came to depend on where the repo happened to be
# checked out (PLAN_HARVEST_REPORTS_2026-08-20/latent-gates-lane.md pinned both, deliberately, as the
# interim). This gate pins the product cure instead: the root is stated ONCE, every other path is relative
# to it, and the document a consumer receives is therefore INDEPENDENT of checkout depth.
#
# The multi-root run already behaves exactly this way -- <root label="…" p="…"/> declares each root once and
# every <f p="label/…"> is relative to it -- so this gate holds the SINGLE-root run to the standard its own
# multi-root sibling already meets, using the same rootRelativeUri()/pathRel() relativizer (sarif.h).
#
# What it proves, per verb, across all three dialects (XML / JSON / MCP):
#   ARM 1  DEPTH-INDEPENDENCE — the same corpus at two very different absolute depths emits BYTE-IDENTICAL
#          documents once the root spelling itself is masked. This is the cure proof: nothing but the
#          envelope anchor may vary with checkout depth.
#   ARM 2  NO ABSOLUTE PATHS — every occurrence of the absolute root in a document sits inside a disclosed
#          envelope anchor (root="…" / "root":"…" / <root label= p=…/>). Anything else is a leak.
#   ARM 3  SPELLING EQUIVALENCE — `ripwire /abs/corpus` and (cd /abs/corpus && `ripwire .`) emit the same
#          document once the anchor is masked. An absolute root is now just a spelling, not a content change.
#   ARM 4  THE ANCHOR SURVIVES — relativizing must not delete the root: each document that names any path
#          still declares its root exactly once, so a consumer can still resolve what it was given.
#
# The two depths differ by 96 characters, so a single un-relativized row is a multi-byte difference ARM 1
# cannot miss. A pre-cure binary fails ARM 1 and ARM 2 by construction.
#
# Exit 0 = ALL PASS, non-zero = SOME FAILED.

set -u
ROOT="$( cd "$( dirname "$0" )/.." && pwd )"
BIN="${1:-${RIPWIRE_BIN:-$ROOT/build/ripwire}}"
[ "${BIN#/}" = "$BIN" ] && BIN="$ROOT/$BIN"
TMP="$( mktemp -d )"; trap 'rm -rf "$TMP"' EXIT
fail=0
ok(){ printf '  PASS  %s\n' "$*"; }
no(){ printf '  FAIL  %s\n' "$*"; fail=1; }

[ -x "$BIN" ] || { echo "no ripwire binary at $BIN — build first (cmake --build build -j)"; exit 2; }
command -v python3 >/dev/null 2>&1 || { echo "rootrelemitcheck: python3 unavailable — skipping"; exit 0; }

FIX="$ROOT/test/fixture"
[ -d "$FIX" ] || { echo "rootrelemitcheck: no test/fixture — cannot run"; exit 2; }

# ── two copies of the SAME corpus at deliberately different absolute depths ──────────────────────────────
SHORT="$TMP/a"
DEEP="$TMP/ddddddddd/ddddddddd/ddddddddd/ddddddddd/ddddddddd/ddddddddd/ddddddddd/ddddddddd/ddddddddd/d"
mkdir -p "$SHORT" "$DEEP"
cp -R "$FIX/." "$SHORT/"
cp -R "$FIX/." "$DEEP/"
DEPTH_DELTA=$(( ${#DEEP} - ${#SHORT} ))

# Identical git history in both, so the churn/co-change/ownership lenses compare like with like rather than
# self-skipping. Fixed identity + fixed dates ⇒ identical commit SHAs (git hashes content, never location);
# -b main pins the default branch (an ambient init.defaultBranch is a known cross-machine gate trap).
seed_git(){
  ( cd "$1" || exit 1
    git init -q -b main >/dev/null 2>&1
    git config user.email rw@example.invalid; git config user.name ripwire
    git add -A >/dev/null 2>&1
    GIT_AUTHOR_DATE='2026-01-01T00:00:00 +0000' GIT_COMMITTER_DATE='2026-01-01T00:00:00 +0000' \
      git commit -q -m seed >/dev/null 2>&1 ) || true
}
seed_git "$SHORT"; seed_git "$DEEP"

# ── the verb matrix ─────────────────────────────────────────────────────────────────────────────────────
# One entry per emitted document shape. Deliberately EXCLUDED, with reasons, so the omissions are a
# decision rather than an oversight:
#   --doctor / --skipped .......... report the MACHINE's own paths (cache dir, binary), not corpus rows;
#                                   an absolute path there is the answer, not a leak.
#   --quality-baseline / --index-out  write a file and report WHERE they wrote it — an absolute path is the
#                                   contract (the caller must be able to find it).
#   --mcp / --listen .............. long-lived servers; their verb payloads are covered by the MCP arm below.
VERBS_XML=(
  "default:"
  "metrics:--metrics"
  "signatures-only:--signatures-only"
  "outline:--outline"
  "pack-signatures:--pack-signatures"
  "pack-task:--pack-task=compute the area"
  "partition:--pack-task=compute the area|--partition=2|--token-budget=40000"
  "for:--for=compute the area"
  "candidates:--for=compute the area|--format=candidates"
  "expand:--expand=total_area"
  "callers:--callers=area_of_triangle"
  "callees:--callees=total_area"
  "around:--around=total_area"
  "impact:--impact=area_of_triangle"
  "uses:--uses=area_of_triangle"
  "connect:--connect=total_area,area_of_triangle"
  "path:--path=total_area,area_of_triangle"
  "grep:--grep=return"
  "match:--match=(function_definition)"
  "hotspots:--hotspots"
  "lint:--lint"
  "clones:--clones"
  "tree:--tree"
  "communities:--communities"
  "deps:--deps"
  "layout:--layout"
  "exemplar:--exemplar=compute the area"
  "recall:--recall=geometry"
  "lego:--lego=Point"
  "seams:--seams"
  "dead-code:--dead-code"
  "test-gate:--test-gate"
  # M12 (capture-audit-2026-09-04): a BARE --test-gate/--situ on a freshly-seeded corpus has an EMPTY git
  # diff, so it emits a header and ZERO rows — which is exactly how "test-gate" above sat green through a
  # binary that printed every <t>/<u> row as the raw ingest-stored spelling. These four seed the SAME verbs
  # with an explicit changed-file argument (geometry.cpp is the one fixture file with a dependent), so the
  # ROW emitters are actually exercised. --affected and --situ join them because L1 (lens2-crossverb) is a
  # CROSS-VERB finding: four verbs answer "which tests do I run" and printed the same file three ways.
  "affected:--affected=distance"
  "test-gate-files:--test-gate=geometry.cpp"
  "test-gate-files-json:--test-gate=geometry.cpp|--json"
  "situ-files:--situ=geometry.cpp"
  # M12 regression guards for the two verbs fixed earlier on this branch (--verify's p= rows, --ensemble's
  # <s>/<f> rows plus its root=); neither was in this matrix at all, which is how both came to drift.
  "verify-uses:--verify=uses(area_of_triangle)"
  "ensemble:--ensemble"
  "handoff:--handoff"
  "owners:--owners"
  "mentions:--mentions=area_of_triangle"
  "readability:--readability"
  "naming-consistency:--naming-consistency"
  "nonlocal-state:--nonlocal-state"
  "field-affinity:--field-affinity"
  "context-ratio:--context-ratio"
  "comment-coherence:--comment-coherence"
  "external-surface:--external-surface"
  "abi:--abi"
  "doc-drift:--doc-drift"
  "graph-query:--graph-query=kind:function"
  "quality-panel:--quality-panel"
  "dmm:--dmm"
  "arch:--arch"
  "cochange:--cochange=geometry.h"
  "situ:--situ"
  "map-diff:--map-diff"
  "pr-context:--pr-context"
  "from-trace:--from-trace=-"
  "json:--json"
  "json-for:--for=compute the area|--json"
  "sarif:--sarif"
  "scip:--scip"
  "html:--html"
  "mermaid:--mermaid"
  "export:--export"
)

# split a '|'-delimited arg spec into the array ARGV
build_argv(){
  ARGV=()
  local spec="$1" part
  [ -z "$spec" ] && return 0
  local IFS='|'
  for part in $spec; do [ -n "$part" ] && ARGV+=( "$part" ); done
}

run_at(){ # run_at <root> <argspec> ; --from-trace reads stdin, everything else ignores it
  local root="$1" spec="$2"
  build_argv "$spec"
  printf 'at total_area (app.py:8)\n' | "$BIN" "$root" ${ARGV+"${ARGV[@]}"} 2>/dev/null
}

# mask: replace the corpus root spelling with a fixed token, then normalize the TWO fields that are allowed
# to still vary with depth. Both exclusions are deliberate and neither is a path:
#
#   size fields (est_tokens / total_bytes / bytes) — the root anchor is genuinely IN the document, so a
#     90-char-longer root makes the document 90 bytes longer and an honest byte/token count MUST say so.
#     Rounding that away would be the dishonest fix. ARM 5 below bounds exactly how much they may move, so
#     this normalization hides nothing: it relocates the assertion from "are they equal" (they can't be) to
#     "is the difference exactly one root, paid once" (which is the cure).
#   the MCP `_index` stamp — a LOCAL freshness fingerprint that folds each file's mtime, so two independent
#     copies of one commit can never agree on it regardless of path. It is not a path and leaks none.
mask(){ python3 -c '
import re, sys
root = sys.argv[1]
data = sys.stdin.buffer.read().decode("utf-8", "replace").replace(root, "@ROOT@")
data = re.sub(r"(\b[a-z_]*(?:tokens|bytes)(?:=\"?|\"\s*:\s*))\d+", r"\1@N@", data)
data = re.sub(r"\b(file|bundle) \d+B\b", r"\1 @N@B", data)          # --expand reason="file 255B < bundle 410B"
data = re.sub(r"\[index: [^\]]*\]", "[index: @IDX@]", data)
data = re.sub(r"relevance \d+\.\d+", "relevance @S@", data)
data = re.sub(r"(n0\[\")[^\"]*(<br/>)", r"\1@R@\2", data)            # --mermaid root NODE LABEL renders the anchor          # see the RANKING RESIDUAL note below
sys.stdout.write(data)
' "$1"; }

# THE ONE DISCLOSED RESIDUAL — RANKING, NOT EMISSION. `--recall`'s relevance scores still move with checkout
# depth, and the `relevance` normalization above is why this gate stays green in spite of it. The mechanism
# is NOT an un-relativized path: the lexical scorer tokenizes ing.files[] — the STORED spelling, which this
# lane deliberately leaves absolute (emission-relative, storage unchanged) — so a deeper checkout feeds the
# scorer more path tokens and shifts tf-idf. Curing it means changing what the RANKER indexes, which is a
# ranking change owing an eval, not an emission change; this lane does not make it. Named here so the next
# reader sees a known, bounded residual with an owner rather than an unexplained normalization.

# count occurrences of the root that are NOT inside a disclosed envelope anchor
leaks(){ python3 -c '
import re, sys
root = sys.argv[1]
data = sys.stdin.buffer.read().decode("utf-8", "replace")
total = data.count(root)
esc = re.escape(root)
anchors = 0
for pat in (r"\sroot=\"" + esc + r"\"",          # XML envelope
            r"\"root\"\s*:\s*\"" + esc + r"\"",  # JSON envelope
            r"<root\s+label=\"[^\"]*\"\s+p=\"" + esc + r"\"",  # multi-root prologue
            r"^root: " + esc + r"$",             # the --situ plain-text envelope (same fact, text dialect)
            r"const ROOT = \"" + esc + r"\"",    # the --html page-level envelope
            r"\"wrote\"\s*:\s*\"" + esc):        # a written-file report names where it wrote
    anchors += len(re.findall(pat, data, re.MULTILINE))
print(total - anchors, total, anchors)
' "$1"; }

echo "rootrelemitcheck — corpus at depths ${#SHORT} and ${#DEEP} chars (delta ${DEPTH_DELTA})"

# ── LIVENESS, before any per-verb arm ────────────────────────────────────────────────────────────────────
# Every arm below treats "this verb emitted nothing" as "no path contract to check" and passes. That is
# right per verb and catastrophic in aggregate: a binary that emits NOTHING AT ALL would sail through every
# arm green. test/binoverridecheck.sh exists to catch exactly that false-green (it points RIPWIRE_BIN at a
# stub that fails on every invocation and requires each gate to notice), and it caught this one. So: the
# plain default map on a real corpus must produce output, or this gate refuses to report on anything.
if [ -z "$( run_at "$SHORT" "" )" ]; then
  no "LIVENESS: the default map emitted NOTHING on the fixture — the binary under test is broken, so every"
  no "           per-verb arm below would be a false green. Refusing to report. (BIN=$BIN)"
  echo "rootrelemitcheck: SOME FAILED"
  exit 1
fi
ok "liveness: the binary under test emits a non-empty default map"

# ── ARM 1 + ARM 2 + ARM 4 ───────────────────────────────────────────────────────────────────────────────
for entry in "${VERBS_XML[@]}"; do
  name="${entry%%:*}"; spec="${entry#*:}"

  out_s="$TMP/out.short"; out_d="$TMP/out.deep"
  run_at "$SHORT" "$spec" > "$out_s"
  run_at "$DEEP"  "$spec" > "$out_d"

  # a verb that emits nothing at all here carries no path contract — say so rather than passing silently
  if [ ! -s "$out_s" ] && [ ! -s "$out_d" ]; then
    ok "$name — empty on this corpus (no path contract to check)"
    continue
  fi

  # ARM 1 — depth independence
  mask "$SHORT" < "$out_s" > "$TMP/m.short"
  mask "$DEEP"  < "$out_d" > "$TMP/m.deep"
  if cmp -s "$TMP/m.short" "$TMP/m.deep"; then
    ok "$name ARM1 depth-independent (byte-identical at both depths)"
  else
    bs=$( wc -c < "$out_s" | tr -d ' ' ); bd=$( wc -c < "$out_d" | tr -d ' ' )
    no "$name ARM1 document DIFFERS with checkout depth (${bs}B vs ${bd}B; +$(( bd - bs ))B over ${DEPTH_DELTA} chars)"
  fi

  # ARM 2 — no absolute path outside an envelope anchor
  read -r lk tot anc <<EOF
$( leaks "$DEEP" < "$out_d" )
EOF
  if [ "$lk" -eq 0 ]; then
    ok "$name ARM2 no absolute path outside the envelope (${anc} anchor(s))"
  else
    no "$name ARM2 ${lk} absolute-path leak(s) of ${tot} occurrence(s) (${anc} anchored)"
  fi

  # ARM 4 — a document that names paths still declares its root exactly once
  if [ "$anc" -gt 1 ] && [ "$name" != "partition" ]; then
    no "$name ARM4 root declared ${anc} times — the envelope states it ONCE"
  fi

  # ARM 5 — THE QUANTIFIED CURE. The document may grow with checkout depth by at most ONE root spelling per
  # envelope anchor (plus a few bytes of digit growth in the size fields that count it). Before the cure the
  # growth was ~26 roots per bundle — proportional to the number of ROWS, not to the number of documents.
  # This is the arm that turns "no leaks" into a measured bound, and its numbers are the lane's headline.
  bs=$( wc -c < "$out_s" | tr -d ' ' ); bd=$( wc -c < "$out_d" | tr -d ' ' )
  grew=$(( bd - bs ))
  # a "partition" run emits N+1 standalone bundles, each legitimately carrying its own anchor
  budget=$(( anc * DEPTH_DELTA + 16 ))
  if [ "$grew" -le "$budget" ]; then
    if [ "$anc" -gt 0 ]; then
      ok "$name ARM5 +${grew}B over ${DEPTH_DELTA} chars of depth (${anc} anchor(s), bound ${budget}B) — root paid once"
    else
      ok "$name ARM5 +${grew}B — depth-free (no anchor, no path)"
    fi
  else
    no "$name ARM5 +${grew}B over ${DEPTH_DELTA} chars exceeds the ${budget}B one-root-per-anchor bound (${anc} anchor(s))"
  fi
done

# ── ARM 3 — an absolute root is a spelling, not a content change ────────────────────────────────────────
# Mask only the ANCHOR VALUES (never the whole root string — a relative root is "." , which occurs
# everywhere): after the cure the two spellings differ in the envelope and nowhere else.
anchor_mask(){ python3 -c '
import re, sys
data = sys.stdin.buffer.read().decode("utf-8", "replace")
data = re.sub(r"(\sroot=\")[^\"]*(\")",              r"\1@R@\2", data)
data = re.sub(r"(\"root\"\s*:\s*\")[^\"]*(\")",      r"\1@R@\2", data)
data = re.sub(r"(<root\s+label=\"[^\"]*\"\s+p=\")[^\"]*(\")", r"\1@R@\2", data)
data = re.sub(r"(?m)(^root: ).*$",                    r"\1@R@", data)
data = re.sub(r"(const ROOT = \")[^\"]*(\")",         r"\1@R@\2", data)
# the SAME size/stamp/score normalizations mask() applies, and for the same reasons documented there:
# an absolute root and a "." root are different LENGTHS, so any honest byte/token count must differ.
data = re.sub(r"(\b[a-z_]*(?:tokens|bytes)(?:=\"?|\"\s*:\s*))\d+", r"\1@N@", data)
data = re.sub(r"\b(file|bundle) \d+B\b", r"\1 @N@B", data)
data = re.sub(r"\[index: [^\]]*\]", "[index: @IDX@]", data)
data = re.sub(r"relevance \d+\.\d+", "relevance @S@", data)
data = re.sub(r"(n0\[\")[^\"]*(<br/>)", r"\1@R@\2", data)            # --mermaid root NODE LABEL renders the anchor
sys.stdout.write(data)
'; }

for entry in "${VERBS_XML[@]}"; do
  name="${entry%%:*}"; spec="${entry#*:}"
  build_argv "$spec"
  printf 'at total_area (app.py:8)\n' | "$BIN" "$SHORT" ${ARGV+"${ARGV[@]}"} 2>/dev/null > "$TMP/abs.out"
  ( cd "$SHORT" && printf 'at total_area (app.py:8)\n' | "$BIN" "." ${ARGV+"${ARGV[@]}"} 2>/dev/null ) > "$TMP/rel.out"
  if [ ! -s "$TMP/abs.out" ] && [ ! -s "$TMP/rel.out" ]; then continue; fi
  anchor_mask < "$TMP/abs.out" > "$TMP/abs.m"
  anchor_mask < "$TMP/rel.out" > "$TMP/rel.m"
  if cmp -s "$TMP/abs.m" "$TMP/rel.m"; then
    ok "$name ARM3 absolute root ≡ relative root"
  else
    no "$name ARM3 absolute and relative root spellings emit different documents"
  fi
done

# ── ARM 6 — ONE SPELLING ACROSS THE FOUR "which tests do I run" LISTS ───────────────────────────────────
# lens2-crossverb L1 (capture-audit-2026-09-04, M12): --affected, --test-gate (XML and JSON) and --situ all
# answer the same question over the same corpus and named the SAME file three different ways —
# "/abs/root/sub/consumer.cpp", "./sub/consumer.cpp" and "sub/consumer.cpp" — so the four lists could not be
# diffed with `sort | uniq`. The arms above catch each verb's leak in isolation; this one pins the CROSS-VERB
# property directly, because that is the property an agent actually consumes. Run at BOTH root spellings: a
# verb can be self-consistent and still disagree with its siblings on only one of the two.
tests_to_run_rows(){ # <root> <argspec...> → one path per line
  local root="$1"; shift
  "$BIN" "$root" "$@" 2>/dev/null \
    | tr '<' '\n' | sed -n 's/^test p="\([^"]*\)".*/\1/p; s/^t p="\([^"]*\)".*/\1/p'
}
# This arm needs a corpus that HAS a test file. $SHORT/$DEEP do not: the fixture's one cross-dir caller is a
# test only by virtue of the "test/fixture/…" path it lives at in THIS repo, and a copy of it elsewhere is
# just a source file — which is why --affected reports tests=0 on $SHORT. So ARM 6 builds its own copy with
# an unambiguous tests/ member, rather than quietly asserting nothing.
A6="$TMP/tests-to-run"; rm -rf "$A6"; mkdir -p "$A6"; cp -R "$FIX/." "$A6/"
cat > "$A6/test_geometry.cpp" <<'A6EOF'
#include "geometry.h"

// the corpus's test member: it calls into geometry.cpp's definitions, so every "which tests do I run" verb
// must name THIS file — and all four must name it the SAME way.
double test_distance( Point a, Point b )
{
    return distance( a, b );
}
A6EOF
seed_git "$A6"
for spelling in abs rel; do
  if [ "$spelling" = abs ]; then RT="$A6"; CD="$PWD"; else RT="."; CD="$A6"; fi
  # --affected is seeded by SYMBOL here: a file seed walks callers of that file's definitions and, on
  # this corpus, reaches only the cross-dir consumer — the symbol reading is the one that reaches the test.
  a_rows=$( cd "$CD" && tests_to_run_rows "$RT" --affected=distance )
  g_rows=$( cd "$CD" && tests_to_run_rows "$RT" --test-gate=geometry.cpp )
  # the JSON twin carries "p" in BOTH arrays — narrow to tests_to_run so this compares like with like
  j_rows=$( cd "$CD" && "$BIN" "$RT" --test-gate=geometry.cpp --json 2>/dev/null \
            | sed -n 's/.*"tests_to_run":\[\([^]]*\)\].*/\1/p' | tr ',' '\n' | sed -n 's/.*"p":"\([^"]*\)".*/\1/p' )
  s_rows=$( cd "$CD" && "$BIN" "$RT" --situ=geometry.cpp 2>/dev/null \
            | sed -n '/tests to run/,/^  \[3\]/p' | sed -n 's/^        \([^( ][^(]*\)$/\1/p' | sed 's/[[:space:]]*$//' )
  if [ -z "$a_rows" ]; then
    no "ARM6/$spelling --affected emitted NO test row for distance — the arm would be a false green"
    continue
  fi
  for pair in "test-gate:$g_rows" "test-gate-json:$j_rows" "situ:$s_rows"; do
    other="${pair#*:}"; who="${pair%%:*}"
    if [ "$a_rows" = "$other" ]; then
      ok "ARM6/$spelling --affected ≡ --$who tests_to_run spelling ($a_rows)"
    else
      no "ARM6/$spelling --affected says '$a_rows' but --$who says '$other' — the two lists cannot be diffed"
    fi
  done
  case "$a_rows" in
    ./*|/*) no "ARM6/$spelling tests_to_run row '$a_rows' is not root-relative (leading ./ or absolute)" ;;
    *)      ok "ARM6/$spelling tests_to_run rows are root-relative" ;;
  esac
done

# ── ARM 7 — THE WRITE SURFACES: an edit receipt and the follow-up it tells you to paste ─────────────────
# M12: the MCP/CLI edit engine's receipt "file" key and main.cpp's stderr follow-up hint
# (`--edit-check=<file>:<sym>, then --affected=<file>`) both printed ing.files[] RAW. On a relative root that
# is "./app.py", which --edit-check itself never prints and which --affected then re-spells differently; on an
# absolute root it is the whole checkout prefix. An edit verb WRITES, so this arm runs against its own
# throwaway copy of the fixture, once per root spelling, and never touches $SHORT/$DEEP.
for spelling in abs rel; do
  ED="$TMP/edit-$spelling"; rm -rf "$ED"; mkdir -p "$ED"; cp -R "$FIX/." "$ED/"
  printf '// tail\n' > "$TMP/payload.txt"
  if [ "$spelling" = abs ]; then RT="$ED"; else RT="."; fi
  ( cd "$ED" && "$BIN" "$RT" --insert-after-symbol=area_of_triangle --edit-payload="$TMP/payload.txt" \
      > "$TMP/edit.out" 2> "$TMP/edit.err" )
  rcpt=$( sed -n 's/.*"file":"\([^"]*\)".*/\1/p' "$TMP/edit.out" )
  hint=$( sed -n 's/.*--edit-check=\([^:]*\):.*/\1/p' "$TMP/edit.err" )
  if [ -z "$rcpt" ]; then
    no "ARM7/$spelling the edit verb produced no receipt — the arm would be a false green ($( head -c 120 "$TMP/edit.err" ))"
    continue
  fi
  case "$rcpt" in
    ./*|/*) no "ARM7/$spelling edit receipt \"file\":\"$rcpt\" is not root-relative" ;;
    *)      ok "ARM7/$spelling edit receipt \"file\":\"$rcpt\" is root-relative" ;;
  esac
  if [ "$hint" = "$rcpt" ]; then
    ok "ARM7/$spelling the --edit-check= hint pastes the receipt's own spelling ($hint)"
  else
    no "ARM7/$spelling the --edit-check= hint says '$hint' but the receipt says '$rcpt'"
  fi
  # the hint is only useful if the command it prints RUNS — the strongest form of this assertion
  if ( cd "$ED" && "$BIN" "$RT" --edit-check="$hint:area_of_triangle" >/dev/null 2>&1 ); then
    ok "ARM7/$spelling the printed --edit-check=$hint:area_of_triangle actually runs"
  else
    no "ARM7/$spelling the printed --edit-check=$hint:area_of_triangle does NOT run"
  fi
done

# ── ARM 8 — --quality-delta's gating stderr names what its gating ROW names ─────────────────────────────
# M12: the XML/JSON rows normalize sym's path segment through quality::displaySym; the one stderr line that
# names the first gating finding did not, so the same finding was "./geometry.cpp::geo::worse" on stderr and
# "geometry.cpp::geo::worse" in the row (and the full checkout prefix on stderr under an absolute root).
QD="$TMP/qd"; rm -rf "$QD"; mkdir -p "$QD"; cp -R "$FIX/." "$QD/"
cat >> "$QD/geometry.cpp" <<'QDEOF'

namespace geo
{
double worse( int a, int b )
{
    if( a > 1 ) { a += 1; }
    if( a > 2 ) { a += 2; }
    if( a > 3 ) { a += 3; }
    if( a > 4 ) { a += 4; }
    if( a > 5 ) { a += 5; }
    if( a > 6 ) { a += 6; }
    if( a > 7 ) { a += 7; }
    if( a > 8 ) { a += 8; }
    if( a > 9 ) { a += 9; }
    if( a > 10 ) { a += 10; }
    return double( a + b );
}
}
QDEOF
seed_git "$QD"
# now make the COMMITTED symbol materially worse in the working tree — a preexisting-worse major finding,
# which is the only shape that reaches the stderr line under test
python3 - "$QD/geometry.cpp" <<'QDPY'
import sys
p = sys.argv[1]
s = open(p).read()
i = s.index("    return double( a + b );")
extra = "".join("    if( b > %d && a < %d ) { for( int i = 0; i < %d; ++i ) { if( i %% 2 ) { a += i; } } }\n" % (k, k, k)
                for k in range(11, 26))
open(p, "w").write(s[:i] + extra + s[i:])
QDPY
for spelling in abs rel; do
  if [ "$spelling" = abs ]; then RT="$QD"; else RT="."; fi
  ( cd "$QD" && "$BIN" "$RT" --quality-delta > "$TMP/qd.out" 2> "$TMP/qd.err" ) || true
  qerr=$( sed -n 's/.*gating: [0-9]* preexisting-worse major finding(s); first: [a-z-]* \([^ ]*\) .*/\1/p' "$TMP/qd.err" )
  qrow=$( tr '<' '\n' < "$TMP/qd.out" | sed -n 's/^r .*gating="1".*/&/p' | sed -n 's/.* sym="\([^"]*\)".*/\1/p' | head -1 )
  if [ -z "$qerr" ] || [ -z "$qrow" ]; then
    no "ARM8/$spelling no gating finding was produced (stderr='$qerr' row='$qrow') — the arm would be a false green"
    continue
  fi
  if [ "$qerr" = "$qrow" ]; then
    ok "ARM8/$spelling the gating stderr line and its row name the same sym ($qrow)"
  else
    no "ARM8/$spelling stderr names '$qerr' but the gating row names '$qrow'"
  fi
done

# ── the MCP dialect ─────────────────────────────────────────────────────────────────────────────────────
if ! python3 "$ROOT/test/rootrelemitmcp.py" "$BIN" "$SHORT" "$DEEP"; then
  fail=1
fi

echo
if [ "$fail" -eq 0 ]; then echo "rootrelemitcheck: ALL PASS"; else echo "rootrelemitcheck: SOME FAILED"; fi
exit "$fail"
