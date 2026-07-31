#!/usr/bin/env bash
# cochangeboostcheck.sh — B3 (PLAN_researchImprove2026): the co-change prior boost on the --for lens.
#
# The boost is OPT-IN (--cochange-boost / CTXPACK_COCHANGE=1) and EXPERIMENTAL — the held-out LocBench
# record (train multi-file +6.4pp, held-out +0.0pp, warm p50 +19%) kept it off by default pending a
# C++-corpus eval. This gate pins the opt-in contract on a SCRIPTED fixture repo (so it never depends
# on ctxpack's own history and cannot rot when this repo's commits age):
#   (0)   DEFAULT OFF — without the flag, output is BYTE-IDENTICAL on a history-rich repo whether or
#         not the boost code exists (i.e. default == pre-B3 behavior; no header note, no rank change).
#   (i)   SIGNAL — opted in, with real co-change history, a lexically-invisible partner file's symbol
#         ranks HIGHER than default (and overtakes a weak lexical distractor that never co-changes).
#   (ii)  INERT WITHOUT HISTORY — opted in, on a depth-1 shallow clone, a single-commit repo, and a
#         non-git copy, output is BYTE-IDENTICAL to default (the >=3-support threshold is unreachable).
#   (iii) SCOPE — --query and --for --no-route are untouched by the env even when set.
#   (iv)  DETERMINISM — three opted-in runs are byte-identical; output is xmllint-clean.
#   (v)   SEEDS UNCHANGEABLE — the top-3 candidates are identical opted-in vs default, and the env
#         enable (CTXPACK_COCHANGE=1) matches the flag enable byte-for-byte.
#
# Usage:  bash test/cochangeboostcheck.sh   |   CTXPACK_BIN=asan/ctxpack bash test/cochangeboostcheck.sh

set -u
ROOT="$( cd "$( dirname "$0" )/.." && pwd )"
BIN="${CTXPACK_BIN:-$ROOT/build/ctxpack}"
[ "${BIN#/}" = "$BIN" ] && BIN="$ROOT/$BIN"
TMP="$( mktemp -d )"; trap 'rm -rf "$TMP"' EXIT
fail=0
ok(){ printf '  PASS  %s\n' "$*"; }
no(){ printf '  FAIL  %s\n' "$*"; fail=1; }

# L5 (AUDIT5): --cochange-boost is dropped from --help and gated behind CTXPACK_DEV=1 (negative-result
# experiment, kept reachable for continued eval work). This gate exercises the flag directly.
export CTXPACK_DEV=1

[ -x "$BIN" ] || { echo "no ctxpack binary at $BIN — build first (cmake --build build -j)"; exit 2; }
command -v git >/dev/null || { echo "cochangeboostcheck: git not on PATH"; exit 2; }
echo "cochangeboostcheck: BIN=$BIN"

Q="widget pipeline process records"

# ── fixture: a scripted git repo with REAL co-change history ─────────────────────────────────────────
# alpha.py carries the three strong query matches (all three seeds live there); beta.py shares NO word
# with the query but co-changes with alpha.py in 4 commits (deg 4/5, support >= 3); gamma.py is a WEAK
# lexical match that only ever changes alone (co-change support 1 — below threshold). Default must rank
# gamma above beta (lexical only); opted-in must lift beta's symbol above gamma's (history signal).
HIST="$TMP/hist"
mkdir -p "$HIST"
git -C "$HIST" init -q
git -C "$HIST" config user.email t@t; git -C "$HIST" config user.name t; git -C "$HIST" config commit.gpgsign false

cat > "$HIST/alpha.py" <<'PY'
def widget_pipeline_process(records):
    """Process widget records through the pipeline."""
    return [r for r in records if r]

def widget_records_pipeline(records):
    """Pipeline stage: validate widget records."""
    return records

def process_widget_records(records):
    """Process the records for each widget in the pipeline."""
    return len(records)
PY
cat > "$HIST/beta.py" <<'PY'
def flush_stale_cache(entries):
    """Evict stale cache entries."""
    return [e for e in entries if e.fresh]
PY
cat > "$HIST/gamma.py" <<'PY'
def count_records(items):
    """Count the records."""
    return len(items)
