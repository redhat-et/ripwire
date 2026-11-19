#!/usr/bin/env bash
# mcpforroutecheck.sh — RT2 MCP PARITY: MCP `for` routes by the SAME frozen rule as the CLI's bare --for (verbs_forroute.h
# mcpForVerbRoute). A routed MCP payload must carry the SAME rows as the CLI routed answer for the same question: the <route>
# element, the <text_only> fold, the <def> rows and every verb row, byte for byte once the legend comments and the echoed
# root= are set aside (MCP passes its absolute path; the CLI echoes the root as typed). The carried page differs BY DESIGN:
# a warned CLI answer carries the CLI's first --for page, a warned MCP answer carries MCP's own `for` answer (MCP serves `for`
# unpaged) — both say page1="1" and both carry a <ctx> as the root's last child.
#
#   test/mcpforroutecheck.sh [BIN]     # BIN defaults to $RIPWIRE_BIN, then build/ripwire
#
# BATCH (coordinator 2026-11-19): the `batch` sub-verb `for` routes by the same path and call-shape conditions — a batch item's
# routed rows equal the top-level MCP `for` rows for the same question (arms b1–b3; red before the batch arm routed).
#
# Arms: [P] routed (who-calls, plain), [P] folded (direct-radius, a text-only file), [P] warned + carried (transitive, a
# callback hop; and who-calls through a macro), [N] unrouted (no symbol) — no <route>, the ranked <ctx>, [N] no_verb_route
# and budget_tokens — never routed, [C] determinism and well-formedness. Every [P] arm is RED on a binary whose MCP `for`
# does not route (the frozen RT2 binary): that is the control.
set -u
ROOT="$( cd "$( dirname "$0" )/.." && pwd )"
BIN="${1:-${RIPWIRE_BIN:-$ROOT/build/ripwire}}"
[ "${BIN#/}" = "$BIN" ] && BIN="$ROOT/$BIN"
DIR="$( mktemp -d )"; trap 'rm -rf "$DIR"' EXIT
fail=0
ok(){ printf '  PASS  %s\n' "$*" || { fail=1; printf '  FAIL  could not write the PASS line for: %s\n' "$*"; }; return 0; }
no(){ printf '  FAIL  %s\n' "$*"; fail=1; }
say(){ if [ "$1" = 0 ]; then ok "$2"; else no "$3"; fi; }
echo "mcpforroutecheck: BIN=$BIN"
[ -x "$BIN" ] || { echo "  FAIL  no ripwire binary at $BIN"; exit 1; }
command -v python3 >/dev/null 2>&1 || { echo "  FAIL  python3 required"; exit 1; }

# ── fixtures (written here; forverbroutecheck's shapes) ─────────────────────────────────────────────────────────────
mkdir -p "$DIR/plain" "$DIR/gap" "$DIR/hop" "$DIR/mac"
printf 'int compute_total( int a );\n' >"$DIR/plain/lib.h"
printf '#include "lib.h"\nint compute_total( int a )\n{\n    return a + 1;\n}\n' >"$DIR/plain/lib.c"
printf '#include "lib.h"\nint run_main( void )\n{\n    return compute_total( 2 );\n}\n' >"$DIR/plain/main.c"
cp "$DIR/plain/"*.[ch] "$DIR/gap/"
printf 'const char* kTotalName = "compute_total";\n' >"$DIR/gap/names.c"
cat >"$DIR/hop/cb.c" <<'C'
struct ops
{
    void ( *on_err )( int );
};
void report_error( int code )
{
    ( void )code;
}
static void handle_failure( int code )
{
    report_error( code );
}
static struct ops table = { handle_failure };
void dispatch( int c )
{
    table.on_err( c );
}
C
cp "$DIR/plain/lib.c" "$DIR/mac/"
printf 'int compute_total( int a );\n#define TOTAL( x ) compute_total( x )\n' >"$DIR/mac/lib.h"
for f in a b; do printf '#include "lib.h"\nint use_%s( void )\n{\n    return TOTAL( 1 );\n}\n' "$f" >"$DIR/mac/$f.c"; done

