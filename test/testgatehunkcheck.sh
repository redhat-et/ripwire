#!/usr/bin/env bash
# testgatehunkcheck.sh — --test-gate's SYMBOL-GRANULAR change set: the gate's obligations (tests to run +
# untested blast radius) seed from the symbols the diff actually touched, with the same per-file conservative
# fallback --situ uses, and the root DISCLOSES the narrowing whenever hunk evidence shaped the answer.
#
#   test/testgatehunkcheck.sh
#   RIPWIRE_BIN=asan/ripwire test/testgatehunkcheck.sh
#
# WHY THIS EXISTS. --situ and --test-gate answer ONE question — "what does this change obligate" — and the
# house rule is one computation, every surface (situ.h's own header: "the point of the seam is not that the
# two agree today, it is that there is only one place where they could stop agreeing"). When --situ grew the
# symbol-granular change set (test/situhunkcheck.sh, the PR #302 field-report fix: 323 tests → 56 on a 3-line
# django edit), the gate verb had to grow it in the same commit or the two siblings would DISAGREE about the
# same dirty tree — an agent reading --situ's 56 and the gate's 323 has no way to know which is the answer.
#
# WHAT THIS GATE PINS.
#   (a) a function-body edit: change_granularity="symbol" on the root, changed_symbols=1, the unrelated
#       feature's test is NOT an obligation, exit 4 stands (the checkout test IS one);
#   (b) the legend DEFINES the attribute whenever the attribute prints (legendcoverage's rule, gated the way
#       untested_modscope's own clause is);
#   (c) the --json twin mirrors the attribute key-for-key;
#   (d) a module-level edit: granularity="file", the conservative superset, both tests obligated;
#   (e) a CLEAN selector run: NO change_granularity attribute at all — zero hunk evidence means zero new
#       bytes, so every pre-existing fixture (clean trees, explicit selectors on clean files) is byte-unchanged;
#   (f) determinism.
#
# Exit 0 = ALL PASS, non-zero = SOME FAILED.

set -u
ROOT="$( cd "$( dirname "$0" )/.." && pwd )"
. "$ROOT/test/lib/clean-env.sh"
BIN="${1:-${RIPWIRE_BIN:-$ROOT/build/ripwire}}"
[ "${BIN#/}" = "$BIN" ] && BIN="$ROOT/$BIN"
TMP="$( mktemp -d )"; trap 'rm -rf "$TMP"' EXIT
fail=0
ok(){ printf '  PASS  %s\n' "$*" || { fail=1; printf '  FAIL  could not write the PASS line for: %s\n' "$*"; }; return 0; }
no(){ printf '  FAIL  %s\n' "$*"; fail=1; }

[ -x "$BIN" ] || { echo "no ripwire binary at $BIN — build first (cmake --build build -j)"; exit 2; }
command -v git >/dev/null 2>&1 || { echo "git required"; exit 2; }

# ── the fixture: the situhunkcheck shape — one shared routes file, two independent features, two tests ──
FX="$TMP/fx"
mkdir -p "$FX/app" "$FX/tests"
cat > "$FX/app/routes.py" <<'EOF'
CUTOFF_MINUTES = 15


def validate_booking(slot):
    return slot


def checkout_entry(slot):
    return validate_booking(slot)


def payment_charge(amount):
    return amount * 2


def encounter_close(enc):
    return enc
EOF
cat > "$FX/tests/test_checkout.py" <<'EOF'
from app.routes import checkout_entry


def test_checkout_slot():
    return checkout_entry("10:00")
EOF
cat > "$FX/tests/test_payment.py" <<'EOF'
from app.routes import payment_charge


def test_payment_charge():
    return payment_charge(5)
EOF
( cd "$FX" && git init -q -b main >/dev/null 2>&1
  git config user.email rw@example.invalid; git config user.name ripwire
  git add -A >/dev/null 2>&1
  GIT_AUTHOR_DATE='2026-01-01T00:00:00 +0000' GIT_COMMITTER_DATE='2026-01-01T00:00:00 +0000' \
    git commit -q -m seed >/dev/null 2>&1 ) || { echo "git fixture setup failed"; exit 2; }

edit_fn(){ python3 - "$FX/app/routes.py" <<'EOF'
import sys
p = sys.argv[1]
s = open(p).read()
old = '''def checkout_entry(slot):
    return validate_booking(slot)'''
new = '''def checkout_entry(slot):
    if slot is None:
        return validate_booking("00:00")
    return validate_booking(slot)'''
assert old in s
open(p, "w").write(s.replace(old, new, 1))
EOF
}

