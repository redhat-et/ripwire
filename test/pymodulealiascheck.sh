#!/usr/bin/env bash
# pymodulealiascheck.sh — issue #287: a Python member call through a module ALIAS (`import target_mod as
# tm` then `tm.run(...)`) must bind to the ONE file the alias's module resolves to, even when the callee's
# NAME is duplicated across several other indexed files. Before this fix the edge was dropped into
# `graph_ambiguous` instead — the issue's own self-contained repro (`import target_mod as tm; tm.run({})`
# against 7 files all defining `run`) shows `count="1"` (only the qualified caller) where it should show
# `count="2"`. With a GLOBALLY UNIQUE callee name the identical alias shape already resolved (the bare-name
# ladder's own accidental uniqueness win, not real module resolution) — this gate is the K>1 case.
#
# Fixture test/pymodulealiasfix:
#   tests/caller_alias.py      import target_mod as tm ; tm.run({})        -> MUST bind pkg/target_mod.py:run
#                                                                             (issue #287's own shape; `run`
#                                                                             is defined 9 times in this fixture)
#   tests/caller_qualified.py  from pkg.target_mod import run ; run({})    -> already bound pre-fix (regression)
#   tests/caller_negative.py   import decoy_mod as dm ; dm.run({})         -> decoy_mod defines NO `run` ->
#                                                                             must NOT bind to any decoy
#   tests/caller_dotted.py     import pkg.sub.deep as dsub ; dsub.run({})  -> dotted module + alias
#   tests/caller_pkgalias.py   import pkgy as p ; p.run({})                -> package __init__.py + alias
#   tests/caller_unique.py     import unique_mod as um ; um.unique_only()  -> globally unique name (sanity;
#                                                                             unaffected by this fix either way)
#   tests/caller_shadow.py     import target_mod as tm ; def f(tm): tm.run({})
#                                                                         -> `tm` is a LOCAL PARAMETER here,
#                                                                            not the module import -> must
#                                                                            NOT force-bind
#   tests/caller_samestem.py   import samestem as ss ; ss.run()           -> `samestem` itself names TWO
#                                                                            files (a2/samestem.py AND
#                                                                            b2/samestem.py) -> the module
#                                                                            itself is ambiguous -> must NOT
#                                                                            bind to either
#   tests/other_1..6.py        def run(tmp_path): ...                     -> decoys, unrelated to any alias
#
# RED on the pre-#287 binary, GREEN on the binary under test — this gate is useless unless it can prove
# that contrast, so it builds a HEAD comparison binary (test/lib/headbinlib.sh, the same shared cache the
# other five *importprecisecheck/*condcheck monotonicity gates use) and runs every arm against BOTH.
#
# Usage:  test/pymodulealiascheck.sh   |   RIPWIRE_BIN=asan/ripwire test/pymodulealiascheck.sh
# Exits non-zero on any failure. Does NOT edit test/regression.sh or test/golden.xml.

set -u
ROOT="$( cd "$( dirname "$0" )/.." && pwd )"
BIN="${1:-${RIPWIRE_BIN:-$ROOT/build/ripwire}}"
[ "${BIN#/}" = "$BIN" ] && BIN="$ROOT/$BIN"
FIX="$ROOT/test/pymodulealiasfix"
. "$ROOT/test/lib/headbinlib.sh"                       # shared sha-keyed cache of the HEAD comparison binary
TMP="$( mktemp -d )"; trap 'rm -rf "$TMP"' EXIT
fail=0
ok(){ printf '  PASS  %s\n' "$*" || { fail=1; printf '  FAIL  could not write the PASS line for: %s\n' "$*"; }; return 0; }
no(){ printf '  FAIL  %s\n' "$*"; fail=1; }
skip(){ printf '  SKIP  %s\n' "$*"; }

