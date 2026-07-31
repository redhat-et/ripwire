#!/usr/bin/env bash
# multirootcheck.sh — the DESIGN_multiRoot.md §8 gate set for multi-root workspaces
# (`ctxpack <dir1> <dir2>` → ONE merged graph with evidence-gated cross-root edges).
#
# Fixture: test/multirootfix/{svc,cli} — two mini-repos, COPIED to a scratch dir and `git init`-ed there
# with DISTINCT histories/authors (never in-tree: nested .git dirs don't belong in this repo). cli/
# includes svc/'s header by an ESCAPING relative include (the §3.1a evidence channel); both roots define
# a decoy `same_name_helper()` with no include evidence.
#
#   G-edge    cross-root call edge into svc's def exists (labeled path), and only via evidence
#   G-forbid  the decoy stays cross-root-edge-less AND merged ambiguous= == sum of the solo runs;
#             MUTATION: point cli's include at the decoy's file → the cross-root edge flips WITH it
#   G-order   `ctxpack svc cli` ≡ `ctxpack cli svc` byte-identical (×3) + warm==cold + xmllint (G4)
#   G-git     per-root history isolation: --owners attributes each root's same-named util.cpp to ITS
#             OWN repo author, never the sibling's
#   G-seam    the churn-backed verbs on roots that are SUBDIRS of ONE repo (a second fixture) — git's
#             repo-relative paths must join across the `<label>/./<rel>` seam: --hotspots ranked>0 with a
#             row from BOTH roots, --cochange exit 0 with pairs>0, --rank-by=churn != the plain map
#   G-pr      --pr-context multi-root (DESIGN §5/§7): one <pr-context root=> section per root inside a
#             <pr-context-workspace> wrapper, labeled changed-file paths, the svc change's blast radius
#             crossing into cli's caller via the evidence edge, determinism + reorder + xmllint, AND the
#             N=1 byte-identity guard (single-root --pr-context == the committed build/ctxpack)
#   G-cache   per-root incrementality: warm rerun reparsed=0 for both roots; touch ONE cli file →
#             only cli reparses (CTXPACK_CACHE_STATS) and svc's cache blob is byte-identical
#   G-solo    N=1 quarantine: single-root output byte-identical to test/golden.xml (today's binary)
#   refusals  --quality-delta/--test-gate/--eval*/--arch --baseline/--index-out/--cache/
#             --scip/--batch each refuse with ONE stderr line + exit 1 (never 2/3/4)
#             (--pr-context is NO LONGER here — it ships per-root sections, see G-pr)
#   hygiene   duplicate root dedupes with a stderr note; nested roots hard-error (exit 1)
#
# Usage:  test/multirootcheck.sh   |   CTXPACK_BIN=asan/ctxpack test/multirootcheck.sh

set -u
ROOT="$( cd "$( dirname "$0" )/.." && pwd )"
# BOTH seams. This gate took CTXPACK_BIN only, so `bash test/multirootcheck.sh <base>/ctxpack` SILENTLY ran
# against build/ctxpack — a red-first run against a pre-fix binary passed for the wrong reason (trap #20).
BIN="${1:-${CTXPACK_BIN:-$ROOT/build/ctxpack}}"
[ "${BIN#/}" = "$BIN" ] && BIN="$ROOT/$BIN"
FIX="$ROOT/test/multirootfix"
TMP="$( mktemp -d )"; trap 'rm -rf "$TMP"' EXIT
fail=0
ok(){ printf '  PASS  %s\n' "$*"; }
no(){ printf '  FAIL  %s\n' "$*"; fail=1; }
skip(){ printf '  SKIP  %s\n' "$*"; }

[ -x "$BIN" ] || { echo "no ctxpack binary at $BIN — build first (cmake --build build -j)"; exit 2; }
echo "multirootcheck: BIN=$BIN  FIX=$FIX  TMP=$TMP"

# ── scratch workspace: sibling checkouts svc/ + cli/, each its own git repo with a distinct history ──
WS="$TMP/ws"; mkdir -p "$WS"
cp -R "$FIX/svc" "$WS/svc"
cp -R "$FIX/cli" "$WS/cli"
initrepo(){ # $1=dir $2=author-email
  ( cd "$1" \
    && git init -q \
    && git -c user.name=t -c user.email="$2" add -A \
    && git -c user.name=t -c user.email="$2" commit -qm init ) || return 1
}
initrepo "$WS/svc" "svc@example.com" || { echo "git init failed"; exit 2; }
initrepo "$WS/cli" "cli@example.com" || { echo "git init failed"; exit 2; }
# distinct churn: one extra commit per repo touching its own util.cpp
( cd "$WS/svc" && echo "// svc touch" >> src/util.cpp && git -c user.name=t -c user.email="svc@example.com" commit -qam svc2 )
( cd "$WS/cli" && echo "// cli touch" >> src/util.cpp && git -c user.name=t -c user.email="cli@example.com" commit -qam cli2 )

# isolate the auto-cache: everything below writes its warm blobs into OUR scratch TMPDIR only.
CACHE="$TMP/cache"; mkdir -p "$CACHE"
run(){ TMPDIR="$CACHE" "$BIN" "$@"; }

# ── G-solo: the N=1 quarantine — single-root output byte-identical to today's committed golden ──────
# (relative root spelling, from $ROOT — the golden's paths are crawl-arg-prefixed `test/fixture/...`)
( cd "$ROOT" && TMPDIR="$CACHE" "$BIN" test/fixture ) >"$TMP/solo.xml" 2>/dev/null
if diff -q "$TMP/solo.xml" "$ROOT/test/golden.xml" >/dev/null; then ok "G-solo: N=1 byte-identical to test/golden.xml"
else no "G-solo: N=1 output diverged from test/golden.xml"; fi

