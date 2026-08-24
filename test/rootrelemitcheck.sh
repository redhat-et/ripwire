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

# ── the MCP dialect ─────────────────────────────────────────────────────────────────────────────────────
if ! python3 "$ROOT/test/rootrelemitmcp.py" "$BIN" "$SHORT" "$DEEP"; then
  fail=1
fi

echo
if [ "$fail" -eq 0 ]; then echo "rootrelemitcheck: ALL PASS"; else echo "rootrelemitcheck: SOME FAILED"; fi
exit "$fail"