[ -x "$BIN" ] || { echo "no ripwire binary at $BIN — build first (cmake --build build -j)"; exit 2; }
echo "pymodulealiascheck: BIN=$BIN  FIX=$FIX  TMP=$TMP"

_n=0
# run "$1"=binary --callers="$2"=target into a fresh scratch file; $TMP/o$_n holds the result.
callers_out(){ _n=$(( _n + 1 )); "$1" "$FIX" --callers="$2" --no-cache --legend=compact >"$TMP/o$_n" 2>/dev/null; }
bound_in_last(){ grep -q "n=\"$1\"" "$TMP/o$_n"; }   # did the row set from the last callers_out include caller $1?

# $1 binary  $2 target(file:name)  $3 caller symbol  $4 label  -> PASS iff $3 IS a caller of $2
assert_bound(){
    callers_out "$1" "$2"
    if bound_in_last "$3"; then ok "$4: $2 binds $3"; else no "$4: $2 did NOT bind $3"; sed 's/^/        | /' "$TMP/o$_n"; fi
}
# $1 binary  $2 target(file:name)  $3 caller symbol  $4 label  -> PASS iff $3 is NOT a caller of $2
assert_not_bound(){
    callers_out "$1" "$2"
    if bound_in_last "$3"; then no "$4: $2 wrongly bound $3"; sed 's/^/        | /' "$TMP/o$_n"; else ok "$4: $2 correctly refused $3"; fi
}

