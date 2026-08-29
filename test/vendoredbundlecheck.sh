#!/usr/bin/env bash
# vendoredbundlecheck.sh — gate for the vendored-BUNDLE extension to the §P4 de-prioritization tier
# (src/filter.h, 2026-08-29 fix round, SWE-Explore loss bucket 4).
#
# vendoredassetcheck.sh already covers the ORIGINAL tier (decks, captures, static/ assets, numbered
# migrations). This gate is for the two families that round added on top of it, because a Yarn Berry repo
# commits its own package-manager executable into version control and nothing in the original tier's path
# table, or the crawl's directory denylist, ever saw it:
#
#   1. PATH signals — `.yarn/releases/*` (the committed yarn-X.Y.Z.cjs release bundle) and the exact
#      basenames `.pnp.cjs` / `.pnp.loader.mjs` (Yarn Plug'n'Play's generated resolution manifest/loader,
#      which conventionally sit at a workspace ROOT, so no directory-component rule can see them).
#   2. An EVIDENCE signal — any def whose own byte span crams kVendoredBundleLineBytes+ bytes onto its
#      physical line count (src/filter.h fileLooksLikeVendoredBundle via rankTierSymbolMultipliers) — the
#      general "minified/bundled single-file artifact" class the path table cannot enumerate, catching the
#      SAME shape of file wherever it happens to live.
#
# THIS TREE CONTAINS NEITHER FAMILY, so (per CONTRIBUTING.md §2) the corpus below is synthetic and carries
# the population directly — a gate written against the repo itself would be green while inert.
#
# RED (the binary at the lane base d8e257d, before this round's filter.h change) — measured, not assumed:
#   for a token-bucket rate-limiter query, the synthetic `.yarn/releases/yarn-3.1.0.cjs` bundle outranks
#   the real src/ implementation (score ratio ~1.8x), and the SAME bundle bytes placed under an ordinary
#   `pkg/generated/` path (no tier rule matches that path at all) do too — proving the loss is not just a
#   missing path rule, evidence is needed. Reproduce with:
#     RIPWIRE_BIN=<path to the d8e257d binary> bash test/vendoredbundlecheck.sh
#   (fails arms 2 and 3 below; every other arm is unaffected since the OLD binary lacks BOTH new features).
#
# GREEN (this gate, against the binary under test): the real implementation outranks both bundle placements
# (path-tagged AND evidence-only); each demoted symbol is still findable by exact name and by `--expand`
# (de-prioritization, never exclusion — the tier's existing disclosure contract, unchanged by this round);
# a `.pnp.cjs` at a workspace root is demoted purely by basename even though its OWN content is ordinary,
# short, hand-editable-looking JS (the PATH rule, not the evidence rule, must be what catches it); and an
# ordinary file with one genuinely long-but-not-extreme line stays undemoted (the evidence floor is not
# hair-triggered on merely-long lines).
#
# Usage:  RIPWIRE_BIN=build/ripwire bash test/vendoredbundlecheck.sh   |   RIPWIRE_BIN=asan/ripwire bash …
# Exits non-zero on any failure. Does NOT edit regression.sh (this file's own registration does that).

set -u
ROOT="$( cd "$( dirname "$0" )/.." && pwd )"
BIN="${1:-${RIPWIRE_BIN:-$ROOT/build/ripwire}}"
[ "${BIN#/}" = "$BIN" ] && BIN="$ROOT/$BIN"
fail=0
ok(){ printf '  PASS  %s\n' "$*"; }
no(){ printf '  FAIL  %s\n' "$*"; fail=1; }

[ -x "$BIN" ] || { echo "no ripwire binary at $BIN — build first"; exit 2; }
echo "vendoredbundlecheck: BIN=$BIN"

TMP="$( mktemp -d )"; trap 'rm -rf "$TMP"' EXIT
R="$TMP/repo"
mkdir -p "$R/src" "$R/.yarn/releases" "$R/pkg/generated" "$R/lib"

QUERY='throttle queue drain bucket token refill'

# a long, repeated-token filler so the synthetic bundle's single line is unambiguously past the
# kVendoredBundleLineBytes floor (2000 bytes/line) while still tokenizing as valid, query-matching JS.
filler=""
i=0; while [ $i -lt 40 ]; do
  filler="${filler}throttleQueueDrainBucketTokenRefillScheduleWorkerPendingJobsReleaseAllowed"
  i=$(( i + 1 ))
done
BUNDLE_LINE="function throttleQueueDrainBundled(a,b){var ${filler}=1;return a+b;}"

