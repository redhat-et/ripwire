#!/usr/bin/env bash
# narrowlangcheck.sh — is Rule-3 import/include narrowing (P2-D / Wave-1's importnarrowcheck.sh) actually
# LANGUAGE-AGNOSTIC, as its own doc comment in src/resolve.h claims ("works off the resolved include graph,
# basename-matched like --deps")? importnarrowcheck.sh proves it end-to-end on ONE language (C++, via
# #include "a.h"). This gate re-runs the IDENTICAL positive/included-only / negative/neither / negative/both
# fixture pattern on Python (a from-scratch language for Rule 3) to check whether the claim holds outside
# C++, and traces the failure to its root cause via --deps (which shares the same file-adjacency resolver,
# resolveIncludeAdj / fileIncludes in src/graph.h).
#
# ═══════════════════════════════════════════════════════════════════════════════════════════════════════
# REAL BUG FOUND (2026-07-03, ripwire HEAD 79d5918): Rule 3 silently NEVER fires on Python (or Go/Rust/
# JS/TS — see the probes below), even though --deps CORRECTLY prints the raw include target text and a
# human reading `--deps` output would reasonably assume the file graph resolved. Root cause, read directly
# from src/graph.h (resolveIncludeAdj, ~line 1022, and the near-identical fileIncludes builder ~line 236):
#
#     HashMap<std::string, ...> byBase;                      // keyed by ing.files[f] basename WITH extension
#     for f in files: byBase[ basename(ing.files[f]) ].push_back(f);      // e.g. "a.py", "a.go", "a.h"
#     ...
#     const auto it = byBase.find( basename(inc.target) );    // looked up by the RAW captured include text
#
# `inc.target` is captured in ingest.cpp::captureIncludes with per-node-type handling:
#   * C++ `preproc_include`        → the exact quoted/angled path, quotes/angles STRIPPED       → "a.h"    (matches "a.h" — WORKS)
#   * Python `import a`            → text after the "import " keyword, VERBATIM, no processing  → "a"      (byBase has "a.py" — MISS)
#   * Python `from a import x`     → text after "from ", VERBATIM                                → "a import helper" (MISS, worse)
#   * Go `import "fmt"`            → text after "import ", VERBATIM (quotes NOT stripped)        → "\"fmt\"" (byBase has "fmt.go" — MISS)
#   * Rust `use lib::helper;`      → text after "use ", VERBATIM (path separator NOT split)      → "lib::helper" (byBase has "lib.rs" — MISS)
#   * JS/TS `import {h} from './a'` → text after "import ", VERBATIM (whole clause kept)          → "{ helper } from './a'" (MISS, worse)
#
# So EVERY non-C++ language's import target fails the basename() lookup — either because the extension is
# absent (Python plain `import a` vs file "a.py"), the text still carries quotes/braces/keywords (Go, JS,
# TS), or a language path separator is left unsplit (Rust `::`). --deps' own afferent/cycle-detection view
# is affected identically (same resolver) — see the afferent=0 probe below, which is the same root cause
# manifesting one layer up. C++ is (accidentally) the only language whose raw AST target text already
# equals a real file basename.
#
# This gate does NOT invent a fix — it PINS the current (buggy) behavior with a loud "REAL BUG" label on
# each affected assertion, so: (a) the gate passes today (per the house rule that a landed-feature gate
# must pass on the binary under test), (b) a future fix flips these specific assertions, which is the
# intended signal to update this file, and (c) the failure mode is fully diagnosed inline for whoever picks
# it up (no re-investigation needed). Per the task brief: report it loudly with the repro rather than
# weakening the gate — done here via prominent comments AND a distinctive "REAL BUG" prefix on stdout.
# ═══════════════════════════════════════════════════════════════════════════════════════════════════════
#
# Fixtures:
#   test/importnarrowfix/         (Wave-1, C++, reused read-only)        — control: proves narrowing WORKS on C++
#   test/narrowlangfix/py/        (this gate, Python)                    — a.py/b.py both def helper();
#                                                                            caller.py imports only a.py (positive),
#                                                                            neither.py imports nothing (control),
#                                                                            both.py imports both (control)
#
# Usage:
#   test/narrowlangcheck.sh
#   RIPWIRE_BIN=asan/ripwire test/narrowlangcheck.sh
#
# Exits non-zero on any failure. Does NOT edit regression.sh or any existing test file.