# ── merged map + header identity ─────────────────────────────────────────────────────────────────────
run "$WS/svc" "$WS/cli" >"$TMP/m1.xml" 2>/dev/null
grep -q 'roots=2' "$TMP/m1.xml" || no "header: roots=2 gauge missing"
# §P8 (2026-07-28) — SPELLING REPINNED: `<root l=>` became `<root label=>`. The prologue's l= was the ONLY
# root-LABEL use of that attribute name against 22 sites where l= is a LINE NUMBER — including the <f p=…>
# rows in this very document — so the one-emission, two-reference minority meaning was renamed and the
# 15+-consumer line-number meaning left alone. This assertion and DESIGN_multiRoot.md §A13 were the two
# references. A run that emits `<root l=` again is the rename regressing, not a new feature.
grep -q '<root label="cli"' "$TMP/m1.xml" && grep -q '<root label="svc"' "$TMP/m1.xml" \
  && ok "header: <root label= p=/> prologue for both roots" \
  || no "header: <root/> prologue missing (or regressed to the colliding l= spelling)"
grep -q '<root l="' "$TMP/m1.xml" \
  && no "header: the colliding <root l=> spelling is back — l= must mean a LINE NUMBER everywhere" \
  || ok "header: no <root l=> spelling survives (l= is a line number tool-wide)"
# §P8 (2026-07-28) — SPELLING REPINNED: the merged path is `<label>/./<rel>`, not `<label>/<rel>`.
# Rationale (workspace.h carries the full note): single-root emits `<crawl-arg>/<rel>`, and the canonical
# crawl arg is `.`, so a single-root id reads `./src/x.h::S::m`. With the old `<label>/<rel>` spelling a
# workspace id (`svc/src/x.h::S::m`) had NO relation to it — not even a suffix — so ids captured in a
# workspace run could not be matched against ids from a single-root run of the same tree (§P8 contract
# bullet 7). Re-inserting the root-relative `./` makes the labeled path literally `<label>/` + the exact
# single-root spelling, so the single-root id is an exact SUFFIX of the workspace id at a '/' boundary.
# The rejected alternative `./<label>/<rel>` is only cosmetically `./`-prefixed: it leaves the two ids
# unrelatable AND breaks the label-prefix strip in resolve.h's §3.1a disk-shape probe.
# Nothing structural moves: every path index is keyed through lexicalNormalize(), which drops `.`
# components, so fileIndex/absIndex and the §3.1 cross-root probes see byte-identical keys.
grep -q 'p="svc/./include/svc_api.h"' "$TMP/m1.xml" && grep -q 'p="cli/./src/cli_main.cpp"' "$TMP/m1.xml" \
  && ok "paths: labeled <label>/./<rel> spelling in the merged map" \
  || no "paths: labeled spelling missing from the merged map"
# the point of the spelling: strip the label and you have the single-root `./rel` spelling verbatim
run "$WS/svc" >"$TMP/solosvc.xml" 2>/dev/null
( cd "$WS/svc" && TMPDIR="$CACHE" "$BIN" . ) >"$TMP/solosvc2.xml" 2>/dev/null
solo_p="$( grep -o 'p="\./[^"]*svc_api\.h"' "$TMP/solosvc2.xml" | head -1 )"
ws_p="$(   grep -o 'p="svc/\./[^"]*svc_api\.h"' "$TMP/m1.xml"    | head -1 )"
# machine-checked: strip the `p="` head off both, then the workspace path must END with the solo path.
solo_tail="${solo_p#p=\"}"; ws_tail="${ws_p#p=\"}"
{ [ -n "$solo_tail" ] && [ -n "$ws_tail" ] && [ "$ws_tail" != "${ws_tail%"$solo_tail"}" ]; } \
  && ok "suffix join: workspace $ws_tail ENDS WITH the single-root $solo_tail (ids relatable across runs)" \
  || no "suffix join: single-root spelling ($solo_tail) is not a suffix of the workspace spelling ($ws_tail)"
if command -v xmllint >/dev/null 2>&1; then
  xmllint --noout "$TMP/m1.xml" && ok "G4: merged map is well-formed XML" || no "G4: xmllint rejected the merged map"
else skip "xmllint not installed"; fi

# ── G-order: canonical root order — argv order is irrelevant, byte-identical ×3; warm == cold ───────
gorder=0
for i in 1 2 3; do
  run "$WS/cli" "$WS/svc" >"$TMP/m2.$i.xml" 2>/dev/null
  diff -q "$TMP/m1.xml" "$TMP/m2.$i.xml" >/dev/null || gorder=1
done
[ $gorder -eq 0 ] && ok "G-order: reorder byte-identity (x3, warm+cold)" || no "G-order: output differs under root reordering"

# ── G-edge: the cross-root evidence edge — cli's caller reaches svc's def through the escaped include ─
run "$WS/svc" "$WS/cli" --callers=svc_handle >"$TMP/callers.xml" 2>/dev/null
grep -q 'cli/./src/cli_main.cpp' "$TMP/callers.xml" \
  && ok "G-edge: cross-root include evidence resolves run_cli -> svc_handle" \
  || no "G-edge: cross-root caller missing from --callers=svc_handle"
grep -q 'svc/./src/svc_main.cpp' "$TMP/callers.xml" \
  && ok "G-edge: svc's own in-root caller intact" \
  || no "G-edge: in-root caller lost in the merge"

# ── G-forbid: the decoy never gets a cross-root edge; merged ambiguous= never rises vs solo sum ─────
run "$WS/svc" "$WS/cli" --callers=same_name_helper >"$TMP/decoy.xml" 2>/dev/null
# cli_main's bare call must resolve to cli's OWN helper — never to svc's decoy header.
run "$WS/svc" "$WS/cli" --callees=run_cli >"$TMP/rc.xml" 2>/dev/null
grep -q 'svc/./include/svc_decoy.h' "$TMP/rc.xml" \
  && no "G-forbid: run_cli grew a name-based cross-root edge into svc's decoy" \
  || ok "G-forbid: no cross-root edge without evidence (decoy stays unlinked)"

amb_of(){ sed -n 's/.*ambiguous=\([0-9]*\).*/\1/p' "$1" | head -1; }
run "$WS/svc" >"$TMP/solo_svc.xml" 2>/dev/null
run "$WS/cli" >"$TMP/solo_cli.xml" 2>/dev/null
A_SVC="$( amb_of "$TMP/solo_svc.xml" )"; A_CLI="$( amb_of "$TMP/solo_cli.xml" )"; A_MERGED="$( amb_of "$TMP/m1.xml" )"
if [ -n "$A_SVC" ] && [ -n "$A_CLI" ] && [ -n "$A_MERGED" ] && [ "$A_MERGED" -le $(( A_SVC + A_CLI )) ]; then
  ok "G-forbid: merged ambiguous=$A_MERGED <= solo sum $(( A_SVC + A_CLI )) (never rises)"
else
  no "G-forbid: merged ambiguous=$A_MERGED vs solo svc=$A_SVC + cli=$A_CLI"
fi

# ── G-forbid MUTATION: point the include AT the decoy's file → the edge must flip WITH the evidence ──
MUT="$TMP/mut"; mkdir -p "$MUT"
cp -R "$WS/svc" "$MUT/svc"; cp -R "$WS/cli" "$MUT/cli"
cat > "$MUT/cli/src/cli_main.cpp" <<'EOF'
// MUTATED: the include now points at the DECOY's file — the same bare call must flip to svc's decoy,
// proving the cross-root edge is include-EVIDENCE-driven, not name-driven.
#include "../../svc/include/svc_decoy.h"

int run_cli( int request )
{
    return request + same_name_helper();
}
EOF
rm -f "$MUT/cli/src/cli_helper.cpp"   # remove cli's own def so the decoy is the single evidenced candidate
run "$MUT/svc" "$MUT/cli" --callees=run_cli >"$TMP/mut.xml" 2>/dev/null
grep -q 'svc/./include/svc_decoy.h' "$TMP/mut.xml" \
  && ok "G-forbid mutation: with include evidence the decoy edge appears (evidence-driven)" \
  || no "G-forbid mutation: evidenced cross-root edge did not appear"

# ── G-git: per-root history isolation — each root's util.cpp owned by ITS OWN repo author ───────────
# §P6.4: util.cpp is solo-authored in each root, so the default --owners output now folds it into the
# <uniform/> summary (authors=1 files carry zero per-file identity by default) — pass --detail=1 to get
# the individual <f/> rows (with top=) this check needs.
run "$WS/svc" "$WS/cli" --owners --detail=1 >"$TMP/owners.xml" 2>/dev/null
svc_row="$( tr '<' '\n' <"$TMP/owners.xml" | grep 'p="svc/./src/util.cpp"' || true )"
cli_row="$( tr '<' '\n' <"$TMP/owners.xml" | grep 'p="cli/./src/util.cpp"' || true )"
case "$svc_row" in *svc@example.com*) ok "G-git: svc/src/util.cpp owned by svc's author only";;
                   *) no "G-git: svc util.cpp ownership wrong/missing: $svc_row";; esac
