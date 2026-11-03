#!/usr/bin/env bash
# mcptoolsubsetcheck.sh — `--mcp-tools=SPEC` lists a SUBSET of the MCP catalog, and the subset is never silent.
#
# THE COST IT EXISTS FOR. tools/list is ~46 KB (~11.6K tokens) for 33 tools, and a client that loads schemas eagerly
# pays it at every session start whether a tool is called or not. `--mcp-tools=` takes a comma list of tool names
# and/or profiles (`core` = the loop the server's own instructions teach, `full` = everything), unioned.
#
# THE CONTRACT this gate holds:
#   (A) no flag and `--mcp-tools=full` are the SAME server: initialize and tools/list byte-identical.
#   (B) [red] `--mcp-tools=core` lists exactly the core set, each stanza byte-identical to the full list's, and the
#             response is valid JSON; a 3-tool allowlist lists exactly those 3.
#   (C) [red] initialize announces the subset (N of 33, the flag), and its instructions name NO tool the subset hides
#             (the 3-tool allowlist drops the hints for explore/from_trace/edit_check/quality_delta/batch); with every
#             instruction-named tool listed (core) the base instructions are unchanged.
#   (D) [red] a tools/call of a hidden tool is REFUSED (-32602) naming the restart that enables it, and the batch
#             sub-query when batch serves it; the pack_task alias follows explore. Never answers, never "unknown tool".
#   (E) [red] listed tools still answer under a subset, and batch still serves a sub-verb the subset hides.
#   (F) [red] the unknown-tool refusal counts the LISTED tools, not 33.
#   (G) [red] argv validation: unknown name (with its near miss and the valid names), a duplicate, an empty item,
#             an empty value, and the flag without --mcp/--listen — each exits 1 with its reason on stderr.
#   (H) [red] the --listen transport lists the same subset.
#   (I) [red] `ripwire wrap` passes the flag into the server command it prints (claude, cursor, opencode), counts
#             the listed verbs, says where it could not pass it (codex), refuses a bad spec, and without the flag
#             (or with `full`) prints the unchanged recipe.
#
# Usage: bash test/mcptoolsubsetcheck.sh [BIN]      Exits non-zero on any failure.

set -u
ROOT="$( cd "$( dirname "$0" )/.." && pwd )"
. "$ROOT/test/lib/clean-env.sh"
BIN="${1:-${RIPWIRE_BIN:-$ROOT/build/ripwire}}"
[ "${BIN#/}" = "$BIN" ] && BIN="$ROOT/$BIN"
TMP="$( mktemp -d )"
SRV_PID=""
cleanup(){ [ -n "$SRV_PID" ] && kill "$SRV_PID" 2>/dev/null; rm -rf "$TMP"; }
trap 'cleanup' EXIT
fail=0
ok(){ printf '  PASS  %s\n' "$*" || { fail=1; printf '  FAIL  could not write the PASS line for: %s\n' "$*"; }; return 0; }
no(){ printf '  FAIL  %s\n' "$*"; fail=1; }

[ -x "$BIN" ] || { echo "no ripwire binary at $BIN — build first (cmake --build build -j)"; exit 2; }
command -v python3 >/dev/null 2>&1 || { echo "python3 required for JSON assertions"; exit 2; }
echo "mcptoolsubsetcheck: BIN=$BIN"

FIX="$TMP/fix"; cp -R "$ROOT/test/zoomfix" "$FIX"
CORE="batch edit_check explore fetch_body from_trace impact quality_delta uses"
INIT='{"jsonrpc":"2.0","id":1,"method":"initialize"}'
LIST='{"jsonrpc":"2.0","id":2,"method":"tools/list"}'

# $1.. = extra server args; stdin = request lines; stdout = one response per line
serve(){ "$BIN" "$FIX" --mcp "$@" 2>"$TMP/serve.err"; }

