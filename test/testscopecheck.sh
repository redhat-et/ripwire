#!/usr/bin/env bash
# testscopecheck.sh — the test/non-test partition must not be PATH-ONLY.
#
# ── THE DEFECT THIS PINS ─────────────────────────────────────────────────────────────────────────────
# filter.h::isTestPath answers "is this a test?" from the FILE PATH alone (a `test/`/`tests/` dir
# segment, or a test_*/`*_test.*`/`*.spec.*` basename). Four mainstream conventions put test code
# INSIDE a production source file, where no path signal exists:
#
#   Rust    `#[cfg(test)] mod tests { … }` and `#[test] fn …` inside src/*.rs — the language's OWN
#           documented convention, so essentially every Rust crate is affected.
#   Python  `class TestFoo:` / `def test_bar():` in a module that also holds production defs.
#   JS/TS   `describe(…)` / `it(…)` / `test(…)` blocks with helper functions declared inside them.
#   C#      `[Fact]` / `[Test]` / `[TestMethod]` methods next to production classes.
#
# Measured on astral-sh/ruff (5945 files) before the fix: the #1-ranked symbol of the whole map was
# `CursorTest::builder`, a test helper inside `crates/ty_ide/src/lib.rs`, and `--ignore-tests` dropped
# 15,811 path-classified symbols WITHOUT changing the top-5 — because the top-5 were in-file tests
# that the path filter cannot see.
#
# ── THE RULE ─────────────────────────────────────────────────────────────────────────────────────────
# A syntactic, per-symbol `testScope` bit is computed at EXTRACTION (ingest.cpp) and OR'd with the
# path signal by the one shared predicate filter.h::isTestSymbol. Every consumer of the path signal
# that is SYMBOL-keyed reads the predicate instead:
#   · --ignore-tests            (filter.h applyIgnoreTests)  — the symbol is dropped
#   · the §P4 retrieval tier    (filter.h rankTierSymbolMultipliers) — the symbol is de-prioritized
#   · tested= / --seams reach   (graph.h testSeeds) — the symbol SEEDS coverage instead of receiving it
# --affected and --situ stay file-granular but recognise Rust test-only modules and exclude fixtures.
# --test-gate additionally recognises inline Rust tests and lists the runnable reader of changed fixture data.
#
# PRECISION OVER RECALL is the contract — a mis-marked production symbol vanishes from --ignore-tests
# output, which is strictly worse than missing a test. Arms 5-8 are the negative controls that pin it:
# a non-test `mod utils`, a Python `class Testament` (must NOT match `Test[A-Z_]`), a JS function
# literally named `describe_thing`, and an unattributed C# class next to an attributed method.
#
# ── ARMS ─────────────────────────────────────────────────────────────────────────────────────────────
#   0. PRESENCE   — the fixtures really do extract every symbol the arms below name (green-while-inert
#                   guard: an arm asserting the absence of a symbol that was never extracted is free).
#   1. RUST       — `#[cfg(test)] mod tests` members and `#[test] fn` (incl. `#[tokio::test]`) are gone
#                   under --ignore-tests; the file's real fn and its non-test `mod utils` survive.
#   2. PYTHON     — `class TestFoo` + its methods and a module-level `def test_bar` are gone; the real
#                   def survives.
#   3. TS/JS      — a helper declared inside a `describe(…)`/`it(…)` block is gone; the real exported
#                   function survives.
#   4. C#         — a `[Fact]`/`[Test]` method is gone; the production class and its method survive.
#   5-8. NEGATIVE — `mod utils`/`helper_in_utils`, `class Testament`/`compute`, `describe_thing`,
#                   `RealService`/`Compute` all SURVIVE --ignore-tests (no over-trigger).
#   9. TESTED=    — a production fn called ONLY from an in-file test now carries tested="1" on
#                   --metrics. Path-only classification could never see that caller, so this is the
#                   coverage half of the same bit.
#  10. TIER       — the §P4 retrieval de-prioritization applies: for a query naming a concept spelled
#                   IDENTICALLY in a production def and in an in-file test class's method, the
#                   production def ranks first.
#  11. NO-TEST PURITY — a corpus with no in-file test convention is byte-identical with and without
#                   the feature's reach (--ignore-tests on a fixture holding only production code
#                   equals the plain map).
#  12. HYGIENE   — two cold runs byte-identical (determinism), well-formed XML, warm == cold (the
#                   extraction change rides kParserVer, so a stale blob must not survive).
#  13. MOUNTS    — propagate test-only ownership through mod declarations; a production path wins.
#  14. GATE      — out-of-line and inline Rust tests run; changing data names the runnable reader.
#  15. FIXTURES  — fixture symbols never seed metrics coverage.
#
# Usage:
#   bash test/testscopecheck.sh
#   RIPWIRE_BIN=build/ripwire bash test/testscopecheck.sh
#
# Exits non-zero on any failure.

