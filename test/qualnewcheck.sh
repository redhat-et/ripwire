#!/usr/bin/env bash
# qualnewcheck.sh — H4 (L-NEW lane) gate: qualified `new` call refs for TS/JS/Java.
#
# The H4 grammar survey found that TS/JS/Java's qualified constructor references were
# DROPPED — `new ns.Inner()` (TS/JS: constructor is a member_expression, only the bare (identifier)
# form was matched) and `new Outer.Inner()` (Java: type is a scoped_type_identifier, only the bare
# type_identifier form was matched). Items 6-7 widen:
#   - queries/typescript/tags.scm + queries/javascript/tags.scm:
#     (new_expression constructor: (member_expression property: (property_identifier) @name))
#   - queries/java/tags.scm:
#     (object_creation_expression type: (scoped_type_identifier (type_identifier) @name .))
# Both bind the constructed CLASS name (member_expression/scoped_type_identifier's final segment,
# verified with --match at 2 AND 3 segments — the anchor `.` in the Java pattern was empirically
# confirmed, not just taken from the survey's candidate: scoped_type_identifier is FLAT at 2
# segments (two direct type_identifier children) but RIGHT-recursive at 3+ (only the class name is
# a direct child at the top level) — the trailing anchor picks the right one at BOTH shapes).
# Same ctor-ref-to-class-def resolution precedent as the pre-existing bare `new Widget()` pattern.
#
# Fixture test/qualnewfix/ — one file per language, each with NO explicit constructors (every
# class name is a single unambiguous def, so ambiguous=0 end to end; the ctor-name-collision case
# is a separate, already-disclosed FP class covered by bench/h4fixtures/java, not re-derived here):
#   main.ts    Widget (bare, control) / ns.QnInner (2-seg) / ns.deep.Boxed (3-seg)
#   main.js    Widget (bare, control) / ns.QnInner (2-seg) / ns.deep.Boxed (3-seg)
#   Main.java  Widget (bare, control) / Outer.Inner (2-seg) / A.B.C (3-seg)
# (TS/JS use "QnInner", not "Inner" — the bare property name "Inner" collides with an unrelated
# dangling ref in the sibling survey fixture bench/h4fixtures/js/main.js; see the comment in
# test/qualnewfix/main.js. Java's "Inner" has no such collision — bisected empirically.)
#
# RED-FIRST (recorded 2026-07-31, plain dev build, both binaries same tree):
#   pre-change (build/ripwire_base): --callees=caller count="1" (Widget only) for all 3 languages.
#   post-change (build/ripwire):     --callees=caller count="3" (Widget + Inner/Boxed + the 3-seg
#                                     class) for all 3 languages.
# This gate reproduces that exact comparison live against build/ripwire_base when present (skips,
# does not fail, if the base binary is absent — e.g. a checkout that only ever built once).
#
# Usage:  test/qualnewcheck.sh   |   RIPWIRE_BIN=asan/ripwire test/qualnewcheck.sh
# Exits non-zero on any failure. Does NOT edit test/regression.sh or test/golden.xml.

set -u
ROOT="$( cd "$( dirname "$0" )/.." && pwd )"
BIN="${RIPWIRE_BIN:-$ROOT/build/ripwire}"
[ "${BIN#/}" = "$BIN" ] && BIN="$ROOT/$BIN"
FIX="$ROOT/test/qualnewfix"
TMP="$( mktemp -d )"; trap 'rm -rf "$TMP"' EXIT
fail=0
ok(){ printf '  PASS  %s\n' "$*"; }
no(){ printf '  FAIL  %s\n' "$*"; fail=1; }
skip(){ printf '  SKIP  %s\n' "$*"; }

[ -x "$BIN" ] || { echo "no ripwire binary at $BIN — build first (cmake --build build -j)"; exit 2; }
echo "qualnewcheck: BIN=$BIN  FIX=$FIX  TMP=$TMP"

callees_count(){  # $1 file:sym  $2 expected count
  local out c
  out="$( "$BIN" "$FIX" --callees="$1" --no-cache 2>/dev/null )"
  c="$( printf '%s' "$out" | grep -oE 'count="[0-9]+"' | head -1 )"
  if [ "$c" = "count=\"$2\"" ]; then ok "$1 callee count=$2"; else no "$1 callee count wrong (got $c, want count=\"$2\"): $out"; fi
}
callees_has(){  # $1 file:sym  $2 substring that MUST be present
  local out
  out="$( "$BIN" "$FIX" --callees="$1" --no-cache 2>/dev/null )"
  if printf '%s' "$out" | grep -q "n=\"$2\""; then ok "$1 callees include $2"; else no "$1 callees MISSING $2: $out"; fi
}