printf '%s\n%s\n' "$INIT" "$LIST" | serve                      >"$TMP/default.out"
printf '%s\n%s\n' "$INIT" "$LIST" | serve --mcp-tools=full     >"$TMP/full.out"
printf '%s\n%s\n' "$INIT" "$LIST" | serve --mcp-tools=core     >"$TMP/core.out"
printf '%s\n%s\n' "$INIT" "$LIST" | serve --mcp-tools=grep,impact,uses >"$TMP/three.out"
printf '%s\n%s\n' "$INIT" "$LIST" | serve --mcp-tools=no-edit  >"$TMP/noedit.out"

echo; echo "=== (A) no flag == --mcp-tools=full, byte for byte ==="
if [ -s "$TMP/default.out" ] && cmp -s "$TMP/default.out" "$TMP/full.out"; then
    ok "(A) initialize + tools/list identical ($( wc -c <"$TMP/default.out" | tr -d ' ' ) B)"
else
    no "(A) --mcp-tools=full differs from the default server (or produced nothing): $( head -c 200 "$TMP/serve.err" )"
fi

# Every JSON verdict below comes from ONE python pass per response file; it prints PASS/FAIL lines itself.
judge(){ python3 - "$@" <<'PY'
import json, re, sys
mode = sys.argv[1]
def lines(p):
    try:
        return [json.loads(l) for l in open(p) if l.strip()]
    except Exception as e:
        return "unparseable: %s" % e
def names(r): return [t["name"] for t in r["result"]["tools"]]
out = []
full = lines(sys.argv[2])
if mode == "list":
    sub = lines(sys.argv[3]); want = sorted(sys.argv[4].split()); tag = sys.argv[5]
    if isinstance(sub, str) or isinstance(full, str) or len(sub) < 2 or "result" not in sub[1]:
        print("FAIL %s: tools/list did not answer: %r" % (tag, sub if isinstance(sub, str) else sub[-1:])); sys.exit(0)
    got = sorted(names(sub[1]))
    print(("PASS" if got == want else "FAIL") + " %s: lists %s (want %s)" % (tag, " ".join(got), " ".join(want)))
    byname = {t["name"]: t for t in full[1]["result"]["tools"]}
    same = all(json.dumps(t, sort_keys=True) == json.dumps(byname.get(t["name"]), sort_keys=True) for t in sub[1]["result"]["tools"])
    print(("PASS" if same else "FAIL") + " %s: every listed stanza is byte-identical to the full catalog's" % tag)
    ins = sub[0]["result"]["instructions"]; base = full[0]["result"]["instructions"]
    alltools = names(full[1])
    # `for` is exempt: the instructions use the English preposition ("for an error"), and every description names
    # the tool in quotes ('for'); src/mcp.h's consteval hint check makes the same exemption, with the same reason.
    hidden = [n for n in alltools if n not in want and n != "for"]
    named_hidden = [n for n in hidden if re.search(r"(?<![a-z_])%s(?![a-z_])" % re.escape(n), ins)]
    print(("PASS" if not named_hidden else "FAIL") + " %s: instructions name no hidden tool%s" % (tag, (" (named: %s)" % named_hidden) if named_hidden else ""))
    m = re.search(r"TOOL SUBSET: this server lists (\d+) of (\d+) tools \(--mcp-tools=([a-z_,-]+)\)", ins)
    good = m and m.group(1) == str(len(want)) and m.group(2) == str(len(alltools))
    print(("PASS" if good else "FAIL") + " %s: instructions announce the subset (%s)" % (tag, m.group(0) if m else "no TOOL SUBSET sentence"))
    if len(sys.argv) > 6:   # the base text must survive unchanged when every tool it names is listed
        print(("PASS" if ins.startswith(base) else "FAIL") + " %s: the base instructions are unchanged ahead of the note" % tag)
PY
}
report(){ while IFS= read -r l; do case "$l" in PASS*) ok "${l#PASS }";; *) no "${l#FAIL }";; esac; done; }