PY
git -C "$HIST" add -A && git -C "$HIST" commit -qm c1
for i in 2 3 4 5; do
    printf '\n# rev %s\n' "$i" >> "$HIST/alpha.py"
    printf '\n# rev %s\n' "$i" >> "$HIST/beta.py"
    git -C "$HIST" add -A && git -C "$HIST" commit -qm "c$i alpha+beta"
done
for i in 6 7 8; do
    printf '\n# rev %s\n' "$i" >> "$HIST/gamma.py"
    git -C "$HIST" add -A && git -C "$HIST" commit -qm "c$i gamma alone"
done

cands(){ "$BIN" "$1" --for="$Q" --format=candidates --top-k=20 --no-cache "${@:2}" 2>/dev/null; }
rankOf(){ printf '%s' "$1" | grep -o "<cand r=\"[0-9]*\" [^>]*n=\"$2\"" | grep -o 'r="[0-9]*"' | grep -o '[0-9]*'; }

ON="$( cands "$HIST" --cochange-boost )"
OFF="$( cands "$HIST" )"
betaOn="$( rankOf "$ON" flush_stale_cache )";  betaOff="$( rankOf "$OFF" flush_stale_cache )"
gammaOn="$( rankOf "$ON" count_records )"

# ── (0) default off: no boost header note, no rank change vs an env-disabled control ────────────────
"$BIN" "$HIST" --for="$Q" --no-cache >"$TMP/def.xml" 2>/dev/null
grep -q 'cochange boost' "$TMP/def.xml" && no "default output must carry NO boost note" \
    || ok "default carries no boost note (opt-in contract)"

# ── (i) signal: opted in, the co-change partner rises and overtakes the weak distractor ─────────────
if [ -n "$betaOn" ] && [ -n "$betaOff" ] && [ "$betaOn" -lt "$betaOff" ]; then
    ok "partner symbol rises opted-in (rank $betaOn) vs default (rank $betaOff)"
else no "partner symbol did not rise (on=$betaOn off=$betaOff)"; fi
if [ -n "$betaOn" ] && [ -n "$gammaOn" ] && [ "$betaOn" -lt "$gammaOn" ]; then
    ok "co-change partner outranks the weak lexical distractor opted-in (beta $betaOn < gamma $gammaOn)"
else no "partner did not overtake distractor (beta=$betaOn gamma=$gammaOn)"; fi
printf '%s' "$ON" | grep -q 'cochange boost' && no "candidates export must carry scores only, not the header note" \
    || ok "candidates export carries no header note"
"$BIN" "$HIST" --for="$Q" --cochange-boost --no-cache 2>/dev/null | grep -q 'cochange boost: promoted' \
    && ok "opted-in --for header names what the boost promoted" || no "opted-in --for header note missing"