# 1) the real implementation — a normal multi-line function using the same vocabulary.
{
  echo '/**'
  echo ' * Throttle outbound requests: a token-bucket rate limiter guarding the queue drain worker.'
  echo ' */'
  echo 'function throttleQueueDrain(queue, now) {'
  echo '  const bucket = queue.bucket;'
  echo '  if (bucket.tokens > 0 && queue.pending.length > 0) {'
  echo '    bucket.tokens -= 1;'
  echo '    return queue.pending.shift();'
  echo '  }'
  echo '  return null;'
  echo '}'
} >"$R/src/rateLimiter.js"

# 2) PATH + EVIDENCE both trigger: the committed yarn release bundle, byte-identical filler to (3).
echo "$BUNDLE_LINE" >"$R/.yarn/releases/yarn-3.1.0.cjs"

# 3) EVIDENCE ONLY: the identical bundle bytes, moved to a path no tier rule names at all — proves the
#    demotion is content-derived, not a second path rule in disguise.
echo "$BUNDLE_LINE" >"$R/pkg/generated/vendorbundle.cjs"

# 4) PATH ONLY: a .pnp.cjs at a workspace root, and a byte-identical CONTROL twin elsewhere (src/), so the
#    two differ ONLY in path — proves the basename rule fires on its own, independent of the evidence
#    signal (this content is ordinary, short, multi-line — nowhere near the bytes-per-line floor).
PNP_BODY=$'// Yarn PnP resolution manifest (synthetic stand-in for this gate)\nfunction throttleQueueDrainPnpStub(a, b) {\n  // throttle the queue drain worker token bucket refill schedule\n  return a + b;\n}\n'
printf '%s' "$PNP_BODY" >"$R/.pnp.cjs"
printf '%s' "$PNP_BODY" | sed 's/PnpStub/PnpControl/' >"$R/src/pnpControl.js"

