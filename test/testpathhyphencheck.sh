#!/usr/bin/env bash
# testpathhyphencheck.sh — filter.h::isTestPath reads the HYPHEN test-name forms from an ALLOWLIST (#466, #472 by @lennix1337).
#
# THE CONTRACT THIS PINS. Every verb shares isTestPath, so a false match hides real source from --ignore-tests and demotes it in --for.
# The bare hyphen forms (`test-*`, `*-test.*`, `*-spec.*`) match shipped source (`attest-spec.ts`, `pod-spec.ts`, `ab-test.ts`,
# `self-test.c`, `test-and-set.c`, zone.js's `async-test.ts`), so only these hyphen forms read as tests:
#   - `test-*` / `*-test.*` when the name ends .sh .bash .zsh .ps1 .bat (shell and batch test scripts, the #466 `test-document-remind.sh`)
#   - `.e2e-spec.` and `.perf-spec.` in any extension (Nest / Angular suffixes)
#
# Eight one-function files, each defining the word pair `widget probe`; `--ignore-tests --for='widget probe'` lists the survivors.
#   A0 [G] presence: without --ignore-tests all nine files answer (an absence arm below is not free while a file is never extracted)
#   A1 [P] RED on the pre-change binary: cats.e2e-spec.ts, test-widget.sh and widget-test.sh are hidden under --ignore-tests
#   A2 [P] RED on the PR hunk as first written (bare test- / -test. / -spec.): ab-test.ts, attest-spec.ts, pod-spec.ts, self-test.c and
#          test-and-set.c stay visible under --ignore-tests
# A1 and A2 are the mutant pair: dropping the allowlist fails A1, widening it back to the bare forms fails A2.
#
# Usage:  bash test/testpathhyphencheck.sh [BIN]   |   RIPWIRE_BIN=asan/ripwire bash test/testpathhyphencheck.sh
# BIN is $1, else RIPWIRE_BIN, else build/ripwire; the first output line names the binary used. Exits non-zero on any failure.

set -u
ROOT="$( cd "$( dirname "$0" )/.." && pwd )"
. "$ROOT/test/lib/clean-env.sh"
BIN="${1:-${RIPWIRE_BIN:-$ROOT/build/ripwire}}"
[ "${BIN#/}" = "$BIN" ] && BIN="$ROOT/$BIN"
echo "testpathhyphencheck: BIN=$BIN"
fail=0
ok(){ printf '  PASS  %s\n' "$*" || { fail=1; printf '  FAIL  could not write the PASS line for: %s\n' "$*"; }; return 0; }
no(){ printf '  FAIL  %s\n' "$*"; fail=1; }
[ -x "$BIN" ] || { echo "no ripwire binary at $BIN — build first"; exit 2; }

T="$( mktemp -d "${TMPDIR:-/tmp}/testpathhyphen.XXXXXX" )" || exit 2
trap '[ -n "${TESTPATHHYPHEN_KEEP:-}" ] || rm -rf "$T"' EXIT
H="$T/home"; mkdir -p "$H" "$T/fx/src"

# ── fixtures (runtime, never under a .gitignored path) ─────────────
for f in ab-test.ts attest-spec.ts cats.e2e-spec.ts pod-spec.ts; do
    printf 'export function widgetProbe(){ return 1; }\n' > "$T/fx/src/$f"
done
for f in self-test.c test-and-set.c; do
    printf 'int widget_probe(void){return 1;}\n' > "$T/fx/src/$f"
done
for f in test-widget.sh widget-test.sh test-upper.SH; do
    printf 'widget_probe() { echo ok; }\n' > "$T/fx/src/$f"
done
HIDDEN="cats.e2e-spec.ts test-widget.sh widget-test.sh test-upper.SH"
SHOWN="ab-test.ts attest-spec.ts pod-spec.ts self-test.c test-and-set.c"

# run FAILS the gate when the binary exits non-zero: an absence arm reads the capture, and a crashed run leaves it empty
run(){ ( cd "$T/fx" || exit 1; HOME="$H" TMPDIR="$T/" "$BIN" "$T/fx" --no-cache "$@" < /dev/null 2>/dev/null ) || no "ripwire exited non-zero: $*"; }
has(){ grep -qF -- "p=\"src/$2\"" "$1"; }

run --for='widget probe' > "$T/all.xml"
run --ignore-tests --for='widget probe' > "$T/ign.xml"

# A0: presence
miss=""
for f in $HIDDEN $SHOWN; do has "$T/all.xml" "$f" || miss="$miss $f"; done
if [ -z "$miss" ]; then ok "A0 presence: all nine files answer without --ignore-tests"
else no "A0 presence: no row for:$miss (the arms below would be inert)"; fi

# the --ignore-tests capture must be a real answer before any absence arm reads it
if [ -s "$T/ign.xml" ] && grep -q 'p="src/' "$T/ign.xml"; then ok "A0 --ignore-tests answers (non-empty, carries rows)"
else no "A0 --ignore-tests answered nothing — the absence arms would pass for free"; fi

# A1: the allowlisted forms are tests
left=""
for f in $HIDDEN; do has "$T/ign.xml" "$f" && left="$left $f"; done
if [ -z "$left" ]; then ok "A1 hidden under --ignore-tests: $HIDDEN"
else no "A1 still visible under --ignore-tests (read as source):$left"; fi

# A2: the near-misses stay source
gone=""
for f in $SHOWN; do has "$T/ign.xml" "$f" || gone="$gone $f"; done
if [ -z "$gone" ]; then ok "A2 shown under --ignore-tests: $SHOWN"
else no "A2 hidden under --ignore-tests (false test match on shipped source):$gone"; fi

[ "$fail" -eq 0 ] && echo "testpathhyphencheck: PASS" || echo "testpathhyphencheck: FAIL"
exit "$fail"
