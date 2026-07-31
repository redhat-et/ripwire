#!/usr/bin/env bash
# archcheck.sh — gate test for P3-B: built-in layers as --arch `layer()` predicate.
#
# Verifies that built-in layer names (game/infra/render/math/audio/ai/test) resolve in
# deny/allow rules WITHOUT explicit `layer NAME = ...` declarations.
#
# Usage:
#   bash test/archcheck.sh                          |  bash test/archcheck.sh asan/ripwire
#   RIPWIRE_BIN=asan/ripwire bash test/archcheck.sh
#
# Exits non-zero on any failure; prints PASS/FAIL per check; prints ALL PASS on success.
#
# Checks 1-9 run from INSIDE the fixture dir (test/archfix/) — historically because they HAD to. The note
# that used to sit here called that an implementation detail: paths came out as `./render/shader.h` and
# `./test/main.cpp` rather than repo-relative spellings starting with `test/`, "which would cause the `test/`
# built-in layer to falsely match render/shader.h". That was the bug, not a detail. Layer substrings are now
# matched against the ROOT-RELATIVE path, so the cwd cannot change a verdict — and check 10 is what proves it,
# by running the identical rules file from the repo root and demanding the same violations= and the same exit
# code. The other checks keep their cwd so that what they assert is unchanged.

set -u
ROOT="$( cd "$( dirname "$0" )/.." && pwd )"
# BOTH seams. `bash test/<gate>.sh asan/ripwire` is how regression.sh and every differential run pass a
# binary; this gate read only RIPWIRE_BIN, so a positional argument was accepted and silently ignored and
# a red-first run against a BASE binary came back ALL PASS against the binary already in build/.
BIN="${1:-${RIPWIRE_BIN:-$ROOT/build/ripwire}}"
[ "${BIN#/}" = "$BIN" ] && BIN="$ROOT/$BIN"          # allow repo-relative RIPWIRE_BIN

FIXTURE="$ROOT/test/archfix"
fail=0

ok(){ printf '  PASS  %s\n' "$*"; }
no(){ printf '  FAIL  %s\n' "$*"; fail=1; }

[ -x "$BIN" ] || { echo "no ripwire binary at $BIN — build first (cmake --build build -j)"; exit 2; }

TMP="$( mktemp -d )"; trap 'rm -rf "$TMP"' EXIT

# run every ripwire invocation from inside the fixture dir so paths are `./render/…` `./test/…`
cd "$FIXTURE"

echo "archcheck: BIN=$BIN  FIXTURE=$FIXTURE"

# ── check 1: built-in-layer violation detected (exit 2) ───────────────────────────────────────────
# rules.txt uses `deny test -> render` — both are BUILT-IN layer names with no `layer` declarations.
# test/main.cpp includes render/shader.h, so ripwire must detect the crossing and exit 2.
"$BIN" . --arch=rules.txt --no-cache >"$TMP/viol.xml" 2>/dev/null
rc_viol=$?
if [ "$rc_viol" -eq 2 ]; then
    ok "built-in-layer deny rule: exit 2 (violation detected)"
else
    no "built-in-layer deny rule: expected exit 2, got $rc_viol"
fi

# ── check 2: violation output mentions the crossing edge ──────────────────────────────────────────
# The arch XML must reference the violating files (non-zero violations count) so the user can act.
if grep -q 'violations="[^0]' "$TMP/viol.xml" 2>/dev/null; then
    ok "violation output reports non-zero violation count"
else
    no "violation output missing non-zero violations (got: $(head -1 "$TMP/viol.xml"))"
fi

# ── check 3: clean rules file (allow test -> render) exits 0 ──────────────────────────────────────
# The same fixture with an allow rule must not exit 2 — built-in layers also work for `allow`.
"$BIN" . --arch=clean_rules.txt --no-cache >/dev/null 2>/dev/null
rc_clean=$?
if [ "$rc_clean" -eq 0 ]; then
    ok "clean built-in-layer allow rule: exit 0 (no violation)"
else
    no "clean built-in-layer allow rule: expected exit 0, got $rc_clean"
fi