echo; echo "=== (B)+(C) core and a 3-tool allowlist: what is listed, and what initialize says ==="
judge list "$TMP/full.out" "$TMP/core.out" "$CORE" "(B/C) core" keepbase | report
judge list "$TMP/full.out" "$TMP/three.out" "grep impact uses" "(B/C) grep,impact,uses" | report
# `no-edit` (what `ripwire wrap claude` registers) = the whole catalog minus the three span-addressed edit twins.
NOEDIT="$( python3 -c '
import json, sys
t = [x["name"] for x in json.loads(open(sys.argv[1]).readlines()[1])["result"]["tools"]]
print(" ".join(n for n in t if n not in ("replace_symbol_body", "insert_before_symbol", "insert_after_symbol")))' "$TMP/full.out" )"
judge list "$TMP/full.out" "$TMP/noedit.out" "$NOEDIT" "(B/C) no-edit" keepbase | report
python3 - "$TMP/three.out" <<'PY' | report
import json, sys
ins = json.loads(open(sys.argv[1]).readline())["result"]["instructions"]
want = ["Use impact before changing a symbol.", "Use uses to see its read/write/import sites."]
print(("PASS" if all(w in ins for w in want) else "FAIL") + " (C) the allowlist keeps the hints for the tools it lists (impact, uses)")
PY

echo; echo "=== (D) a hidden tool is refused with the way to enable it ==="
call(){ printf '%s\n%s\n' "$INIT" "$2" | serve "$1" | tail -1; }
R_FOR="$( call --mcp-tools=core '{"jsonrpc":"2.0","id":3,"method":"tools/call","params":{"name":"for","arguments":{"task":"schedRun"}}}' )"
R_PACK="$( call --mcp-tools=grep,impact,uses '{"jsonrpc":"2.0","id":3,"method":"tools/call","params":{"name":"pack_task","arguments":{"task":"schedRun"}}}' )"
R_EDIT="$( call --mcp-tools=core '{"jsonrpc":"2.0","id":3,"method":"tools/call","params":{"name":"replace_symbol_body","arguments":{"symbol":"x","new_body":"int x;"}}}' )"
python3 - "$R_FOR" "$R_PACK" "$R_EDIT" <<'PY' | report
import json, sys
def err(s):
    try: return json.loads(s).get("error") or {}
    except Exception: return {}
f, p, e = (err(s) for s in sys.argv[1:4])
m = f.get("message", "")
ok = f.get("code") == -32602 and "not enabled" in m and "--mcp-tools=core,for" in m and "--mcp-tools=full" in m and '"verb":"for"' in m
print(("PASS" if ok else "FAIL") + " (D) for under core: -32602 naming --mcp-tools=core,for / full and the batch sub-query: %r" % m[:240])
m = p.get("message", "")
ok = p.get("code") == -32602 and "'pack_task'" in m and "--mcp-tools=grep,impact,uses,explore" in m and "batch" not in m
print(("PASS" if ok else "FAIL") + " (D) pack_task follows explore; no batch offer when batch is hidden: %r" % m[:240])
m = e.get("message", "")
ok = e.get("code") == -32602 and "--mcp-tools=core,replace_symbol_body" in m and "batch sub-query" not in m
print(("PASS" if ok else "FAIL") + " (D) an edit verb hidden by core is refused, with no batch offer (batch does not serve it): %r" % m[:240])
PY