case "$cli_row" in *cli@example.com*) ok "G-git: cli/src/util.cpp owned by cli's author only";;
                   *) no "G-git: cli util.cpp ownership wrong/missing: $cli_row";; esac
case "$svc_row" in *cli@example.com*) no "G-git: cli history leaked into svc's file";; esac
case "$cli_row" in *svc@example.com*) no "G-git: svc history leaked into cli's file";; esac

# ── G-seam: roots that are SUBDIRECTORIES of one repo — `<label>/./<rel>` vs git's REPO-relative paths ──
# §P8.7 (2026-07-28). ea7d7e0 asserted that with the `./` seam restored "git's repo-relative paths still
# suffix-match at a '/' boundary". That holds only when a workspace root IS its repo's root — the seam then
# sits entirely LEFT of <rel> and the boundary test never sees it, which is exactly the shape the WS fixture
# above has, so nothing here noticed. When a root is a SUBDIRECTORY of its repo, git re-spells those leading
# segments WITHOUT the seam (`src/util.cpp`) and `src/./util.cpp` is not a suffix of it: every churn /
# co-change / ownership join resolved NOTHING and the verbs degraded SILENTLY — `--hotspots` returned
# ranked="0" with exit 0, `--rank-by=churn` was byte-identical to the plain map, `--cochange` claimed "git
# unavailable". This fixture is therefore ONE repo with the two roots as subdirs, and it asserts the three
# churn-backed verbs the WS fixture never exercised.
WS2="$TMP/ws2"; mkdir -p "$WS2"
cp -R "$FIX/svc" "$WS2/svc"
cp -R "$FIX/cli" "$WS2/cli"
# a branchy function in BOTH roots: --hotspots ranks complexity × churn, so a churn-only file never appears.
for seamDir in svc cli; do
  cat >"$WS2/$seamDir/src/seam_hot.cpp" <<'SEAMEOF'
int seam_hot( int a, int b )
{
    if( a > b ) { if( a > 10 ) { return a; } else { return b; } }
    for( int i = 0; i < a; ++i ) { if( i % 2 ) { b += i; } else { b -= i; } }
    while( b > 100 ) { b /= 2; if( b == 3 ) { break; } }
    return b;
}
SEAMEOF
done
seamgit(){ git -c user.name=t -c user.email=seam@example.com "$@"; }
( cd "$WS2" && git init -q && seamgit add -A && seamgit commit -qm init ) || { echo "git init (ws2) failed"; exit 2; }
# four commits, each touching seam_hot.cpp AND util.cpp in BOTH roots — clears --cochange's 3-shared-commit
# support floor WITHIN each root (pairs never form across roots: each root mines its own history slice).
for seamN in 1 2 3 4; do
  ( cd "$WS2" \
    && echo "// seam $seamN" >> svc/src/seam_hot.cpp && echo "// seam $seamN" >> svc/src/util.cpp \
    && echo "// seam $seamN" >> cli/src/seam_hot.cpp && echo "// seam $seamN" >> cli/src/util.cpp \
    && seamgit commit -qam "seam$seamN" )