set -u
ROOT="$( cd "$( dirname "$0" )/.." && pwd )"
BIN="${1:-${RIPWIRE_BIN:-$ROOT/build/ripwire}}"
[ "${BIN#/}" = "$BIN" ] && BIN="$ROOT/$BIN"
TMP="$( mktemp -d )"; trap 'rm -rf "$TMP"' EXIT
fail=0

ok(){ printf '  PASS  %s\n' "$*" || { fail=1; printf '  FAIL  could not write the PASS line for: %s\n' "$*"; }; return 0; }
no(){   printf '  FAIL  %s\n' "$*"; fail=1; }

[ -x "$BIN" ] || { echo "no ripwire binary at $BIN — build first (cmake --build build -j)"; exit 2; }
command -v xmllint >/dev/null 2>&1 || { echo "xmllint required"; exit 2; }
echo "testscopecheck: BIN=$BIN  TMP=$TMP"

# ── fixtures ─────────────────────────────────────────────────────────────────────────────────────────
# NOTE: every fixture lives under `src/`, and no basename carries a test_/_test./.spec. marker — so the
# EXISTING path classifier sees production code everywhere here. Anything this gate observes being
# treated as a test is therefore attributable to the in-file signal and to nothing else.
FIX="$TMP/fix/src"; mkdir -p "$FIX"

cat > "$FIX/a.rs" <<'EOF'
pub fn real_function( x: i32 ) -> i32
{
    x + 1
}

pub mod utils
{
    pub fn helper_in_utils() -> u32
    {
        7
    }
}

#[cfg(test)]
mod tests
{
    pub fn cursor_builder() -> u32
    {
        0
    }

    #[test]
    fn it_adds()
    {
        let _v = real_function( 1 );
    }
}

#[test]
fn top_level_test_fn()
{
    let _v = real_function( 2 );
}

#[tokio::test]
async fn async_test_fn()
{
    let _v = real_function( 3 );
}
EOF

cat > "$FIX/b.py" <<'EOF'
def real_helper( x ):
    return x + 1

def compute_widget_layout( grid ):
    return real_helper( grid )

class Testament:
    def compute( self ):
        return real_helper( 1 )

class TestFoo:
    def check_one( self ):
        return real_helper( 1 )

    def compute_widget_layout( self ):
        return real_helper( 2 )

def test_bar():
    return real_helper( 3 )
EOF

cat > "$FIX/c.ts" <<'EOF'
export function realFunction( x: number ): number
{
    return x + 1;
}

function describe_thing( y: number ): number
{
    return realFunction( y );
}

describe( "suite", () => {
    function innerHelper(): number
    {
        return realFunction( 3 );
    }
    it( "works", () => {
        const v = innerHelper();
        return v;
    } );
} );
EOF

cat > "$FIX/d.cs" <<'EOF'
public class RealService
{
    public int Compute( int x )
    {
        return x + 1;
    }
}

