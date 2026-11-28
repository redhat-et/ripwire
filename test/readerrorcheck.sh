#!/usr/bin/env bash
# readerrorcheck.sh — TIDY-TRIAGE C2: a read that fails part-way is a failure, never a shorter answer.
#
# `while( ( n = fread( ... ) ) > 0 ) append;` ends the same way at end of file and at a read error, and an ifstream's
# getline does too. Each reader below handed its caller the prefix it got as if it were the whole file; each now reads
# through src/infra/readall.h (appendRestOf / readFileToEnd) and refuses, naming the file, when the read stopped on an error.
#
# Two deterministic ways to make a read fail, no LD_PRELOAD:
#   (d) A DIRECTORY where the verb takes a FILE: fopen( dir, "rb" ) succeeds on macOS and Linux and the first read fails
#       (EISDIR). A real error through the real stream, red on the base binary, which read it as an empty file.
#   (s) The test seam RIPWIRE_TEST_READ_ERROR=SUBSTR (readall.h): a read whose path or label contains SUBSTR keeps half
#       its bytes and reports an error, as a mid-file EIO would. For streams a caller cannot name from outside: the
#       compact-legend capture (a tmpfile the process wrote) and an indexed source file read after the crawl.
#       The base binary has no seam, so these arms are red on it by construction; (k0) pins that the seam is keyed
#       (a SUBSTR that matches nothing changes no byte).
#
#   (d1) --batch=DIR             exit 1 naming the file, no <batch> answer          (base: exit 0, n="0")
#   (d2) --arch=DIR              exit 1 "cannot read rules file", no <arch> report   (base: exit 0, rules="0" violations="0")
#   (d3) --eval-stray=DIR        exit 1 "cannot read", no eval rows                  (base: exit 0, an empty eval)
#   (d4) --from-trace=DIR        exit 1 "cannot read ... to its end"                 (base: "no frames found", a misread)
#   (d5) --eval-mined=DIR        exit 1 "cannot read ... to its end"                 (base: "no qualifying pairs")
#   (d6) --eval-skills=DIR       exit 1 "cannot read ... to its end"                 (base: "no positive rows")
#   (s1) compact-legend capture  exit 1, EMPTY stdout, stderr says why              (base: the answer, exit 0)
#   (s2) --slice=SYM:VAR         exit 1 "cannot read <file>"                         (base: the slice)
#   (s3) MCP slice               an error reply naming the file                      (base: the slice)
#   (s4) --export=cc.json        the seamed file's loc is 0 (unreadable), others kept (base: the full count)
#   (k0) a seam SUBSTR matching nothing: --batch, --arch, --slice, compact map and cc.json byte-identical to no seam
#   (k1) the same verbs on a regular FILE still answer (premise of every refusal arm: the verb works on the fixture)
# Every arm counts what it saw and FAILS on zero.
# Usage: test/readerrorcheck.sh [BIN]
set -u
ROOT="$( cd "$( dirname "$0" )/.." && pwd )"
. "$ROOT/test/lib/clean-env.sh"
BIN="${1:-${RIPWIRE_BIN:-$ROOT/build/ripwire}}"
[ "${BIN#/}" = "$BIN" ] && BIN="$ROOT/$BIN"
[ -x "$BIN" ] || { echo "no ripwire binary at $BIN — build first"; exit 2; }
command -v python3 >/dev/null 2>&1 || { echo "python3 required for JSON assertions"; exit 2; }
unset RIPWIRE_TEST_READ_ERROR
TMP="$( mktemp -d )"; trap 'rm -rf "$TMP"' EXIT
fail=0
ok(){ printf '  PASS  %s\n' "$*" || { fail=1; printf '  FAIL  could not write the PASS line for: %s\n' "$*"; }; return 0; }
no(){ printf '  FAIL  %s\n' "$*"; fail=1; }
echo "readerrorcheck: BIN=$BIN"

# ── fixture: one Python repo (git, for --eval-stray), a directory to read, regular input files ──────────────────────
REPO="$TMP/repo"; DIR="$TMP/adir"; mkdir -p "$REPO" "$DIR"
cat > "$REPO/app.py" <<'PY'
def helper(x):
    total = x + 1
    return total * 2


def main():
    value = helper(2)
    return value
PY
git -C "$REPO" init -q && git -C "$REPO" add app.py \
    && git -C "$REPO" -c user.email=t@t -c user.name=t -c commit.gpgsign=false commit -qm init \
    || { echo "could not build the git fixture"; exit 2; }
printf 'callers:helper\n' > "$TMP/batch.txt"
printf 'layer app = app\n' > "$TMP/rules.arch"

