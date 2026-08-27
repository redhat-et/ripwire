#!/usr/bin/env bash
# shellgateindexcheck.sh — evidence-only shell gate dependencies in --test-gate.
#
# A shell gate invokes ripwire as a subprocess, so the compiled-language call graph cannot connect it to
# the source path it exercises. This gate fixes the contract around the replacement index:
#   * only gates registered by test/regression.sh are eligible;
#   * an exact path literal in executable shell text is script_literal evidence;
#   * `# RIPWIRE_TEST_DEPS: path[,path...]` is manifest_declared evidence for dynamic shell;
#   * equal basenames, comments and unregistered scripts are never evidence;
#   * the remaining dynamic gates stay disclosed rather than guessed.

set -u
ROOT="$( cd "$( dirname "$0" )/.." && pwd )"
BIN="${1:-${RIPWIRE_BIN:-$ROOT/build/ripwire}}"
[ "${BIN#/}" = "$BIN" ] && BIN="$ROOT/$BIN"
fail=0
ok(){ printf '  PASS  %s\n' "$*"; }
no(){ printf '  FAIL  %s\n' "$*"; fail=1; }

[ -x "$BIN" ] || { echo "no ripwire binary at $BIN — build first"; exit 2; }
echo "shellgateindexcheck: BIN=$BIN"

TMP="$( mktemp -d )"; trap 'rm -rf "$TMP"' EXIT
R="$TMP/repo"; mkdir -p "$R/src" "$R/test"
printf 'int literal_subject() { return 1; }\n' > "$R/src/literal.cpp"
printf 'int dynamic_subject() { return 2; }\n' > "$R/src/dynamic.cpp"
printf 'int unresolved_subject() { return 3; }\n' > "$R/src/unresolved.cpp"
printf 'int samebasename_subject() { return 4; }\n' > "$R/src/samebasename.cpp"

# Four registered gates: two mapped, two honestly unresolved. The manifest itself is literal evidence that
# these scripts are suite members; the unregistered script below must never become an obligation.
printf '%s\n' '#!/usr/bin/env bash' 'for _g in literalcheck dynamiccheck unresolvedcheck samebasename; do' \
       '    bash "test/${_g}.sh"' 'done' > "$R/test/regression.sh"
printf '%s\n' '#!/usr/bin/env bash' 'ripwire . --affected=src/literal.cpp' > "$R/test/literalcheck.sh"
printf '%s\n' '#!/usr/bin/env bash' '# RIPWIRE_TEST_DEPS: src/dynamic.cpp' \
       'target="$CHANGED_FILE"' 'ripwire . --affected="$target"' > "$R/test/dynamiccheck.sh"
printf '%s\n' '#!/usr/bin/env bash' 'target="$CHANGED_FILE"' \
       'ripwire . --affected="$target"' > "$R/test/unresolvedcheck.sh"
printf '%s\n' '#!/usr/bin/env bash' '# src/samebasename.cpp is commentary, not executable evidence' \
       'echo samebasename' > "$R/test/samebasename.sh"
printf '%s\n' '#!/usr/bin/env bash' 'ripwire . --affected=src/literal.cpp' > "$R/test/unregisteredcheck.sh"

run(){ perl -e 'alarm 25; exec @ARGV' "$BIN" "$R" "$@" --no-cache 2>/dev/null; }
rc(){ perl -e 'alarm 25; exec @ARGV' "$BIN" "$R" "$@" --no-cache >/dev/null 2>&1; printf '%s' "$?"; }

L="$( run --test-gate=src/literal.cpp )"; LRC="$( rc --test-gate=src/literal.cpp )"
case "$L" in
    *'<t p="'*'/test/literalcheck.sh" evidence="script_literal" run="bash '*'test/literalcheck.sh"/>'*)
        ok 'literal changed path maps to its registered shell gate with script_literal evidence and run=' ;;
    *) no "literal shell gate row missing/wrong: $L" ;;
esac
[ "$LRC" = 4 ] && ok 'literal shell gate is an exit-4 test obligation' || no "literal test-gate exit=$LRC (want 4)"
case "$L" in
    *unregisteredcheck.sh*) no 'unregistered script leaked into tests-to-run' ;;
    *) ok 'unregistered script is excluded even when it names the changed path' ;;
esac

D="$( run --test-gate=src/dynamic.cpp )"; DJ="$( run --test-gate=src/dynamic.cpp --json )"
case "$D" in
    *'<t p="'*'/test/dynamiccheck.sh" evidence="manifest_declared" run="bash '*'test/dynamiccheck.sh"/>'*)
        ok 'RIPWIRE_TEST_DEPS maps a dynamic gate with manifest_declared evidence' ;;
    *) no "metadata shell gate row missing/wrong: $D" ;;
esac
case "$DJ" in
    *'"p":"'*'/test/dynamiccheck.sh","evidence":"manifest_declared","run":"bash '*'test/dynamiccheck.sh"'*)
        ok 'JSON mirrors manifest_declared evidence and run command' ;;
    *) no "JSON metadata evidence missing/wrong: $DJ" ;;
esac

# The index-level disclosures describe the fixture as a whole, not just the selected changed path.
for OUT in "$L" "$D"; do
    case "$OUT" in
        *'script_gates_registered="4"'*'script_gates_mapped="2"'*'script_gates_unresolved_dynamic="2"'*'counts_floor="1"'*) : ;;
        *) no "shell gate disclosure missing/wrong: $OUT" ;;
    esac
done
[ "$fail" = 0 ] && ok 'registered=4 mapped=2 unresolved_dynamic=2 and counts_floor=1 disclosed' || :
case "$DJ" in
    *'"script_gates_registered":4'*'"script_gates_mapped":2'*'"script_gates_unresolved_dynamic":2'*'"counts_floor":true'*)
        ok 'JSON mirrors shell gate disclosure counts' ;;
    *) no "JSON shell gate disclosure missing/wrong: $DJ" ;;
esac

U="$( run --test-gate=src/unresolved.cpp )"
S="$( run --test-gate=src/samebasename.cpp )"
case "$U$S" in
    *unresolvedcheck.sh*|*samebasename.sh*) no 'dynamic/basename-only gate was guessed into an obligation' ;;
    *) ok 'unresolved dynamic and basename-only gates remain unmapped' ;;
esac

[ "$( run --test-gate=src/literal.cpp )" = "$L" ] \
    && ok 'shell gate index is deterministic (byte-identical run-to-run)' || no 'shell gate index is nondeterministic'
if command -v xmllint >/dev/null 2>&1; then
    printf '%s' "$L" | xmllint --noout - 2>/dev/null && ok 'shell-indexed --test-gate XML well formed' || no 'shell-indexed XML malformed'
fi

[ "$fail" = 0 ] && echo 'ALL PASS' || echo 'FAILURES ABOVE'
exit "$fail"