run_arms(){   # $1 = binary, $2 = arm-label suffix (e.g. "new" or "old")
    local B="$1" L="$2"
    assert_bound     "$B" pkg/target_mod.py:run        uses_module_alias   "alias ($L)"
    assert_bound     "$B" pkg/target_mod.py:run        uses_qualified      "qualified regression ($L)"
    # negative arm: decoy_mod.py defines NO `run` at all (defs=0 for that query — a sanity floor), so the
    # real risk is elsewhere: `dm.run()` must not spuriously latch onto ANY *other* real `run` definition
    # in the tree either (target_mod / sub.deep / pkgy's own, each a distinct alias-narrow target below).
    assert_not_bound "$B" pkg/decoy_mod.py:run          uses_negative_alias "negative: alias to a module with no run ($L)"
    assert_not_bound "$B" pkg/target_mod.py:run         uses_negative_alias "negative: does not leak onto target_mod's run ($L)"
    assert_not_bound "$B" pkg/sub/deep.py:run           uses_negative_alias "negative: does not leak onto sub.deep's run ($L)"
    assert_not_bound "$B" pkgy/__init__.py:run          uses_negative_alias "negative: does not leak onto pkgy's run ($L)"
    assert_bound     "$B" pkg/sub/deep.py:run           uses_dotted_alias   "dotted module alias ($L)"
    assert_bound     "$B" pkgy/__init__.py:run          uses_pkg_alias      "package __init__ alias ($L)"
    assert_bound     "$B" pkg/unique_mod.py:unique_only uses_unique_alias   "unique-name sanity ($L)"
    assert_not_bound "$B" pkg/target_mod.py:run         uses_shadowed       "local shadow refuses ($L)"
    assert_not_bound "$B" a2/samestem.py:run            uses_samestem_alias "ambiguous module stem, side a ($L)"
    assert_not_bound "$B" b2/samestem.py:run            uses_samestem_alias "ambiguous module stem, side b ($L)"
    # from-import-member arm (numpy corpus false positive, caught by hand-grading real edges before this
    # arm existed): `from pkg.target_mod import helper_fn` binds `helper_fn` to a NAME *inside* target_mod,
    # not to the module itself (RawBind::importedName stays empty — capturePythonImportBinds, kParserVer
    # 115). `helper_fn.run()` is a call on THAT value (numpy: `greater_equal.outer(...)`, a ufunc METHOD,
    # not numeric.py's free `outer`) and must NOT be narrowed onto target_mod.py's own `run`.
    assert_not_bound "$B" pkg/target_mod.py:run         uses_fromimport_member "from-import member is not the module ($L)"
    # rebind arms (issue #287 round 2, review rv-p6.md HIGH finding): each of these files re-binds the
    # alias name `tm` AFTER `import target_mod as tm` and BEFORE `tm.run(...)`, in one of the forms
    # capturePythonRebindShadowDecls now recognises — every one must refuse, the same as the pre-existing
    # parameter-shadow arm above (uses_shadowed).
    assert_not_bound "$B" pkg/target_mod.py:run         uses_rebind_assign    "rebind: plain local assignment ($L)"
    assert_not_bound "$B" pkg/target_mod.py:run         uses_rebind_module    "rebind: module-level reassignment ($L)"
    assert_not_bound "$B" pkg/target_mod.py:run         uses_rebind_for       "rebind: for-loop target ($L)"
    assert_not_bound "$B" pkg/target_mod.py:run         uses_rebind_with      "rebind: with-as target ($L)"
    assert_not_bound "$B" pkg/target_mod.py:run         uses_rebind_except    "rebind: except-as target ($L)"
    assert_not_bound "$B" pkg/target_mod.py:run         uses_rebind_walrus    "rebind: walrus target ($L)"
    assert_not_bound "$B" pkg/target_mod.py:run         uses_rebind_defshadow "rebind: nested def shadow ($L)"
    assert_not_bound "$B" pkg/target_mod.py:run         uses_rebind_global    "rebind: global statement elsewhere in file ($L)"
    # negative control: a DIFFERENT name's global rebind in the SAME file must NOT veto `tm` — the veto is
    # per-name, not "any rebind anywhere in the file poisons every alias in it".
    assert_bound     "$B" pkg/target_mod.py:run         uses_rebind_negctrl   "rebind negative control: unrelated name ($L)"
    # round-3 arms (issue #287 round 3, review rv-p6.md HIGH finding): a LATER `import ... as tm` whose
    # target is OUTSIDE the indexed tree (stdlib, third-party, or simply unknown) is still a REBINDING of
    # `tm` — "unresolved" must never read as "absent evidence" and let a stale earlier import keep winning.
    assert_not_bound "$B" pkg/target_mod.py:run         uses_rebind_outoftree  "rebind: later re-import to an out-of-tree module ($L)"
    assert_not_bound "$B" pkg/target_mod.py:run         uses_rebind_unresolved "rebind: later re-import to an unresolvable name ($L)"
    # regression-only (already correct before this round; documents it stays correct): both try/except
    # branches import `tm` from a DIFFERENT in-tree module each — genuinely ambiguous, must degrade on
    # EITHER candidate, never guess one arm.
    assert_not_bound "$B" pkg/target_mod.py:run         uses_rebind_tryexcept  "rebind: try/except fallback import, both in-tree ($L)"
    assert_not_bound "$B" pkg/sub/deep.py:run           uses_rebind_tryexcept  "rebind: try/except fallback import, both in-tree, other arm ($L)"
    # round-3 LOW (review rv-p6.md): a class-BODY rebind reaches no call site at all — Python method
    # bodies do not inherit their enclosing class body's scope — so it must neither veto this method NOR
    # any other function in the file; the alias narrow should bind normally here.
    assert_bound     "$B" pkg/target_mod.py:run         RebindClassBody.uses_rebind_classbody  "rebind: class-body assignment does not leak into its own method ($L)"
    # twin (QUALNAME-1): a method caller prints Owner.name, so the bare spelling is NO row — this proves the
    # exact-match probe above is a real exact check (it can only pass on the qualified row) and that the
    # alias still binds the method, not a stray bare `uses_rebind_classbody` function.
    assert_not_bound "$B" pkg/target_mod.py:run         uses_rebind_classbody  "rebind: class-body method row is Owner-qualified, never bare ($L)"
}

# ── the binary under test: every arm ────────────────────────────────────────────────────────────────
run_arms "$BIN" new