# ── the widening: qualified `new` at 2 AND 3 segments resolves, alongside the bare-new control ──
callees_count 'main.ts:caller'    3
callees_has   'main.ts:caller'    Widget
callees_has   'main.ts:caller'    QnInner
callees_has   'main.ts:caller'    Boxed

callees_count 'main.js:caller'    3
callees_has   'main.js:caller'    Widget
callees_has   'main.js:caller'    QnInner
callees_has   'main.js:caller'    Boxed

callees_count 'Main.java:caller'  3
callees_has   'Main.java:caller'  Widget
callees_has   'Main.java:caller'  Inner
callees_has   'Main.java:caller'  C

# ── ambiguity accounting: no explicit ctors in the fixture ⇒ every widened edge is PRECISE ──────
famb="$( "$BIN" "$FIX" --no-cache 2>/dev/null | grep -oE 'ambiguous=[0-9]+' | head -1 )"
[ "$famb" = "ambiguous=0" ] && ok "fixture $famb (no ctor-name collisions in this fixture)" || no "fixture $famb (expected 0)"
funr="$( "$BIN" "$FIX" --no-cache 2>/dev/null | grep -oE 'unresolved=[0-9]+' | head -1 )"
[ "$funr" = "unresolved=0" ] && ok "fixture $funr" || no "fixture $funr (expected 0)"

# ── determinism + warm==cold ──────────────────────────────────────────────────────────────────
"$BIN" "$FIX" --no-cache >"$TMP/d1" 2>/dev/null
"$BIN" "$FIX" --no-cache >"$TMP/d2" 2>/dev/null
cmp -s "$TMP/d1" "$TMP/d2" && ok "deterministic (two --no-cache runs identical)" || no "non-deterministic"
"$BIN" "$FIX" --cache="$TMP/c.bin" >"$TMP/cold" 2>/dev/null
"$BIN" "$FIX" --cache="$TMP/c.bin" >"$TMP/warm" 2>/dev/null
cmp -s "$TMP/cold" "$TMP/warm" && ok "warm == cold" || no "warm != cold"

# ── well-formed XML ───────────────────────────────────────────────────────────────────────────
command -v xmllint >/dev/null 2>&1 \
  && { xmllint --noout "$TMP/d1" 2>/dev/null && ok "xml well-formed" || no "xml malformed"; } \
  || ok "xml well-formed (xmllint absent — skipped)"

# ── RED-FIRST live check against a committed pre-change binary, when present ────────────────────
redfirst_check()
{
    local BASE="$ROOT/build/ripwire_base"
    [ -x "$BASE" ] || { skip "red-first: build/ripwire_base not present (build it before any H4 edit to re-run this arm)"; return; }
    local before_ts before_js before_java
    before_ts="$(   "$BASE" "$FIX" --callees='main.ts:caller'   --no-cache 2>/dev/null | grep -oE 'count="[0-9]+"' | head -1 )"
    before_js="$(   "$BASE" "$FIX" --callees='main.js:caller'   --no-cache 2>/dev/null | grep -oE 'count="[0-9]+"' | head -1 )"
    before_java="$( "$BASE" "$FIX" --callees='Main.java:caller' --no-cache 2>/dev/null | grep -oE 'count="[0-9]+"' | head -1 )"
    if [ "$before_ts" = 'count="1"' ] && [ "$before_js" = 'count="1"' ] && [ "$before_java" = 'count="1"' ]; then
        ok "red-first: build/ripwire_base under-counts (count=\"1\", Widget only) on all 3 languages — this gate is a real regression fence"
    elif [ "$before_ts" = 'count="3"' ] && [ "$before_js" = 'count="3"' ] && [ "$before_java" = 'count="3"' ]; then
        # H4 W2b post-merge fix: any lane that saves a POST-wave-2a binary as its ripwire_base gets the
        # widened counts here — that is a VINTAGE mismatch, not a regression; failing on it made this gate
        # unconditionally red in every later worktree. The fence itself is the literal-count arms above.
        skip "red-first: build/ripwire_base is wave-2a-or-later (count=\"3\" on all 3 — the qualified-new widening shipped in wave 2a) — vintage not applicable to this arm"
    else
        # ripwire_base is an UNCOMMITTED local scratch binary of arbitrary vintage. This arm can only
        # assert when the binary is provably the pre-change reference (the 1/1/1 signature); any other
        # signature (mixed-vintage, incompatible/errored binary) is a vintage mismatch, not a regression.
        skip "red-first: build/ripwire_base is not the pre-change reference (ts=$before_ts js=$before_js java=$before_java, want 1/1/1) — vintage not applicable to this arm"
    fi
}
redfirst_check

[ "$fail" -eq 0 ] && echo "ALL PASS" || { echo "SOME CHECKS FAILED"; exit 1; }