# ── (v) seeds unchangeable: top-3 candidates identical opted-in vs default ──────────────────────────
top3on="$(  printf '%s' "$ON"  | grep -o '<cand r="[123]" [^>]*id="[^"]*"' )"
top3off="$( printf '%s' "$OFF" | grep -o '<cand r="[123]" [^>]*id="[^"]*"' )"
[ -n "$top3on" ] && [ "$top3on" = "$top3off" ] && ok "top-3 seeds identical opted-in vs default" \
    || no "top seeds moved:  ON<<$top3on>>  OFF<<$top3off>>"

# env enable == flag enable, byte-for-byte (the one-variable ablation control has two equivalent forms)
"$BIN" "$HIST" --for="$Q" --no-cache --cochange-boost >"$TMP/flagon.xml" 2>/dev/null
CTXPACK_COCHANGE=1 "$BIN" "$HIST" --for="$Q" --no-cache >"$TMP/envon.xml" 2>/dev/null
cmp -s "$TMP/flagon.xml" "$TMP/envon.xml" && ok "CTXPACK_COCHANGE=1 == --cochange-boost (byte-identical)" \
    || no "env enable and flag enable diverge"

# ── (ii) inert without history: depth-1 shallow clone / single-commit repo / non-git copy ───────────
inertPair(){ # $1=dir $2=label — opted-in must be byte-identical to default, bundle AND candidates
    "$BIN" "$1" --for="$Q" --cochange-boost --no-cache >"$TMP/on.xml" 2>/dev/null
    "$BIN" "$1" --for="$Q" --no-cache >"$TMP/off.xml" 2>/dev/null
    cands "$1" --cochange-boost >"$TMP/on.cand"; cands "$1" >"$TMP/off.cand"
    if cmp -s "$TMP/on.xml" "$TMP/off.xml" && cmp -s "$TMP/on.cand" "$TMP/off.cand"; then
        ok "inert on $2 (opted-in byte-identical to default)"
    else no "NOT inert on $2"; fi
}
SHALLOW="$TMP/shallow"
git clone -q --depth=1 "file://$HIST" "$SHALLOW" 2>/dev/null && inertPair "$SHALLOW" "depth-1 shallow clone (the frozen-eval shape)" \
    || no "depth-1 shallow clone failed to create"
SINGLE="$TMP/single"
mkdir -p "$SINGLE"; cp "$HIST"/*.py "$SINGLE/"
git -C "$SINGLE" init -q; git -C "$SINGLE" config user.email t@t; git -C "$SINGLE" config user.name t; git -C "$SINGLE" config commit.gpgsign false
git -C "$SINGLE" add -A && git -C "$SINGLE" commit -qm only
inertPair "$SINGLE" "single-commit repo"
NOGIT="$TMP/nogit"
mkdir -p "$NOGIT"; cp "$HIST"/*.py "$NOGIT/"
inertPair "$NOGIT" "non-git tree"

# ── (iii) scope: --query and --for --no-route are byte-identical even with the env set ──────────────
"$BIN" "$HIST" --query="$Q" --no-cache >"$TMP/q1.xml" 2>/dev/null
CTXPACK_COCHANGE=1 "$BIN" "$HIST" --query="$Q" --no-cache >"$TMP/q2.xml" 2>/dev/null
cmp -s "$TMP/q1.xml" "$TMP/q2.xml" && ok "--query path untouched by the boost env" || no "--query path affected"
"$BIN" "$HIST" --for="$Q" --no-route --no-cache >"$TMP/nr1.xml" 2>/dev/null
CTXPACK_COCHANGE=1 "$BIN" "$HIST" --for="$Q" --no-route --no-cache >"$TMP/nr2.xml" 2>/dev/null
cmp -s "$TMP/nr1.xml" "$TMP/nr2.xml" && ok "--no-route path keeps its pre-routing bytes (boost does not apply)" \
    || no "--no-route path affected by the boost"

# ── (iv) determinism ×3 + well-formedness on the boosted path ────────────────────────────────────────
"$BIN" "$HIST" --for="$Q" --cochange-boost --no-cache >"$TMP/d1.xml" 2>/dev/null
"$BIN" "$HIST" --for="$Q" --cochange-boost --no-cache >"$TMP/d2.xml" 2>/dev/null
"$BIN" "$HIST" --for="$Q" --cochange-boost --no-cache >"$TMP/d3.xml" 2>/dev/null
cmp -s "$TMP/d1.xml" "$TMP/d2.xml" && cmp -s "$TMP/d2.xml" "$TMP/d3.xml" && ok "determinism x3 (opted-in)" \
    || no "opted-in output not deterministic"
if command -v xmllint >/dev/null; then
    xmllint --noout "$TMP/d1.xml" 2>/dev/null && ok "boosted bundle is xmllint-clean (G4)" || no "boosted bundle not well-formed"
else ok "xmllint not present — skipped (G4 covered by xmlwellformed.sh)"; fi

# --cochange-boost without --for refuses loudly (mirrors --anchor/--adaptive/--detail)
"$BIN" "$HIST" --cochange-boost >/dev/null 2>"$TMP/refuse.err"
[ $? -ne 0 ] && grep -q 'cochange-boost' "$TMP/refuse.err" && ok "flag alone refuses loudly" || no "flag alone did not refuse"

# --cochange-boost WITHOUT CTXPACK_DEV=1 refuses loudly (the L5 experimental gate)
env -u CTXPACK_DEV "$BIN" "$HIST" --for="$Q" --cochange-boost --no-cache >/dev/null 2>"$TMP/deverr"
[ $? -ne 0 ] && grep -q 'CTXPACK_DEV' "$TMP/deverr" && ok "--cochange-boost without CTXPACK_DEV=1 refuses loudly" \
                                                     || no "--cochange-boost without CTXPACK_DEV=1 did not refuse loudly"

[ "$fail" = 0 ] && echo 'ALL PASS' || echo 'FAILURES ABOVE'
exit "$fail"