echo; echo "=== (E) listed tools answer; batch serves a hidden sub-verb ==="
R_IMP="$( call --mcp-tools=core '{"jsonrpc":"2.0","id":4,"method":"tools/call","params":{"name":"impact","arguments":{"symbol":"schedRun"}}}' )"
R_BAT="$( call --mcp-tools=core '{"jsonrpc":"2.0","id":5,"method":"tools/call","params":{"name":"batch","arguments":{"queries":["grep:schedRun"]}}}' )"
python3 - "$R_IMP" "$R_BAT" <<'PY' | report
import json, sys
i, b = (json.loads(s) if s.strip() else {} for s in sys.argv[1:3])
print(("PASS" if "result" in i else "FAIL") + " (E) impact answers under core: %s" % (list(i.keys())))
t = b.get("result", {}).get("content", [{}])[0].get("text", "")
print(("PASS" if 'verb="grep"' in t and 'ok="1"' in t else "FAIL") + " (E) batch answers a grep sub-query under core (grep itself is not listed): %r" % t[:160])
PY

echo; echo "=== (F) the unknown-tool refusal counts the listed tools ==="
R_UNK="$( call --mcp-tools=core '{"jsonrpc":"2.0","id":6,"method":"tools/call","params":{"name":"no_such_tool","arguments":{}}}' )"
case "$R_UNK" in *"for the 8 available tools"*) ok "(F) unknown tool under core: 'call tools/list for the 8 available tools'";;
                 *) no "(F) unknown-tool refusal under core does not count 8: $( printf '%s' "$R_UNK" | cut -c1-240 )";; esac

echo; echo "=== (G) argv validation ==="
refuse(){ # $1 = label, $2 = stderr substring, rest = args
    local label="$1" want="$2"; shift 2
    printf '%s\n' "$INIT" | "$BIN" "$FIX" "$@" >"$TMP/g.out" 2>"$TMP/g.err"; local rc=$?
    if [ "$rc" = 1 ] && grep -qF -- "$want" "$TMP/g.err" && [ ! -s "$TMP/g.out" ]; then ok "(G) $label: exit 1, '$want'"
    else no "(G) $label: rc=$rc stderr=$( head -c 240 "$TMP/g.err" ) stdout=$( head -c 80 "$TMP/g.out" )"; fi
}
refuse "unknown name + near miss"  "unknown tool 'fro' (did you mean 'for'?)" --mcp --mcp-tools=core,fro
refuse "unknown name lists valid"   "core, no-edit, full (profiles); analyze"  --mcp --mcp-tools=nope
refuse "duplicate"                  "names 'impact' twice"                     --mcp --mcp-tools=impact,uses,impact
refuse "empty item"                 "empty name"                               --mcp --mcp-tools=impact,,uses
refuse "empty value"                "--mcp-tools="                             --mcp --mcp-tools=
refuse "without --mcp/--listen"     "--mcp-tools is read by the MCP server"    --mcp-tools=core

echo; echo "=== (H) --listen lists the same subset ==="
. "$ROOT/test/lib/gatehttp.sh"
GATEHTTP="$( gatehttp_install "$TMP" )" || { no "(H) could not install the shared HTTP client"; GATEHTTP=""; }
PORT=$(( 25000 + ( $$ % 4000 ) ))
if [ -n "$GATEHTTP" ]; then
    "$BIN" "$FIX" --listen=127.0.0.1:"$PORT" --mcp-tools=grep,impact,uses >"$TMP/srv.out" 2>"$TMP/srv.err" &
    SRV_PID=$!
    if python3 "$GATEHTTP" wait "$PORT" "$SRV_PID" >"$TMP/srv.why"; then
        H_LIST="$( python3 "$GATEHTTP" post "$PORT" "$LIST" 30 2>/dev/null )"
        H_NAMES="$( printf '%s' "$H_LIST" | python3 -c 'import json,sys; print(" ".join(sorted(t["name"] for t in json.load(sys.stdin)["result"]["tools"])))' 2>/dev/null )"
        if [ "$H_NAMES" = "grep impact uses" ]; then ok "(H) --listen tools/list: $H_NAMES"; else no "(H) --listen tools/list: '$H_NAMES'"; fi
    else
        no "(H) listener did not answer: $( cat "$TMP/srv.why" ) $( head -c 200 "$TMP/srv.err" )"
    fi
    kill "$SRV_PID" 2>/dev/null; wait "$SRV_PID" 2>/dev/null; SRV_PID=""
