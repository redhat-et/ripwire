#!/usr/bin/env bash
# testgaterefusecheck.sh — the --test-gate=FILES refusal surface (def-over-decl lane finding, 2026-08-24).
#
# THE DEFECT THIS GATE EXISTS FOR: `--test-gate=da61bac..HEAD` — an argument form the verb cannot parse
# (it takes FILES, never a git ref range) — reported `changed="0"` and exited 0. A silent zero on an
# unparseable input is a breach of non-negotiable #3 ("a zero means none found, never none exists"): a
# caller reads exit 0 + changed="0" as "your change touches nothing" and skips every test. The house
# refusal standard is --quality-delta's (qdrefpaircheck arms (C)): refuse at exit 1, NAME the offending
# token verbatim, and offer an ADJACENT PROBE the caller can run. This gate holds --test-gate to that
# standard for every unparseable form:
#
#   (a) the found case, A..B      → refused; token named; the probe expands the range into its files
#   (b) the three-dot form A...B  → refused the same way, never silently read as A..B
#   (c) the half-typed --test-gate= (EmptyValue::Refuse, same ruling as --dmm=/--quality-delta=: a
#       half-typed value — usually an unset shell variable — must not silently run the bare git-diff form)
#   (d) a token matching no indexed file → refused; token named; probe points at --skipped
#   (e) a MIXED list: one good file must not mask a bad token (the silent-drop variant of the same zero)
#   (f) a comma-only list (names no files) → refused, not run as an all-zero mask
#   (g) control: a valid FILES list is untouched — the report and its exit-4 obligation contract hold
#   (h) the refusal is identical under --json, and never emits a report body to stdout
#
# RED BEFORE GREEN: against the pre-fix binary (da61bac, sha256 275ecfbb6c6cdeff…) arms (a)/(b)/(d)/(f)/(h)
# emitted the silent-zero report at exit 0, (e) exited 4 having silently dropped the bad token, and (c) ran
# as the bare form (exit 1 only because the corpus has no git; its wording sub-arm red) — 7 of 8 arms red,
# verified before the code. Only the control arm (g) was green.
#
# Usage:  RIPWIRE_BIN=build/ripwire bash test/testgaterefusecheck.sh   |   bash test/testgaterefusecheck.sh asan/ripwire
# Exits non-zero on any failure. Does NOT edit regression.sh.

set -u
ROOT="$( cd "$( dirname "$0" )/.." && pwd )"
BIN="${1:-${RIPWIRE_BIN:-$ROOT/build/ripwire}}"   # BOTH seams: positional and RIPWIRE_BIN
[ "${BIN#/}" = "$BIN" ] && BIN="$ROOT/$BIN"
fail=0
ok(){ printf '  PASS  %s\n' "$*"; }
no(){ printf '  FAIL  %s\n' "$*"; fail=1; }

[ -x "$BIN" ] || { echo "no ripwire binary at $BIN — build first"; exit 2; }
echo "testgaterefusecheck: BIN=$BIN"

# Synthetic corpus, no git needed: the refusal is lexical + index-based, exactly like the mask it guards.
TMP="$( mktemp -d )"; trap 'rm -rf "$TMP"' EXIT
R="$TMP/repo"; mkdir -p "$R/src" "$R/test"
printf 'int covered() { return 1; }\n'        > "$R/src/covered.cpp"
printf 'void test_covered() { covered(); }\n' > "$R/test/test_covered.cpp"

run(){ perl -e 'alarm 15; exec @ARGV' "$BIN" "$R" "$@" --no-cache >"$TMP/out" 2>"$TMP/err"; echo $?; }

# ── (a) the found case: a two-dot ref range is refused, named, and given the expansion probe ──────────
RC="$( run --test-gate=deadbeef..HEAD )"
[ "$RC" = 1 ] && ok "(a) A..B exits 1" || no "(a) A..B exit was $RC, expected 1 (the found defect: silent changed=0 at exit 0)"
[ -s "$TMP/out" ] && no "(a) A..B still wrote a report body to stdout ($( head -c 120 "$TMP/out" ))" \
                  || ok "(a) A..B emits NO report — a refusal never carries a changed=\"0\" answer"
grep -qF 'deadbeef..HEAD' "$TMP/err" && ok "(a) the refusal NAMES the offending token verbatim" \
                                     || { no "(a) refusal does not name the token"; head -2 "$TMP/err"; }
