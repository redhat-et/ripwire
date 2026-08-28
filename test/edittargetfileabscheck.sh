#!/usr/bin/env bash
# edittargetfileabscheck.sh — A2: an ABSOLUTE --edit-target-file hint resolves, and a not-found refusal
# never suggests the very name it was asked for.
#
# THE BUG THIS GATE PINS. The hint was a raw substring test against the index's spelling of each file, which
# is derived from the ROOT AS TYPED. So an absolute path — the spelling an agent pastes back out of a
# receipt, a stack trace or its own shell, and the most natural thing to type — matched nothing whenever the
# root was spelled relatively. The refusal then read:
#
#   symbol 'alpha' not found under path '/abs/.../a.py'; nearest: alpha, delta, gamma, beta
#
# Two dishonest claims in one line: the named file DOES define alpha, and the did-you-mean list leads with
# the exact name that was requested. An agent that believes either wastes the rest of the task.
#
# EVERY EDIT ARM RUNS FROM A RELATIVE ROOT (cd into the parent, pass `corpus`), because that is the only
# spelling under which the bug exists. An absolute root makes ing.files absolute too, so the old raw
# substring test happened to work and an absolute-root gate would be vacuously green on the broken binary —
# verified: arms 1/2/6 written against an absolute root all PASSED against the pre-fix binary.
#
# ARMS:
#   1. absolute file hint resolves, under a relative root, and the edit lands in that file.
#   2. absolute DIRECTORY hint resolves (the substring rule is preserved, just in the absolute frame).
#   3. absolute hint naming the WRONG file still refuses — the fix must not degrade the hint to a no-op.
#   4. relative hints are untouched (the pre-existing fast path).
#   5. a genuine not-found never echoes the requested name back as a suggestion.
#   6. MCP's `file` argument gets the same treatment (same engine, same seam), also from a relative root.
#
# Usage: test/edittargetfileabscheck.sh [BIN]
set -u
ROOT="$( cd "$( dirname "$0" )/.." && pwd )"
BIN="${1:-${RIPWIRE_BIN:-$ROOT/build/ripwire}}"
[ "${BIN#/}" = "$BIN" ] && BIN="$ROOT/$BIN"
TMP="$( mktemp -d )"; trap 'rm -rf "$TMP"' EXIT
fail=0
ok(){ printf '  PASS  %s\n' "$*"; }
no(){ printf '  FAIL  %s\n' "$*"; fail=1; }
[ -x "$BIN" ] || { echo "no ripwire binary at $BIN — build first"; exit 2; }
command -v python3 >/dev/null 2>&1 || { echo "python3 required"; exit 2; }

echo "edittargetfileabscheck: BIN=$BIN"

hashcorpus(){ ( cd "$1" && find . -type f -print | LC_ALL=C sort | xargs shasum -a 256 ) | shasum -a 256; }

# build $TMP/<name>/corpus from the template; echo the PARENT to cd into.
scratch(){
    local d="$TMP/$1"
    mkdir -p "$d"
    cp -R "$TMP/template" "$d/corpus"
    printf '%s' "$d"
}

mkdir -p "$TMP/template"
cat >"$TMP/template/a.py" <<'PY'
def alpha( x ):
    return x + 1


def beta( x ):
    return alpha( x ) * 2
PY
cat >"$TMP/template/b.py" <<'PY'
def alpha( x ):
    return x + 100
PY
printf 'def alpha( x ):\n    return 42\n' >"$TMP/pay"

echo
echo "=== 1. an absolute file hint resolves the same-named ambiguity (relative root) ==="
P1="$( scratch absfile )"
if ( cd "$P1" && "$BIN" corpus --replace-symbol-body=alpha --edit-target-file="$P1/corpus/b.py" \
        --edit-payload="$TMP/pay" ) >"$TMP/1.out" 2>"$TMP/1.err"; then
    ok "absolute --edit-target-file resolves under a relative root (exit 0)"
else
    no "absolute --edit-target-file refused: $( head -1 "$TMP/1.err" )"
fi
grep -q 'return 42' "$P1/corpus/b.py" \
    && ok "the edit landed in the file the absolute hint named" \
    || no "the edit did not land in b.py"
grep -q 'return x + 1$' "$P1/corpus/a.py" \
    && ok "the other definition of the same name is untouched" \
    || no "the edit touched a.py as well"

echo
echo "=== 2. an absolute DIRECTORY hint resolves (substring rule, absolute frame) ==="
P2="$TMP/absdir"; mkdir -p "$P2/corpus/lib" "$P2/corpus/app"
cp "$TMP/template/a.py" "$P2/corpus/app/a.py"
cp "$TMP/template/b.py" "$P2/corpus/lib/b.py"
if ( cd "$P2" && "$BIN" corpus --replace-symbol-body=alpha --edit-target-file="$P2/corpus/lib" \
        --edit-payload="$TMP/pay" ) >"$TMP/2.out" 2>"$TMP/2.err"; then
    ok "an absolute directory hint narrows to that subtree"