# ── monotonicity: a HEAD comparison binary ─────────────────────────────────────────────────────────
# NOT a one-time "prove issue #287 was broken" snapshot — headbinlib always builds from the CURRENT
# checkout's committed HEAD, so once this fix is itself committed, HEAD carries it too and a from-then-on
# run reads OLD == NEW on every arm (the true, permanent passing state; that is not a bug in the gate).
# The red-before/green-after PROOF for issue #287 is a one-time artifact, pasted in the lane report,
# captured by running this gate against origin/main BEFORE this fix's commit landed — a snapshot no
# in-tree gate can re-derive after the fact, the same reason pyimportprecisecheck.sh's own monotonic_check
# (this function's model) states a forward MONOTONICITY contract instead of a historical one.
#
# The contract going forward: whatever HEAD already binds, the binary under test must ALSO bind (a
# regression net — a future change that WEAKENS the alias narrow reds here); whatever HEAD refuses to
# bind, the binary under test must ALSO refuse (no new over-binding). Each arm is checked in whichever
# direction its own name promises, so the assertion text stays honest whether OLD's answer today is
# "bound" (the now-permanent case) or "not yet bound" (only possible re-running this exact gate against
# a pre-fix HEAD, which the report captures separately).
# The four monotonicity comparators below all read the same script-scope $OLDBIN (set by monotonic_check
# right before it calls any of them) — pulled out of monotonic_check's own body (--quality-delta flagged
# that function's verbosity once round 3's arms were added inline) rather than folded into one generic
# comparator: each name states its own OLD/NEW contract, which is the point of the whole file's assertion
# labels, and a single parameterised version would hide exactly that in a mode flag.
OLDBIN=""   # set by monotonic_check before any comparator below runs; empty means "not yet built"

# $1 target  $2 caller  $3 label — NEW must bind at least everywhere OLD does.
must_not_regress(){
    callers_out "$OLDBIN" "$1"
    if bound_in_last "$2"; then
        assert_bound "$BIN" "$1" "$2" "monotonicity ($3): HEAD already binds this, NEW must too"
    else
        skip "monotonicity ($3): HEAD does not (yet) bind $1 -> $2 — nothing to enforce this run"
    fi
}
# $1 target  $2 caller  $3 label — must stay UNBOUND on both (no new over-binding, ever).
must_stay_unbound(){
    assert_not_bound "$OLDBIN" "$1" "$2" "monotonicity ($3), old"
    assert_not_bound "$BIN"    "$1" "$2" "monotonicity ($3), new"
}
# $1 target  $2 caller  $3 label — a rebind arm whose committed HEAD, at whichever round found it,
# wrongly bound this: RED on that pre-fix binary, GREEN on the one under test. Once its own fix is
# itself committed HEAD carries the fix too and this converges to must_stay_unbound's shape; kept as
# its own helper so the RED half stays a real, dated assertion rather than silently reading as
# "nothing to prove" the moment it lands. Shared across rounds (round 2's 8 forms, round 3's
# out-of-tree/unresolved re-import) — the CONTRACT is identical, only which HEAD sha was pre-fix differs.
must_fix_rebind(){
    callers_out "$OLDBIN" "$1"
    if bound_in_last "$2"; then
        ok "RED on pre-fix HEAD ($3): $1 wrongly bound $2"
    else
        skip "($3): HEAD already refuses $1 -> $2 — this rebind fix is already on HEAD"
    fi
    assert_not_bound "$BIN" "$1" "$2" "rebind fix ($3), new"
}
# $1 target  $2 caller  $3 label — a precision fix for a SAFE over-refusal (review rv-p6.md LOW: a
# class-body rebind never reached the call site at all, so refusing it was conservative, never wrong).
# The permanent contract is just "the binary under test binds it correctly" (assert_bound on $BIN) — OLD's
# reading is reported but never asserted either way, because unlike a wrong-bind HIGH, OLD here was NEVER
# incorrect: before this round's fix OLD safely refused (informational only), and once this fix is itself
# committed HEAD OLD correctly binds too — asserting "OLD must refuse" would (and once did) go stale the
# moment the fix landed, the same lesson must_not_regress already encodes for the HIGH-class arms above.
must_fix_overrefusal(){
    callers_out "$OLDBIN" "$1"
    if bound_in_last "$2"; then
        ok "($3): pre-fix HEAD already binds $1 -> $2 too — this fix is already on HEAD"
    else
        ok "($3): pre-fix HEAD safely (over-)refused $1 -> $2, as it did before this precision fix landed"
    fi
    assert_bound "$BIN" "$1" "$2" "fix ($3), new"
}