grep -qF 'diff --name-only' "$TMP/err" && ok "(a) the refusal offers the adjacent probe (expand the range into FILES)" \
                                        || no "(a) refusal gives no runnable range-to-files probe"

# ── (b) the three-dot form: refused the same way, never silently read as A..B ─────────────────────────
RC="$( run --test-gate=deadbeef...HEAD )"
[ "$RC" = 1 ] && ok "(b) A...B exits 1" || no "(b) A...B exit was $RC, expected 1"
grep -qF 'deadbeef...HEAD' "$TMP/err" && ok "(b) the three-dot token is named verbatim (not silently rewritten)" \
                                       || { no "(b) three-dot token not named"; head -2 "$TMP/err"; }

# ── (c) the half-typed --test-gate= is refused, not run as the bare git-diff form ─────────────────────
RC="$( run --test-gate= )"
[ "$RC" = 1 ] && ok "(c) --test-gate= exits 1" || no "(c) --test-gate= exit was $RC, expected 1"
[ -s "$TMP/out" ] && no "(c) --test-gate= still wrote to stdout" || ok "(c) --test-gate= wrote nothing to stdout"
grep -qF -- '--test-gate' "$TMP/err" && grep -q 'is empty' "$TMP/err" \
    && ok "(c) the refusal names the flag and states the real problem (empty value)" \
    || { no "(c) refusal wrong (must be the table's empty-value sentence, not the bare form's git error)"; head -2 "$TMP/err"; }

# ── (d) a token matching no indexed file: named, with the --skipped adjacent probe ────────────────────
RC="$( run --test-gate=zz_no_such_file_xyz.zzz )"
[ "$RC" = 1 ] && ok "(d) a no-such-file token exits 1" || no "(d) no-such-file exit was $RC, expected 1"
[ -s "$TMP/out" ] && no "(d) no-such-file still wrote a report body" || ok "(d) no-such-file emits NO report"
grep -qF 'zz_no_such_file_xyz.zzz' "$TMP/err" && ok "(d) the refusal names the token" \
                                               || { no "(d) refusal does not name the token"; head -2 "$TMP/err"; }
grep -qF -- '--skipped' "$TMP/err" && ok "(d) the refusal offers the adjacent probe (--skipped)" \
                                   || no "(d) refusal gives no adjacent probe"

# ── (e) a MIXED list: the good file must not mask the bad token ───────────────────────────────────────
RC="$( run --test-gate=src/covered.cpp,zz_no_such_file_xyz.zzz )"
[ "$RC" = 1 ] && grep -qF 'zz_no_such_file_xyz.zzz' "$TMP/err" \
    && ok "(e) a mixed list refuses and names the BAD token (good files cannot mask it)" \
    || { no "(e) mixed list not refused (rc=$RC) — a silently dropped token is the same silent zero"; head -2 "$TMP/err"; }

# ── (f) a comma-only list names no files: refused, never an all-zero mask ─────────────────────────────
RC="$( run --test-gate=, )"
[ "$RC" = 1 ] && ok "(f) --test-gate=, exits 1 (names no files)" \
              || no "(f) comma-only exit was $RC, expected 1"
[ -s "$TMP/out" ] && no "(f) comma-only still wrote a report body" || ok "(f) comma-only emits NO report"

# ── (g) control: a valid FILES list is untouched by all of this ───────────────────────────────────────
RC="$( run --test-gate=src/covered.cpp )"
[ "$RC" = 4 ] && ok "(g) a valid file still gates: exit 4 on the covering-test obligation" \
              || no "(g) valid-file exit was $RC, expected 4 — the refusal must not reach parseable input"
grep -q '<test-gate ' "$TMP/out" && grep -q 'changed="1"' "$TMP/out" \
    && ok "(g) the report still emits with changed=\"1\"" \
    || no "(g) valid-file report body wrong"

# ── (h) the refusal is identical under --json, and stdout stays empty ─────────────────────────────────
RC="$( run --test-gate=deadbeef..HEAD --json )"
[ "$RC" = 1 ] && [ ! -s "$TMP/out" ] && grep -qF 'deadbeef..HEAD' "$TMP/err" \
    && ok "(h) --json refuses identically (exit 1, empty stdout, token named)" \
    || no "(h) --json refusal drifted (rc=$RC, stdout $( wc -c <"$TMP/out" | tr -d ' ' ) bytes)"

[ "$fail" = 0 ] && echo "ALL PASS" || echo "FAILURES ABOVE"
exit $fail