done
attrNum(){ grep -o "$1=\"[0-9]*\"" "$2" | head -n1 | tr -dc '0-9'; }

run "$WS2/svc" "$WS2/cli" --hotspots >"$TMP/seam.hot" 2>/dev/null
seamRanked="$( attrNum ranked "$TMP/seam.hot" )"
if [ "${seamRanked:-0}" -gt 0 ]; then ok "G-seam: --hotspots ranked=$seamRanked (churn joined across the /./ seam)"
else no "G-seam: --hotspots ranked=\"${seamRanked:-?}\" — subdir-root churn resolved NOTHING (silent zero, exit 0)"; fi
grep -q 'p="svc/\./' "$TMP/seam.hot" && ok "G-seam: --hotspots has a row from the svc root" \
  || no "G-seam: --hotspots has no svc row: $( head -c 400 "$TMP/seam.hot" )"
grep -q 'p="cli/\./' "$TMP/seam.hot" && ok "G-seam: --hotspots has a row from the cli root" \
  || no "G-seam: --hotspots has no cli row: $( head -c 400 "$TMP/seam.hot" )"

run "$WS2/svc" "$WS2/cli" --cochange >"$TMP/seam.cc" 2>"$TMP/seam.cc.err"; seamRc=$?
seamPairs="$( attrNum pairs "$TMP/seam.cc" )"
if [ "$seamRc" -eq 0 ] && [ "${seamPairs:-0}" -gt 0 ]; then ok "G-seam: --cochange exit 0, pairs=$seamPairs"
else no "G-seam: --cochange rc=$seamRc pairs=\"${seamPairs:-?}\" err=$( head -1 "$TMP/seam.cc.err" )"; fi

run "$WS2/svc" "$WS2/cli" >"$TMP/seam.plain" 2>/dev/null
run "$WS2/svc" "$WS2/cli" --rank-by=churn >"$TMP/seam.churn" 2>/dev/null
cmp -s "$TMP/seam.plain" "$TMP/seam.churn" \
  && no "G-seam: --rank-by=churn is BYTE-IDENTICAL to the plain map — the churn signal is all zero" \
  || ok "G-seam: --rank-by=churn re-ranks (churn is a real signal in a subdir-root workspace)"

# ── G-cache: per-root blobs + drift-proportional incrementality (CTXPACK_CACHE_STATS) ───────────────
GC="$TMP/gcache"; mkdir -p "$GC"
TMPDIR="$GC" "$BIN" "$WS/svc" "$WS/cli" >/dev/null 2>"$TMP/cold.err"        # cold: writes one blob per root
TMPDIR="$GC" CTXPACK_CACHE_STATS=1 "$BIN" "$WS/svc" "$WS/cli" >/dev/null 2>"$TMP/warm.err"
warm_lines="$( grep -c 'cache-stats' "$TMP/warm.err" || true )"
warm_zero="$( grep -c 'reparsed=0' "$TMP/warm.err" || true )"
if [ "$warm_lines" = "2" ] && [ "$warm_zero" = "2" ]; then ok "G-cache: warm run reparses nothing in either root"
else no "G-cache: warm run stats unexpected: $( tr '\n' ';' <"$TMP/warm.err" )"; fi
# identify svc's blob: only two blobs exist; snapshot both, then dirty ONE cli file.
# AUDIT5 Y4: shard-aware lookup — blobs may be flat under $GC or under $GC/<xx>/ (2-hex shard).
blobsum(){ find "$GC" -maxdepth 2 -type f -name 'ctxpack-*.bin' 2>/dev/null | sort | xargs -I{} md5 -q {} 2>/dev/null || find "$GC" -maxdepth 2 -type f -name 'ctxpack-*.bin' 2>/dev/null | sort | xargs md5sum; }
blobsum >"$TMP/blobs.before"
printf '\n// dirty\n' >> "$WS/cli/src/cli_helper.cpp"
TMPDIR="$GC" CTXPACK_CACHE_STATS=1 "$BIN" "$WS/svc" "$WS/cli" >/dev/null 2>"$TMP/dirty.err"
blobsum >"$TMP/blobs.after"
dirty_zero="$( grep -c 'reparsed=0' "$TMP/dirty.err" || true )"
dirty_one="$( grep -c 'reparsed=1' "$TMP/dirty.err" || true )"
if [ "$dirty_zero" = "1" ] && [ "$dirty_one" = "1" ]; then ok "G-cache: editing cli reparses ONLY cli (svc reparsed=0)"
else no "G-cache: dirty-run stats unexpected: $( tr '\n' ';' <"$TMP/dirty.err" )"; fi
changed_blobs="$( diff <(cat "$TMP/blobs.before") <(cat "$TMP/blobs.after") | grep -c '^[<>]' || true )"
if [ "$changed_blobs" = "2" ]; then ok "G-cache: exactly one blob rewritten (svc's blob byte-identical)"   # 2 diff lines = 1 changed file
else no "G-cache: expected exactly one changed blob, diff lines=$changed_blobs"; fi

# ── refusals: single-root-only verbs refuse with ONE stderr line + exit 1 ────────────────────────────
refuse(){ # $@ = flags
  run "$WS/svc" "$WS/cli" "$@" >/dev/null 2>"$TMP/ref.err"; rc=$?
  if [ $rc -eq 1 ] && grep -q 'single-root only' "$TMP/ref.err"; then ok "refusal: $* (exit 1 + clear stderr)"
  else no "refusal: $* rc=$rc err=$( head -1 "$TMP/ref.err" )"; fi
}
refuse --quality-delta
refuse --quality-baseline
refuse --test-gate
refuse --eval
refuse --eval-retrieval
refuse --index-out=x
refuse --cache=/tmp/x.bin
refuse --scip=idx.scip
refuse --batch=-
printf 'layer a = svc\n' > "$TMP/rules.txt"
refuse --arch="$TMP/rules.txt" --baseline