public class ServiceTests
{
    [Fact]
    public void ComputeWorks()
    {
        var s = new RealService();
    }

    [Test]
    public void AnotherOne()
    {
        var s = new RealService();
    }
}
EOF

# A production-only corpus for arm 11 (no in-file test convention anywhere).
PURE="$TMP/pure/src"; mkdir -p "$PURE"
cat > "$PURE/p.rs" <<'EOF'
pub fn only_production( x: i32 ) -> i32
{
    x + 1
}

pub mod utils
{
    pub fn helper() -> u32
    {
        7
    }
}
EOF

MAP="$TMP/map.xml"
IGN="$TMP/ignore.xml"
"$BIN" "$TMP/fix" > "$MAP" 2>/dev/null
"$BIN" "$TMP/fix" --ignore-tests > "$IGN" 2>/dev/null

# n="NAME" presence helpers. The map is minified single-line XML, so a literal attribute match is the
# whole test — no parsing needed, and a name can never straddle a line break.
has(){ grep -q "n=\"$1\"" "$2"; }

# ── arm 0: PRESENCE ──────────────────────────────────────────────────────────────────────────────────
missing=""
for s in real_function utils helper_in_utils tests cursor_builder it_adds top_level_test_fn async_test_fn \
         real_helper compute_widget_layout Testament compute TestFoo check_one test_bar \
         realFunction describe_thing innerHelper \
         RealService Compute ServiceTests ComputeWorks AnotherOne
do
    has "$s" "$MAP" || missing="$missing $s"
done
if [ -z "$missing" ]; then ok "arm0 presence: every fixture symbol is extracted in the plain map"
else no "arm0 presence: plain map is MISSING:$missing (the arms below would be vacuously green)"; fi

# ── arms 1-4: the in-file test symbols are DROPPED by --ignore-tests ──────────────────────────────────
armdrop(){   # $1=label  $2..=names that must be ABSENT from --ignore-tests output
    local label="$1"; shift
    local bad=""
    for s in "$@"; do has "$s" "$IGN" && bad="$bad $s"; done
    if [ -z "$bad" ]; then ok "$label: in-file test symbols dropped by --ignore-tests"
    else no "$label: --ignore-tests KEPT in-file test symbols:$bad"; fi
}
armkeep(){   # $1=label  $2..=names that must SURVIVE --ignore-tests
    local label="$1"; shift
    local bad=""
    for s in "$@"; do has "$s" "$IGN" || bad="$bad $s"; done
    if [ -z "$bad" ]; then ok "$label: production symbols survive --ignore-tests"
    else no "$label: --ignore-tests DROPPED production symbols:$bad"; fi
}

armdrop "arm1 rust"   tests cursor_builder it_adds top_level_test_fn async_test_fn
armkeep "arm1 rust"   real_function
armdrop "arm2 python" TestFoo check_one test_bar
armkeep "arm2 python" real_helper
armdrop "arm3 ts"     innerHelper
armkeep "arm3 ts"     realFunction
armdrop "arm4 csharp" ComputeWorks AnotherOne
armkeep "arm4 csharp" RealService Compute

# ── arms 5-8: NEGATIVE controls — no over-trigger ────────────────────────────────────────────────────
armkeep "arm5 negative rust"   utils helper_in_utils
armkeep "arm6 negative python" Testament compute
armkeep "arm7 negative ts"     describe_thing
armkeep "arm8 negative csharp" ServiceTests

# ── arm 9: tested= — an in-file test SEEDS coverage ──────────────────────────────────────────────────
# real_function's only callers are the #[test] fns; real_helper's only test caller is TestFoo::check_one
# / test_bar; realFunction is reached from innerHelper (inside describe). Path-only classification sees
# no test in this corpus at all, so tested= can only appear if the in-file bit reached graph.h.
MET="$TMP/metrics.xml"
"$BIN" "$TMP/fix" --metrics > "$MET" 2>/dev/null
testedrow(){   # $1=symbol name → prints its <s …> row
    tr '<' '\n' < "$MET" | grep "n=\"$1\"" | head -1
}
bad=""
for s in real_function real_helper realFunction; do
    printf '%s' "$( testedrow "$s" )" | grep -q 'tested="1"' || bad="$bad $s"
