#!/usr/bin/env bash
# qdtestdeadcheck.sh — QD-TEST-DEAD gate: --quality-delta's dead-code kind must not report a NEW Go or Rust test, which its
# language's test runner calls with no call in the tree (quality.h testRunnerInvokedSymbol).
#
# Found by the P5 seeded-defect pilot (2026-11-10): every seeded Go `func TestX(t *testing.T)` in a `_test.go` file (4/4) and
# every Rust `#[cfg(test)] mod` with a `#[test]` fn (2/2, plus the module itself) printed a dead-code row, while the same test in
# Python or TypeScript printed none. The Python rule (pythonFrameworkInvokedSymbol) is name-level inside a test module; the Go
# rule is too (`go test` naming in a `_test.go` file), and Rust's is its test attribute (the in-file testScope bit).
#
#   (a) Go: TestX, BenchmarkX, ExampleX, FuzzX, TestMain and Test_x added to a _test.go file report no dead-code row.
#   (b) Go controls: `Testify` (a lowercase letter after the prefix is no test), an unused helper in the _test.go file and a
#       TestInProd in a production file still report dead-code — the rule is the runner's, not "anything in a test file".
#   (c) Rust: a `#[cfg(test)] mod` with a `#[test]` fn, and a `#[test]` fn in tests/, report no dead-code row.
#   (d) Rust control: a new unused private fn in production code still reports dead-code.
#   (e) the run exits 0 (dead-code rows on new symbols never gate, so this pins no gating side effect).
#
# Usage: test/qdtestdeadcheck.sh [BIN]   (default build/ripwire). Red before the fix: (a) and (c) fail.
set -u
ROOT="$( cd "$( dirname "$0" )/.." && pwd )"
. "$ROOT/test/lib/clean-env.sh"
BIN="${1:-${RIPWIRE_BIN:-$ROOT/build/ripwire}}"
[ "${BIN#/}" = "$BIN" ] && BIN="$ROOT/$BIN"
[ -x "$BIN" ] || { echo "no ripwire binary at $BIN — build first"; exit 2; }
TMP="$( mktemp -d )"; trap 'rm -rf "$TMP"' EXIT
export TMPDIR="$TMP/cache"; mkdir -p "$TMPDIR"
fail=0
ok(){ printf '  PASS  %s\n' "$*"; }
no(){ printf '  FAIL  %s\n' "$*"; fail=1; }
echo "qdtestdeadcheck: BIN=$BIN"

R="$TMP/repo"; mkdir -p "$R/golib" "$R/src" "$R/tests"
cat > "$R/go.mod" <<'EOF'
module example.com/golib

go 1.22
EOF
cat > "$R/golib/lib.go" <<'EOF'
package golib

func Used() int { return 1 }
EOF
cat > "$R/golib/lib_test.go" <<'EOF'
package golib

import "testing"

func TestUsed(t *testing.T) {
	if Used() != 1 {
		t.Fatal("bad")
	}
}
EOF
cat > "$R/src/lib.rs" <<'EOF'
pub fn used() -> i32 {
    1
}
EOF
( cd "$R" && git init -q && git add -A && git -c user.name=t -c user.email=t@t commit -qm base ) || { echo "git setup failed"; exit 2; }

cat >> "$R/golib/lib_test.go" <<'EOF'

func TestNewThing(t *testing.T) {
	if Used() != 1 {
		t.Fatal("bad")
	}
}

func Test_underscored(t *testing.T) {
	if Used() != 1 {
		t.Fatal("bad")
	}
}

func BenchmarkNewThing(b *testing.B) {
	for i := 0; i < b.N; i++ {
		Used()
	}
}

func ExampleUsed() {
	println(Used())
}

func FuzzNewThing(f *testing.F) {
	f.Fuzz(func(t *testing.T, n int) {
		Used()
	})
}

func TestMain(m *testing.M) {
	m.Run()
}

func Testify() int {
	return Used() + 1
}

func helperUnused() int {
	return Used() + 2
}
EOF
cat >> "$R/golib/lib.go" <<'EOF'

func TestInProd() int { return Used() + 3 }
EOF
cat >> "$R/src/lib.rs" <<'EOF'

fn unused_prod() -> i32 {
    used() + 1
}

#[cfg(test)]
mod qd_new_tests {
    use super::*;

    #[test]
    fn used_works() {
        assert_eq!(used(), 1);
    }
}
EOF
cat > "$R/tests/integration.rs" <<'EOF'
#[test]
fn integration_works() {
    assert_eq!(1 + 1, 2);
}
EOF
( cd "$R" && git add -A && git -c user.name=t -c user.email=t@t commit -qm tests ) || { echo "git commit failed"; exit 2; }

OUT="$TMP/out.xml"
"$BIN" "$R" --quality-delta=HEAD~1..HEAD --legend=compact >"$OUT" 2>"$TMP/err"; rc=$?
DEAD="$( tr '<' '\n' <"$OUT" | grep '^r kind="dead-code"' | sed 's/.* sym="\([^"]*\)".*/\1/' | sed 's/.*:://' | sort )"
echo "  dead-code rows: $( echo $DEAD )"
has(){ printf '%s\n' "$DEAD" | grep -qx "$1"; }

for t in TestNewThing Test_underscored BenchmarkNewThing ExampleUsed FuzzNewThing TestMain; do
    has "$t" && no "(a) Go test-runner entry $t reported dead-code" || ok "(a) Go test-runner entry $t is not dead-code"
done
for t in Testify helperUnused TestInProd; do
    has "$t" && ok "(b) Go control $t still reported dead-code" || no "(b) Go control $t lost its dead-code row (rule too wide)"
done
for t in used_works qd_new_tests integration_works; do
    has "$t" && no "(c) Rust test $t reported dead-code" || ok "(c) Rust test $t is not dead-code"
done
has unused_prod && ok "(d) Rust control unused_prod still reported dead-code" || no "(d) Rust control unused_prod lost its dead-code row"
[ "$rc" -eq 0 ] && ok "(e) exit 0" || { no "(e) exit $rc"; cat "$TMP/err"; }

echo
[ "$fail" -eq 0 ] && { echo "ALL PASS"; exit 0; } || { echo "SOME CHECKS FAILED"; exit 1; }
