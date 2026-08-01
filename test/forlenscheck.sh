#!/usr/bin/env bash
# forlenscheck.sh — the Wave-Q Q3 "quality lens on --for" gate.
#
#   test/forlenscheck.sh                       # uses build/ripwire on test/fixture (+ a scratch git repo)
#   RIPWIRE_BIN=asan/ripwire test/forlenscheck.sh
#
# Q3 folds the quality FACTS (ccx + churn + clone-membership + tested= + change-amplification amp=) onto
# the --for bundle's ranked <d> signatures — steering at read time (facts fed at read time measurably
# change output). These are DESCRIPTIVE attributes, never gates. This gate asserts:
#   * the --for bundle carries the quality attrs (ccx/amp on the ranked <d> blocks).
#   * GOLDEN NEUTRALITY — the plain --pack-signatures output carries NONE of the new lens attrs (churn/
#     clone/amp/tested), and the DEFAULT map is unaffected (that's regression.sh's golden; re-checked here).
#   * churn= appears in a git repo and DEGRADES cleanly (omitted, no crash) with no git.
#   * tested= / clone= fire on a crafted scratch corpus where a symbol is test-referenced / duplicated.
#   * determinism (run twice → byte-identical) + well-formed XML.
# Mutation-tested: an attribute-presence assertion is checked to actually FAIL when it shouldn't hold.
# Exits non-zero on any failure.

set -u
ROOT="$( cd "$( dirname "$0" )/.." && pwd )"
BIN="${RIPWIRE_BIN:-$ROOT/build/ripwire}"
[ "${BIN#/}" = "$BIN" ] && BIN="$ROOT/$BIN"          # allow a repo-relative RIPWIRE_BIN
TMP="$( mktemp -d )"; trap 'rm -rf "$TMP"' EXIT
fail=0
ok(){ printf '  PASS  %s\n' "$*"; }
no(){ printf '  FAIL  %s\n' "$*"; fail=1; }

[ -x "$BIN" ] || { echo "no ripwire binary at $BIN — build first (cmake --build build -j)"; exit 2; }
cd "$ROOT"
echo "forlenscheck: BIN=$BIN"

# a helper to pull the <d …> line for a signature substring, one-attr-per-line.
dline(){ printf '%s' "$1" | sed 's/></>\n</g' | grep -E "<d [^>]*>$2" | head -1; }

# ── 1) the --for bundle carries the quality lens on its ranked <d> blocks (ccx + amp) ─────────────────
FOR1="$( "$BIN" test/fixture --no-cache --for="compute perimeter distance" 2>/dev/null )"
DL="$( dline "$FOR1" 'double distance' )"
printf '%s' "$DL" | grep -q ' ccx=' && ok "--for <d> carries ccx (cognitive complexity): $DL" || no "--for <d> missing ccx: $DL"
printf '%s' "$DL" | grep -q ' amp=' && ok "--for <d> carries amp (change-amplification)"          || no "--for <d> missing amp: $DL"