done
if [ -z "$bad" ]; then ok "arm9 tested=: in-file tests seed the coverage partition"
else no "arm9 tested=: production symbols reached ONLY from an in-file test lack tested=\"1\":$bad"; fi
# and the negative half: the test symbols themselves are seeds, never coverage rows
if printf '%s' "$( testedrow "check_one" )" | grep -q 'tested="1"'; then
    no "arm9 tested=: an in-file TEST symbol (check_one) was itself marked tested=\"1\" (seeds are not rows)"
else ok "arm9 tested=: in-file test symbols are seeds, not coverage rows"; fi

# ── arm 10: §P4 retrieval tier — an in-file test loses a tie it used to win ──────────────────────────
# Two src/ files carrying the SAME doc-comment evidence for the query, one inside a `#[cfg(test)] mod`.
# Measured against the pre-feature binary: the scaffold file ranked FIRST (ties break its way — its
# def carries fewer competing tokens). Nothing but the §P4 tier factor can flip that, so this arm is a
# real discriminator and not a restatement of the ranker's default order. The filenames are chosen
# aaa_/zzz_ so a lexicographic fallback would ALSO put the scaffold first — a stub that ignored the
# ranking entirely cannot pass.
TIER="$TMP/tier/src"; mkdir -p "$TIER"
cat > "$TIER/aaa_scaffold.rs" <<'EOF'
#[cfg(test)]
mod tests
{
    /// Quantize the audio buffer.
    pub fn scaffold_entry( n: u32 ) -> u32
    {
        n
    }
}
EOF
cat > "$TIER/zzz_production.rs" <<'EOF'
/// Quantize the audio buffer.
pub fn production_entry( n: u32 ) -> u32
{
    n
}
EOF
topfile="$( "$BIN" "$TMP/tier" --for="quantize the audio buffer" 2>/dev/null | tr '<' '\n' | grep -o 'p="[^"]*\.rs"' | head -1 )"
case "$topfile" in
    *zzz_production.rs*) ok "arm10 tier: the in-file test scaffold is de-prioritized below equal production evidence" ;;
    *aaa_scaffold.rs*)   no "arm10 tier: an in-file test scaffold still outranks equal production evidence ($topfile)" ;;
    *)                   no "arm10 tier: --for named no .rs file at all (cannot judge the tier): '$topfile'" ;;
esac

# ── arm 10b: --affected stays file-granular ──────────────────────────────────────────────────────────
# An inline #[cfg(test)] module on its own does not make its production file a runnable test file.
# --test-gate separately reports inline Rust tests (arm 14).
AFF="$( "$BIN" "$TMP/fix" --affected=src/a.rs 2>/dev/null )"
if printf '%s' "$AFF" | tr '<' '\n' | grep -q 't p="src/a\.rs"'; then
    no "arm10b scope: --affected named the src file itself as a test to run (the in-file bit leaked into the file-keyed verbs)"
else ok "arm10b scope: --affected does not name a src/ file as a test to run"; fi

# ── arm 11: NO-TEST PURITY ───────────────────────────────────────────────────────────────────────────
"$BIN" "$TMP/pure" > "$TMP/pure_plain.xml" 2>/dev/null
"$BIN" "$TMP/pure" --ignore-tests > "$TMP/pure_ign.xml" 2>/dev/null
if diff -q "$TMP/pure_plain.xml" "$TMP/pure_ign.xml" >/dev/null 2>&1; then
    ok "arm11 purity: a production-only corpus is byte-identical with and without --ignore-tests"