run(){   # run NAME ARGS... — stdout, stderr and rc of one call, in $TMP/NAME.{out,err,rc}
    local name="$1"; shift
    ( cd "$REPO" && "$BIN" . --no-cache "$@" >"$TMP/$name.out" 2>"$TMP/$name.err" ); echo $? > "$TMP/$name.rc"
}
rc(){ cat "$TMP/$1.rc"; }
has(){ grep -q -- "$2" "$TMP/$1.$3"; }

# ── (k1) premises: each verb answers on a regular file ───────────────────────────────────────────────────────────────
run k1batch --batch="$TMP/batch.txt"
if [ "$( rc k1batch )" = 0 ] && has k1batch 'n="1"' out; then ok "(k1) --batch=FILE answers one sub-query"; else no "(k1) --batch=FILE: rc=$( rc k1batch ) $( head -c 200 "$TMP/k1batch.err" )"; fi
run k1arch --arch="$TMP/rules.arch"
if [ "$( rc k1arch )" = 0 ] && has k1arch '<arch ' out && has k1arch 'layers="1"' out; then ok "(k1) --arch=FILE reports its one layer"; else no "(k1) --arch=FILE: rc=$( rc k1arch ) $( head -c 200 "$TMP/k1arch.err" )"; fi
run k1slice --slice=helper:total
if [ "$( rc k1slice )" = 0 ] && has k1slice 'total' out; then ok "(k1) --slice=helper:total answers"; else no "(k1) --slice: rc=$( rc k1slice ) $( head -c 200 "$TMP/k1slice.err" )"; fi
run k1compact --callers=helper --legend=compact
if [ "$( rc k1compact )" = 0 ] && [ -s "$TMP/k1compact.out" ]; then ok "(k1) --callers --legend=compact answers"; else no "(k1) compact: rc=$( rc k1compact )"; fi
run k1cc --export=cc.json
if [ "$( rc k1cc )" = 0 ] && has k1cc '"loc"' out; then ok "(k1) --export=cc.json answers with loc"; else no "(k1) cc.json: rc=$( rc k1cc ) $( head -c 200 "$TMP/k1cc.err" )"; fi

# ── (d) a directory where a FILE is taken ────────────────────────────────────────────────────────────────────────────
run d1 --batch="$DIR"
if [ "$( rc d1 )" != 0 ] && has d1 'cannot read' err && ! has d1 '<batch' out; then ok "(d1) --batch=DIR refuses, naming the file"; else no "(d1) --batch=DIR: rc=$( rc d1 ) out=$( head -c 120 "$TMP/d1.out" )"; fi
run d2 --arch="$DIR"
if [ "$( rc d2 )" != 0 ] && has d2 'cannot read rules file' err && ! has d2 '<arch ' out; then ok "(d2) --arch=DIR refuses (no rules=\"0\" exit-0 gate)"; else no "(d2) --arch=DIR: rc=$( rc d2 ) $( grep -o '<arch [^>]*>' "$TMP/d2.out" | head -1 )"; fi
run d3 --eval-stray="$DIR"
if [ "$( rc d3 )" != 0 ] && has d3 'cannot read' err; then ok "(d3) --eval-stray=DIR refuses"; else no "(d3) --eval-stray=DIR: rc=$( rc d3 )"; fi
run d4 --from-trace="$DIR"
if [ "$( rc d4 )" != 0 ] && has d4 'cannot read .* to its end' err; then ok "(d4) --from-trace=DIR says it cannot read the file"; else no "(d4) --from-trace=DIR: rc=$( rc d4 ) $( head -c 200 "$TMP/d4.err" )"; fi
run d5 --eval-mined="$DIR"
if [ "$( rc d5 )" != 0 ] && has d5 'cannot read .* to its end' err; then ok "(d5) --eval-mined=DIR says it cannot read the file"; else no "(d5) --eval-mined=DIR: rc=$( rc d5 ) $( head -c 200 "$TMP/d5.err" )"; fi
( cd "$ROOT" && "$BIN" skills --no-cache --eval-skills="$DIR" >"$TMP/d6.out" 2>"$TMP/d6.err" ); echo $? > "$TMP/d6.rc"
if [ "$( rc d6 )" != 0 ] && has d6 'cannot read .* to its end' err; then ok "(d6) --eval-skills=DIR says it cannot read the corpus"; else no "(d6) --eval-skills=DIR: rc=$( rc d6 ) $( head -c 200 "$TMP/d6.err" )"; fi