# ── 2) GOLDEN NEUTRALITY — plain --pack-signatures must NOT carry any lens attr; default map unchanged ─
PS="$( "$BIN" test/fixture --no-cache --pack-signatures 2>/dev/null )"
LEAK="$( printf '%s' "$PS" | grep -oE ' (churn|clone|amp|tested)="[^"]*"' | head -1 )"
[ -z "$LEAK" ] && ok "golden-neutral: --pack-signatures carries no lens attr (lens is --for-only)" || no "lens attr leaked into --pack-signatures: $LEAK"
# the default map must be byte-identical to the committed golden (the authoritative golden-neutral check).
if [ -f "$ROOT/test/golden.xml" ]; then
    "$BIN" test/fixture --no-cache 2>/dev/null | diff -q - "$ROOT/test/golden.xml" >/dev/null \
        && ok "golden-neutral: default map byte-identical to test/golden.xml" \
        || no "default map drifted from golden.xml (Q3 leaked into the default map)"
else
    ok "golden.xml absent — default-map neutral check skipped"
fi

# ── 3) determinism + well-formed XML on the --for bundle ──────────────────────────────────────────────
"$BIN" test/fixture --no-cache --for="compute perimeter distance" >"$TMP/f1" 2>/dev/null
"$BIN" test/fixture --no-cache --for="compute perimeter distance" >"$TMP/f2" 2>/dev/null
diff -q "$TMP/f1" "$TMP/f2" >/dev/null && ok "determinism (--for byte-identical run-to-run)" || no "non-deterministic --for output"
command -v xmllint >/dev/null 2>&1 && { printf '%s' "$FOR1" | xmllint --noout - 2>/dev/null && ok "xml well-formed (--for lens)" || no "xml malformed (--for lens)"; } || ok "xml well-formed (xmllint absent — skipped)"

# ── 4) tested= / clone= on a crafted scratch corpus (OUTSIDE test/, so tested= can fire) ──────────────
SC="$TMP/proj"; mkdir -p "$SC/tests"
cat >"$SC/lib.py" <<'PY'
def compute_area(w, h):
    return w * h
def compute_volume(w, h, d):
    return w * h
def clone_a(w, h):
    return w + h + 1 + 2 + 3 + 4 + 5 + 6 + 7 + 8 + 9 + 10 + 11 + 12 + 13 + 14 + 15 + 16 + 17 + 18 + 19 + 20
def clone_b(w, h):
    return w + h + 1 + 2 + 3 + 4 + 5 + 6 + 7 + 8 + 9 + 10 + 11 + 12 + 13 + 14 + 15 + 16 + 17 + 18 + 19 + 20
PY
cat >"$SC/tests/test_lib.py" <<'PY'
from lib import compute_area
def test_it():
    assert compute_area(2, 3) == 6
PY
SCFOR="$( "$BIN" "$SC" --no-cache --for="compute area volume" 2>/dev/null )"
printf '%s' "$( dline "$SCFOR" 'def compute_area' )" | grep -q ' tested="1"' \
    && ok "tested=1 folded onto --for for a test-referenced symbol (compute_area)" \
    || no "tested= missing on compute_area in --for: $( dline "$SCFOR" 'def compute_area' )"
# clone_a / clone_b are token-identical bodies (>=40 tokens matched by --clones default) → clone="1".
printf '%s' "$( dline "$SCFOR" 'def clone_a' )" | grep -q ' clone="1"' \
    && ok "clone=1 folded onto --for for a duplicated body (clone_a)" \
    || no "clone= missing on a duplicated body in --for: $( dline "$SCFOR" 'def clone_a' )"
# tested= must NEVER leak into the scratch project's DEFAULT map either.
"$BIN" "$SC" --no-cache 2>/dev/null | grep -q 'tested=' && no "tested= leaked into scratch default map" || ok "tested= stays --for/--metrics-only (scratch default map clean)"

# ── 5) churn= present in a git repo + clean git-less degrade ──────────────────────────────────────────
# The scratch dir above has no git → churn= must be ABSENT (clean degrade, no crash).
printf '%s' "$( dline "$SCFOR" 'def compute_area' )" | grep -q ' churn=' \
    && no "churn= wrongly present without git: $( dline "$SCFOR" 'def compute_area' )" \
    || ok "churn= omitted cleanly with no git (degrade)"
# now make it a git repo with one commit → churn= must appear.
if command -v git >/dev/null 2>&1; then
    ( cd "$SC" && git init -q && git config user.email t@t && git config user.name t && git add -A && git commit -qm init ) 2>/dev/null
    SCFORG="$( "$BIN" "$SC" --no-cache --for="compute area volume" 2>/dev/null )"
    printf '%s' "$( dline "$SCFORG" 'def compute_area' )" | grep -q ' churn=' \
        && ok "churn= appears once the corpus is a git repo (compute_area)" \
        || no "churn= missing in a git repo: $( dline "$SCFORG" 'def compute_area' )"
else
    ok "git absent — churn-present check skipped (degrade path already covered above)"
fi

# ── 6) MUTATION self-test — asserting a lens attr on a symbol that lacks it MUST fail (assertion live) ─
# compute_volume has NO caller and is untested → it must NOT carry tested=; asserting it does must trip.
MUT="$( ok(){ :; }; no(){ echo TRIPPED; }
        l="$( dline "$SCFOR" 'def compute_volume' )"
        if printf '%s' "$l" | grep -q ' tested="1"'; then ok; else no; fi )"
[ "$MUT" = "TRIPPED" ] && ok "mutation self-test (a false tested= assertion is correctly detected)" \
                       || no "mutation self-test broke — a false attr assertion did NOT fail"

[ "$fail" -eq 0 ] && echo "ALL PASS" || echo "SOME FAILED"
exit "$fail"