# ── (a) THE NARROWED GATE — exit 4 kept, obligations focused ────────────────────────────────────────────
( cd "$FX" && git checkout -q -- app/routes.py )
edit_fn
OUT_A="$TMP/a.xml"
( cd "$FX" && "$BIN" . --test-gate --no-cache >"$OUT_A" 2>/dev/null ); RC_A=$?
if [ "$RC_A" -eq 4 ]; then ok "(a) the narrowed gate still exits 4 — obligations remain"
else no "(a) the narrowed gate exited $RC_A, expected 4 (the checkout test is an obligation)"; fi
for tok in 'change_granularity="symbol"' 'changed_symbols="1"' 'files_narrowed="1"' 'diff_hunks_unlocated="0"'; do
  case "$( cat "$OUT_A" )" in *"$tok"*) ok "(a) root carries $tok" ;; *) no "(a) root lacks $tok" ;; esac
done
if grep -q 'test_checkout.py' "$OUT_A"; then ok "(a) <t> rows obligate the checkout test"
else no "(a) <t> rows lost the checkout test"; fi
if grep -q 'test_payment.py' "$OUT_A"; then no "(a) <t> rows still obligate the unrelated payment test — the gate did not narrow"
else ok "(a) <t> rows exclude the unrelated payment test"; fi

# ── (b) THE LEGEND DEFINES THE ATTRIBUTE it prints ──────────────────────────────────────────────────────
# the LEADING comment block (everything before the root element) is the legend the reader meets first.
DOC_A="$( cat "$OUT_A" )"
LEAD_A="${DOC_A%%<test-gate *}"
case "$LEAD_A" in
  *'change_granularity='*) ok "(b) the leading legend defines change_granularity= beside the root that carries it" ;;
  *) no "(b) the root prints change_granularity= but the leading legend never mentions it" ;;
esac

# ── (c) THE JSON TWIN MIRRORS THE ATTRIBUTE ─────────────────────────────────────────────────────────────
OUT_J="$TMP/a.json"
( cd "$FX" && "$BIN" . --test-gate --json --no-cache >"$OUT_J" 2>/dev/null )
for tok in '"change_granularity":"symbol"' '"changed_symbols":1' '"files_narrowed":1'; do
  case "$( cat "$OUT_J" )" in *"$tok"*) ok "(c) JSON twin carries $tok" ;; *) no "(c) JSON twin lacks $tok" ;; esac
done
if python3 -c 'import json,sys; json.load(open(sys.argv[1]))' "$OUT_J" 2>/dev/null
then ok "(c) JSON twin parses"; else no "(c) JSON twin is malformed"; fi

# ── (d) THE FALLBACK GATE — a module-level edit keeps the conservative superset ────────────────────────
( cd "$FX" && git checkout -q -- app/routes.py )
python3 - "$FX/app/routes.py" <<'EOF'
import sys
p = sys.argv[1]
s = open(p).read()
open(p, "w").write(s.replace("CUTOFF_MINUTES = 15", "CUTOFF_MINUTES = 15\nGRACE_MINUTES = 5", 1))
EOF
OUT_D="$TMP/d.xml"
( cd "$FX" && "$BIN" . --test-gate --no-cache >"$OUT_D" 2>/dev/null ); RC_D=$?
case "$( cat "$OUT_D" )" in *'change_granularity="file"'*) ok "(d) the fallback root names change_granularity=file" ;;
  *) no "(d) the module-level edit's root does not name granularity=file" ;; esac
case "$( cat "$OUT_D" )" in *'diff_hunks_unlocated="1"'*) ok "(d) the unlocatable hunk is disclosed" ;;
  *) no "(d) the unlocatable hunk is not disclosed: $( grep -o 'diff_hunks_unlocated="[0-9]*"' "$OUT_D" | head -1 )" ;; esac
if grep -q 'test_payment.py' "$OUT_D" && grep -q 'test_checkout.py' "$OUT_D"; then
  ok "(d) both tests are obligations again — the fallback is the conservative superset"
else
  no "(d) the fallback lost an obligation"
fi
if [ "$RC_D" -eq 4 ]; then ok "(d) the fallback gate exits 4"
else no "(d) the fallback gate exited $RC_D, expected 4"; fi

# ── (e) THE CLEAN SELECTOR — no hunk evidence, no new attribute, no new bytes ──────────────────────────
( cd "$FX" && git checkout -q -- app/routes.py )
OUT_E="$TMP/e.xml"
( cd "$FX" && "$BIN" . --test-gate=app/routes.py --no-cache >"$OUT_E" 2>/dev/null )
case "$( cat "$OUT_E" )" in *change_granularity*) no "(e) a clean selector run prints change_granularity — zero-evidence runs must be byte-conservative" ;;
  *) ok "(e) a clean selector run carries no change_granularity attribute" ;; esac