fi

echo; echo "=== (I) ripwire wrap passes the subset through ==="
WRAPDIR="$TMP/wrapcwd"; mkdir -p "$WRAPDIR"
wrap(){ ( cd "$WRAPDIR" && "$BIN" wrap "$@" 2>"$TMP/wrap.err" ); }
wrap claude >"$TMP/w.default"; wrap claude --mcp-tools=full >"$TMP/w.full"; wrap claude --mcp-tools=core >"$TMP/w.core"
# check LABEL CMD... — one verdict per arm, through if/else (a failed PASS write must never read as FAIL)
check(){ local label="$1"; shift; if "$@"; then ok "$label"; else no "$label"; fi; }
same_recipe(){ [ -s "$TMP/w.cursor.default" ] && cmp -s "$TMP/w.cursor.default" "$TMP/w.cursor.full"; }
# claude is the one agent whose DEFAULT recipe is a subset: Claude Code must Read before it edits, so it registers the
# server WITHOUT the three edit twins (--mcp-tools=no-edit); an explicit --mcp-tools=full gets the whole catalog back.
claude_default_no_edit(){ grep -qE -- '^claude mcp add ripwire -- .* --mcp --mcp-tools=no-edit$' "$TMP/w.default" \
                          && grep -qF '(30 total)' "$TMP/w.default" && ! grep -qE '^#   edit:' "$TMP/w.default"; }
claude_full_has_edit(){ grep -qE -- '^claude mcp add ripwire -- .* --mcp$' "$TMP/w.full" \
                        && grep -qF '(33 total)' "$TMP/w.full" && grep -qE '^#   edit:' "$TMP/w.full"; }
core_listing(){ grep -qF '(8 total)' "$TMP/w.core" && ! grep -qE '^#   edit:' "$TMP/w.core"; }
wrap cursor >"$TMP/w.cursor.default"; wrap cursor --mcp-tools=full >"$TMP/w.cursor.full"
check "(I) wrap cursor: --mcp-tools=full prints the unchanged recipe (no flag == full for an agent with no read-before-edit rule)" same_recipe
check "(I) wrap claude: the DEFAULT server command carries --mcp-tools=no-edit and lists 30 tools, no edit group" claude_default_no_edit
check "(I) wrap claude: --mcp-tools=full restores the unflagged command, 33 tools, the edit group" claude_full_has_edit
check "(I) wrap claude: the server command carries --mcp-tools=core" grep -qE -- '^claude mcp add ripwire -- .* --mcp --mcp-tools=core$' "$TMP/w.core"
check "(I) wrap claude: the verb list counts the 8 listed tools and drops the empty edit group" core_listing
wrap cursor --mcp-tools=core >"$TMP/w.cursor"
check "(I) wrap cursor: JSON args carry the flag" grep -qF '"args": ["--mcp", "--mcp-tools=core"]' "$TMP/w.cursor"
wrap opencode --mcp-tools=core >"$TMP/w.opencode"
check "(I) wrap opencode: the command array carries the flag" grep -qF '"--mcp", "--mcp-tools=core"]' "$TMP/w.opencode"
wrap codex --mcp-tools=core >"$TMP/w.codex"
check "(I) wrap codex: says the flag was not written into its form" grep -qF 'NOTE: --mcp-tools=core is not written into' "$TMP/w.codex"
wrap claude --mcp-tools=bogus >"$TMP/w.bad"; rc=$?
bad_refused(){ [ "$rc" = 2 ] && grep -qF "unknown tool 'bogus'" "$TMP/wrap.err"; }
check "(I) wrap claude --mcp-tools=bogus: exit 2, named (rc=$rc)" bad_refused

echo
if [ "$fail" = 0 ]; then echo "ALL PASS"; exit 0; fi
echo "SOME CHECKS FAILED"; exit 1