# ── hygiene: duplicate root dedupes (stderr note, proceeds); nested root hard-errors ────────────────
run "$WS/svc" "$WS/svc" >"$TMP/dup.xml" 2>"$TMP/dup.err"; rc=$?
if [ $rc -eq 0 ] && grep -q 'duplicate root' "$TMP/dup.err" && ! grep -q 'roots=2' "$TMP/dup.xml"; then
  ok "hygiene: duplicate root dedupes to a single-root run (stderr note)"
else no "hygiene: duplicate-root handling rc=$rc"; fi
run "$WS/svc" "$WS/svc/src" >/dev/null 2>"$TMP/nest.err"; rc=$?
if [ $rc -eq 1 ] && grep -q 'nested roots' "$TMP/nest.err"; then ok "hygiene: nested roots hard-error (exit 1)"
else no "hygiene: nested-root handling rc=$rc"; fi

# ── G-pr: --pr-context multi-root — per-root sections, labeled paths, cross-root blast radius ────────
# Fresh workspace so the working-tree edits below are isolated from the caches/dirtying above.
PRW="$TMP/prw"; mkdir -p "$PRW"
cp -R "$FIX/svc" "$PRW/svc"; cp -R "$FIX/cli" "$PRW/cli"
initrepo "$PRW/svc" "svc@example.com" || { echo "git init failed"; exit 2; }
initrepo "$PRW/cli" "cli@example.com" || { echo "git init failed"; exit 2; }
# an UNCOMMITTED working-tree change in EACH root (shows in `git diff HEAD`, one changed file per root)
printf '\n// pr edit svc\n' >> "$PRW/svc/include/svc_api.h"
printf '\n// pr edit cli\n' >> "$PRW/cli/src/cli_main.cpp"
run "$PRW/svc" "$PRW/cli" --pr-context >"$TMP/prc.xml" 2>/dev/null

grep -q '<pr-context-workspace ' "$TMP/prc.xml" \
  && ok "G-pr: single-document <pr-context-workspace> wrapper present" \
  || no "G-pr: <pr-context-workspace> wrapper missing"
grep -q 'root="svc"' "$TMP/prc.xml" && grep -q 'root="cli"' "$TMP/prc.xml" \
  && ok "G-pr: both roots' <pr-context root=> sections present" \
  || no "G-pr: a per-root <pr-context root=> section is missing"
grep -q 'p="svc/./include/svc_api.h"' "$TMP/prc.xml" && grep -q 'p="cli/./src/cli_main.cpp"' "$TMP/prc.xml" \
  && ok "G-pr: labeled changed-file paths in each root's section" \
  || no "G-pr: labeled changed-file paths missing"
# cross-root blast radius: the svc-root change (svc_api.h→svc_handle) must reach cli's run_cli caller
# via the evidence edge — asserted INSIDE the svc section only (cli_main.cpp is itself changed in cli's).
svc_sec="$( tr '<' '\n' <"$TMP/prc.xml" | sed -n '/root="svc"/,/\/pr-context/p' )"
printf '%s\n' "$svc_sec" | grep -q 'f p="cli/./src/cli_main.cpp"' \
  && ok "G-pr: svc section blast radius crosses roots (svc_api.h reaches cli_main.cpp)" \
  || no "G-pr: cross-root blast radius absent from the svc section"
# determinism x2 + reorder-stable + G4 xmllint
run "$PRW/svc" "$PRW/cli" --pr-context >"$TMP/prc2.xml" 2>/dev/null
diff -q "$TMP/prc.xml" "$TMP/prc2.xml" >/dev/null && ok "G-pr: determinism (x2 byte-identical)" || no "G-pr: nondeterministic across runs"
run "$PRW/cli" "$PRW/svc" --pr-context >"$TMP/prc3.xml" 2>/dev/null
diff -q "$TMP/prc.xml" "$TMP/prc3.xml" >/dev/null && ok "G-pr: reorder-stable (argv order irrelevant)" || no "G-pr: differs under root reordering"
if command -v xmllint >/dev/null 2>&1; then
  xmllint --noout "$TMP/prc.xml" && ok "G-pr: G4 well-formed XML" || no "G-pr: xmllint rejected the bundle"
else skip "G-pr: xmllint not installed"; fi

# ── G-pr N=1: single-root --pr-context is byte-identical to today (the multi-root path is quarantined) ─
run "$PRW/svc" --pr-context >"$TMP/prc_solo_new.xml" 2>/dev/null
grep -q 'pr-context-workspace' "$TMP/prc_solo_new.xml" \
  && no "G-pr N=1: single-root emitted a workspace wrapper (leak)" \
  || ok "G-pr N=1: single-root emits a bare <pr-context> (no wrapper)"
grep -q 'root="' "$TMP/prc_solo_new.xml" \
  && no "G-pr N=1: single-root leaked a root= attribute" \
  || ok "G-pr N=1: single-root header carries no root= attribute"
REF="$ROOT/build/ctxpack"
if [ -x "$REF" ] && [ "$REF" != "$BIN" ]; then
  TMPDIR="$CACHE" "$REF" "$PRW/svc" --pr-context >"$TMP/prc_solo_ref.xml" 2>/dev/null
  diff -q "$TMP/prc_solo_new.xml" "$TMP/prc_solo_ref.xml" >/dev/null \
    && ok "G-pr N=1: single-root --pr-context byte-identical to committed build/ctxpack" \
    || no "G-pr N=1: single-root --pr-context diverged from committed build/ctxpack"
else skip "G-pr N=1: reference build/ctxpack unavailable for the byte diff"; fi