# ── check 4: user-declared layer wins over built-in on name clash ─────────────────────────────────
# A rules file that declares `layer test = /no-such-path/` means NO files match `test` → 0 violations.
# If the built-in overwrote the user layer, test/main.cpp would still match and exit 2.
cat >"$TMP/override.txt" <<'EOF'
# user overrides the built-in `test` layer with a non-matching path
layer test = /no-such-path-xyz/
deny test -> render
EOF
"$BIN" . --arch="$TMP/override.txt" --no-cache >/dev/null 2>/dev/null
rc_over=$?
if [ "$rc_over" -eq 0 ]; then
    ok "user-defined layer wins over built-in (no false violation when user redefines 'test')"
else
    no "user-defined layer lost to built-in (expected exit 0 with user override, got $rc_over)"
fi

# ── check 5: determinism — two runs with built-in layers produce byte-identical output ────────────
"$BIN" . --arch=rules.txt --no-cache >"$TMP/det_a.xml" 2>/dev/null || true
"$BIN" . --arch=rules.txt --no-cache >"$TMP/det_b.xml" 2>/dev/null || true
if diff -q "$TMP/det_a.xml" "$TMP/det_b.xml" >/dev/null 2>&1; then
    ok "determinism: byte-identical output across two runs with built-in layers"
else
    no "determinism: output differs between runs with built-in layers"
    diff "$TMP/det_a.xml" "$TMP/det_b.xml" | head -8
fi

# ── check 6: existing behavior unchanged — rules that only use user-declared layers still work ────
# A fully user-declared rule file must be unaffected by the built-in auto-add logic.
cat >"$TMP/userlayers.txt" <<'EOF'
# all layers are user-declared — no built-in auto-add should trigger
layer myrender = render
layer mytest   = test
deny mytest -> myrender
EOF
"$BIN" . --arch="$TMP/userlayers.txt" --no-cache >/dev/null 2>/dev/null
rc_user=$?
if [ "$rc_user" -eq 2 ]; then
    ok "user-declared-only rules still detect violations (no regression)"
else
    no "user-declared-only rules: expected exit 2, got $rc_user (regression in existing behavior)"
fi

# ── check 7 (D9): a malformed rules line must REJECT the whole file loudly — not silently disarm ──
# `deny: test -> render` (colon typo) used to tokenize "deny:" as the keyword, match neither "allow" nor
# "deny", and get silently ignored — the file "parsed" to zero rules/violations and exited 0, quietly
# turning off a CI gate. It must now behave like --lint-rules: refuse the file, print a specific
# path:lineNo message, and exit 1 (not 0, not 2 — a REFUSAL, distinct from "ran clean" and "found debt").
cat >"$TMP/typo_colon.txt" <<'EOF'
deny: test -> render
EOF
"$BIN" . --arch="$TMP/typo_colon.txt" --no-cache >"$TMP/typo_colon.out" 2>"$TMP/typo_colon.err"
rc_typo=$?
if [ "$rc_typo" -eq 1 ]; then
    ok "malformed rules line ('deny:' colon typo): exit 1 (refused, not silently disarmed)"
else
    no "malformed rules line ('deny:' colon typo): expected exit 1, got $rc_typo"
fi
if grep -q 'typo_colon.txt:1' "$TMP/typo_colon.err" 2>/dev/null; then
    ok "malformed rules line: stderr names the file and line number"
else
    no "malformed rules line: stderr missing a path:lineNo diagnostic (got: $(cat "$TMP/typo_colon.err"))"
fi
if [ ! -s "$TMP/typo_colon.out" ]; then
    ok "malformed rules line: no XML emitted on refusal"
else
    no "malformed rules line: unexpectedly emitted XML on refusal: $(cat "$TMP/typo_colon.out")"
fi

# ── check 8 (D9): other malformed-line shapes are refused the same way ────────────────────────────
cat >"$TMP/bad_layer.txt" <<'EOF'
layer test
EOF
"$BIN" . --arch="$TMP/bad_layer.txt" --no-cache >/dev/null 2>"$TMP/bad_layer.err"
rc_badlayer=$?
[ "$rc_badlayer" -eq 1 ] && grep -q 'bad_layer.txt:1' "$TMP/bad_layer.err" \
    && ok "malformed 'layer' line (missing '= subs'): exit 1 with a line diagnostic" \
    || no "malformed 'layer' line: expected exit 1 + diagnostic, got exit $rc_badlayer, stderr: $(cat "$TMP/bad_layer.err")"