# one MCP tools/call of `for`; extra JSON arguments in $3 (e.g. ,"no_verb_route":true)
mcpfor(){ python3 - "$BIN" "$1" "$2" "${3:-}" <<'PY'
import json, subprocess, sys
binp, path, task, extra = sys.argv[1:5]
args = dict(path=path, task=task); args.update(json.loads("{" + extra.lstrip(",") + "}") if extra else {})
req = [ {"jsonrpc": "2.0", "id": 1, "method": "initialize"},
        {"jsonrpc": "2.0", "id": 2, "method": "tools/call", "params": {"name": "for", "arguments": args}} ]
p = subprocess.run([binp, "--mcp"], input="".join(json.dumps(r) + "\n" for r in req), capture_output=True, text=True)
for line in p.stdout.splitlines():
    try:
        r = json.loads(line)
    except ValueError:
        continue
    if r.get("id") == 2:
        sys.stdout.write("".join(c.get("text", "") for c in r.get("result", {}).get("content", [])))
PY
}
cli(){ ( cd "$DIR" && "$BIN" "$1" --for="$2" 2>/dev/null ); }
# the rows: comments dropped, root= dropped, and everything from the carried <ctx task= on cut (its own surface's page)
rows(){ python3 -c '
import re, sys
d = re.sub(r"<!--.*?-->", "", sys.stdin.read(), flags=re.S)
d = re.sub(r" root=\"[^\"]*\"", "", d, count=1)
i = d.find("<ctx task=")
if i > 0 and not d.startswith("<ctx"):
    d = d[:i] + d[d.rfind("</"):]
sys.stdout.write(d.strip())'; }
attr(){ python3 -c 'import re,sys; m=re.search(r"(?<![\w])"+sys.argv[2]+r"=\"([^\"]*)\"",sys.argv[1]); print(m.group(1) if m else "")' "$1" "$2"; }
routeOf(){ python3 -c 'import re,sys; d=re.sub(r"<!--.*?-->","",sys.stdin.read(),flags=re.S); m=re.search(r"<route [^>]*/>",d); print(m.group(0) if m else "")'; }

pair(){ # $1 id, $2 fixture, $3 question, $4 kind, $5 warned (1/0), $6 fold (1/0)
    local M C; M="$( mcpfor "$DIR/$2" "$3" )"; C="$( cli "$2" "$3" )"
    printf '%s' "$M" >"$DIR/$1.mcp"; printf '%s' "$C" >"$DIR/$1.cli"
    local RM RC; RM="$( printf '%s' "$M" | routeOf )"; RC="$( printf '%s' "$C" | routeOf )"
    [ -n "$RM" ] && [ "$( attr "$RM" kind )" = "$4" ]
    say $? "($1) [P] MCP for routes: kind=$4 ($( attr "$RM" verb ))" "($1) [P] MCP for did not route: '${M:0:200}'"
    [ -n "$RM" ] && [ "$RM" = "$RC" ]
    say $? "($1) [P] the MCP <route> element equals the CLI's" "($1) [P] <route> differs: MCP '$RM' vs CLI '$RC'"
    [ -n "$RM" ] && [ "$( printf '%s' "$M" | rows )" = "$( printf '%s' "$C" | rows )" ]
    say $? "($1) [P] the MCP payload carries the CLI routed answer's rows, byte for byte (legend and root= aside)" "($1) [P] rows differ: MCP '$( printf '%s' "$M" | rows | head -c 300 )' vs CLI '$( printf '%s' "$C" | rows | head -c 300 )'"
    if [ "$5" = 1 ]; then
        [ "$( attr "$RM" warn )" = 1 ] && [ "$( attr "$RM" page1 )" = 1 ] && printf '%s' "$M" | grep -q '<ctx task='
        say $? "($1) [P] warned: warn=1 page1=1, MCP's own for answer rides as the carried page" "($1) [P] warned arm reads '$RM'"
    else
        [ -z "$( attr "$RM" warn )" ] && ! printf '%s' "$M" | grep -q '<ctx task='
        say $? "($1) [P] unwarned: no warn=, no carried page" "($1) [P] '$RM'"
    fi
    if [ "$6" = 1 ]; then
        printf '%s' "$M" | grep -q '<text_only n="1"><tx p="names.c:1"/></text_only>'
        say $? "($1) [P] the fold rides the MCP payload" "($1) [P] no fold"
    fi
    if command -v xmllint >/dev/null 2>&1; then
        printf '%s' "$M" | xmllint --noout - 2>/dev/null
        say $? "($1) [C] the MCP payload is one well-formed XML document" "($1) [C] not well-formed"
    fi
}
pair r1 plain 'Who calls `compute_total`?'                                      who-calls     0 0
pair r2 gap   'Which files are affected if `compute_total` changes?'            direct-radius 0 1
pair r3 hop   'Trace the transitive callers of `report_error`, including callback registrations.' transitive 1 0
pair r4 mac   'Who calls `compute_total`?'                                      who-calls     1 0
pair r5 plain 'Where is `compute_total` used?'                                  where-used    0 0

# [N] unrouted: no symbol named — the ranked <ctx>, no <route>
U="$( mcpfor "$DIR/plain" 'How does the total get computed?' )"
case "$U" in *"<route "*) no "(n1) [N] an unnamed question was routed" ;; *"<ctx"*) ok "(n1) [N] no symbol named: MCP for answers the ranked <ctx>, no <route>" ;; *) no "(n1) [N] no answer: '${U:0:200}'" ;; esac
# [N] the opt-out and a budget never route
O="$( mcpfor "$DIR/plain" 'Who calls `compute_total`?' ',"no_verb_route":true' )"
case "$O" in *"<route "*) no "(n2) [N] no_verb_route=true was routed" ;; *"<ctx"*) ok "(n2) [N] no_verb_route=true: the ranked <ctx>, never routed" ;; *) no "(n2) [N] no answer: '${O:0:200}'" ;; esac
B="$( mcpfor "$DIR/plain" 'Who calls `compute_total`?' ',"budget_tokens":2000' )"
case "$B" in *"<route "*) no "(n3) [N] a budgeted for was routed" ;; *"<ctx"*) ok "(n3) [N] budget_tokens: the ranked <ctx>, never routed (as the CLI's --token-budget)" ;; *) no "(n3) [N] no answer: '${B:0:200}'" ;; esac
# [C] determinism
M2="$( mcpfor "$DIR/hop" 'Trace the transitive callers of `report_error`, including callback registrations.' )"
[ "$M2" = "$( cat "$DIR/r3.mcp" )" ]
say $? "(c1) [C] two MCP runs of the warned arm are byte-identical" "(c1) [C] MCP runs differ"