set -u
ROOT="$( cd "$( dirname "$0" )/.." && pwd )"
BIN="${RIPWIRE_BIN:-$ROOT/build/ripwire}"
[ "${BIN#/}" = "$BIN" ] && BIN="$ROOT/$BIN"
CPPFIX="test/importnarrowfix"          # relative — so emitted p="..." paths match the C++ control's own gate style
PYFIX="test/narrowlangfix/py"
TMP="$( mktemp -d )"; trap 'rm -rf "$TMP"' EXIT
fail=0
bugs=0
ok(){ printf '  PASS  %s\n' "$*"; }
no(){ printf '  FAIL  %s\n' "$*"; fail=1; }
bug(){ printf '  REAL BUG (pinned, not asserted-correct)  %s\n' "$*"; bugs=$((bugs+1)); }

[ -x "$BIN" ] || { echo "no ripwire binary at $BIN — build first (cmake --build build -j)"; exit 2; }
cd "$ROOT"
[ -d "$CPPFIX" ] || { echo "no test/importnarrowfix directory"; exit 2; }
[ -d "$PYFIX" ]  || { echo "no test/narrowlangfix/py directory"; exit 2; }

echo "narrowlangcheck: BIN=$BIN  CPPFIX=test/importnarrowfix  PYFIX=test/narrowlangfix/py"

# ═══════════════════════════════════════════════════════════════════════════
echo
echo "=== CONTROL: C++ Rule-3 narrowing still works (importnarrowcheck.sh's own headline check) ==="
# ═══════════════════════════════════════════════════════════════════════════
CPP_MAP="$( "$BIN" "$CPPFIX" --no-cache 2>/dev/null )"
CPP_AMB="$( printf '%s' "$CPP_MAP" | grep -o 'ambiguous=[0-9]*' | head -1 | grep -o '[0-9]*' )"
[ "$CPP_AMB" = "2" ] && ok "C++ control: ambiguous=2 (Rule 3 narrows the positive caller, controls stay split)" \
                     || no "C++ control regressed: ambiguous=$CPP_AMB (want 2) — this should be unrelated to this gate; if it fails, importnarrowcheck.sh should ALSO be failing"

# ═══════════════════════════════════════════════════════════════════════════
echo
echo "=== --deps: does the file-adjacency resolver (Rule 3's dependency) resolve Python includes? ==="
# ═══════════════════════════════════════════════════════════════════════════
# Root-cause probe: caller.py imports a.py; if the resolver worked, a.py would show afferent >= 1 (someone
# depends on it) exactly like a.h shows afferent=2 in the C++ fixture. This isolates the bug to the shared
# resolveIncludeAdj/fileIncludes basename-matcher, independent of Rule 3's own logic.
CPP_DEPS="$( "$BIN" "$CPPFIX" --deps --no-cache 2>/dev/null )"
# RE-PINNED 2026-08-19 (R-E CORRECTION): p= is root-relative to the crawl root ($CPPFIX), so the row
# spells p="a.h", not the fixture-prefixed path this probe was written against.
printf '%s' "$CPP_DEPS" | grep -q 'p="a.h"[^/]*afferent="[1-9]' \
    && ok "C++ control: a.h shows afferent>=1 in --deps (adjacency resolver works on C++)" \
    || no "C++ control: a.h afferent count regressed to 0 — the resolver itself may be broken (unrelated to this gate's finding)"

PY_DEPS="$( "$BIN" "$PYFIX" --deps --no-cache 2>/dev/null )"
printf '%s' "$PY_DEPS" | grep -q 'p="caller.py"[^/]*<inc t="a"/>' \
    && ok "Python: --deps correctly captures the raw include text (t=\"a\") for caller.py" \
    || no "Python: --deps did not even capture the raw include text — investigate before the narrowing checks below"
if printf '%s' "$PY_DEPS" | grep -q 'p="test/narrowlangfix/py/a.py"[^/]*afferent="[1-9]'; then
    ok "Python: a.py shows afferent>=1 (adjacency resolver DOES resolve Python — narrowing checks below should then PASS as correct, not just pinned)"
    PY_ADJ_WORKS=1
else
    bug "Python: a.py shows afferent=0 (or no <f> entry) in --deps despite caller.py's 'import a' — the basename-match resolver never connects a.py's file id to the import (see the header comment for the exact code-level root cause: byBase keys carry the .py extension, inc.target for Python does not)"
    PY_ADJ_WORKS=0
fi

# ═══════════════════════════════════════════════════════════════════════════
echo
echo "=== Rule-3 narrowing on Python: same positive/negative pattern as the C++ control ==="
# ═══════════════════════════════════════════════════════════════════════════
PY_MAP="$( "$BIN" "$PYFIX" --no-cache 2>/dev/null )"
PY_AMB="$( printf '%s' "$PY_MAP" | grep -o 'ambiguous=[0-9]*' | head -1 | grep -o '[0-9]*' )"
echo "  (Python ambiguous=$PY_AMB — a WORKING Rule 3 would give 2 [both.py + neither.py stay split, like the C++ control]; a NON-firing Rule 3 gives 3 [caller.py ALSO stays split])"