# the monotonicity arms themselves — every target/caller/label triple, one comparator call each (see the
# four comparators above for what each name asserts). Split out of monotonic_check's own body so THAT
# function's setup (build OLDBIN, bail out cleanly) stays a stable, un-churned few lines across rounds —
# only this list grows as arms are added.
run_monotonic_arms()
{
    must_not_regress  pkg/target_mod.py:run        uses_module_alias   "alias"
    must_not_regress  pkg/sub/deep.py:run           uses_dotted_alias   "dotted alias"
    must_not_regress  pkgy/__init__.py:run          uses_pkg_alias      "package alias"
    must_not_regress  pkg/target_mod.py:run         uses_qualified      "qualified regression"
    must_not_regress  pkg/unique_mod.py:unique_only uses_unique_alias   "unique-name sanity"
    must_stay_unbound pkg/decoy_mod.py:run          uses_negative_alias "negative arm"
    must_stay_unbound pkg/target_mod.py:run         uses_shadowed       "local shadow"
    must_stay_unbound a2/samestem.py:run            uses_samestem_alias "ambiguous stem a"
    must_stay_unbound b2/samestem.py:run            uses_samestem_alias "ambiguous stem b"
    must_stay_unbound pkg/target_mod.py:run         uses_fromimport_member "from-import member"
    must_fix_rebind   pkg/target_mod.py:run         uses_rebind_assign    "plain local assignment"
    must_fix_rebind   pkg/target_mod.py:run         uses_rebind_module    "module-level reassignment"
    must_fix_rebind   pkg/target_mod.py:run         uses_rebind_for       "for-loop target"
    must_fix_rebind   pkg/target_mod.py:run         uses_rebind_with      "with-as target"
    must_fix_rebind   pkg/target_mod.py:run         uses_rebind_except    "except-as target"
    must_fix_rebind   pkg/target_mod.py:run         uses_rebind_walrus    "walrus target"
    must_fix_rebind   pkg/target_mod.py:run         uses_rebind_defshadow "nested def shadow"
    must_fix_rebind   pkg/target_mod.py:run         uses_rebind_global    "global statement elsewhere in file"
    must_not_regress  pkg/target_mod.py:run         uses_rebind_negctrl   "rebind negative control: unrelated name"
    must_fix_rebind      pkg/target_mod.py:run       uses_rebind_outoftree  "later re-import to an out-of-tree module"
    must_fix_rebind      pkg/target_mod.py:run       uses_rebind_unresolved "later re-import to an unresolvable name"
    must_stay_unbound    pkg/target_mod.py:run       uses_rebind_tryexcept  "try/except fallback import, both in-tree"
    must_stay_unbound    pkg/sub/deep.py:run         uses_rebind_tryexcept  "try/except fallback import, both in-tree, other arm"
    must_fix_overrefusal pkg/target_mod.py:run       RebindClassBody.uses_rebind_classbody  "class-body assignment does not leak into its own method"
}

