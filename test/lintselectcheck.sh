#!/usr/bin/env bash
# lintselectcheck.sh — L7 gate: --lint-select=/--lint-ignore=PREFIX[,...] and the applicable=/inert_rules=
# per-language disclosure on --lint's own tally (src/lintcatalog.h).
#
#   1) --lint-select=cache- emits ONLY the cache-* family and discloses selected="K of N".
#   2) --lint-ignore='*' (ignore everything) emits findings="0" WITH the filter disclosure — a filtered
#      zero, not a bare "no findings".
#   3) an unresolvable PREFIX refuses (exit 1) and names a near-miss.
#   4) a Go-only fixture makes a C-family-only rule (magic-number) report applicable="0" and the root
#      tallies inert_rules >= 1.
#
#   RIPWIRE_BIN=build/ripwire bash test/lintselectcheck.sh
#   RIPWIRE_BIN=asan/ripwire  bash test/lintselectcheck.sh

set -u
ROOT="$( cd "$( dirname "$0" )/.." && pwd )"
BIN="${RIPWIRE_BIN:-$ROOT/build/ripwire}"
[ "${BIN#/}" = "$BIN" ] && BIN="$ROOT/$BIN"
TMP="$( mktemp -d )"; trap 'rm -rf "$TMP"' EXIT
fail=0
ok(){ printf '  PASS  %s\n' "$*"; }
no(){ printf '  FAIL  %s\n' "$*"; fail=1; }

[ -x "$BIN" ] || { echo "no ripwire binary at $BIN — build first"; exit 2; }

CORPUS="$ROOT/test/lintfix"
[ -d "$CORPUS" ] || { echo "no test/lintfix dir — fixture missing"; exit 2; }

# 1) --lint-select=cache- selects only the cache-* family, and only that family.
"$BIN" "$CORPUS" --lint --lint-select=cache- --no-cache >"$TMP/select" 2>/dev/null
python3 - "$TMP/select" <<'PY'
import sys
import xml.etree.ElementTree as ET
fail = 0
def ok(m): print("  PASS  " + m)
def no(m):
    global fail; fail = 1; print("  FAIL  " + m)
root = ET.parse(sys.argv[1]).getroot()
names = [r.get("name") for r in root.findall("rule")]
if names and all(n.startswith("cache-") for n in names):
    ok(f"--lint-select=cache- emits ONLY cache-* rows ({len(names)} of them)")
else:
    no(f"--lint-select=cache- emitted non-cache-* rows: {[n for n in names if not n.startswith('cache-')]}")
sel = root.get("selected")
if sel and sel.endswith(" of 39") and sel.split(" of ")[0] == "8":
    ok(f'root discloses selected="{sel}"')
else:
    no(f'root selected= is "{sel}", expected "8 of 39" (cache- names exactly 8 rules)')
if root.get("select") == "cache-":
    ok('root echoes select="cache-"')
else:
    no(f'root select= is "{root.get("select")}", expected "cache-"')
sys.exit(fail)
PY
[ $? -ne 0 ] && fail=1

# 2) --lint-ignore='*' drops everything: findings="0", but the root still carries the filter disclosure
# (a filtered zero must never look like an unfiltered "no findings").
"$BIN" "$CORPUS" --lint --lint-ignore='*' --no-cache >"$TMP/ignoreall" 2>/dev/null
python3 - "$TMP/ignoreall" <<'PY'
import sys
import xml.etree.ElementTree as ET
fail = 0
def ok(m): print("  PASS  " + m)
def no(m):
    global fail; fail = 1; print("  FAIL  " + m)
root = ET.parse(sys.argv[1]).getroot()
if root.get("findings") == "0":
    ok('--lint-ignore=* emits findings="0"')
else:
    no(f'--lint-ignore=* findings= is "{root.get("findings")}", expected "0"')
if len(root.findall("rule")) == 0:
    ok("--lint-ignore=* emits zero <rule> tally rows")
else:
    no(f"--lint-ignore=* still emitted {len(root.findall('rule'))} <rule> rows")
if root.get("selected") == "0 of 39":
    ok('root discloses selected="0 of 39"')
else:
    no(f'root selected= is "{root.get("selected")}", expected "0 of 39"')
if root.get("ignore") == "*":
    ok('root echoes ignore="*"')
else:
    no(f'root ignore= is "{root.get("ignore")}", expected "*"')
sys.exit(fail)
PY
[ $? -ne 0 ] && fail=1

# 3) an unresolvable PREFIX refuses loudly (exit 1) and names a near-miss ('cach-' -> 'cache-').
err="$( "$BIN" "$CORPUS" --lint --lint-select=cach- --no-cache 2>&1 1>/dev/null )"
rc=$?
if [ "$rc" -ne 0 ]; then ok "--lint-select=cach- (unresolvable) refuses (exit $rc)"; else no "--lint-select=cach- (unresolvable) exited 0"; fi
case "$err" in
    *"did you mean"*"cache-"*) ok "refusal names the near-miss family ('cache-')" ;;
    *) no "refusal did not name a near-miss: $err" ;;
esac

# a prefix that resolves to nothing AND is nowhere near any real rule name still refuses, with no
# near-miss claimed (an honest 'no plausible suggestion' beats a bad guess).
err2="$( "$BIN" "$CORPUS" --lint --lint-select=zzzzznotarule --no-cache 2>&1 1>/dev/null )"
rc2=$?
if [ "$rc2" -ne 0 ]; then ok "--lint-select=zzzzznotarule refuses (exit $rc2)"; else no "--lint-select=zzzzznotarule exited 0"; fi

# 4) a Go-only fixture makes a C-family-only rule (magic-number) structurally inert: applicable="0",
# and the root tallies inert_rules >= 1.
GOFIX="$TMP/gofix"
mkdir -p "$GOFIX"
cat >"$GOFIX/a.go" <<'EOF'
package main

func f(a, b int) int {
	x := a
	y := 12345
	return x + y + b
}
EOF
"$BIN" "$GOFIX" --lint --no-cache >"$TMP/goonly" 2>/dev/null
python3 - "$TMP/goonly" <<'PY'
import sys
import xml.etree.ElementTree as ET
fail = 0
def ok(m): print("  PASS  " + m)
def no(m):
    global fail; fail = 1; print("  FAIL  " + m)
root = ET.parse(sys.argv[1]).getroot()
magic = next((r for r in root.findall("rule") if r.get("name") == "magic-number"), None)
if magic is None:
    no("no magic-number row in --lint output at all")
elif magic.get("applicable") == "0":
    ok('a Go-only corpus makes magic-number report applicable="0"')
else:
    no(f'magic-number applicable= is "{magic.get("applicable")}" on a Go-only corpus, expected "0"')
inert = root.get("inert_rules")
if inert and int(inert) >= 1:
    ok(f'root tallies inert_rules="{inert}" (>= 1) on a Go-only corpus')
else:
    no(f'root inert_rules= is "{inert}", expected >= 1 on a Go-only corpus')
# a rule that DOES apply to Go (goto) must NOT carry applicable="0" — the disclosure is per-language,
# not "everything is inert because the corpus is small".
goto = next((r for r in root.findall("rule") if r.get("name") == "goto"), None)
if goto is not None and goto.get("applicable") is None:
    ok('goto (Go IS one of its languages) carries no applicable="0" on the same Go-only corpus')
else:
    no(f'goto applicable= is "{goto.get("applicable") if goto is not None else None}", expected absent')
sys.exit(fail)
PY
[ $? -ne 0 ] && fail=1

[ "$fail" = 0 ] && echo "ALL PASS" || echo "FAILURES ABOVE"
exit $fail