# ── multi-root verbs stay deterministic + well-formed on the payoff surface ─────────────────────────
run "$WS/svc" "$WS/cli" --impact=svc_handle >"$TMP/imp1.xml" 2>/dev/null
run "$WS/cli" "$WS/svc" --impact=svc_handle >"$TMP/imp2.xml" 2>/dev/null
diff -q "$TMP/imp1.xml" "$TMP/imp2.xml" >/dev/null && ok "--impact: reorder-stable over the merged graph" \
  || no "--impact: differs under root reordering"
grep -q 'cli/./src/cli_main.cpp' "$TMP/imp1.xml" && ok "--impact: blast radius crosses roots via the evidence edge" \
  || no "--impact: cross-root blast radius missing"

# ── G-connect: --connect runs on the merged graph like every other read verb above — it was never in
#    the refusal list (checked: grep the refuse() block, it isn't there), and the BFS/Steiner search is
#    pure graph structure over NodeIds, so the root-scoped evidence-gated merge it needs is one the
#    graph already enforces. (a) a genuine cross-root join over the SAME evidence edge G-edge asserts:
#    run_cli (cli root) calls svc_handle (svc root) directly, so a 2-terminal --connect must span both
#    roots through that one edge. (b) a same-named-in-both-roots NEGATIVE: cli's own same_name_helper
#    and svc's decoy same_name_helper share a name but have NO path between them in the merged graph
#    (the decoy is uncalled; cli's is only reached in-root) — --connect must report them UNCONNECTED,
#    proving the join is edge-evidence-driven, never a name coincidence.
run "$WS/svc" "$WS/cli" --connect=run_cli,svc_handle >"$TMP/conn1.xml" 2>/dev/null
grep -q '<t n="run_cli" t="fn" p="cli/./src/cli_main.cpp' "$TMP/conn1.xml" \
  && grep -q '<t n="svc_handle" t="fn" p="svc/./include/svc_api.h' "$TMP/conn1.xml" \
  && grep -q '<e f="run_cli" t="svc_handle"/>' "$TMP/conn1.xml" \
  && grep -q 'groups="1"' "$TMP/conn1.xml" \
  && ok "G-connect: cross-root join spans both roots through the evidence edge (one group)" \
  || no "G-connect: cross-root join missing/malformed: $( cat "$TMP/conn1.xml" )"
if command -v xmllint >/dev/null 2>&1; then
  xmllint --noout "$TMP/conn1.xml" && ok "G-connect: G4 well-formed XML" || no "G-connect: xmllint rejected the connect output"
else skip "G-connect: xmllint not installed"; fi

# reorder-stability + determinism, exactly like G-order above but for --connect specifically.
run "$WS/cli" "$WS/svc" --connect=run_cli,svc_handle >"$TMP/conn2.xml" 2>/dev/null
diff -q "$TMP/conn1.xml" "$TMP/conn2.xml" >/dev/null \
  && ok "G-connect: reorder-stable + deterministic over the merged graph" \
  || no "G-connect: differs under root reordering"

# same-named-decoy NEGATIVE: file:-disambiguated terminals in each root, zero graph path between them.
# NOTE (§P8 spelling): the terminals are deliberately written in the `<label>/<rel>` form WITHOUT the
# `/./` seam — graph.h's filePathContains() collapses it, so the natural spelling a reader would type
# still selects the file even though the tool now PRINTS `<label>/./<rel>`.
run "$WS/svc" "$WS/cli" \
  --connect="svc/include/svc_decoy.h:same_name_helper,cli/src/cli_helper.cpp:same_name_helper" \
  >"$TMP/conn3.xml" 2>/dev/null
conn3_unconn="$( grep -o '<unconnected ' "$TMP/conn3.xml" | wc -l | tr -d ' ' )"
grep -q 'groups="0"' "$TMP/conn3.xml" && [ "$conn3_unconn" = "2" ] \
  && ok "G-connect NEGATIVE: same-named symbols in different roots stay unconnected (no name-coincidence join)" \
  || no "G-connect NEGATIVE: decoy pair wrongly joined (unconnected=$conn3_unconn): $( cat "$TMP/conn3.xml" )"
grep -q '<e f="' "$TMP/conn3.xml" \
  && no "G-connect NEGATIVE: an edge was emitted between the unrelated same-named decoys" \
  || ok "G-connect NEGATIVE: no edge emitted between the unrelated same-named decoys"

# ── Decision B (§3.2, decided 2026-07-11): cross-root CONFIG-FILE import evidence ────────────────────
# tsconfig.json `paths` alias + go.mod `replace` that point at the sibling root admit cross-root import
# resolution — evidence-only (unique-or-degrade, never name-based), exactly like escaping includes.
#   tsconfig: cli/src/cli_app.ts imports "@svc/api" → paths @svc/* → svc/src/svc_api.ts (svcTsApi)
run "$WS/svc" "$WS/cli" --callers=svcTsApi >"$TMP/tsalias.xml" 2>/dev/null
grep -q 'cli/./src/cli_app.ts' "$TMP/tsalias.xml" \
  && ok "B/tsconfig: @svc/* paths alias resolves runTsApp -> svcTsApi across roots" \
  || no "B/tsconfig: cross-root tsconfig-alias edge missing"
#   go.mod: cli/main.go imports "example.com/svc/pkg" → replace => ../svc → svc/pkg/handle.go (GoHandle)
run "$WS/svc" "$WS/cli" --callers=GoHandle >"$TMP/goreplace.xml" 2>/dev/null
grep -q 'cli/./main.go' "$TMP/goreplace.xml" \
  && ok "B/go.mod: replace directive resolves runGoMain -> GoHandle across roots" \
  || no "B/go.mod: cross-root go.mod-replace edge missing"
# ambiguous= never rises from the config channels: the G-forbid gauge check above already ran on m1.xml
# WITH these config edges present (A_MERGED <= A_SVC + A_CLI), so evidence-only-ness is already asserted.

