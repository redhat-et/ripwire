#!/usr/bin/env bash
# lintbudgetcheck.sh — §P0.2 gate: --lint must report TRUE per-rule totals, not a starved floor.
#
# Before the fix all 11 built-in AST rules shared ONE pooled astQuery budget (maxMatches=5000).
# `(number_literal)` saturated it alone, the pool was path-sorted then cut, so the scan stopped at
# ./src/ingest.cpp and never reached main.cpp / quality.h / test/ / third_party/ — ~14% of the tree.
# `--lint` then printed goto=1 (truth 2), do-while=0 (truth 1), c-style-cast=100 (truth 215), and
# false zeros for unsafe-c-fn / weak-crypto / empty-catch over ~86% of the tree.
#
# The invariant this gate freezes: a rule's count must equal what the SAME engine reports for the same
# query under --match (ground truth), and must NOT change when another rule's matches explode.
#
#   CTXPACK_BIN=build/ctxpack      bash test/lintbudgetcheck.sh
#   CTXPACK_BIN=build_base/ctxpack bash test/lintbudgetcheck.sh   # must FAIL (pre-fix binary)

set -u
ROOT="$( cd "$( dirname "$0" )/.." && pwd )"
BIN="${CTXPACK_BIN:-$ROOT/build/ctxpack}"
[ "${BIN#/}" = "$BIN" ] && BIN="$ROOT/$BIN"
TMP="$( mktemp -d )"; trap 'rm -rf "$TMP"' EXIT
fail=0
ok(){ printf '  PASS  %s\n' "$*"; }
no(){ printf '  FAIL  %s\n' "$*"; fail=1; }

[ -x "$BIN" ] || { echo "no ctxpack binary at $BIN — build first"; exit 2; }
echo "lintbudgetcheck: BIN=$BIN  ROOT=$ROOT"

# ── ground truth: the same engine, one query at a time (--match has always had its own full budget)
truth(){ "$BIN" "$ROOT" --match="$1" 2>/dev/null | grep -oE 'hits="[0-9]+"' | head -1 | grep -oE '[0-9]+'; }
GOTO_TRUTH="$( truth '(goto_statement) @c' )"
DOWH_TRUTH="$( truth '(do_statement) @c' )"
CAST_TRUTH="$( truth '(cast_expression) @c' )"

"$BIN" "$ROOT" --lint >"$TMP/lint.xml" 2>/dev/null
ruleCount(){ grep -oE "<rule name=\"$1\" count=\"[0-9]+\"" "$TMP/lint.xml" | grep -oE 'count="[0-9]+"' | grep -oE '[0-9]+'; }

# ── 1. per-rule counts are TRUE totals, agreeing with the single-query ground truth
GOTO_LINT="$( ruleCount goto )"
[ "${GOTO_LINT:-x}" = "${GOTO_TRUTH:-y}" ] && [ "${GOTO_LINT:-0}" -ge 2 ] \
    && ok "goto count=$GOTO_LINT == --match ground truth ($GOTO_TRUTH)" \
    || no "goto count=${GOTO_LINT:-<none>} != --match ground truth ${GOTO_TRUTH:-<none>} (expected >= 2)"

DOWH_LINT="$( ruleCount do-while )"
[ "${DOWH_LINT:-x}" = "${DOWH_TRUTH:-y}" ] && [ "${DOWH_LINT:-0}" -ge 1 ] \
    && ok "do-while count=$DOWH_LINT == --match ground truth ($DOWH_TRUTH)" \
    || no "do-while count=${DOWH_LINT:-<none>} != --match ground truth ${DOWH_TRUTH:-<none>} (expected >= 1)"

CAST_LINT="$( ruleCount c-style-cast )"
[ "${CAST_LINT:-x}" = "${CAST_TRUTH:-y}" ] && [ "${CAST_LINT:-0}" -ge 200 ] \
    && ok "c-style-cast count=$CAST_LINT == --match ground truth ($CAST_TRUTH), >= 200" \
    || no "c-style-cast count=${CAST_LINT:-<none>} != --match ground truth ${CAST_TRUTH:-<none>} (expected >= 200)"

# ── 2. saturation is DISCLOSED, never silent: (number_literal) alone exceeds any single-rule budget on
#      this repo, so magic-number must declare its count a floor and the root must say findings_capped.
grep -q '<lint[^>]* findings_capped="1"' "$TMP/lint.xml" \
    && ok 'root declares findings_capped="1" (a rule saturated its own budget)' \
    || no 'root does NOT declare findings_capped="1" while a rule saturates its budget'