else
    no "an absolute directory hint refused: $( head -1 "$TMP/2.err" )"
fi
grep -q 'return 42' "$P2/corpus/lib/b.py" \
    && ok "the edit landed under the named subtree" \
    || no "the edit did not land under lib/"

echo
echo "=== 3. an absolute hint naming the WRONG file still refuses ==="
P3="$( scratch absmiss )"
printf 'def solo():\n    return 0\n' >"$P3/corpus/c.py"
B3="$( hashcorpus "$P3/corpus" )"
if ( cd "$P3" && "$BIN" corpus --replace-symbol-body=solo --edit-target-file="$P3/corpus/a.py" \
        --edit-payload="$TMP/pay" ) >"$TMP/3.out" 2>"$TMP/3.err"; then
    no "an absolute hint naming a file WITHOUT the symbol wrongly succeeded"
else
    ok "an absolute hint naming the wrong file still refuses"
fi
[ "$B3" = "$( hashcorpus "$P3/corpus" )" ] \
    && ok "that refusal leaves the corpus byte-identical" \
    || no "that refusal modified the corpus"

echo
echo "=== 4. relative hints are unchanged ==="
P4="$( scratch rel )"
if ( cd "$P4" && "$BIN" corpus --replace-symbol-body=alpha --edit-target-file=b.py \
        --edit-payload="$TMP/pay" ) >"$TMP/4.out" 2>"$TMP/4.err"; then
    ok "a relative hint still resolves"
else
    no "a relative hint regressed: $( head -1 "$TMP/4.err" )"
fi

echo
echo "=== 5. a not-found refusal never suggests the name it was asked for ==="
P5="$( scratch echoback )"
( cd "$P5" && "$BIN" corpus --replace-symbol-body=alpha --edit-target-file=nosuchdir/ \
    --edit-payload="$TMP/pay" ) >"$TMP/5.out" 2>"$TMP/5.err" && no "a hint matching no file wrongly succeeded"
python3 - "$TMP/5.err" >"$TMP/5.verdict" <<'PY'
import re, sys
err = open(sys.argv[1], encoding="utf-8").read()
m = re.search(r"nearest: (.*)$", err.strip(), re.M)
names = [n.strip() for n in m.group(1).split(",")] if m else []
print(("SELF_ECHO" if "alpha" in names else "CLEAN") + " | " + ",".join(names))
PY
grep -q '^CLEAN' "$TMP/5.verdict" \
    && ok "the did-you-mean list omits the requested name ($( cat "$TMP/5.verdict" ))" \
    || no "the did-you-mean list echoes the requested name back: $( cat "$TMP/5.verdict" )"

echo
echo "=== 6. MCP's file argument takes an absolute path too ==="
# The MCP `path` is always absolute in practice, but the index's spelling still follows the ROOT AS GIVEN,
# so a RELATIVE path argument is what reproduces the CLI's frame here.
P6="$( scratch mcp )"
python3 - >"$TMP/6.req" <<PY
import json
print(json.dumps({"jsonrpc":"2.0","id":1,"method":"initialize"}))
print(json.dumps({"jsonrpc":"2.0","id":2,"method":"tools/call","params":{
    "name":"replace_symbol_body",
    "arguments":{"path":"corpus","symbol":"alpha","file":"$P6/corpus/b.py",
                 "new_body":"def alpha( x ):\n    return 4242\n"}}}))
PY
( cd "$P6" && "$BIN" --mcp <"$TMP/6.req" ) >"$TMP/6.out" 2>/dev/null
python3 - "$TMP/6.out" >"$TMP/6.verdict" <<'PY'
import json, sys
last = [l for l in open(sys.argv[1], encoding="utf-8") if l.strip()][-1]
r = json.loads(last)
print("ERROR " + r["error"]["message"].replace("\n", " ") if "error" in r
      else "OK " + r["result"]["content"][0]["text"].replace("\n", " "))
PY
grep -q '^OK' "$TMP/6.verdict" \
    && ok "MCP replace_symbol_body accepts an absolute file argument" \
    || no "MCP refused an absolute file argument: $( head -c 200 "$TMP/6.verdict" )"
grep -q 'return 4242' "$P6/corpus/b.py" \
    && ok "the MCP edit landed in the file the absolute argument named" \
    || no "the MCP edit did not land in b.py"

[ "$fail" -eq 0 ] && echo "ALL PASS" || echo "FAILURES ABOVE"
exit "$fail"