# B MUTATION: point BOTH the alias and the replace at a BOGUS path → both cross-root edges must vanish
# (proving they are config-EVIDENCE-driven, not name-driven).
BMUT="$TMP/bmut"; mkdir -p "$BMUT"; cp -R "$WS/svc" "$BMUT/svc"; cp -R "$WS/cli" "$BMUT/cli"
cat > "$BMUT/cli/tsconfig.json" <<'EOF'
{ "compilerOptions": { "baseUrl": ".", "paths": { "@svc/*": ["../svc/NONEXISTENT/*"] } } }
EOF
cat > "$BMUT/cli/go.mod" <<'EOF'
module example.com/cli
go 1.21
replace example.com/svc => ../svc/NONEXISTENT
EOF
run "$BMUT/svc" "$BMUT/cli" --callers=svcTsApi >"$TMP/tsmut.xml" 2>/dev/null
grep -q 'cli/./src/cli_app.ts' "$TMP/tsmut.xml" \
  && no "B/mutation: tsconfig edge survived a bogus alias target (name-driven, not evidence)" \
  || ok "B/mutation: bogus tsconfig target → the cross-root edge disappears (evidence-driven)"
run "$BMUT/svc" "$BMUT/cli" --callers=GoHandle >"$TMP/gomut.xml" 2>/dev/null
grep -q 'cli/./main.go' "$TMP/gomut.xml" \
  && no "B/mutation: go.mod edge survived a bogus replace target (name-driven, not evidence)" \
  || ok "B/mutation: bogus go.mod replace target → the cross-root edge disappears (evidence-driven)"

# ── Decision A (A11, decided 2026-07-11): MCP EDIT verbs accept `paths` — multi-root writes to the REAL
#    disk file, with the unambiguous-across-roots safety rule (a same-named symbol in >1 root needs the
#    root-labeled path form, else refused naming candidates). Writes go to diskPath, never the label. ──
mcp_call() { printf '%s\n' "$@" | "$BIN" --mcp 2>/dev/null | tail -1; }
AWS="$TMP/aws"; mkdir -p "$AWS"; cp -R "$WS/svc" "$AWS/svc"; cp -R "$WS/cli" "$AWS/cli"

# A1 — svc_unique_target exists in svc ONLY → resolves unambiguously across the workspace with no label,
#      and the edit lands in svc's REAL on-disk file.
rA1="$( mcp_call '{"jsonrpc":"2.0","id":1,"method":"initialize"}' \
  "{\"jsonrpc\":\"2.0\",\"id\":2,\"method\":\"tools/call\",\"params\":{\"name\":\"replace_symbol_body\",\"arguments\":{\"paths\":[\"$AWS/svc\",\"$AWS/cli\"],\"symbol\":\"svc_unique_target\",\"new_body\":\"int svc_unique_target()\\n{\\n    return 2000;\\n}\"}}}" )"
case "$rA1" in *applied*replace_symbol_body*svc/./src/editme.cpp*) ok "A/paths: unambiguous cross-workspace edit via paths[] returns success";;
              *) no "A/paths: unambiguous edit failed: $( echo "$rA1" | head -c 180 )";; esac
grep -q 2000 "$AWS/svc/src/editme.cpp" \
  && ok "A/paths: the svc REAL disk file (not the label) was modified" \
  || no "A/paths: svc real file unchanged after a reported success"

# A2 — shared_edit_target is defined in BOTH roots; WITHOUT the labeled form → refusal naming BOTH
#      labeled candidates, and BOTH files left byte-identical.
cp "$AWS/svc/src/editme.cpp" "$TMP/svc_editme.b2"; cp "$AWS/cli/src/editme.cpp" "$TMP/cli_editme.b2"
rA2="$( mcp_call '{"jsonrpc":"2.0","id":1,"method":"initialize"}' \
  "{\"jsonrpc\":\"2.0\",\"id\":2,\"method\":\"tools/call\",\"params\":{\"name\":\"replace_symbol_body\",\"arguments\":{\"paths\":[\"$AWS/svc\",\"$AWS/cli\"],\"symbol\":\"shared_edit_target\",\"new_body\":\"x\"}}}" )"
case "$rA2" in
  *ambiguous*svc/./src/editme.cpp*cli/./src/editme.cpp*|*ambiguous*cli/./src/editme.cpp*svc/./src/editme.cpp*)
     ok "A/ambiguous: same-named-in-both-roots refused, naming BOTH root-labeled candidates";;
  *ambiguous*) no "A/ambiguous: refused but candidate list incomplete: $( echo "$rA2" | head -c 220 )";;
  *) no "A/ambiguous: expected a cross-root ambiguity refusal, got: $( echo "$rA2" | head -c 220 )";;
esac
cmp -s "$AWS/svc/src/editme.cpp" "$TMP/svc_editme.b2" && cmp -s "$AWS/cli/src/editme.cpp" "$TMP/cli_editme.b2" \
  && ok "A/ambiguous: BOTH roots' files byte-identical after the refusal (no partial write)" \
  || no "A/ambiguous: a file was modified despite the refusal"

# A3 — WITH the root-labeled form file:"svc/" → svc's REAL file is edited; cli's file stays untouched.
cp "$AWS/cli/src/editme.cpp" "$TMP/cli_editme.b3"
rA3="$( mcp_call '{"jsonrpc":"2.0","id":1,"method":"initialize"}' \
  "{\"jsonrpc\":\"2.0\",\"id\":2,\"method\":\"tools/call\",\"params\":{\"name\":\"replace_symbol_body\",\"arguments\":{\"paths\":[\"$AWS/svc\",\"$AWS/cli\"],\"symbol\":\"shared_edit_target\",\"file\":\"svc/\",\"new_body\":\"int shared_edit_target()\\n{\\n    return 5555;\\n}\"}}}" )"
case "$rA3" in *applied*replace_symbol_body*svc/./src/editme.cpp*) ok "A/labeled: file:'svc/' resolves to svc's def unambiguously";;
              *) no "A/labeled: labeled edit failed: $( echo "$rA3" | head -c 220 )";; esac