monotonic_check()
{
    command -v git   >/dev/null 2>&1 || { skip "monotonicity: git absent"; return; }
    command -v cmake >/dev/null 2>&1 || { skip "monotonicity: cmake absent"; return; }
    ( cd "$ROOT" && git rev-parse --verify HEAD >/dev/null 2>&1 ) || { skip "monotonicity: not a git repo"; return; }

    OLDBIN="$( ripwire_head_binary "$ROOT" "$TMP" )" \
        || { headbin_refusal $? "monotonicity"; return; }

    run_monotonic_arms
}
monotonic_check

# ── multi-root cross-root safety (CodeRabbit PR #292 finding 4052087919) ──────────────────────────
# resolvePythonModuleSuffix (Step-A's absolute-spec fallback, resolve.h) used to scan the WHOLE
# fileIndex with no per-root restriction. In a merged multi-root workspace (`ripwire dir1 dir2 <verb>`)
# that let an import in one root bind to a same-named module in an UNRELATED root, with no import path
# or workspace configuration connecting them — Rule 2d (graph.h) then narrowed the bare-name candidates
# onto that cross-root file and emitted a call edge no evidence justified.
#
# Root A's caller imports `target_mod` (absolute spec) but root A itself has NO target_mod.py — Step-A's
# two direct bases (relative-to-file, relative-to-crawl-root) both miss, same as issue #287's own
# fixture. Root B, an UNRELATED root with no import path connecting it to A, happens to define
# `target_mod.py:run`. Root A also carries its own decoy `run` (decoy.py) so the callee name is NOT
# globally unique — without that, the bare-name ladder's own accidental-uniqueness win would bind
# correctly regardless of Rule 2d, and the cross-root defect would stay invisible (the same reason
# run_arms above needs a K>1 callee name, not issue #287's original K=1 sanity case).
MRA="$TMP/mroot_a"; MRB="$TMP/mroot_b"
mkdir -p "$MRA" "$MRB"
cat >"$MRA/caller.py" <<'PY'
import target_mod as tm

def uses_module_alias():
    return tm.run({})
PY
cat >"$MRA/decoy.py" <<'PY'
def run(x):
    return x
PY
cat >"$MRB/target_mod.py" <<'PY'
def run(x):
    return x
PY
_n=$(( _n + 1 )); "$BIN" "$MRA" "$MRB" --callers=target_mod.py:run --no-cache --legend=compact >"$TMP/o$_n" 2>/dev/null
if bound_in_last uses_module_alias; then
    no "multi-root: root A's caller wrongly bound to root B's UNRELATED target_mod.py:run (no import path connects the roots)"
    sed 's/^/        | /' "$TMP/o$_n"
else
    ok "multi-root: root A's caller does NOT bind root B's unrelated target_mod.py:run (no evidence-free cross-root edge)"
fi

# ── determinism + warm==cold (the fixture, binary under test) ─────────────────────────────────────
"$BIN" "$FIX" --no-cache >"$TMP/d1" 2>/dev/null
"$BIN" "$FIX" --no-cache >"$TMP/d2" 2>/dev/null
if cmp -s "$TMP/d1" "$TMP/d2"; then ok "deterministic (two --no-cache runs identical)"; else no "non-deterministic"; fi
"$BIN" "$FIX" --cache="$TMP/c.bin" >"$TMP/cold" 2>/dev/null
"$BIN" "$FIX" --cache="$TMP/c.bin" >"$TMP/warm" 2>/dev/null
if cmp -s "$TMP/cold" "$TMP/warm"; then ok "warm == cold (resolver order-stable through cache)"; else no "warm != cold"; fi

# ── well-formed XML ─────────────────────────────────────────────────────────────────────────────────
command -v xmllint >/dev/null 2>&1 \
  && { xmllint --noout "$TMP/d1" 2>/dev/null && ok "xml well-formed" || no "xml malformed"; } \
  || ok "xml well-formed (xmllint absent — skipped)"

[ "$fail" -eq 0 ] && echo "ALL PASS" || { echo "SOME CHECKS FAILED"; exit 1; }
