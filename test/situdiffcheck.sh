#!/usr/bin/env bash
# situdiffcheck.sh — the S5-D situational_awareness(diff) MCP-verb gate.
#
#   test/situdiffcheck.sh                          # uses build/ctxpack on test/zoomfix
#   CTXPACK_BIN=asan/ctxpack test/situdiffcheck.sh
#
# Drives the verb the way an agent would: newline-delimited JSON-RPC over stdin to `ctxpack --mcp`
# (initialize, then tools/call situational_awareness with an explicit changed-file list). Asserts the
# response is the 5-field JSON object — blast_radius, tests_to_run, forgotten, hotspot_alert,
# modules_touched — all present; that blast_radius is computed correctly (the deterministic, git-independent
# signal); that modules_touched names the changed file's directory; and that the call is DETERMINISTIC.
#
# The fixture: changing core/engine.cpp (defines engineRun) must blast-radius into core/scheduler.cpp (calls
# engineRun) and app.cpp (calls schedRun → engineRun). An explicit diff list is used so the gate does not
# depend on the working-tree git state.

set -u
ROOT="$( cd "$( dirname "$0" )/.." && pwd )"
BIN="${1:-${CTXPACK_BIN:-$ROOT/build/ctxpack}}"
[ "${BIN#/}" = "$BIN" ] && BIN="$ROOT/$BIN"          # allow a repo-relative CTXPACK_BIN
CORPUS="$ROOT/test/zoomfix"
TMP="$( mktemp -d )"; trap 'rm -rf "$TMP"' EXIT
fail=0
ok(){ printf '  PASS  %s\n' "$*"; }
no(){ printf '  FAIL  %s\n' "$*"; fail=1; }

[ -x "$BIN" ] || { echo "no ctxpack binary at $BIN — build first (cmake --build build -j)"; exit 2; }
command -v python3 >/dev/null 2>&1 || { echo "python3 required for JSON assertions"; exit 2; }

echo "situdiffcheck: BIN=$BIN  CORPUS=$CORPUS"

# the JSON-RPC handshake: initialize, then tools/call with a changed-file list (core/engine.cpp).
req(){
  printf '%s\n' \
    '{"jsonrpc":"2.0","id":1,"method":"initialize"}' \
    '{"jsonrpc":"2.0","id":2,"method":"tools/call","params":{"name":"situational_awareness","arguments":{"path":"'"$CORPUS"'","diff":"core/engine.cpp"}}}'
}

# 1) determinism — the verb's response is byte-identical across two identical drives.
req | "$BIN" --mcp >"$TMP/a" 2>/dev/null
req | "$BIN" --mcp >"$TMP/b" 2>/dev/null
diff -q "$TMP/a" "$TMP/b" >/dev/null && ok "determinism (byte-identical MCP response)" || no "non-deterministic MCP response"

# extract the inner situational_awareness JSON text (the tools/call response is id=2, last line).
INNER="$( tail -1 "$TMP/a" | python3 -c '
import sys,json
r=json.load(sys.stdin)
if "error" in r: print("__ERROR__:"+json.dumps(r["error"])); sys.exit(0)
print(r["result"]["content"][0]["text"])
' )"
case "$INNER" in __ERROR__*) no "verb returned an error: ${INNER#__ERROR__:}";; esac

# 2) all 5 JSON fields present (the contract: a one-call "what did I forget" object).
printf '%s' "$INNER" | python3 -c '
import sys,json
d=json.load(sys.stdin)
need=["blast_radius","tests_to_run","forgotten","hotspot_alert","modules_touched"]
missing=[k for k in need if k not in d]
print("MISSING:"+",".join(missing) if missing else "OK")
' >"$TMP/fields"
[ "$( cat "$TMP/fields" )" = "OK" ] && ok "all 5 fields present (blast_radius, tests_to_run, forgotten, hotspot_alert, modules_touched)" || no "fields $( cat "$TMP/fields" )"

# 3) blast_radius is correct — the deterministic, git-independent core signal. Changing engine.cpp must reach
#    scheduler.cpp (calls engineRun) AND app.cpp (calls schedRun). Assert both files appear.
printf '%s' "$INNER" | python3 -c '
import sys,json
d=json.load(sys.stdin)
br=[x["file"] for x in d["blast_radius"]]
has_sched=any(f.endswith("/core/scheduler.cpp") for f in br)
has_app  =any(f.endswith("/app.cpp") for f in br)
print("OK" if (has_sched and has_app) else "BAD:"+";".join(br))
' >"$TMP/br"
[ "$( cat "$TMP/br" )" = "OK" ] && ok "blast_radius reaches scheduler.cpp + app.cpp (transitive dependents)" || no "blast_radius wrong: $( cat "$TMP/br" )"