# ── (s) the seam: a mid-file read error on a stream no caller can name ───────────────────────────────────────────────
RIPWIRE_TEST_READ_ERROR="compact-legend capture" run s1 --callers=helper --legend=compact
if [ "$( rc s1 )" != 0 ] && [ ! -s "$TMP/s1.out" ] && has s1 'could not read the captured answer back whole' err; then ok "(s1) capture read-back error: nothing printed, exit $( rc s1 )"; else no "(s1) capture: rc=$( rc s1 ) stdout=$( wc -c < "$TMP/s1.out" ) B"; fi
RIPWIRE_TEST_READ_ERROR="app.py" run s2 --slice=helper:total
if [ "$( rc s2 )" = 1 ] && has s2 'cannot read .*app.py' err && [ ! -s "$TMP/s2.out" ]; then ok "(s2) --slice refuses a definition file read part-way"; else no "(s2) --slice: rc=$( rc s2 ) $( head -c 200 "$TMP/s2.err" )"; fi
mcp_slice(){ printf '%s\n' '{"jsonrpc":"2.0","id":1,"method":"initialize"}' \
    '{"jsonrpc":"2.0","id":2,"method":"tools/call","params":{"name":"slice","arguments":{"paths":["."],"symbol":"helper","var":"total"}}}' \
    | ( cd "$REPO" && "$BIN" --mcp 2>/dev/null ) > "$TMP/mcp.raw"; local mrc=$?
    if [ "$mrc" != 0 ]; then echo "__ERROR__:the MCP server exited $mrc"; return 0; fi
    tail -1 "$TMP/mcp.raw" | python3 -c '
import sys, json
r = json.load(sys.stdin)
if "error" in r: print("__ERROR__:" + r["error"].get("message", ""))
else:
    c = r["result"]; t = c["content"][0]["text"]
    print(("__ERROR__:" if c.get("isError") else "") + t)
'; }
mcp_slice > "$TMP/s3k.txt"
RIPWIRE_TEST_READ_ERROR="app.py" mcp_slice > "$TMP/s3.txt"
if ! grep -q '__ERROR__' "$TMP/s3k.txt" && grep -q 'total' "$TMP/s3k.txt"; then
    if grep -q '^__ERROR__:.*cannot read .*app.py' "$TMP/s3.txt"; then ok "(s3) MCP slice answers an error naming the file read part-way"; else no "(s3) MCP slice under the seam: $( head -c 200 "$TMP/s3.txt" )"; fi
else no "(s3) premise: the MCP slice answers without the seam: $( head -c 200 "$TMP/s3k.txt" )"; fi
RIPWIRE_TEST_READ_ERROR="app.py" run s4 --export=cc.json
locs(){ python3 -c '
import sys, json
def walk(n, acc):
    if n.get("type") == "File": acc[n["name"]] = n.get("attributes", {}).get("loc")
    for c in n.get("children", []): walk(c, acc)
    return acc
d = json.load(open(sys.argv[1])); roots = d.get("nodes") or d.get("data", {}).get("nodes") or []
acc = {}
for n in roots: walk(n, acc)
print(acc.get("app.py"))
' "$1" 2>/dev/null; }
base_loc="$( locs "$TMP/k1cc.out" )"; seam_loc="$( locs "$TMP/s4.out" )"
if [ -n "$base_loc" ] && [ "$base_loc" != None ] && [ "$base_loc" != 0 ]; then
    if [ "$seam_loc" = 0 ]; then ok "(s4) cc.json: app.py read part-way is loc 0 (unreadable), not a short count (whole: $base_loc)"; else no "(s4) cc.json loc under the seam: '$seam_loc' (whole: $base_loc)"; fi
else no "(s4) premise: app.py's loc in the plain cc.json export: '$base_loc'"; fi

# ── (k0) the seam is keyed: a SUBSTR that matches nothing moves no byte ──────────────────────────────────────────────
K0=0
for arm in "k1batch:--batch=$TMP/batch.txt" "k1arch:--arch=$TMP/rules.arch" "k1slice:--slice=helper:total" "k1cc:--export=cc.json"; do
    name="${arm%%:*}"; arg="${arm#*:}"
    RIPWIRE_TEST_READ_ERROR="no-such-path-anywhere" run "k0$name" "$arg"
    if cmp -s "$TMP/$name.out" "$TMP/k0$name.out"; then K0=$(( K0 + 1 )); else no "(k0) $arg moved under a seam that matches nothing"; fi
done
RIPWIRE_TEST_READ_ERROR="no-such-path-anywhere" run k0compact --callers=helper --legend=compact
if cmp -s "$TMP/k1compact.out" "$TMP/k0compact.out"; then K0=$(( K0 + 1 )); else no "(k0) the compact capture moved under a seam that matches nothing"; fi
if [ "$K0" = 5 ]; then ok "(k0) 5 of 5 answers byte-identical under a seam that matches nothing"; else no "(k0) $K0 of 5 byte-identical"; fi

[ "$fail" = 0 ] && echo "readerrorcheck: PASS" || echo "readerrorcheck: FAIL"
exit "$fail"