PY_CE="$( "$BIN" "$PYFIX" --callees=call_included_only --no-cache 2>/dev/null )"
PY_CE_N="$( printf '%s' "$PY_CE" | grep -o 'count="[0-9]*"' | grep -o '[0-9]*' )"

if [ "$PY_ADJ_WORKS" = "1" ]; then
    # if a future fix makes the adjacency resolver work for Python, Rule 3 should narrow exactly like C++.
    [ "$PY_AMB" = "2" ] && ok "Python: ambiguous=2 — Rule 3 narrows call_included_only (adjacency now works, narrowing follows)" \
                        || no "Python: adjacency resolver works (afferent>=1) but Rule 3 STILL did not narrow (ambiguous=$PY_AMB, want 2) — a NEW, more specific bug in Rule 3 itself"
    [ "$PY_CE_N" = "1" ] && ok "Python: --callees=call_included_only narrowed to exactly 1 target" \
                         || no "Python: --callees=call_included_only still returns $PY_CE_N targets (want 1)"
else
    # LEVER-B UPDATE (2026-07): the narrowing bug is now FIXED, but the $PY_ADJ_WORKS proxy above still
    # reads 0 — deliberately. The fix (§B, resolve.h::resolvePythonImport)
    # made the RESOLVER's private include-set path-precise, while leaving the SEPARATE `--deps`
    # resolveIncludeAdj on the basename path (§3.5, `--deps` back-compat). So
    # `--deps` still shows a.py afferent=0 (→ $PY_ADJ_WORKS=0) even though the narrow now fires correctly.
    # The two signals DECOUPLED; assert the narrowing behavior DIRECTLY here (2/1 = fixed), independent of
    # the `--deps` proxy. The former "pinned buggy 3/2" state is now itself the failure trigger.
    if [ "$PY_AMB" = "2" ] && [ "$PY_CE_N" = "1" ]; then
        ok "Python: ambiguous=2, call_included_only narrows to 1 target — LEVER-B Python Step-A fires (a.py resolved path-precisely; b.py decoy rejected). See test/pyimportprecisecheck.sh for the full soundness gate."
    elif [ "$PY_AMB" = "3" ] && [ "$PY_CE_N" = "2" ]; then
        no "Python: REGRESSION — call_included_only stays AMBIGUOUS (amb=$PY_AMB callees=$PY_CE_N); the LEVER-B Python precise import resolver stopped firing (was fixed to 2/1)"
    else
        no "Python: unexpected ambiguity shape (amb=$PY_AMB callees=$PY_CE_N) — neither fixed (2/1) nor the old known-broken (3/2); investigate, do not assume"
    fi
fi

# negative controls MUST hold regardless of whether Rule 3 fires for the positive case — a call with 0 or
# >=2 candidate included files must NEVER incorrectly narrow (the "never a wrong narrow" contract is
# language-agnostic and does not depend on the adjacency-resolver bug above).
PY_NEITHER_CE="$( "$BIN" "$PYFIX" --callees=call_neither --no-cache 2>/dev/null | grep -o 'count="[0-9]*"' | grep -o '[0-9]*' )"
[ "$PY_NEITHER_CE" = "2" ] && ok "Python control: call_neither() keeps BOTH helper edges (2 — correctly stays ambiguous, no wrong narrow)" \
                           || no "Python control: call_neither() has $PY_NEITHER_CE callee(s) (want 2 — a wrong narrow would be worse than no narrow)"
PY_BOTH_CE="$( "$BIN" "$PYFIX" --callees=call_both --no-cache 2>/dev/null | grep -o 'count="[0-9]*"' | grep -o '[0-9]*' )"
[ "$PY_BOTH_CE" = "2" ] && ok "Python control: call_both() keeps BOTH helper edges (2 — correctly stays ambiguous on a tie, no wrong narrow)" \
                        || no "Python control: call_both() has $PY_BOTH_CE callee(s) (want 2)"