# 4) the changed file itself is reported, and modules_touched names its directory ("core").
printf '%s' "$INNER" | python3 -c '
import sys,json
d=json.load(sys.stdin)
chg=[x["file"] for x in d["changed_files"]]
ok_chg=any(f.endswith("/core/engine.cpp") for f in chg)
ok_mod="core" in d["modules_touched"]
print("OK" if (ok_chg and ok_mod) else "BAD changed=%r modules=%r"%(chg,d["modules_touched"]))
' >"$TMP/mod"
[ "$( cat "$TMP/mod" )" = "OK" ] && ok "changed file reported + modules_touched=['core']" || no "$( cat "$TMP/mod" )"

# 5) the field types are arrays (a well-formed object the agent can consume without guessing shapes).
printf '%s' "$INNER" | python3 -c '
import sys,json
d=json.load(sys.stdin)
bad=[k for k in ["blast_radius","tests_to_run","forgotten","hotspot_alert","modules_touched"] if not isinstance(d.get(k),list)]
print("OK" if not bad else "NON_ARRAY:"+",".join(bad))
' >"$TMP/types"
[ "$( cat "$TMP/types" )" = "OK" ] && ok "all 5 fields are JSON arrays" || no "non-array fields: $( cat "$TMP/types" )"

# 6) clean-tree gate — create a fresh git repo with one committed file (clean working tree) and call
#    situational_awareness with NO diff/files arg. The verb must return a VALID RESULT (not -32602 error)
#    with all 5 fields present as empty arrays. This is the core Bug 12 regression guard.
CLEAN_REPO="$TMP/clean_repo"
mkdir -p "$CLEAN_REPO"
git -C "$CLEAN_REPO" init -q
git -C "$CLEAN_REPO" config user.email "test@test.com"
git -C "$CLEAN_REPO" config user.name "Test"
# create one committed C source file so ctxpack has something to ingest (avoids empty-dir edge case).
printf 'int main(void) { return 0; }\n' > "$CLEAN_REPO/main.c"
git -C "$CLEAN_REPO" add main.c
git -C "$CLEAN_REPO" commit -q -m "init"
# now the tree is perfectly clean — no uncommitted changes.
CLEAN_RESP="$( printf '%s\n' \
  '{"jsonrpc":"2.0","id":1,"method":"initialize"}' \
  '{"jsonrpc":"2.0","id":2,"method":"tools/call","params":{"name":"situational_awareness","arguments":{"path":"'"$CLEAN_REPO"'"}}}' \
  | "$BIN" --mcp 2>/dev/null | tail -1 )"
printf '%s' "$CLEAN_RESP" | python3 -c '
import sys,json
try:
    r=json.load(sys.stdin)
    if "error" in r:
        print("ERROR:-32602" if r["error"].get("code")==-32602 else "ERROR:other:"+json.dumps(r["error"]))
        sys.exit(0)
    d=json.loads(r["result"]["content"][0]["text"])
    need=["blast_radius","tests_to_run","forgotten","hotspot_alert","modules_touched"]
    missing=[k for k in need if k not in d]
    if missing: print("MISSING_FIELDS:"+",".join(missing)); sys.exit(0)
    non_empty=[k for k in need if d[k]]
    if non_empty: print("NON_EMPTY:"+",".join(non_empty)); sys.exit(0)
    print("OK")
except Exception as e:
    print("EXCEPTION:"+str(e))
' >"$TMP/clean"
[ "$( cat "$TMP/clean" )" = "OK" ] \
  && ok "clean-tree: valid result with all-empty arrays (no -32602 error)" \
  || no "clean-tree: expected valid empty result, got: $( cat "$TMP/clean" )"

# 7) the git-diff DEFAULT path on fixture corpus — omitting diff/files on the fixture repo (which may or may
#    not have uncommitted changes in the worktree) must also return a VALID result (not an error), because
#    the fixture is always inside a git repo. Either an empty-arrays result (clean) or a populated one (dirty).
printf '%s\n' \
  '{"jsonrpc":"2.0","id":1,"method":"initialize"}' \
  '{"jsonrpc":"2.0","id":2,"method":"tools/call","params":{"name":"situational_awareness","arguments":{"path":"'"$CORPUS"'"}}}' \
  | "$BIN" --mcp 2>/dev/null | tail -1 | python3 -c '
import sys,json
try:
    r=json.load(sys.stdin)
    if "error" in r:
        print("ERROR:"+json.dumps(r["error"]))
        sys.exit(0)
    d=json.loads(r["result"]["content"][0]["text"])
    need=["blast_radius","tests_to_run","forgotten","hotspot_alert","modules_touched"]
    missing=[k for k in need if k not in d]
    print("MISSING:"+",".join(missing) if missing else "OK")