else no "arm11 purity: --ignore-tests changed a corpus that holds NO test convention (over-trigger)"; fi

# ── arm 12: HYGIENE ──────────────────────────────────────────────────────────────────────────────────
rm -rf "$TMP/fix/.ripwire_cache" 2>/dev/null
"$BIN" "$TMP/fix" --no-cache > "$TMP/cold1.xml" 2>/dev/null
"$BIN" "$TMP/fix" --no-cache > "$TMP/cold2.xml" 2>/dev/null
if diff -q "$TMP/cold1.xml" "$TMP/cold2.xml" >/dev/null 2>&1; then ok "arm12 determinism: two cold runs byte-identical"
else no "arm12 determinism: two cold runs differ"; fi
if xmllint --noout "$IGN" 2>/dev/null; then ok "arm12 well-formed: --ignore-tests output parses"
else no "arm12 well-formed: --ignore-tests output is not well-formed XML"; fi
# warm == cold: a blob written by a pre-feature binary must be invalidated by the kParserVer bump. The
# second run below reads the cache the first one wrote.
"$BIN" "$TMP/fix" --ignore-tests > "$TMP/warm.xml" 2>/dev/null
if diff -q "$IGN" "$TMP/warm.xml" >/dev/null 2>&1; then ok "arm12 warm==cold: cached extraction agrees with the fresh parse"
else no "arm12 warm==cold: a warm run disagrees with the cold run (cache key missed the extraction change)"; fi

# Rust ownership: a cfg(test) mount propagates to an out-of-line helper, but a production mount wins.
# Source-shaped data is never a test root; even a symbol-free input must name the test that reads it.
RUST_MOUNTS="$TMP/rust-mounts"
mkdir -p "$RUST_MOUNTS/src/checks" "$RUST_MOUNTS/src/testdata"
cat > "$RUST_MOUNTS/Cargo.toml" <<'EOF'
[package]
name = "rust-mounts"
version = "0.1.0"
edition = "2021"
EOF
cat > "$RUST_MOUNTS/src/lib.rs" <<'EOF'
mod anchor;
mod fixture_anchor;
mod shared;
#[cfg(test)]
mod checks;
mod inline_anchor;
#[cfg(test)]
mod tests {
    #[test]
    fn inline_regression() { crate::inline_anchor::inline_anchor(); }
}
EOF
printf 'pub fn production_anchor() {}\n' > "$RUST_MOUNTS/src/anchor.rs"
printf 'pub fn inline_anchor() {}\n' > "$RUST_MOUNTS/src/inline_anchor.rs"
printf 'pub fn fixture_only_anchor() {}\n' > "$RUST_MOUNTS/src/fixture_anchor.rs"
printf 'pub fn dual_mount_helper() {}\n' > "$RUST_MOUNTS/src/shared.rs"
cat > "$RUST_MOUNTS/src/checks.rs" <<'EOF'
mod nested;
#[path = "shared.rs"]
mod shared;
use crate::anchor::production_anchor;
use std::{fs, path::Path};
#[test]
fn checks_anchor() {
    production_anchor();
    // A comment argument and a join chain past the old twelve-call depth limit still name the fixture directory.
    let _ = fs::read_dir(/* fixtures */ Path::new(env!("CARGO_MANIFEST_DIR")).join(".").join(".").join(".").join(".").join(".").join(".").join(".").join(".").join(".").join(".").join(".").join(".").join(".").join("src/testdata"));
}
EOF
printf 'pub fn mounted_helper() {}\n' > "$RUST_MOUNTS/src/checks/nested.rs"
printf 'use crate::fixture_anchor::fixture_only_anchor;\n#[test]\nfn not_a_runnable_case() { fixture_only_anchor(); }\n' > "$RUST_MOUNTS/src/testdata/golden.rs"
printf '// Source-shaped fixture with no symbols.\n' > "$RUST_MOUNTS/src/testdata/empty.rs"
if "$BIN" "$RUST_MOUNTS" --ignore-tests --no-cache > "$TMP/rust_mounts.xml" 2>/dev/null \
    && grep -q 'n="dual_mount_helper"' "$TMP/rust_mounts.xml" \
    && ! grep -Eq 'n="(mounted_helper|checks_anchor|not_a_runnable_case)"' "$TMP/rust_mounts.xml"; then
    ok "arm13 Rust mounts: test-only modules and fixture definitions are filtered, dual mounts survive"