# ═══════════════════════════════════════════════════════════════════════════
echo
echo "=== cross-language adjacency probes (Go / Rust / JS-ES-import) — same root cause, quick confirmation ==="
# ═══════════════════════════════════════════════════════════════════════════
# These are lighter-weight probes (no full positive/negative fixture set) that show the SAME
# resolveIncludeAdj basename-mismatch bug hits Go, Rust, and JS/TS ES-style imports too, each via a
# DIFFERENT textual malformation (see the header comment). Scratch corpora built in TMP (not committed).
GO="$TMP/go"; mkdir -p "$GO"
cat > "$GO/a.go" <<'EOF'
package pkg
func Helper() int { return 1 }
EOF
cat > "$GO/caller.go" <<'EOF'
package main
import "a"
func CallIt() int { return Helper() }
EOF
GO_DEPS="$( cd "$GO" && "$BIN" . --deps --no-cache 2>/dev/null )"
if printf '%s' "$GO_DEPS" | grep -q 'p="./a.go"[^/]*afferent="[1-9]'; then
    ok "Go: adjacency resolver DOES resolve 'import \"a\"' -> a.go (afferent>=1) — no bug here"
else
    bug "Go: adjacency resolver does NOT resolve 'import \"a\"' -> a.go (quotes are not stripped from the Go import target before the basename lookup, unlike C++'s preproc_include path)"
fi

RS="$TMP/rs"; mkdir -p "$RS"
cat > "$RS/lib.rs" <<'EOF'
pub fn helper() -> i32 { 1 }
EOF
cat > "$RS/main.rs" <<'EOF'
use lib::helper;
fn main() { helper(); }
EOF
RS_DEPS="$( cd "$RS" && "$BIN" . --deps --no-cache 2>/dev/null )"
if printf '%s' "$RS_DEPS" | grep -q 'p="./lib.rs"[^/]*afferent="[1-9]'; then
    ok "Rust: adjacency resolver DOES resolve 'use lib::helper' -> lib.rs (afferent>=1) — no bug here"
else
    bug "Rust: adjacency resolver does NOT resolve 'use lib::helper' -> lib.rs (the '::method' suffix is not split off before the basename lookup)"
fi

JS="$TMP/js"; mkdir -p "$JS"
cat > "$JS/a.js" <<'EOF'
function helper() { return 1; }
module.exports = { helper };
EOF
cat > "$JS/caller.js" <<'EOF'
import { helper } from './a.js';
function callIt() { return helper(); }
EOF
JS_DEPS="$( cd "$JS" && "$BIN" . --deps --no-cache 2>/dev/null )"
if printf '%s' "$JS_DEPS" | grep -q 'p="./a.js"[^/]*afferent="[1-9]'; then
    ok "JS: adjacency resolver DOES resolve ES 'import { helper } from ./a.js' -> a.js (afferent>=1) — no bug here"
else
    bug "JS/TS: adjacency resolver does NOT resolve ES-module 'import { x } from ...' — the captured include target keeps the WHOLE clause text ('{ helper } from ./a.js'), never isolates the module path, so basename matching cannot possibly succeed"
fi

# ═══════════════════════════════════════════════════════════════════════════
echo
echo "=== determinism (the pinned-buggy Python behavior is at least stable, not flaky) ==="
# ═══════════════════════════════════════════════════════════════════════════
"$BIN" "$PYFIX" --no-cache >"$TMP/py1.xml" 2>/dev/null
"$BIN" "$PYFIX" --no-cache >"$TMP/py2.xml" 2>/dev/null
diff -q "$TMP/py1.xml" "$TMP/py2.xml" >/dev/null && ok "Python narrowlangfix map deterministic (byte-identical across runs)" || no "Python narrowlangfix map non-deterministic"

# ═══════════════════════════════════════════════════════════════════════════
echo
echo "=== MUTATION: prove the ambiguity-count assertions are load-bearing ==="
# ═══════════════════════════════════════════════════════════════════════════
MUT="$( ok(){ :; }; no(){ echo TRIPPED; }
        if [ "$PY_AMB" = "0" ]; then ok; else no; fi )"
[ "$MUT" = "TRIPPED" ] && ok "mutation self-test (asserting Python ambiguous=0 on the real \$PY_AMB correctly fails)" \
                       || no "mutation self-test broke — the ambiguous= assertion is not live"

MUT2="$( ok(){ :; }; no(){ echo TRIPPED; }
        if [ "$PY_NEITHER_CE" = "1" ]; then ok; else no; fi )"
[ "$MUT2" = "TRIPPED" ] && ok "mutation self-test (asserting call_neither has 1 callee when it really has 2 correctly fails)" \
                        || no "mutation self-test broke — the negative-control assertion is not live"

echo
echo "summary: $bugs known-and-pinned real bug(s) documented above (see header comment for full root-cause trace)."
[ "$fail" -eq 0 ] && echo "ALL PASS" || echo "SOME CHECKS FAILED"
exit "$fail"