grep -qE '<rule name="magic-number"[^/]*capped="1"' "$TMP/lint.xml" \
    && ok 'magic-number row declares capped="1" (count= is a floor)' \
    || no 'magic-number row does not declare capped="1"'

# ── 3. NO-STARVATION, the core invariant: a quiet rule's count must not change when a noisy rule is
#      added beside it. Exercised through the --lint-rules= path, which shares the same engine/pool.
mkdir -p "$TMP/quiet" "$TMP/both"
cat >"$TMP/quiet/q.yml" <<'YML'
- id: quiet-goto
  language: cpp
  severity: warn
  message: goto found
  query: |
    (goto_statement) @hit
YML
cp "$TMP/quiet/q.yml" "$TMP/both/q.yml"
cat >"$TMP/both/noisy.yml" <<'YML'
- id: noisy-number
  language: cpp
  severity: warn
  message: number literal
  query: |
    (number_literal) @hit
YML

userCount(){ "$BIN" "$ROOT" --lint-rules="$1" 2>/dev/null \
    | grep -oE "<rule name=\"quiet-goto\" sev=\"[a-z]+\" count=\"[0-9]+\"" | grep -oE 'count="[0-9]+"' | grep -oE '[0-9]+'; }
Q_ALONE="$( userCount "$TMP/quiet" )"
Q_BESIDE="$( userCount "$TMP/both" )"
[ -n "${Q_ALONE:-}" ] && [ "${Q_ALONE:-0}" -ge 2 ] \
    && ok "custom quiet rule alone: count=$Q_ALONE" \
    || no "custom quiet rule alone: count=${Q_ALONE:-<none>} (expected >= 2)"
[ "${Q_ALONE:-x}" = "${Q_BESIDE:-y}" ] \
    && ok "no starvation: quiet rule count unchanged beside a saturating rule ($Q_BESIDE)" \
    || no "STARVED: quiet rule count ${Q_ALONE:-<none>} alone vs ${Q_BESIDE:-<none>} beside a noisy rule"

# ── 4. determinism (two runs, byte-identical) — the cap must stay a pure function of the input
"$BIN" "$ROOT" --lint >"$TMP/d1" 2>/dev/null
"$BIN" "$ROOT" --lint >"$TMP/d2" 2>/dev/null
diff -q "$TMP/d1" "$TMP/d2" >/dev/null && ok "deterministic (byte-identical run-to-run)" \
    || no "non-deterministic --lint output"

# ── adversarial-round extension: cap disclosure must not leak across the built-in/user namespaces ────
# A user rule may share a built-in rule's NAME. Its saturation must never paint capped="1" onto the
# built-in row (which fabricates "my truthful count is a floor of 5000 raw captures"), nor vice versa.
COLLIDE="$( mktemp -d )"; trap 'rm -rf "$COLLIDE"' RETURN 2>/dev/null || true
printf -- '- id: goto\n  severity: warn\n  message: noisy collider\n  query: (number_literal) @hit\n' > "$COLLIDE/goto.yml"
crow_builtin="$( "$BIN" "$ROOT" --lint --lint-rules="$COLLIDE" 2>/dev/null | grep -oE '<rule name="goto"[^/]*/>' | grep -v 'sev=' )"
crow_user="$(    "$BIN" "$ROOT" --lint --lint-rules="$COLLIDE" 2>/dev/null | grep -oE '<rule name="goto"[^/]*/>' | grep    'sev=' )"
case "$crow_builtin" in
    *capped* ) no "built-in goto row inherited the colliding USER rule's cap: $crow_builtin" ;;
    *count=\"2\"* ) ok "built-in goto row stays a clean total beside a saturating same-named user rule" ;;
    * ) no "built-in goto row unexpected shape: $crow_builtin" ;;
esac
case "$crow_user" in
    *capped=\"1\"* ) ok "colliding user rule's own saturation still disclosed: capped=\"1\"" ;;
    * ) no "user goto rule saturated its budget but carries no capped=: $crow_user" ;;
esac
rm -rf "$COLLIDE"

[ "$fail" = 0 ] && echo "ALL PASS" || echo "FAILURES ABOVE"
exit $fail