else no "arm13 Rust mounts: bad production-only partition"; fi
if python3 - "$BIN" "$RUST_MOUNTS" <<'PY'
import json
import subprocess
import sys
import xml.etree.ElementTree as ET

binary, root = sys.argv[1:]
for cold in (True, False, False):
    for path, expected in (
        ("src/anchor.rs", "src/checks.rs"),
        ("src/inline_anchor.rs", "src/lib.rs"),
        ("src/lib.rs", "src/lib.rs"),
        ("src/testdata/golden.rs", "src/checks.rs"),
        ("src/testdata/empty.rs", "src/checks.rs"),
    ):
        cmd = [binary, root, f"--test-gate={path}"]
        if cold:
            cmd.append("--no-cache")
        p = subprocess.run([*cmd, "--json"], capture_output=True, text=True, timeout=15)
        assert p.returncode == 4, (path, p.returncode, p.stdout, p.stderr)
        gate = json.loads(p.stdout)
        rows = gate["tests_to_run"]
        paths = [name for row in rows for name in (row["p"] if isinstance(row["p"], list) else [row["p"]])]
        if path == "src/lib.rs":
            assert any(row["p"] == expected and row.get("changed") is True for row in rows), gate
        else:
            assert paths == [expected] and gate["untested"] == 0, (path, gate)
        is_fixture = path.startswith("src/testdata/")
        assert any(row.get("fixture_reader") is True for row in rows) == is_fixture, (path, gate)
        if is_fixture:
            xml = subprocess.run(cmd, capture_output=True, text=True, timeout=15)
            assert xml.returncode == 4, xml
            report = ET.fromstring("<doc>" + xml.stdout + "</doc>").find("test-gate")
            assert report.find("t[@fixture_reader='1']") is not None, xml.stdout
# A fixture reader with no call path sorts after the hops=1 rows, so run_first= still marks the direct test.
p = subprocess.run([binary, root, "--test-gate=src/testdata/empty.rs,src/inline_anchor.rs", "--json", "--no-cache"],
                   capture_output=True, text=True, timeout=15)
assert p.returncode == 4, (p.returncode, p.stdout, p.stderr)
gate = json.loads(p.stdout)
rows = gate["tests_to_run"]
assert [row["p"] for row in rows] == ["src/lib.rs", "src/checks.rs"] and rows[1].get("fixture_reader") is True, gate
assert gate.get("run_first") == 1, gate
PY
then ok "arm14 Rust gate: inline tests, test modules and fixture readers survive cache replay"
else no "arm14 Rust gate: wrong test owner or evidence"; fi

MET="$TMP/rust_mount_metrics.xml"
"$BIN" "$RUST_MOUNTS" --metrics --no-cache > "$MET" 2>/dev/null
fixture_row="$( testedrow fixture_only_anchor )"
if [ -n "$fixture_row" ] && ! grep -q 'tested="1"' <<<"$fixture_row" \
    && grep -q 'tested="1"' <<<"$( testedrow production_anchor )"; then
    ok "arm15 Rust fixture syntax cannot seed metrics coverage; its runnable test still can"
else no "arm15 Rust fixture coverage contaminated the tested partition: $fixture_row"; fi

echo
[ "$fail" -eq 0 ] && echo "testscopecheck: ALL PASS" || echo "testscopecheck: FAILURES"
exit "$fail"