# 5) NEAR MISS: the SAME filler bytes as (2)/(3) — so term density is a controlled match, not a confound —
#    split across ~5 lines instead of packed onto one, dropping bytes/line well under the 2000 floor. Must
#    NOT be demoted, or the floor is hair-triggered on ordinary multi-line files with one long token run.
{
  echo 'function throttleQueueDrainWideSignature(a,b){'
  echo '  var x ='
  fifth=$(( ${#filler} / 5 + 1 ))
  off=0
  while [ $off -lt ${#filler} ]; do
    printf '    "%s" +\n' "${filler:$off:$fifth}"
    off=$(( off + fifth ))
  done
  echo '    "";'
  echo '  return a+b;'
  echo '}'
} >"$R/lib/wideSignature.js"

# ── the probe: one ranked candidate list, parsed into "name rank score" rows ──────────────────────────
CAND="$TMP/cand.xml"
"$BIN" "$R" --for="$QUERY" --format=candidates >"$CAND" 2>"$TMP/err" || { echo "binary failed"; cat "$TMP/err"; exit 2; }
tr '>' '\n' <"$CAND" | grep -o 'r="[0-9]*" s="[0-9.]*" n="[^"]*"' \
  | sed -E 's/r="([0-9]*)" s="([0-9.]*)" n="([^"]*)"/\3 \1 \2/' >"$TMP/ranks"

rankOf(){ awk -v n="$1" '$1==n {print $2; found=1; exit} END{ if(!found) print "" }' "$TMP/ranks"; }
scoreOf(){ awk -v n="$1" '$1==n {print $3; found=1; exit} END{ if(!found) print "" }' "$TMP/ranks"; }

missing=''
for s in throttleQueueDrain throttleQueueDrainBundled; do
  [ -n "$( rankOf "$s" )" ] || missing="$missing $s"
done
if [ -n "$missing" ]; then
  no "presence guard — these symbols never reached the ranked list, so nothing below could be tested:$missing"
  printf '        ranked rows were:\n'; sed 's/^/          /' "$TMP/ranks"
  exit 1
fi
ok "presence guard — the real impl and the bundle symbol are both indexed and ranked"

real="$( rankOf throttleQueueDrain )"
bundleYarn="$( rankOf throttleQueueDrainBundled )"
if [ "$real" -lt "$bundleYarn" ]; then
  ok "the real implementation (rank $real) outranks the .yarn/releases/ bundle (rank $bundleYarn)"
else
  no "the .yarn/releases/ bundle (rank $bundleYarn) still outranks the real implementation (rank $real)"
fi

# arms 2/3 share a symbol NAME (both files define throttleQueueDrainBundled), so the evidence-only copy is
# distinguished by asking whether IT ALONE (bundle demoted by path, evidence-only copy absent) still beats
# the real impl — instead re-run the probe over evidence-only-file-alone to isolate it.
R2="$TMP/repo-evidence-only"
mkdir -p "$R2/src" "$R2/pkg/generated"
cp "$R/src/rateLimiter.js" "$R2/src/rateLimiter.js"
cp "$R/pkg/generated/vendorbundle.cjs" "$R2/pkg/generated/vendorbundle.cjs"
CAND2="$TMP/cand2.xml"
"$BIN" "$R2" --for="$QUERY" --format=candidates >"$CAND2" 2>"$TMP/err2" || { echo "binary failed (evidence-only repo)"; cat "$TMP/err2"; exit 2; }
tr '>' '\n' <"$CAND2" | grep -o 'r="[0-9]*" s="[0-9.]*" n="[^"]*"' \
  | sed -E 's/r="([0-9]*)" s="([0-9.]*)" n="([^"]*)"/\3 \1 \2/' >"$TMP/ranks2"
rankOf2(){ awk -v n="$1" '$1==n {print $2; found=1; exit} END{ if(!found) print "" }' "$TMP/ranks2"; }
real2="$( rankOf2 throttleQueueDrain )"; bundleEv="$( rankOf2 throttleQueueDrainBundled )"
if [ -n "$real2" ] && [ -n "$bundleEv" ] && [ "$real2" -lt "$bundleEv" ]; then
  ok "EVIDENCE ALONE (pkg/generated/, no path rule matches) demotes the bundle — real (rank $real2) beats it (rank $bundleEv)"
else
  no "evidence-only bundle was not demoted by content alone: real=$real2 bundle=$bundleEv"
fi

# de-prioritization, NOT exclusion: the .yarn/-tagged bundle symbol is still reachable by its own name,
# and --expand on it (an EXPLICIT request) still returns its body.
if "$BIN" "$R" --for="throttleQueueDrainBundled" --format=candidates 2>/dev/null | grep -q 'n="throttleQueueDrainBundled"'; then
  ok "the demoted bundle symbol is still findable by exact name"
else
  no "throttleQueueDrainBundled vanished from a name query — the tier is a filter, not a down-weight"
fi
if "$BIN" "$R" --expand=throttleQueueDrainBundled 2>/dev/null | grep -q 'throttleQueueDrainBundled'; then
  ok "--expand on the demoted bundle symbol, named explicitly, still returns its body"
else
  no "--expand=throttleQueueDrainBundled returned nothing — the tier is hiding content a user named explicitly"
fi

# PATH ONLY: .pnp.cjs vs its byte-identical src/ control twin — same content, so a plain rank/score
# comparison against the real impl would just measure content strength. The ratio between the twins is the
# direct read on whether the BASENAME rule fired on its own: ~1.0 if not, ~1/0.35≈2.86 if it did.
pnpScore="$( scoreOf throttleQueueDrainPnpStub )"
pnpCtrlScore="$( scoreOf throttleQueueDrainPnpControl )"
pnpRatioOk="$( awk -v a="$pnpCtrlScore" -v b="$pnpScore" 'BEGIN{ if (b+0==0){print "no"; exit} r=a/b; print (r>=2.0)?"yes":"no" }' )"
if [ -n "$pnpScore" ] && [ -n "$pnpCtrlScore" ] && [ "$pnpRatioOk" = "yes" ]; then
  ok "the src/ control twin (score $pnpCtrlScore) outscores its byte-identical .pnp.cjs copy (score $pnpScore) by >=2.0x — basename rule alone"
else
  no ".pnp.cjs (score ${pnpScore:-<absent>}) was not demoted vs its control twin (score ${pnpCtrlScore:-<absent>}) — the basename rule did not fire"
fi

# NEAR MISS: the SAME filler bytes as the two demoted bundles, merely spread over ~5 lines instead of one,
# must score close to what an UNDEMOTED file with that term density gets — not ~0.35x it. The demoted
# .yarn/ bundle (arm 2) is the SAME content on one line, so score(wide)/score(bundleYarn) is a direct read
# on whether the multiplier fired: ~1.0 if wide was (wrongly) demoted too, ~1/0.35≈2.86 if it was not.
wideScore="$( scoreOf throttleQueueDrainWideSignature )"
bundleScore="$( scoreOf throttleQueueDrainBundled )"
ratioOk="$( awk -v a="$wideScore" -v b="$bundleScore" 'BEGIN{ if (b+0==0){print "no"; exit} r=a/b; print (r>=2.0)?"yes":"no" }' )"
if [ -n "$wideScore" ] && [ "$ratioOk" = "yes" ]; then
  ok "same filler split over 5 lines (score $wideScore) is NOT demoted — ratio vs the demoted 1-line twin (score $bundleScore) is >=2.0, near the 1/0.35 factor"
else
  no "same filler split over 5 lines (score ${wideScore:-<absent>}) scores too close to its demoted 1-line twin (score ${bundleScore:-<absent>}) — floor too aggressive on ordinary multi-line files"
fi

[ "$fail" -eq 0 ] && echo "vendoredbundlecheck: ALL PASS" || echo "vendoredbundlecheck: FAILURES"
exit "$fail"