except Exception as e:
    print("BAD:"+str(e))
' >"$TMP/def"
[ "$( cat "$TMP/def" )" = "OK" ] && ok "git-diff default path returns valid 5-field result (no error)" || no "default path: $( cat "$TMP/def" )"

# 8) §H6b — the verb's git-diff DEFAULT path resolves changed paths through the ONE shared join, so it must
#    work when the scanned root is a SUBDIR of the repo and every indexed path is spelled "./<name>".
#    situ.h's gitDiffChangedMask delegates to prcontext.h's gitDiffChangedMaskNumstat, which until §H6b
#    carried its own anchored-then-suffix join: the anchored pass only fires when the root IS the repo
#    toplevel, and "./util.h" is not a boundary-suffix of git's "src/util.h", so the verb reported
#    changed_files=[] with the note "0 changed files — working tree is clean" on a tree that was not clean.
#    (The CLI --situ takes a DIFFERENT builder — main.cpp's gitChangedFiles, git diff --name-only — which has
#    been on the shared join since §H6; this arm covers the MCP half, which is the one that inherited §H6b.)
SUBREPO="$TMP/subrepo"
mkdir -p "$SUBREPO/src"
git -C "$SUBREPO" init -q
git -C "$SUBREPO" config user.email "test@test.com"
git -C "$SUBREPO" config user.name "Test"
printf 'int utilAlpha( int a ) { return a + 1; }\n'                >"$SUBREPO/src/util.h"
printf '#include "util.h"\nint appMain() { return utilAlpha( 2 ); }\n' >"$SUBREPO/src/app.cpp"
git -C "$SUBREPO" add -A
git -C "$SUBREPO" commit -qm init
printf 'int utilAlpha( int a ) { return a + 2; }\nint utilGamma() { return 9; }\n' >"$SUBREPO/src/util.h"
#    The root must be spelled "." (cwd = the subdir): an ABSOLUTE "$SUBREPO/src" makes every indexed path
#    end with git's "src/util.h", so the old suffix fallback bound it by luck of spelling and the arm would
#    pass on the pre-fix binary for the wrong reason. "." is the spelling that has no such tail.
( cd "$SUBREPO/src" && printf '%s\n' \
  '{"jsonrpc":"2.0","id":1,"method":"initialize"}' \
  '{"jsonrpc":"2.0","id":2,"method":"tools/call","params":{"name":"situational_awareness","arguments":{"path":"."}}}' \
  | "$BIN" --mcp 2>/dev/null | tail -1 ) | python3 -c '
import sys,json
try:
    r=json.load(sys.stdin)
    if "error" in r: print("ERROR:"+json.dumps(r["error"])); sys.exit(0)
    d=json.loads(r["result"]["content"][0]["text"])
    chg=[x["file"] for x in d.get("changed_files",[])]
    note=d.get("note","")
    if len(chg)==1 and chg[0].endswith("/util.h") and "clean" not in note: print("OK")
    else: print("BAD changed=%r note=%r"%(chg,note))
except Exception as e:
    print("BAD:"+str(e))
' >"$TMP/subroot"
[ "$( cat "$TMP/subroot" )" = "OK" ] \
  && ok "§H6b: subdir root (paths spelled ./name) binds its changed file — not a false 'working tree is clean'" \
  || no "§H6b: subdir root: $( cat "$TMP/subroot" )"

# ── THE CLI AND THE MCP FORM OF THE SAME VERB MUST BUILD THE SAME CHANGED SET ────────────────────────
# situ.h's mask builder is `git diff --numstat`-based and drops a content-identical entry — git reports
# "0<TAB>0<TAB>path" for a pure mode flip, which `--name-only` cannot tell from a real edit. Its header
# records the incident that bought that fix: a mass chmod turned into a 272-file "change set" of pure noise.
# The MCP arms called it; the CLI (--situ / --test-gate / --map-diff / --eval) went through a SECOND builder
# in main.cpp that still ran --name-only, so the two forms of one verb disagreed about exactly that shape.
#
# And the disagreement was not merely noisy. In this fixture the chmod lands on the TEST file, so on the
# unconverged CLI the test is inside the change set and therefore not counted as blast radius: --test-gate
# reported changed="4" impacted="0" tests="0" and exited 0 — a clean bill of health on a change that needs a
# test run — while the MCP verb on the same tree named src/core.cpp alone. The inflation SWALLOWED the
# obligation. Both arms now call situ.h's gitDiffChangedMask; this asserts the property, not the agreement of
# two implementations that happen to match today.
MODEREPO="$TMP/modeonly"; mkdir -p "$MODEREPO/src" "$MODEREPO/test"
printf 'int engineRun( int x ) { return x + 1; }\n'                            > "$MODEREPO/src/core.cpp"
printf 'int alpha( int x ) { return x; }\n'                                    > "$MODEREPO/src/one.cpp"
printf 'int beta( int x ) { return x; }\n'                                     > "$MODEREPO/src/two.cpp"
printf 'int engineRun( int x );\nint testEngine( void ) { return engineRun( 1 ); }\n' > "$MODEREPO/test/t_core.cpp"
( cd "$MODEREPO" && git init -q && git config user.email t@t && git config user.name t \
  && git add -A && git commit -qm init >/dev/null 2>&1 )