cat >"$TMP/bad_kw.txt" <<'EOF'
denyy test -> render
EOF
"$BIN" . --arch="$TMP/bad_kw.txt" --no-cache >/dev/null 2>"$TMP/bad_kw.err"
rc_badkw=$?
[ "$rc_badkw" -eq 1 ] && grep -q 'bad_kw.txt:1' "$TMP/bad_kw.err" \
    && ok "unrecognized keyword ('denyy'): exit 1 with a line diagnostic" \
    || no "unrecognized keyword: expected exit 1 + diagnostic, got exit $rc_badkw, stderr: $(cat "$TMP/bad_kw.err")"

# a well-formed file is UNAFFECTED by the tightened parser (no false-positive rejection).
"$BIN" . --arch=rules.txt --no-cache >/dev/null 2>"$TMP/wellformed.err"
rc_wf=$?
[ "$rc_wf" -eq 2 ] && [ ! -s "$TMP/wellformed.err" ] \
    && ok "well-formed rules file: still exits 2 on a real violation, no spurious stderr" \
    || no "well-formed rules file: regressed (exit $rc_wf, stderr: $(cat "$TMP/wellformed.err"))"

# ── check 10: THE SAME RULES FILE MUST GIVE THE SAME VERDICT FROM ANY WORKING DIRECTORY ───────────
# Every check above runs from INSIDE the fixture. The header used to explain why as an implementation
# note — `./render/shader.h` and `./test/main.cpp` are "real dir-component-first paths", where the
# repo-relative spelling starting with `test/` "would cause the `test/` built-in layer to falsely match
# render/shader.h". That is not an implementation note, it is the bug: the layer substrings were matched
# against the path as EMITTED, so `/…/test/archfix/render/shader.h` contains `/test/` and first-match-wins
# put the render file in the test layer, both endpoints landed in one layer, and `deny test -> render`
# reported violations="0" at exit 0. Measured on the pre-fix binary: violations="1" from inside the fixture
# and violations="0" from the repo root, same fixture, same rules file, same binary.
#
# Rules are now matched against the ROOT-RELATIVE path, so the workaround is no longer load-bearing — and
# this arm is what keeps it that way: the verdict must be identical whether the corpus is named `.` from
# inside or by an absolute path from outside. A CI gate that reports clean because of where it was invoked
# from is worse than no gate.
ARCH_OUT_INSIDE="$( "$BIN" . --arch=rules.txt --no-cache 2>/dev/null | grep -oE '<arch [^>]*' )"
rc_inside=$?
ARCH_OUT_OUTSIDE="$( cd "$ROOT" && "$BIN" "$FIXTURE" --arch="$FIXTURE/rules.txt" --no-cache 2>/dev/null | grep -oE '<arch [^>]*' )"
v_inside="$(  printf '%s' "$ARCH_OUT_INSIDE"  | grep -oE 'violations="[0-9]+"' )"
v_outside="$( printf '%s' "$ARCH_OUT_OUTSIDE" | grep -oE 'violations="[0-9]+"' )"
if [ -z "$v_inside" ] || [ -z "$v_outside" ]; then
    no "check 10 could not read violations= from one of the two runs (inside='$v_inside' outside='$v_outside')"
elif [ "$v_inside" = "$v_outside" ] && [ "$v_inside" != 'violations="0"' ]; then
    ok "layer rules give the same verdict from inside the fixture and from the repo root ($v_inside)"
else
    no "layer verdict depends on the working directory: inside=$v_inside outside=$v_outside — an unanchored layer substring bound to the checkout path"
fi
# and the EXIT CODE, which is what CI reads, must agree too.
( cd "$ROOT" && "$BIN" "$FIXTURE" --arch="$FIXTURE/rules.txt" --no-cache >/dev/null 2>&1 )
rc_outside=$?
[ "$rc_outside" -eq 2 ] \
    && ok "…and the CI exit code is 2 from outside the fixture too (not a silent 0)" \
    || no "running the same rules from outside the fixture exits $rc_outside, not 2 — the gate disarms itself off-cwd"

# ── summary ───────────────────────────────────────────────────────────────────────────────────────
echo
if [ "$fail" -eq 0 ]; then
    echo "ALL PASS"
    exit 0
else
    echo "SOME CHECKS FAILED"
    exit 1
fi
