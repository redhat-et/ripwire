#!/usr/bin/env bash
# notfoundtextcheck.sh — BX2 FIX 9: a found="0" answer of --callers / --uses / --impact still carries the selector's
# plain-text occurrences, labelled as TEXT, never as calls (verbs_navigate.h notFoundTextEvidence, selectorrefuse.h
# writeNotFoundAnswer; lane BS1's fastify-02 shape, results/BS1_BLINDSPOT_1118).
#
#   test/notfoundtextcheck.sh [BIN]        # BIN defaults to $RIPWIRE_BIN, then build/ripwire
#
# fastify keys a reply property with `kReplyHijacked: Symbol( … )`, an object-literal data property and not a definition, so
# every graph verb answered found="0" and nothing else, while the two files that read and write reply[kReplyHijacked] were one
# --grep away. The not-found answer now adds text_hits= (whole-word lines) and text_files= on its root, one <text p=FILE:LINE
# n=> row per file (its first line, its count; at most 20 rows), and next="--grep=NAME". The graph's claim is unchanged:
# found="0", the exit status 1, and the legend says the rows are text, not calls or uses.
#
# Arm classes: [P] positive — RED on the parent binary; [N] near miss — must stay byte-for-byte the old answer; [C] control.
set -u
ROOT="$( cd "$( dirname "$0" )/.." && pwd )"
BIN="${1:-${RIPWIRE_BIN:-$ROOT/build/ripwire}}"
[ "${BIN#/}" = "$BIN" ] && BIN="$ROOT/$BIN"
DIR="$( mktemp -d )"; trap 'rm -rf "$DIR"' EXIT
fail=0
# every verdict is an if/else: a failed write of a PASS line must never print FAIL for an arm that passed (gateexitcheck G2)
ok(){ printf '  PASS  %s\n' "$*" || { fail=1; printf '  FAIL  could not write the PASS line for: %s\n' "$*"; }; return 0; }
no(){ printf '  FAIL  %s\n' "$*"; fail=1; }
has(){ if printf '%s' "$1" | grep -qF -- "$2"; then ok "$3"; else no "$3 — missing: $2"; fi; }
hasnt(){ if printf '%s' "$1" | grep -qF -- "$2"; then no "$3 — present: $2"; else ok "$3"; fi; }
body(){ printf '%s' "$1" | sed 's/^.*-->//'; }

echo "notfoundtextcheck: BIN=$BIN"
[ -x "$BIN" ] || { echo "  FAIL  no ripwire binary at $BIN"; exit 1; }

# ── the corpus, written here ─────────────────────────────────────────────────────────────────────────────────────────
# lib/symbols.js  exports the key as an object-literal property (no definition of the name).
# lib/reply.js    writes reply[kKeyHijacked] twice; lib/wrap.js reads it once; lib/other.js names only kKeyHijackedExtra.
mkdir -p "$DIR/lib"
printf "'use strict'\nmodule.exports = {\n  kKeyHijacked: Symbol('k.hijacked')\n}\n" >"$DIR/lib/symbols.js"
printf "'use strict'\nconst { kKeyHijacked } = require('./symbols')\nfunction hijack (reply) {\n  reply[kKeyHijacked] = true\n}\nfunction reset (reply) {\n  reply[kKeyHijacked] = false\n}\nmodule.exports = { hijack, reset }\n" >"$DIR/lib/reply.js"
printf "'use strict'\nconst { kKeyHijacked } = require('./symbols')\nfunction wrap (reply) {\n  if (reply[kKeyHijacked]) return\n}\nmodule.exports = { wrap }\n" >"$DIR/lib/wrap.js"
printf "'use strict'\nconst kKeyHijackedExtra = 1\nmodule.exports = { kKeyHijackedExtra }\n" >"$DIR/lib/other.js"
cd "$DIR" || exit 1
export TMPDIR="$DIR/tmp"; mkdir -p "$TMPDIR"
rw(){ "$BIN" "$@" 2>/dev/null; }

echo "[P] the not-found answer carries its text evidence"
for v in callers uses impact; do
    a="$( rw . --$v=kKeyHijacked )"; rc=$?
    b="$( body "$a" )"
    has "$b" 'found="0"' "[C-$v] --$v=kKeyHijacked still answers found=\"0\""
    if [ "$rc" -eq 1 ]; then ok "[C-$v] exit status stays 1 (a refusal)"; else no "[C-$v] exit status $rc, expected 1"; fi
    has "$b" 'text_hits="' "[P-$v] text_hits= rides the root"
    has "$b" '<text p="lib/reply.js:2" n="3"/>' "[P-$v] reply.js: first line 2, three lines"
    has "$b" '<text p="lib/wrap.js:' "[P-$v] wrap.js is named"
    has "$b" 'next="--grep=kKeyHijacked"' "[P-$v] next= runs the grep"
    hasnt "$b" 'other.js' "[N-$v] a longer identifier is not a whole-word occurrence"
    has "$a" 'PLAIN TEXT' "[P-$v] the legend labels the rows as text, not calls"
done
a="$( rw . --callers=kKeyHijacked --json )"
has "$a" '"text_hits":' "[P-json] the JSON dialect carries text_hits"

a="$( body "$( rw . --callers=Reply.kKeyHijacked )" )"
hasnt "$a" 'text_hits' "[N3] a QUALIFIED selector seeks no text: an unknown qualifier is never read as the bare name (qualendpointcheck (h))"

q='{"jsonrpc":"2.0","id":1,"method":"tools/call","params":{"name":"find_referencing_symbols","arguments":{"path":"'"$DIR"'","symbol":"kKeyHijacked"}}}'
a="$( printf '%s\n%s\n' '{"jsonrpc":"2.0","id":0,"method":"initialize","params":{}}' "$q" | "$BIN" --mcp 2>/dev/null )"
has "$a" 'text_hits' "[P-mcp] MCP find_referencing_symbols' not-found document carries the text evidence"
has "$a" '{\"file\":\"lib/reply.js\",\"line\":2,\"n\":3}' "[P-mcp] ... in MCP's own \"file\" / \"line\" keys, as every MCP row (BX2 step 1)"
hasnt "$a" '\"p\":\"lib/' "[N-mcp] ... never the CLI-JSON \"p\":\"F:L\""
a="$( rw . --callers=kKeyHijacked --json )"
has "$a" '{"p":"lib/reply.js:2","n":3}' "[C-json] the CLI --json dialect keeps \"p\":\"F:L\""

echo "[N] a name no file holds: the answer is unchanged"
a="$( body "$( rw . --callers=noSuchNameAnywhere )" )"
hasnt "$a" 'text_hits' "[N1] no text_hits= when no file holds the name"
has "$a" '/>' "[N2] the root stays self-closing"
a="$( rw . --callers=kKeyHijacked )"
if [ "$( rw . --callers=kKeyHijacked )" = "$a" ]; then ok "[C1] two runs byte-identical"; else no "[C1] two runs differ"; fi

if [ "$fail" -eq 0 ]; then echo "notfoundtextcheck: ALL PASS"; else echo "notfoundtextcheck: FAIL"; fi
exit "$fail"