printf 'int engineRun( int x ) { return x + 2; }\n' > "$MODEREPO/src/core.cpp"   # the ONE real edit
chmod 755 "$MODEREPO/src/one.cpp" "$MODEREPO/src/two.cpp" "$MODEREPO/test/t_core.cpp"

# the premise, asserted rather than assumed: git must really report three 0/0 rows beside one content row,
# or every arm below is measuring a tree that has nothing to disagree about.
NUMSTAT_ZERO="$( git -C "$MODEREPO" diff --numstat HEAD | grep -c '^0	0	' )"
[ "$NUMSTAT_ZERO" = 3 ] \
    && ok "mode-only premise: git reports 3 content-identical (0/0) rows beside 1 real edit" \
    || no "mode-only premise broken: expected 3 pure mode-flip rows, git reports $NUMSTAT_ZERO — the arms below prove nothing"

CLI_SITU="$( "$BIN" "$MODEREPO" --situ --no-cache 2>/dev/null | head -1 )"
printf '%s' "$CLI_SITU" | grep -q '1 changed file(s)' \
    && ok "CLI --situ counts the 1 real edit, not the 3 chmods" \
    || no "CLI --situ change set inflated by mode-only entries: $CLI_SITU"

CLI_TG="$( "$BIN" "$MODEREPO" --test-gate --no-cache 2>/dev/null | grep -oE '<test-gate [^>]*' )"
"$BIN" "$MODEREPO" --test-gate --no-cache >/dev/null 2>&1; TG_RC=$?
{ printf '%s' "$CLI_TG" | grep -q 'changed="1"' && printf '%s' "$CLI_TG" | grep -q 'tests="1"' && [ "$TG_RC" = 4 ]; } \
    && ok "CLI --test-gate names the impacted test and exits 4 (the chmod no longer hides the obligation)" \
    || no "CLI --test-gate wrong on the mode-only tree (rc=$TG_RC): $CLI_TG"

# the MCP arm on the SAME tree, taking its change set from git the same way (no explicit diff= argument).
MCP_CHANGED="$( printf '%s\n' \
  '{"jsonrpc":"2.0","id":1,"method":"initialize"}' \
  '{"jsonrpc":"2.0","id":2,"method":"tools/call","params":{"name":"situational_awareness","arguments":{"path":"'"$MODEREPO"'"}}}' \
  | "$BIN" --mcp 2>/dev/null | tail -1 | python3 -c '
import sys,json
try:
    r=json.load(sys.stdin)
    if "error" in r: print("ERROR:"+json.dumps(r["error"])); sys.exit(0)
    d=json.loads(r["result"]["content"][0]["text"])
    print(",".join(sorted(x["file"].rsplit("/",2)[-2]+"/"+x["file"].rsplit("/",1)[-1] for x in d.get("changed_files",[]))))
except Exception as e:
    print("ERROR:"+str(e))
' )"
[ "$MCP_CHANGED" = "src/core.cpp" ] \
    && ok "MCP situational_awareness names the same single changed file" \
    || no "MCP changed set is not src/core.cpp alone: $MCP_CHANGED"

# THE ARM: the two surfaces must AGREE, stated as an equality rather than as two separate expectations —
# an arm that only checks each side against a constant goes green if both drift the same way.
CLI_COUNT="$( printf '%s' "$CLI_SITU" | grep -oE '[0-9]+ changed file' | grep -oE '^[0-9]+' )"
MCP_COUNT="$( [ -z "$MCP_CHANGED" ] && echo 0 || printf '%s' "$MCP_CHANGED" | tr ',' '\n' | grep -c . )"
[ "${CLI_COUNT:-x}" = "${MCP_COUNT:-y}" ] \
    && ok "CLI and MCP agree about the mass chmod (both $CLI_COUNT changed file(s)) — one mask builder, two surfaces" \
    || no "the CLI and MCP forms of one verb disagree about the change set: CLI=${CLI_COUNT:-<unread>} MCP=${MCP_COUNT:-<unread>}"

[ "$fail" -eq 0 ] && echo "ALL PASS" || echo "SOME FAILED"
exit "$fail"