if grep -q 'test_payment.py' "$OUT_E"; then ok "(e) the clean selector keeps the file-granular obligations (unchanged behavior)"
else no "(e) the clean selector lost the payment obligation — a regression in the untouched path"; fi

# ── (f) determinism on the narrowed arm ─────────────────────────────────────────────────────────────────
( cd "$FX" && git checkout -q -- app/routes.py )
edit_fn
( cd "$FX" && "$BIN" . --test-gate --no-cache >"$TMP/f1.xml" 2>/dev/null )
( cd "$FX" && "$BIN" . --test-gate --no-cache >"$TMP/f2.xml" 2>/dev/null )
if cmp -s "$TMP/f1.xml" "$TMP/f2.xml"; then ok "(f) the narrowed gate report is byte-identical across two runs"
else no "(f) the narrowed gate report is not deterministic"; fi

# ── the boundary arms (maintainer round on #423) ────────────────────────────────────────────────────────────
mkrepo(){ # mkrepo DIR — a committed repo whose files the caller has already written
  ( cd "$1" && git init -q -b main >/dev/null 2>&1
    git config user.email rw@example.invalid; git config user.name ripwire
    git add -A >/dev/null 2>&1
    GIT_AUTHOR_DATE='2026-01-01T00:00:00 +0000' GIT_COMMITTER_DATE='2026-01-01T00:00:00 +0000' \
      git commit -q -m seed >/dev/null 2>&1 ) || { echo "git fixture setup failed"; exit 2; }
}
sub(){ python3 - "$1" "$2" "$3" <<'EOF'
import sys
p, old, new = sys.argv[1:4]
s = open(p).read()
assert old in s, old
open(p, "w").write(s.replace(old, new, 1))
EOF
}

# ── (g) B2 — a constructor / property body hunk must NOT narrow; callers reach the CLASS, not the member ───
# Narrowed to the constructor symbol the walk finds zero callers, so the gate turned GREEN (exit 0) on an edit
# every user of the class feels. The honest fallback is the old file-level answer: the gate stays red (exit 4)
# with the class's test an obligation, disclosed as change_granularity="file". One fixture per language the
# narrowing reaches; each has an unrelated second function so that "narrowed" and "file-level" differ.
b2_arm(){ # b2_arm LABEL DIR OLD NEW FILE EXPECT_TEST
  ( cd "$2" && git checkout -q -- . )
  sub "$2/$5" "$3" "$4"
  ( cd "$2" && "$BIN" . --test-gate --no-cache >"$TMP/b2.xml" 2>/dev/null ); local rc=$?
  if [ "$rc" -eq 4 ]; then ok "(g) $1: the gate stays red (exit 4)"; else no "(g) $1: the gate exited $rc, expected 4 (ctor/property edit narrowed to zero callers)"; fi
  case "$( cat "$TMP/b2.xml" )" in *'change_granularity="file"'*) ok "(g) $1: change_granularity=file (honest fallback, disclosed)" ;;
    *) no "(g) $1: the fallback is not disclosed as change_granularity=file" ;; esac
  if grep -q "$6" "$TMP/b2.xml"; then ok "(g) $1: $6 is an obligation"; else no "(g) $1: $6 lost — the class's users are gone from the answer"; fi
}
PYD="$TMP/g_py"; mkdir -p "$PYD"
cat > "$PYD/svc.py" <<'EOF'
class Svc:
    def __init__(self):
        self.n = 0

    @property
    def size(self):
        return 1

    def run(self, x):
        return x


def other(x):
    return x
EOF
printf 'from svc import Svc\n\n\ndef test_svc():\n    assert Svc().run(1)\n' > "$PYD/test_svc.py"
printf 'from svc import Svc\n\n\ndef test_size():\n    assert Svc().size\n' > "$PYD/test_size.py"
printf 'from svc import other\n\n\ndef test_other():\n    assert other(1)\n' > "$PYD/test_other.py"
mkrepo "$PYD"
b2_arm "python __init__" "$PYD" "self.n = 0" "self.n = 1" svc.py test_svc.py
b2_arm "python @property" "$PYD" "return 1" "return 2" svc.py test_size.py

TSD="$TMP/g_ts"; mkdir -p "$TSD"
cat > "$TSD/lib.ts" <<'EOF'
export class Box {
  size = 1;
  constructor() {
    this.size = 1;
  }
  grow(x: number): number {
    return x + 1;
  }
}