# ── BATCH arms (b1–b3): the batch sub-verb `for` routes exactly as the top-level MCP `for` does ─────────────────────
# one batch call; prints sub-answer i's payload (CDATA unwrapped, the split `]]>` rejoined), or ERR:<text> for a failed item
mcpbatch(){ python3 - "$BIN" "$1" "$2" "$3" <<'PY'
import json, re, subprocess, sys
binp, path, queries, want = sys.argv[1], sys.argv[2], json.loads(sys.argv[3]), int(sys.argv[4])
req = [ {"jsonrpc": "2.0", "id": 1, "method": "initialize"},
        {"jsonrpc": "2.0", "id": 2, "method": "tools/call", "params": {"name": "batch", "arguments": {"path": path, "queries": queries}}} ]
p = subprocess.run([binp, "--mcp"], input="".join(json.dumps(r) + "\n" for r in req), capture_output=True, text=True)
text = ""
for line in p.stdout.splitlines():
    try:
        r = json.loads(line)
    except ValueError:
        continue
    if r.get("id") == 2:
        text = "".join(c.get("text", "") for c in r.get("result", {}).get("content", []))
m = re.search(r'<q i="%d"[^>]*ok="1"[^>]*>(.*?)</q>' % want, text, re.S)
if not m:
    e = re.search(r'<q i="%d"[^>]*>(.*?)</q>' % want, text, re.S)
    sys.stdout.write("ERR:" + (e.group(1)[:300] if e else text[:300])); sys.exit(0)
body = m.group(1)
parts = re.findall(r"<!\[CDATA\[(.*?)\]\]>", body, re.S)
sys.stdout.write("".join(parts) if parts else body)
PY
}
QW='Who calls `compute_total`?'
QS="$( python3 -c 'import json,sys; print(json.dumps([{"verb":"for","task":sys.argv[1]},{"verb":"for","task":"How does the total get computed?"},{"verb":"for","task":sys.argv[1],"no_verb_route":True}]))' "$QW" )"
B0="$( mcpbatch "$DIR/plain" "$QS" 0 )"; B1="$( mcpbatch "$DIR/plain" "$QS" 1 )"; B2="$( mcpbatch "$DIR/plain" "$QS" 2 )"
T0="$( cat "$DIR/r1.mcp" )"
[ -n "$( printf '%s' "$B0" | routeOf )" ] && [ "$( printf '%s' "$B0" | routeOf )" = "$( printf '%s' "$T0" | routeOf )" ] && [ "$( printf '%s' "$B0" | rows )" = "$( printf '%s' "$T0" | rows )" ]
say $? "(b1) [P] mixed batch, routed item: its <route> and rows equal the top-level MCP for's" "(b1) [P] batch item 0: '${B0:0:300}'"
case "$B1" in *"<route "*) no "(b1) [N] mixed batch, unnamed item was routed" ;; *"<ctx"*) ok "(b1) [N] mixed batch, unnamed item: the ranked <ctx>, no <route>" ;; *) no "(b1) [N] unnamed item: '${B1:0:200}'" ;; esac
case "$B2" in *"<route "*) no "(b1) [N] mixed batch, no_verb_route item was routed" ;; ERR:*) no "(b1) [N] no_verb_route item refused: '${B2:0:200}'" ;; *"<ctx"*) ok "(b1) [N] mixed batch, no_verb_route=true item: the ranked <ctx>, never routed" ;; *) no "(b1) [N] no_verb_route item: '${B2:0:200}'" ;; esac
# (b2) a warned + carried item: the same route and rows as the top-level warned answer, and a carried page
QH='Trace the transitive callers of `report_error`, including callback registrations.'
BH="$( mcpbatch "$DIR/hop" "$( python3 -c 'import json,sys; print(json.dumps([{"verb":"for","task":sys.argv[1]}]))' "$QH" )" 0 )"
TH="$( cat "$DIR/r3.mcp" )"
[ -n "$( printf '%s' "$BH" | routeOf )" ] && [ "$( printf '%s' "$BH" | routeOf )" = "$( printf '%s' "$TH" | routeOf )" ] && [ "$( printf '%s' "$BH" | rows )" = "$( printf '%s' "$TH" | rows )" ] \
    && printf '%s' "$BH" | grep -q '<ctx task='
say $? "(b2) [P] batch, warned item: route, rows and a carried page as the top-level MCP for" "(b2) [P] batch warned item: '${BH:0:300}'"
# (b3) a file-paged item (limit=) is a shaped call: never routed, as at the top level
BL="$( mcpbatch "$DIR/plain" "$( python3 -c 'import json,sys; print(json.dumps([{"verb":"for","task":sys.argv[1],"limit":5}]))' "$QW" )" 0 )"
case "$BL" in *"<route "*) no "(b3) [N] batch item with limit= was routed" ;; ERR:*) no "(b3) [N] batch item with limit= refused: '${BL:0:200}'" ;; *) ok "(b3) [N] batch item with limit=: a file page, never routed" ;; esac

if [ "$fail" = 0 ]; then echo "ALL PASS"; else echo "FAILURES ABOVE"; fi
exit "$fail"