grep -q 5555 "$AWS/svc/src/editme.cpp" \
  && ok "A/labeled: svc's REAL disk file carries the edit" || no "A/labeled: svc real file not edited"
cmp -s "$AWS/cli/src/editme.cpp" "$TMP/cli_editme.b3" \
  && ok "A/labeled: cli's file left untouched (edit lands in the correct root only)" \
  || no "A/labeled: cli's file was wrongly modified"

# ── §B6 (capture-audit-4, wave 3): the ONE deliberate CLI/MCP divergence, DISCLOSED ────────────────────
#
# The CLI refuses --batch in a multi-root workspace; the MCP `batch` verb with a `paths` array answers a
# MERGED multi-root batch. That asymmetry is a decision, not an oversight — but the CLI's sentence used to
# say "batch sub-queries run against ONE root in v1", which is false about the TOOL rather than restrictive
# about this surface. These arms pin BOTH sides, so the divergence cannot silently become a bug in either
# direction: the CLI must still refuse AND must point at the surface that can do it, and the MCP verb must
# still actually merge.
printf 'grep:shared_edit_target\n' > "$TMP/b6batch.txt"
"$BIN" "$AWS/svc" "$AWS/cli" --batch="$TMP/b6batch.txt" >"$TMP/b6.out" 2>"$TMP/b6.err"; b6rc=$?
[ "$b6rc" -eq 1 ] && ok "B6/batch: the CLI still refuses --batch in a multi-root workspace (exit 1)" \
                  || no "B6/batch: CLI --batch exited $b6rc in a workspace (want 1)"
[ ! -s "$TMP/b6.out" ] && ok "B6/batch: the CLI refusal wrote nothing to stdout" \
                       || no "B6/batch: the CLI refusal still emitted $( wc -c <"$TMP/b6.out" | tr -d ' ' ) bytes"
grep -q 'MCP `batch` verb' "$TMP/b6.err" \
    && ok "B6/batch: the refusal NAMES the surface that does answer a merged multi-root batch" \
    || no "B6/batch: the refusal does not point at the MCP verb: [$( head -c 200 "$TMP/b6.err" )]"
grep -q 'ONE root in v1' "$TMP/b6.err" \
    && no "B6/batch: the refusal still claims 'ONE root in v1' — false about the tool, the MCP verb merges" \
    || ok "B6/batch: the refusal no longer claims the capability does not exist"
# the other half of the claim: the MCP verb really does merge. Without this the arms above would happily
# describe a divergence that is not there.
rB6="$( mcp_call '{"jsonrpc":"2.0","id":1,"method":"initialize","params":{"protocolVersion":"2025-11-25"}}' \
  "{\"jsonrpc\":\"2.0\",\"id\":2,\"method\":\"tools/call\",\"params\":{\"name\":\"batch\",\"arguments\":{\"paths\":[\"$AWS/svc\",\"$AWS/cli\"],\"queries\":[{\"verb\":\"grep\",\"pattern\":\"shared_edit_target\"}]}}}" )"
case "$rB6" in
    *'"result"'*'<batch'*) ok "B6/batch: the MCP batch verb ANSWERS a two-root workspace (the divergence is real)" ;;
    *) no "B6/batch: the MCP batch verb did not answer a paths[] batch: $( echo "$rB6" | head -c 200 )" ;;
esac

# ── F-LOW-3: the `paths` lower bound the refusal states must be the bound it enforces ──────────────────
# The missing-`path` refusal said "a `paths` array of 2..16" while the schema row says "an ARRAY of 1..16"
# and the enforcement is mcpArrayArg( …, 1, 16 ). Measured: a ONE-element paths answers, so the refusal's
# lower bound was the wrong one. Both directions asserted, because a bound is only pinned by both.
rF1="$( mcp_call '{"jsonrpc":"2.0","id":1,"method":"initialize","params":{"protocolVersion":"2025-11-25"}}' \
  "{\"jsonrpc\":\"2.0\",\"id\":2,\"method\":\"tools/call\",\"params\":{\"name\":\"find_symbol\",\"arguments\":{\"paths\":[\"$AWS/svc\"],\"symbol\":\"svc_unique_target\"}}}" )"
case "$rF1" in *'"result"'*svc_unique_target*) ok "F-LOW-3: a ONE-element paths[] ANSWERS (the enforced lower bound is 1)";;
               *) no "F-LOW-3: paths:[one root] did not answer: $( echo "$rF1" | head -c 200 )";; esac
rF2="$( mcp_call '{"jsonrpc":"2.0","id":1,"method":"initialize","params":{"protocolVersion":"2025-11-25"}}' \
  '{"jsonrpc":"2.0","id":2,"method":"tools/call","params":{"name":"find_symbol","arguments":{"paths":[],"symbol":"x"}}}' )"
case "$rF2" in *'1..16'*) ok "F-LOW-3: an EMPTY paths[] refuses and states 1..16";;
               *) no "F-LOW-3: the empty-paths refusal does not say 1..16: $( echo "$rF2" | head -c 200 )";; esac
rF3="$( mcp_call '{"jsonrpc":"2.0","id":1,"method":"initialize","params":{"protocolVersion":"2025-11-25"}}' \
  '{"jsonrpc":"2.0","id":2,"method":"tools/call","params":{"name":"find_symbol","arguments":{"symbol":"x"}}}' )"
case "$rF3" in
    *'2..16'*) no "F-LOW-3: the missing-path refusal still says 2..16 while the schema and enforcement say 1..16" ;;
    *'1..16'*) ok "F-LOW-3: the missing-path refusal now states the SAME bound as the schema and the enforcement" ;;
    *)         no "F-LOW-3: the missing-path refusal states no paths bound at all: $( echo "$rF3" | head -c 200 )" ;;
esac

echo
[ $fail -eq 0 ] && echo "multirootcheck: ALL PASS" || echo "multirootcheck: FAILURES"
exit $fail