export function tsOther(x: number): number {
  return x * 2;
}
EOF
printf 'import { Box } from "./lib";\n\ntest("grow", () => { expect(new Box().grow(1)).toBe(2); });\n' > "$TSD/check_box.test.ts"
printf 'import { tsOther } from "./lib";\n\ntest("other", () => { expect(tsOther(1)).toBe(2); });\n' > "$TSD/check_other.test.ts"
mkrepo "$TSD"
b2_arm "typescript constructor" "$TSD" "this.size = 1;" "this.size = 2;" lib.ts check_box.test.ts

CPD="$TMP/g_cpp"; mkdir -p "$CPD"
cat > "$CPD/lib.h" <<'EOF'
#pragma once
int cppOther( int x );
struct Widget
{
    Widget();
    int grow( int x );
};
EOF
cat > "$CPD/lib.cpp" <<'EOF'
#include "lib.h"

static const int kLimit = 5;

int cppOther( int x )
{
    return x * 2;
}

Widget::Widget()
{
    kLimit;
}

int Widget::grow( int x )
{
    return x + 1;
}
EOF
printf '#include "lib.h"\n#include <cassert>\nint main() { Widget w; assert( w.grow(1) > 0 ); }\n' > "$CPD/test_widget.cpp"
printf '#include "lib.h"\n#include <cassert>\nint main() { assert( cppOther(1) > 0 ); }\n' > "$CPD/test_other.cpp"
mkrepo "$CPD"
b2_arm "c++ constructor" "$CPD" "    kLimit;" "    kLimit + 1;" lib.cpp test_widget.cpp

# ── (h) B3 — an EXPLICIT file list is never narrowed by the working-tree diff ───────────────────────────────
# A committed edit to alpha plus an UNRELATED uncommitted edit to beta: --test-gate=app.py names the FILE, so
# the obligations are the file-level ones (alpha's test stays) and no hunk attribute rides.
HD="$TMP/g_h"; mkdir -p "$HD"
printf 'def alpha(x):\n    return x + 1\n\n\ndef beta(x):\n    return x * 2\n' > "$HD/app.py"
printf 'from app import alpha\n\n\ndef test_alpha():\n    assert alpha(1)\n' > "$HD/test_alpha.py"
printf 'from app import beta\n\n\ndef test_beta():\n    assert beta(1)\n' > "$HD/test_beta.py"
mkrepo "$HD"
sub "$HD/app.py" "return x + 1" "return x + 11"; ( cd "$HD" && git commit -qam 'alpha (committed)' )
sub "$HD/app.py" "return x * 2" "return x * 3"
( cd "$HD" && "$BIN" . --test-gate=app.py --no-cache >"$TMP/h.xml" 2>/dev/null ); RC_H=$?
if grep -q 'test_alpha.py' "$TMP/h.xml" && grep -q 'test_beta.py' "$TMP/h.xml"; then
  ok "(h) --test-gate=app.py keeps both obligations on a dirty tree (the file-level answer)"
else no "(h) --test-gate=app.py was narrowed by the working-tree diff (alpha's obligation dropped)"; fi
case "$( cat "$TMP/h.xml" )" in *change_granularity*) no "(h) an explicit list prints a hunk attribute — the diff did not shape this answer" ;;
  *) ok "(h) an explicit list carries no hunk attribute" ;; esac

# ── (i) B4 — a hunk over a body AND module-level lines is not located ───────────────────────────────────────
sub "$HD/app.py" "return x * 3" "return x * 3
CFG = 2"
( cd "$HD" && "$BIN" . --test-gate --no-cache >"$TMP/i.xml" 2>/dev/null )
case "$( cat "$TMP/i.xml" )" in *'change_granularity="file"'*'diff_hunks_unlocated="1"'*|*'diff_hunks_unlocated="1"'*'change_granularity="file"'*) ok "(i) the half-in-a-body hunk is unlocated: change_granularity=file" ;;
  *) no "(i) a hunk reaching module level counted as located: $( grep -o 'change_granularity="[a-z]*"\|diff_hunks_unlocated="[0-9]*"' "$TMP/i.xml" | tr '\n' ' ' )" ;; esac
if grep -q 'test_alpha.py' "$TMP/i.xml"; then ok "(i) alpha's obligation stays (the file seeds whole)"; else no "(i) alpha's obligation was dropped"; fi

if [ "$fail" -eq 0 ]; then echo "testgatehunkcheck: ALL PASS"; else echo "testgatehunkcheck: SOME FAILED"; fi
exit "$fail"
