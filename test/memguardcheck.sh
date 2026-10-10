#!/usr/bin/env bash
# memguardcheck.sh — #350 layers 1 + 3: a root nobody chose is refused, and memory is bounded on every root.
#
# The incident: an MCP server started in a home directory that is not a git repository crawled it for 7 hours
# and reached a 67 GB footprint. Two layers are pinned here (layer 2, the non-git crawl budget, is separate):
#
#   (A) layer 1 — an IMPLICIT root that is $HOME itself (git repo or not), "/" or a system directory is refused
#       with one honest line, on the CLI (no positional root, cwd there) and on the MCP server (launch cwd, no
#       path= in the request); the server stays up. An EXPLICIT path is honoured, the home directory included.
#   (B) layer 3 — the memory guard. A tiny --max-memory stops the crawl or the parse and the map answers from
#       what was built, DISCLOSED in its header (memory_stop=), well-formed and deterministic; a limit no partial
#       answer fits under is a clean exit 5 naming the limit and the override; a verb that cannot carry the
#       disclosure refuses rather than answering from a partial index.
#   (C) a default run is byte-identical to the same run with the guard's limit made huge (flag and env).
#   (D) bad --max-memory / RIPWIRE_MAX_MEMORY values are refused with a message.
#
# Real footprints are machine-dependent, so the partial arms inject the trip instead: RIPWIRE_TEST_MEMGUARD=
# crawl:N makes the crawl's Nth guarded entry read as over its line, parse:N the Nth parsed file, request:N the
# Nth MCP tool call's pre-check; the 5 s time gate is off under it. The stop, the partial answer and the
# disclosure are the real code paths; only the footprint reading is replaced. Nothing here crawls a real home
# directory or a system tree: every home is a fake one under a temp dir, and the system-directory arms only
# ever reach the refusal (a regression that crawled instead would still be a tiny /dev walk).
#
#   bash test/memguardcheck.sh [path/to/ripwire]

set -u
ROOT="$( cd "$( dirname "$0" )/.." && pwd )"
. "$ROOT/test/lib/clean-env.sh"   # no inherited agent homes or GIT_* repository selection (the gate builds a repo)
BIN="${1:-${RIPWIRE_BIN:-$ROOT/build/ripwire}}"
[ "${BIN#/}" = "$BIN" ] && BIN="$ROOT/$BIN"
TMP="$( mktemp -d )"; trap 'rm -rf "$TMP"' EXIT
TMP="$( cd "$TMP" && pwd -P )"
fail=0
ok(){ printf '  PASS  %s\n' "$*" || { fail=1; printf '  FAIL  could not write the PASS line for: %s\n' "$*"; }; return 0; }
no(){ printf '  FAIL  %s\n' "$*"; fail=1; }

[ -x "$BIN" ] || { echo "no ripwire binary at $BIN — build first"; exit 2; }
echo "memguardcheck: BIN=$BIN"

# ── fixtures ────────────────────────────────────────────────────────────────────────────────────────────────
# FX: 72 C files in 4 directories, each function calling the previous one (a real call graph to rank).
FX="$TMP/fx"
for d in a b c d; do
    mkdir -p "$FX/$d"
    for i in $( seq -w 0 17 ); do
        printf 'int %s%s( int x );\nint %s_%s( int x ) { return x > 0 ? %s_%s( x - 1 ) : 0; }\n' \
            "p" "$i" "$d" "$i" "$d" "$i" >"$FX/$d/f$i.c"
    done
done

HOMEDIR="$TMP/home"; mkdir -p "$HOMEDIR/proj"
printf 'int hp( void ) { return 1; }\nint hq( void ) { return hp(); }\n' >"$HOMEDIR/proj/p.c"
printf 'int dot( void ) { return 0; }\n' >"$HOMEDIR/dot.c"
GITHOME="$TMP/githome"; mkdir -p "$GITHOME/proj"
cp "$HOMEDIR/proj/p.c" "$GITHOME/proj/p.c"
git -C "$GITHOME" init -q 2>/dev/null

mcp_call(){   # $1 = cwd, $2.. = extra argv; stdin = request lines (after initialize)
    local cwd="$1"; shift
    # S7 fence: a regression that let a server crawl "/" or a system tree stops at 2,000 entries and 120 s, never the disk
    { printf '%s\n' '{"jsonrpc":"2.0","id":1,"method":"initialize"}'; cat; } \
        | ( cd "$cwd" && RIPWIRE_TEST_MEMGUARD="${RIPWIRE_TEST_MEMGUARD:-crawl:2000}" perl -e 'alarm shift; exec @ARGV' 120 "$BIN" --mcp "$@" 2>/dev/null )
}
mcp_field(){  # $1 = response file, $2 = id, $3 = error|text|<envelope key>
    python3 - "$1" "$2" "$3" <<'PY'
import json, sys
path, want_id, what = sys.argv[1], int( sys.argv[2] ), sys.argv[3]
for line in open( path, encoding="utf-8", errors="replace" ):
    line = line.strip()
    if not line.startswith( "{" ):
        continue
    try:
        r = json.loads( line )
    except ValueError:
        continue
    if r.get( "id" ) != want_id:
        continue
    res = r.get( "result", {} )
    if what == "error":
        e = r.get( "error" )
        if e:
            print( e.get( "message", "" ) ); break
        if res.get( "isError" ):
            print( "".join( c.get( "text", "" ) for c in res.get( "content", [] ) ) ); break
        print( "" ); break
    if what == "text":
        print( "".join( c.get( "text", "" ) for c in res.get( "content", [] ) ) ); break
    print( res.get( what, "" ) ); break
PY
}

echo "=== (A) layer 1: an implicit home/system root is refused; an explicit one is honoured ==="

# (A1) CLI, no positional root, cwd = $HOME (not a git repo): one honest line, exit 1
( cd "$HOMEDIR" && HOME="$HOMEDIR" "$BIN" --grep=dot >"$TMP/a1.out" 2>"$TMP/a1.err" ); rc=$?
if [ "$rc" = 1 ] && grep -q "no project root: $HOMEDIR is a home/system directory; pass a project path" "$TMP/a1.err" && [ ! -s "$TMP/a1.out" ]; then
    ok "(A1) CLI with no root in \$HOME refuses with the no-project-root line (exit 1, empty stdout)"
else
    no "(A1) rc=$rc stderr: $( head -c 300 "$TMP/a1.err" )"
fi

# (A2) the same when $HOME is itself a git repository (a dotfiles repo is still nobody's project root)
( cd "$GITHOME" && HOME="$GITHOME" "$BIN" --grep=hp >"$TMP/a2.out" 2>"$TMP/a2.err" ); rc=$?
if [ "$rc" = 1 ] && grep -q "no project root: $GITHOME is a home/system directory" "$TMP/a2.err"; then
    ok "(A2) a git-repo \$HOME is refused as an implicit root too"
else
    no "(A2) rc=$rc stderr: $( head -c 300 "$TMP/a2.err" )"
fi

# (A3) CLI, no root, cwd = a directory that is neither home nor system: the usage refusal, unchanged
( cd "$HOMEDIR/proj" && HOME="$HOMEDIR" "$BIN" --grep=hp >/dev/null 2>"$TMP/a3.err" ); rc=$?
if [ "$rc" = 1 ] && ! grep -q "no project root" "$TMP/a3.err"; then
    ok "(A3) a missing root in an ordinary directory keeps the plain usage refusal"
else
    no "(A3) rc=$rc stderr: $( head -c 200 "$TMP/a3.err" )"
fi

# (A4) MCP launched in $HOME, request omits path: the tool answers "no project root", the server stays up
printf '%s\n' \
    '{"jsonrpc":"2.0","id":2,"method":"tools/call","params":{"name":"find_symbol","arguments":{"symbol":"hp"}}}' \
    "{\"jsonrpc\":\"2.0\",\"id\":3,\"method\":\"tools/call\",\"params\":{\"name\":\"find_symbol\",\"arguments\":{\"path\":\"$HOMEDIR/proj\",\"symbol\":\"hp\"}}}" \
    | HOME="$HOMEDIR" mcp_call "$HOMEDIR" >"$TMP/a4.out"
e2="$( mcp_field "$TMP/a4.out" 2 error )"; t3="$( mcp_field "$TMP/a4.out" 3 text )"
case "$e2" in *"no project root: $HOMEDIR is a home/system directory; pass a project path"*) a4=ok;; *) a4=no;; esac
if [ "$a4" = ok ]; then
    ok "(A4) MCP in \$HOME: a path-less request answers no-project-root"
else
    no "(A4) id=2 answered: ${e2:0:300}"
fi
case "$t3" in *hp*) ok "(A4b) the server stayed up: the next request (explicit subfolder) answers";; *) no "(A4b) id=3: ${t3:0:200}";; esac

# (A5) MCP launched in a git-repo $HOME: refused the same way
printf '%s\n' '{"jsonrpc":"2.0","id":2,"method":"tools/call","params":{"name":"grep","arguments":{"pattern":"hp"}}}' \
    | HOME="$GITHOME" mcp_call "$GITHOME" >"$TMP/a5.out"
case "$( mcp_field "$TMP/a5.out" 2 error )" in *"no project root: $GITHOME is a home/system directory"*) ok "(A5) MCP in a git-repo \$HOME refuses too";;
    *) no "(A5) id=2: $( mcp_field "$TMP/a5.out" 2 error | head -c 300 )";; esac

# (A6) MCP launched in "/" and in a system directory (/dev): refused, naming the directory
for sysdir in / /dev; do
    printf '%s\n' '{"jsonrpc":"2.0","id":2,"method":"tools/call","params":{"name":"find_symbol","arguments":{"symbol":"hp"}}}' \
        | HOME="$HOMEDIR" mcp_call "$sysdir" >"$TMP/a6.out"
    case "$( mcp_field "$TMP/a6.out" 2 error )" in
        *"missing required field: path"*"no project root: $sysdir is a home/system directory"*) ok "(A6) MCP launched in $sysdir refuses with no-project-root";;
        *) no "(A6) MCP in $sysdir: $( mcp_field "$TMP/a6.out" 2 error | head -c 300 )";; esac
done

# (A7) an EXPLICIT path is honoured: the home directory itself on the CLI and over MCP, and a subfolder
HOME="$HOMEDIR" "$BIN" "$HOMEDIR" --no-cache >"$TMP/a7.out" 2>/dev/null; rc=$?
if [ "$rc" = 0 ] && grep -q 'n="dot"' "$TMP/a7.out"; then
    ok "(A7) CLI: an explicit path to \$HOME is honoured (map, exit 0)"
else
    no "(A7) rc=$rc"
fi
( cd "$HOMEDIR" && HOME="$HOMEDIR" "$BIN" proj --no-cache >"$TMP/a7b.out" 2>/dev/null ); rc=$?
if [ "$rc" = 0 ] && grep -q 'n="hq"' "$TMP/a7b.out"; then
    ok "(A7b) CLI: an explicit subfolder from inside \$HOME works"
else
    no "(A7b) rc=$rc"
fi
# (A8) MCP: an agent's path= IS the #350 incident (grep path=$HOME) — refused like the implicit case, server stays up;
#      a git-repo $HOME, "/", a system tree and a `paths` workspace holding $HOME are refused too
printf '%s\n' \
    "{\"jsonrpc\":\"2.0\",\"id\":2,\"method\":\"tools/call\",\"params\":{\"name\":\"grep\",\"arguments\":{\"path\":\"$HOMEDIR\",\"pattern\":\"dot\"}}}" \
    "{\"jsonrpc\":\"2.0\",\"id\":3,\"method\":\"tools/call\",\"params\":{\"name\":\"find_symbol\",\"arguments\":{\"path\":\"$HOMEDIR/proj\",\"symbol\":\"hp\"}}}" \
    "{\"jsonrpc\":\"2.0\",\"id\":4,\"method\":\"tools/call\",\"params\":{\"name\":\"find_symbol\",\"arguments\":{\"path\":\"/\",\"symbol\":\"hp\"}}}" \
    "{\"jsonrpc\":\"2.0\",\"id\":5,\"method\":\"tools/call\",\"params\":{\"name\":\"find_symbol\",\"arguments\":{\"path\":\"/dev\",\"symbol\":\"hp\"}}}" \
    "{\"jsonrpc\":\"2.0\",\"id\":6,\"method\":\"tools/call\",\"params\":{\"name\":\"find_symbol\",\"arguments\":{\"paths\":[\"$HOMEDIR\",\"$FX\"],\"symbol\":\"hp\"}}}" \
    | HOME="$HOMEDIR" mcp_call "$HOMEDIR/proj" >"$TMP/a8.out"
case "$( mcp_field "$TMP/a8.out" 2 error )" in *"no project root: $HOMEDIR is a home/system directory; pass a project path"*) ok "(A8) MCP: an explicit path=\$HOME is refused with no-project-root";;
    *) no "(A8) id=2: $( mcp_field "$TMP/a8.out" 2 error | head -c 200 ) text: $( mcp_field "$TMP/a8.out" 2 text | head -c 120 )";; esac
case "$( mcp_field "$TMP/a8.out" 3 text )" in *hp*) ok "(A8b) the server stayed up: an explicit subfolder answers next";; *) no "(A8b) id=3: $( head -c 300 "$TMP/a8.out" )";; esac
for id in 4 5; do
    case "$( mcp_field "$TMP/a8.out" "$id" error )" in *"no project root: /"*) ok "(A8c) MCP: an explicit system/root path= is refused (id=$id)";;
        *) no "(A8c) id=$id: $( mcp_field "$TMP/a8.out" "$id" error | head -c 200 )";; esac
done
case "$( mcp_field "$TMP/a8.out" 6 error )" in *"no project root: $HOMEDIR"*) ok "(A8d) MCP: a paths workspace holding \$HOME is refused";;
    *) no "(A8d) id=6: $( mcp_field "$TMP/a8.out" 6 error | head -c 200 )";; esac
printf '%s\n' "{\"jsonrpc\":\"2.0\",\"id\":2,\"method\":\"tools/call\",\"params\":{\"name\":\"grep\",\"arguments\":{\"path\":\"$GITHOME\",\"pattern\":\"hp\"}}}" \
    | HOME="$GITHOME" mcp_call "$GITHOME/proj" >"$TMP/a8e.out"
case "$( mcp_field "$TMP/a8e.out" 2 error )" in *"no project root: $GITHOME"*) ok "(A8e) MCP: an explicit path= to a git-repo \$HOME is refused";;
    *) no "(A8e) id=2: $( mcp_field "$TMP/a8e.out" 2 error | head -c 200 )";; esac

# (A9) the ONE exception: the root the server was started on (`ripwire <root> --mcp`) is a human's choice — honoured,
#      whether the request names it or omits path=
printf '%s\n' \
    "{\"jsonrpc\":\"2.0\",\"id\":2,\"method\":\"tools/call\",\"params\":{\"name\":\"find_symbol\",\"arguments\":{\"path\":\"$HOMEDIR\",\"symbol\":\"dot\"}}}" \
    '{"jsonrpc":"2.0","id":3,"method":"tools/call","params":{"name":"find_symbol","arguments":{"symbol":"dot"}}}' \
    | HOME="$HOMEDIR" mcp_call "$TMP" "$HOMEDIR" >"$TMP/a9.out"
case "$( mcp_field "$TMP/a9.out" 2 text )" in *dot*) ok "(A9) MCP started as 'ripwire \$HOME --mcp': path=\$HOME is honoured";; *) no "(A9) id=2: $( head -c 300 "$TMP/a9.out" )";; esac
case "$( mcp_field "$TMP/a9.out" 3 text )" in *dot*) ok "(A9b) …and a path-less request answers about that startup root";; *) no "(A9b) id=3: $( mcp_field "$TMP/a9.out" 3 error | head -c 200 )";; esac

# (A10) the background hooks that pass the session cwd to ripwire exit silently in $HOME (a git-repo $HOME included)
#       and in "/", without running ripwire; the control — a project directory — does run it (the arm can fail)
if command -v jq >/dev/null 2>&1; then
    SHIM="$TMP/shim"; mkdir -p "$SHIM"
    printf '#!/usr/bin/env bash\nprintf "%%s\\n" "$*" >>"%s/shim.calls"\nexec "%s" "$@"\n' "$TMP" "$BIN" >"$SHIM/ripwire"; chmod +x "$SHIM/ripwire"
    git -C "$HOMEDIR/proj" init -q 2>/dev/null
    mkdir -p "$TMP/hooktmp"   # the toolroute hook's per-session hint cap lives in $TMPDIR: keep it inside this run
    hookrun(){   # hookrun HOOK CWD HOMEVAL JSON-EXTRA → stdout in $TMP/hook.out, calls counted
        rm -f "$TMP/shim.calls"
        jq -n --arg cwd "$2" --arg p "where is the parser defined" "{cwd:\$cwd, prompt:\$p, session_id:\"s1\"} + $4" \
            | ( cd "$2" && HOME="$3" PATH="$SHIM:$PATH" RIPWIRE_DATA_HOME="$TMP/data" TMPDIR="$TMP/hooktmp" bash "$ROOT/hooks/$1" ) >"$TMP/hook.out" 2>/dev/null
        hookrc=$?
        hookcalls="$( grep -c . "$TMP/shim.calls" 2>/dev/null )"; hookcalls="${hookcalls:-0}"   # a bare `ripwire` (the rule probe) logs an empty line: not a crawl
    }
    for h in ripwire-claude-route.sh ripwire-codex-route.sh; do
        for case_ in "$GITHOME:$GITHOME" "/:$HOMEDIR"; do
            hcwd="${case_%%:*}"; hhome="${case_#*:}"
            hookrun "$h" "$hcwd" "$hhome" '{}'
            if [ "$hookrc" = 0 ] && [ "$hookcalls" = 0 ] && [ ! -s "$TMP/hook.out" ]; then
                ok "(A10) $h in $hcwd (HOME=$( basename "$hhome" )): silent exit 0, ripwire never ran"
            else
                no "(A10) $h in $hcwd: rc=$hookrc ripwire calls=$hookcalls stdout=$( head -c 120 "$TMP/hook.out" )"
            fi
        done
        hookrun "$h" "$HOMEDIR/proj" "$HOMEDIR" '{}'
        if [ "$hookcalls" -gt 0 ]; then
            ok "(A10) control: $h in a project below \$HOME still runs ripwire ($hookcalls call(s))"
        else
            no "(A10) control: $h in $HOMEDIR/proj never ran ripwire — the skip arm above proves nothing"
        fi
    done
    hookrun ripwire-claude-toolroute.sh "$GITHOME" "$GITHOME" '{hook_event_name:"PreToolUse", tool_name:"Grep", tool_input:{pattern:"hp", path:"."}}'
    if [ "$hookrc" = 0 ] && [ "$hookcalls" = 0 ] && [ ! -s "$TMP/hook.out" ]; then
        ok "(A10) ripwire-claude-toolroute.sh in a git-repo \$HOME: silent exit 0, ripwire never ran"
    else
        no "(A10) ripwire-claude-toolroute.sh in \$HOME: rc=$hookrc calls=$hookcalls stdout=$( head -c 120 "$TMP/hook.out" )"
    fi
    # the toolroute hook needs no ripwire call to recommend one, so its control is the recommendation itself
    hookrun ripwire-claude-toolroute.sh "$HOMEDIR/proj" "$HOMEDIR" '{hook_event_name:"PreToolUse", tool_name:"Grep", tool_input:{pattern:"hp", path:"."}}'
    if [ -s "$TMP/hook.out" ] || [ "$hookcalls" -gt 0 ]; then
        ok "(A10) control: ripwire-claude-toolroute.sh in a project below \$HOME still answers"
    else
        no "(A10) control: ripwire-claude-toolroute.sh in $HOMEDIR/proj produced nothing — the skip arm above proves nothing"
    fi
else
    echo "  SKIP  (A10) jq is not installed — the hooks need it"
fi

echo "=== (B) layer 3: the memory guard stops cleanly and says so ==="

run_trip(){ RIPWIRE_TEST_MEMGUARD="$1" "$BIN" "${@:2}"; }

# (B1) crawl stop at the 30th entry: the map answers from what the crawl saw, and says so
run_trip crawl:30 "$FX" --max-memory=64M --no-cache >"$TMP/b1a.out" 2>"$TMP/b1a.err"; rc=$?
run_trip crawl:30 "$FX" --max-memory=64M --no-cache >"$TMP/b1b.out" 2>/dev/null
hdr="$( grep -oE '<!-- files=[^>]*-->' "$TMP/b1a.out" | head -1 )"
files="$( printf '%s' "$hdr" | grep -oE 'files=[0-9]+' | head -1 | grep -oE '[0-9]+' )"
if [ "$rc" = 0 ]; then
    ok "(B1) a crawl stop still answers (exit 0)"
else
    no "(B1) rc=$rc stderr: $( head -c 300 "$TMP/b1a.err" )"
fi
case "$hdr" in *"memory_stop=crawl"*"memory_limit=64M"*) ok "(B1b) the header discloses memory_stop=crawl and memory_limit=64M";; *) no "(B1b) header: $hdr";; esac
if [ -n "$files" ] && [ "$files" -gt 0 ] && [ "$files" -lt 30 ]; then
    ok "(B1c) files=$files: a partial corpus, not a total (72 in the tree)"
else
    no "(B1c) files=${files:-<none>}"
fi
if perl -ne 'print $1 if /^(<!-- ripwire map.*?-->)/' "$TMP/b1a.out" | grep -q 'memory_stop='; then
    ok "(B1d) the answer's own legend defines memory_stop="
else
    no "(B1d) the legend does not define memory_stop="
fi
if xmllint --noout "$TMP/b1a.out" 2>/dev/null; then
    ok "(B1e) the partial map is well-formed (xmllint)"
else
    no "(B1e) xmllint rejected the partial map"
fi
if cmp -s "$TMP/b1a.out" "$TMP/b1b.out"; then
    ok "(B1f) the partial map is byte-identical across two runs"
else
    no "(B1f) two runs differ"
fi
# a dev build (no NDEBUG) also traces each DISCLOSE site on stderr as "[math degraded] …"; the user-facing lines are "ripwire: …"
if [ "$( grep -c '^ripwire:' "$TMP/b1a.err" )" = 1 ] && grep '^ripwire:' "$TMP/b1a.err" | grep -q "memory guard"; then
    ok "(B1g) stderr carries the one-line note too"
else
    no "(B1g) stderr: $( head -c 300 "$TMP/b1a.err" )"
fi

# (B2) parse stop at the 10th parsed file: the crawl was whole, the parse was not
run_trip parse:10 "$FX" --max-memory=64M --no-cache >"$TMP/b2.out" 2>"$TMP/b2.err"; rc=$?
hdr="$( grep -oE '<!-- files=[^>]*-->' "$TMP/b2.out" | head -1 )"
parsed="$( printf '%s' "$hdr" | grep -oE 'memory_parsed=[0-9]+' | grep -oE '[0-9]+' )"
if [ "$rc" = 0 ] && case "$hdr" in *"files=72 "*"memory_stop=parse"*) true;; *) false;; esac; then
    ok "(B2) a parse stop: the crawl was whole (files=72), the header says memory_stop=parse"
else
    no "(B2) rc=$rc header: $hdr"
fi
if [ "$parsed" = 10 ]; then
    ok "(B2b) memory_parsed=10 of files=72: exactly the first 10 files of the parse order"
else
    no "(B2b) memory_parsed=${parsed:-<none>} (want exactly 10)"
fi
run_trip parse:10 "$FX" --max-memory=64M --no-cache >"$TMP/b2r.out" 2>/dev/null
for i in 2 3 4; do run_trip parse:10 "$FX" --max-memory=64M --no-cache >"$TMP/b2r$i.out" 2>/dev/null; done
if cmp -s "$TMP/b2.out" "$TMP/b2r.out" && cmp -s "$TMP/b2.out" "$TMP/b2r2.out" && cmp -s "$TMP/b2.out" "$TMP/b2r3.out" && cmp -s "$TMP/b2.out" "$TMP/b2r4.out"; then
    ok "(B2f) a parse-stopped map is byte-identical across five runs"
else
    no "(B2f) parse-stopped runs differ"
fi
if xmllint --noout "$TMP/b2.out" 2>/dev/null; then
    ok "(B2c) the parse-stopped map is well-formed"
else
    no "(B2c) xmllint rejected it"
fi
if perl -ne 'print $1 if /^(<!-- ripwire map.*?-->)/' "$TMP/b2.out" | grep -q 'memory_parsed='; then
    ok "(B2d) the legend defines memory_parsed="
else
    no "(B2d) the legend does not define memory_parsed="
fi
# (B2e) the WARM path: a full run fills the cache, half the files change, a parse stop runs on that cache — which must
#       not be written — and the next warm run equals a cold one (a cut warm run that saved would serve the gap)
FXW="$TMP/fxw"; cp -R "$FX" "$FXW"; mkdir -p "$TMP/cachedir"
TMPDIR="$TMP/cachedir" "$BIN" "$FXW" >/dev/null 2>&1
for f in "$FXW"/a/*.c "$FXW"/b/*.c; do printf 'int %s_extra( void ) { return 0; }\n' "$( basename "${f%.c}" )$( basename "$( dirname "$f" )" )" >>"$f"; done
TMPDIR="$TMP/cachedir" run_trip parse:5 "$FXW" --max-memory=64M >/dev/null 2>&1
TMPDIR="$TMP/cachedir" "$BIN" "$FXW" >"$TMP/b2e.out" 2>/dev/null
"$BIN" "$FXW" --no-cache >"$TMP/b2f.out" 2>/dev/null
if cmp -s "$TMP/b2e.out" "$TMP/b2f.out" && grep -q 'extra' "$TMP/b2e.out"; then
    ok "(B2e) a warm partial parse was never cached: the next warm run equals a cold one"
else
    no "(B2e) the warm run after a cut differs from a cold one (files= $( grep -oE 'files=[0-9]+ symbols=[0-9]+' "$TMP/b2e.out" | head -1 ) vs $( grep -oE 'files=[0-9]+ symbols=[0-9]+' "$TMP/b2f.out" | head -1 ))"
fi

# (B3) nothing built yet when the guard trips: exit 5, one line naming the limit and both overrides, no map
run_trip crawl:1 "$FX" --max-memory=64M --no-cache >"$TMP/b3.out" 2>"$TMP/b3.err"; rc=$?
if [ "$rc" = 5 ]; then
    ok "(B3) no partial answer possible: exit 5"
else
    no "(B3) rc=$rc"
fi
if [ ! -s "$TMP/b3.out" ]; then
    ok "(B3b) nothing on stdout"
else
    no "(B3b) stdout: $( head -c 200 "$TMP/b3.out" )"
fi
grep '^ripwire:' "$TMP/b3.err" >"$TMP/b3.line"
if [ "$( grep -c . "$TMP/b3.line" )" = 1 ] && grep -q 'at the crawl line' "$TMP/b3.line" && grep -q '64M' "$TMP/b3.line" && grep -q -- '--max-memory' "$TMP/b3.line" && grep -q 'RIPWIRE_MAX_MEMORY' "$TMP/b3.line"; then
    ok "(B3c) one stderr line naming the line crossed (the crawl line of the 64M limit) and both overrides"
else
    no "(B3c) stderr: $( cat "$TMP/b3.err" )"
fi

# (B4) a verb that cannot carry the disclosure refuses instead of answering from a partial index
run_trip crawl:30 "$FX" --max-memory=64M --no-cache --callers=a_03 >"$TMP/b4.out" 2>"$TMP/b4.err"; rc=$?
if [ "$rc" = 5 ] && [ ! -s "$TMP/b4.out" ] && grep -q -- '--callers' "$TMP/b4.err"; then
    ok "(B4) --callers under a crawl stop refuses (exit 5, names the verb)"
else
    no "(B4) rc=$rc stderr: $( head -c 300 "$TMP/b4.err" )"
fi

# (B5) the env var is the same knob; the flag wins over it
RIPWIRE_MAX_MEMORY=64M run_trip crawl:30 "$FX" --no-cache >"$TMP/b5.out" 2>/dev/null
if cmp -s "$TMP/b1a.out" "$TMP/b5.out"; then
    ok "(B5) RIPWIRE_MAX_MEMORY=64M == --max-memory=64M"
else
    no "(B5) env and flag differ"
fi
RIPWIRE_MAX_MEMORY=1G run_trip crawl:30 "$FX" --max-memory=64M --no-cache >"$TMP/b5b.out" 2>/dev/null
if cmp -s "$TMP/b1a.out" "$TMP/b5b.out"; then
    ok "(B5b) the flag wins over the env var"
else
    no "(B5b) the flag did not win"
fi

# (B6) MCP: a soft stop answers with the envelope disclosure, and every answer from that partial index keeps it
printf '%s\n' \
    "{\"jsonrpc\":\"2.0\",\"id\":2,\"method\":\"tools/call\",\"params\":{\"name\":\"grep\",\"arguments\":{\"path\":\"$FX\",\"pattern\":\"a_01\"}}}" \
    "{\"jsonrpc\":\"2.0\",\"id\":3,\"method\":\"tools/call\",\"params\":{\"name\":\"find_symbol\",\"arguments\":{\"path\":\"$FX\",\"symbol\":\"a_02\"}}}" \
    | RIPWIRE_TEST_MEMGUARD=crawl:30 mcp_call "$TMP" --max-memory=64M >"$TMP/b6.out"
ms2="$( mcp_field "$TMP/b6.out" 2 _memory_stop )"; ms3="$( mcp_field "$TMP/b6.out" 3 _memory_stop )"
case "$ms2" in *"memory guard"*crawl*64M*) ok "(B6) MCP grep under a crawl stop carries _memory_stop";; *) no "(B6) id=2 _memory_stop='${ms2:0:200}' resp: $( head -c 300 "$TMP/b6.out" )";; esac
case "$ms3" in *"memory guard"*) ok "(B6b) the next answer from the same partial index still carries it";; *) no "(B6b) id=3 _memory_stop='${ms3:0:200}'";; esac
printf '%s\n' "{\"jsonrpc\":\"2.0\",\"id\":2,\"method\":\"tools/call\",\"params\":{\"name\":\"grep\",\"arguments\":{\"path\":\"$FX\",\"pattern\":\"a_01\"}}}" \
    | mcp_call "$TMP" >"$TMP/b6c.out"
if grep -q '_memory_stop' "$TMP/b6c.out"; then
    no "(B6c) a normal MCP answer carries _memory_stop"
else
    ok "(B6c) a normal MCP answer carries no _memory_stop"
fi

# (B7) MCP: over the hard limit a tool call is refused by name, and the server stays up
printf '%s\n' \
    "{\"jsonrpc\":\"2.0\",\"id\":2,\"method\":\"tools/call\",\"params\":{\"name\":\"grep\",\"arguments\":{\"path\":\"$FX\",\"pattern\":\"a_01\"}}}" \
    "{\"jsonrpc\":\"2.0\",\"id\":3,\"method\":\"tools/call\",\"params\":{\"name\":\"grep\",\"arguments\":{\"path\":\"$FX\",\"pattern\":\"a_01\"}}}" \
    '{"jsonrpc":"2.0","id":4,"method":"tools/list"}' \
    | RIPWIRE_TEST_MEMGUARD=request:2 mcp_call "$TMP" --max-memory=64M >"$TMP/b7.out"
if [ -z "$( mcp_field "$TMP/b7.out" 2 error )" ]; then
    ok "(B7) the first call is answered"
else
    no "(B7) id=2: $( mcp_field "$TMP/b7.out" 2 error | head -c 200 )"
fi
case "$( mcp_field "$TMP/b7.out" 3 error )" in *"memory limit"*64M*) ok "(B7b) over the hard limit the next tool call is refused by name";;
    *) no "(B7b) id=3: $( mcp_field "$TMP/b7.out" 3 error | head -c 300 )";; esac
if grep -q '"id":4' "$TMP/b7.out"; then
    ok "(B7c) the server stayed up (tools/list answered)"
else
    no "(B7c) no answer to id=4"
fi

# (B8) the REAL reading (no seam): a fixture whose parsed facts alone sit far over 64M (80 files x 1500 small functions;
#      unguarded peak 150-185M), so the hard line after the ingest fires on its own reading.
# (B8b) the seam is ADDITIVE: a trip that never fires (crawl:999999999) does not switch the real guard off — the same
#      run under that seam still ends on the real hard line.
#   0.6.6 (#364): both arms used to run on this repo's src/, whose footprint AT THE HARD LINE (not its peak: 72-93M on a
#   10-core host with the pool forced to 3/4 workers) straddles 64M, and whose ingest can outlast the five-second gate on
#   a slow host. Measured under `taskpolicy -b` at 4 workers, that gave three outcomes, none of them a disabled guard: the
#   hard line (rc 5), a time-gated soft parse stop (rc 0, memory_stop= disclosed), and a complete run whose phase readings
#   all fell under the limit (rc 0) — the last is what CI's macOS legs hit, and B8b read it as "the seam turned the guard
#   off". The run is not guarded per allocation: a sub-five-second transient over the limit between phase readings is the
#   documented contract, so this was the gate's assumption, not a product gap. On $EG both runs measured rc 5 with the
#   ingest line 40/40 (with and without the seam; 3/4/10/16 workers; foreground and taskpolicy -b; 0.7-4.7 s).
EG="$TMP/eg"; mkdir -p "$EG"
python3 - "$EG" <<'PY2'
import os, sys
root = sys.argv[1]
for d in "abcdefgh":
    os.makedirs( os.path.join( root, d ), exist_ok=True )
    for f in range( 40 ):
        open( os.path.join( root, d, "f%02d.c" % f ), "w" ).write( "int %s_%d(int x){ return x; }\n" % ( d, f ) )
os.makedirs( os.path.join( root, "z" ), exist_ok=True )
for f in range( 80 ):
    open( os.path.join( root, "z", "big%02d.c" % f ), "w" ).write(
        "".join( "int z%d_%d(int x){ return x>0 ? z%d_%d(x-1)+%d : %d; }\n" % ( f, k, f, ( k + 1 ) % 1500, k, k ) for k in range( 1500 ) ) )
PY2
b8why(){ printf 'rc=%s memory_stop=%s stdout=%sB stderr: %s' "$1" "$( grep -oE 'memory_stop=[a-z]+' "$2" | head -1 | cut -d= -f2 )" "$( wc -c < "$2" | tr -d ' ' )" "$( grep '^ripwire:' "$3" | head -c 200 )"; }
"$BIN" "$EG" --no-cache --max-memory=64M >"$TMP/b8.out" 2>"$TMP/b8.err"; rc=$?
if [ "$rc" = 5 ] && grep -q '^ripwire: memory limit reached during the ingest' "$TMP/b8.err" && [ ! -s "$TMP/b8.out" ]; then
    ok "(B8) a real footprint over --max-memory=64M (no seam): exit 5 with the ingest line"
else
    no "(B8) $( b8why "$rc" "$TMP/b8.out" "$TMP/b8.err" )"
fi
RIPWIRE_TEST_MEMGUARD=crawl:999999999 "$BIN" "$EG" --no-cache --max-memory=64M >"$TMP/b8b.out" 2>"$TMP/b8b.err"; rc=$?
if [ "$rc" = 5 ] && grep -q '^ripwire: memory limit reached during the ingest' "$TMP/b8b.err" && [ ! -s "$TMP/b8b.out" ]; then
    ok "(B8b) RIPWIRE_TEST_MEMGUARD cannot disable the guard (crawl:999999999 still exits 5 with the ingest line)"
else
    no "(B8b) the never-firing seam changed the real outcome: $( b8why "$rc" "$TMP/b8b.out" "$TMP/b8b.err" )"
fi

# (B9) the pressure path: a pressure stop is disclosed as such, and a pressure stop with nothing built says pressure
run_trip pressure:30 "$FX" --no-cache >"$TMP/b9.out" 2>"$TMP/b9.err"; rc=$?
hdr="$( grep -oE '<!-- files=[^>]*-->' "$TMP/b9.out" | head -1 )"
if [ "$rc" = 0 ] && case "$hdr" in *"memory_stop=crawl"*"memory_pressure=1"*) true;; *) false;; esac \
   && perl -ne 'print $1 if /^(<!-- ripwire map.*?-->)/' "$TMP/b9.out" | grep -q 'memory_pressure=' \
   && grep -q '^ripwire: .*critical system memory pressure' "$TMP/b9.err"; then
    ok "(B9) a pressure stop: memory_pressure=1 in the header, defined in the legend, named on stderr"
else
    no "(B9) rc=$rc header: $hdr stderr: $( grep '^ripwire:' "$TMP/b9.err" | head -c 200 )"
fi
run_trip pressure:1 "$FX" --no-cache >/dev/null 2>"$TMP/b9b.err"; rc=$?
if [ "$rc" = 5 ] && grep -q '^ripwire: the memory guard stopped the crawl under critical system memory pressure before anything was built' "$TMP/b9b.err"; then
    ok "(B9b) a pressure stop with nothing built: exit 5, the line names the pressure, not a limit"
else
    no "(B9b) rc=$rc stderr: $( grep '^ripwire:' "$TMP/b9b.err" | head -c 200 )"
fi

# (B10) nothing derived from a cut ingest is persisted (review B1): a --quality-delta whose HEAD ingest the guard cut
#       exits 5 with the line, and the NEXT run, with no trip, equals one on a fresh cache directory
QD="$TMP/qd"; cp -R "$FX" "$QD"
git -C "$QD" init -q && git -C "$QD" add -A && git -C "$QD" -c user.name=t -c user.email=t@example.com commit -qm base
rm -rf "$QD/c" "$QD/d"
mkdir -p "$TMP/qcache" "$TMP/qfresh" "$TMP/qfresh2"
( cd "$QD" && TMPDIR="$TMP/qcache" RIPWIRE_TEST_MEMGUARD=crawl:50 "$BIN" . --quality-delta >/dev/null 2>"$TMP/b10a.err" ); rc=$?
if [ "$rc" = 5 ] && grep -q '^ripwire: the memory guard stopped an ingest this answer depends on' "$TMP/b10a.err"; then
    ok "(B10) --quality-delta over a cut HEAD ingest: exit 5 with the memory line"
else
    no "(B10) rc=$rc stderr: $( grep '^ripwire:' "$TMP/b10a.err" | head -c 200 )"
fi
( cd "$QD" && TMPDIR="$TMP/qcache" "$BIN" . --quality-delta >"$TMP/b10b.out" 2>/dev/null ); rcb=$?
( cd "$QD" && TMPDIR="$TMP/qfresh" "$BIN" . --quality-delta >"$TMP/b10c.out" 2>/dev/null ); rcc=$?
if [ "$rcb" = "$rcc" ] && cmp -s "$TMP/b10b.out" "$TMP/b10c.out"; then
    ok "(B10b) the next --quality-delta equals a fresh-cache one: no partial snapshot was persisted"
else
    no "(B10b) rc=$rcb vs fresh rc=$rcc; the persisted snapshot differs ($( grep -oE 'regressions="[0-9]+"' "$TMP/b10b.out" ) vs $( grep -oE 'regressions="[0-9]+"' "$TMP/b10c.out" ))"
fi
# (B10c) MCP quality_baseline over a cut ingest refuses and writes nothing; MCP quality_delta discloses the cut HEAD ingest
printf '%s\n' "{\"jsonrpc\":\"2.0\",\"id\":2,\"method\":\"tools/call\",\"params\":{\"name\":\"quality_baseline\",\"arguments\":{\"path\":\"$QD\"}}}" \
    | TMPDIR="$TMP/qcache" RIPWIRE_TEST_MEMGUARD=crawl:30 mcp_call "$TMP" >"$TMP/b10d.out"
if case "$( mcp_field "$TMP/b10d.out" 2 error )" in *"memory guard"*) true;; *) false;; esac && [ ! -e "$QD/.ripwire_quality_baseline" ]; then
    ok "(B10c) MCP quality_baseline over a cut ingest refuses and writes no sidecar"
else
    no "(B10c) id=2: $( head -c 300 "$TMP/b10d.out" ); sidecar present: $( [ -e "$QD/.ripwire_quality_baseline" ] && echo yes || echo no )"
fi
rm -f "$QD/.ripwire_quality_baseline"
printf '%s\n' "{\"jsonrpc\":\"2.0\",\"id\":2,\"method\":\"tools/call\",\"params\":{\"name\":\"quality_delta\",\"arguments\":{\"path\":\"$QD\"}}}" \
    | TMPDIR="$TMP/qfresh2" RIPWIRE_TEST_MEMGUARD=crawl:50 mcp_call "$TMP" >"$TMP/b10e.out"
case "$( mcp_field "$TMP/b10e.out" 2 _memory_stop )$( mcp_field "$TMP/b10e.out" 2 error )" in *"memory guard"*) ok "(B10d) MCP quality_delta over a cut HEAD ingest discloses it (_memory_stop or a refusal)";;
    *) no "(B10d) id=2 carries no memory disclosure: $( head -c 300 "$TMP/b10e.out" )";; esac

# (B13) the selector-bearing map modifiers refuse a partial index (review CR1): d_17 lives in a file parse:10 never parsed,
#       so an answer would be a false "no match"
for mod in "--expand=d_17" "--outline=d_17"; do
    run_trip parse:10 "$FX" --no-cache "$mod" >"$TMP/b13.out" 2>"$TMP/b13.err"; rc=$?
    if [ "$rc" = 5 ] && [ ! -s "$TMP/b13.out" ] && grep -q "^ripwire: .*${mod%%=*} cannot answer from a partial index" "$TMP/b13.err"; then
        ok "(B13) $mod over a partial parse refuses (exit 5, names ${mod%%=*}), never a false no-match"
    else
        no "(B13) $mod rc=$rc stdout=$( wc -c <"$TMP/b13.out" | tr -d ' ' )B stderr: $( grep '^ripwire:' "$TMP/b13.err" | head -c 200 )"
    fi
done
# (B13b) --in=DIR resolves a directory against the crawl's files, so a crawl stop refuses it (a directory the crawl never
#        reached would read as "no indexed file"); a parse stop leaves the crawl whole and --in still answers
FXG="$TMP/fxg"; cp -R "$FX" "$FXG"
git -C "$FXG" init -q && git -C "$FXG" add -A && git -C "$FXG" -c user.name=t -c user.email=t@t commit -qm init
run_trip crawl:30 "$FXG" --no-cache --rank-by=churn-decay --in=d >"$TMP/b13b.out" 2>"$TMP/b13b.err"; rc=$?
if [ "$rc" = 5 ] && [ ! -s "$TMP/b13b.out" ] && grep -q '^ripwire: .*--in cannot answer from a partial index' "$TMP/b13b.err"; then
    ok "(B13b) --in=d over a crawl stop refuses (exit 5, names --in), never a false \"no indexed file\""
else
    no "(B13b) rc=$rc stdout=$( wc -c <"$TMP/b13b.out" | tr -d ' ' )B stderr: $( grep '^ripwire:' "$TMP/b13b.err" | head -c 250 )"
fi
run_trip parse:10 "$FXG" --no-cache --rank-by=churn-decay --in=d >"$TMP/b13c.out" 2>"$TMP/b13c.err"; rc=$?
if [ "$rc" = 0 ] && grep -q 'memory_stop=parse' "$TMP/b13c.out" && ! grep -q 'cannot answer from a partial index' "$TMP/b13c.err"; then
    ok "(B13c) --in=d over a parse stop (crawl whole) still answers, disclosed memory_stop=parse"
else
    no "(B13c) rc=$rc stderr: $( grep '^ripwire:' "$TMP/b13c.err" | head -c 250 )"
fi
# (B21) a refusal does not wait for the history walk (CodeRabbit on #383, main.cpp:3721). --for starts the 18-month git walk
#        beside the ingest; a memory-guard refusal used to join that walk's future before exiting, so the exit code waited for
#        the end of the log. With a git shim whose `log --name-only` (the walk's own stream; its sha-list probe and every other
#        git call reach the real git) streams one line every 0.1 s for 6 s, the refusal must return well before the stream ends:
#        the walker stops at its next line and the join ends there. Fresh TMPDIR, so no cached stream from an earlier arm stands
#        in for the walk; the shim records that it served the walk.
SHIM="$TMP/shim"; mkdir -p "$SHIM" "$TMP/b21tmp"
REALGIT="$( command -v git )"
cat > "$SHIM/git" <<EOF
#!/bin/sh
for a in "\$@"; do
    if [ "\$a" = --name-only ]; then
        : > "$SHIM/log-served"
        i=0
        while [ \$i -lt 60 ]; do echo "shim-line \$i" || exit 0; sleep 0.1; i=\$((i+1)); done
        exit 0
    fi
done
exec "$REALGIT" "\$@"
EOF
chmod +x "$SHIM/git"
t0=$( date +%s )
PATH="$SHIM:$PATH" TMPDIR="$TMP/b21tmp" run_trip crawl:30 "$FXG" --no-cache --for=d --max-memory=64M >"$TMP/b21.out" 2>"$TMP/b21.err"; rc=$?
el=$(( $( date +%s ) - t0 ))
if [ ! -e "$SHIM/log-served" ]; then
    no "(B21) premise: the shim never served a git log --name-only — the history walk did not run against it (rc=$rc)"
elif [ "$rc" = 5 ] && grep -q '^ripwire: .*cannot answer from a partial index' "$TMP/b21.err" && [ "$el" -le 3 ]; then
    ok "(B21) --for over a crawl stop refuses in ${el}s while the shim's log still streams: the walk is abandoned, not joined"
else
    no "(B21) rc=$rc elapsed=${el}s (the shim's log streams for 6 s; a join waits it out) stderr: $( grep '^ripwire:' "$TMP/b21.err" | head -c 200 )"
fi
# (B16) --query --format=candidates is a report verb, so it refuses a partial index like the rest (pinned: its
#       <candidates> root has no header to carry the cut)
run_trip parse:10 "$FX" --no-cache --query=d_17 --format=candidates >"$TMP/b16.out" 2>"$TMP/b16.err"; rc=$?
if [ "$rc" = 5 ] && [ ! -s "$TMP/b16.out" ] && grep -q '^ripwire: .*--query cannot answer from a partial index' "$TMP/b16.err"; then
    ok "(B16) --query --format=candidates over a partial parse refuses (exit 5, names --query)"
else
    no "(B16) rc=$rc stdout=$( wc -c <"$TMP/b16.out" | tr -d ' ' )B stderr: $( grep '^ripwire:' "$TMP/b16.err" | head -c 250 )"
fi
# (B17) --batch sub-answers carry no memory disclosure, so a batch over a cut index refuses whole (callers:d_17 would
#       otherwise answer "symbol not found" for a symbol in a file the guard never parsed)
printf 'callers:d_17\ngrep:d_17\n' >"$TMP/b17.batch"
run_trip parse:10 "$FX" --no-cache --batch="$TMP/b17.batch" >"$TMP/b17.out" 2>"$TMP/b17.err"; rc=$?
if [ "$rc" = 5 ] && [ ! -s "$TMP/b17.out" ] && grep -q '^ripwire: .*--batch cannot answer from a partial index' "$TMP/b17.err"; then
    ok "(B17) --batch over a partial parse refuses whole (exit 5, empty stdout), never a false 'not found'"
else
    no "(B17) rc=$rc stdout=$( wc -c <"$TMP/b17.out" | tr -d ' ' )B stderr: $( grep '^ripwire:' "$TMP/b17.err" | head -c 250 )"
fi
# (B18) an edit resolves its target against the index: over a cut index it refuses and writes nothing (a same-named
#       definition in an unparsed file would make an ambiguous target read as unique). CLI verb, --edit-plan, MCP tool.
FXE="$TMP/fxe"; cp -R "$FX" "$FXE"; cp "$FXE/a/f00.c" "$TMP/b18.orig"
printf 'int a_00( int x ) { return x + 1; }\n' >"$TMP/b18.body"
run_trip parse:10 "$FXE" --no-cache --replace-symbol-body=a_00 --edit-payload="$TMP/b18.body" >"$TMP/b18.out" 2>"$TMP/b18.err"; rc=$?
if [ "$rc" = 5 ] && [ ! -s "$TMP/b18.out" ] && cmp -s "$FXE/a/f00.c" "$TMP/b18.orig" \
   && grep -q '^ripwire: --replace-symbol-body: .*cannot answer from a partial index' "$TMP/b18.err" && [ "$( grep -c '^ripwire' "$TMP/b18.err" )" = 1 ]; then
    ok "(B18) --replace-symbol-body over a partial parse refuses (exit 5, one line), file byte-unchanged"
else
    no "(B18) rc=$rc stdout=$( wc -c <"$TMP/b18.out" | tr -d ' ' )B unchanged=$( cmp -s "$FXE/a/f00.c" "$TMP/b18.orig" && echo 1 || echo 0 ) stderr: $( grep '^ripwire' "$TMP/b18.err" | head -c 250 )"
fi
mkdir -p "$TMP/b18plan"; cp "$TMP/b18.body" "$TMP/b18plan/body.c"
printf '{"version":1,"edits":[{"op":"replace_symbol_body","target":"a_00","payload":"body.c"}]}\n' >"$TMP/b18plan/plan.json"
run_trip parse:10 "$FXE" --no-cache --edit-plan="$TMP/b18plan/plan.json" --apply >"$TMP/b18b.out" 2>"$TMP/b18b.err"; rc=$?
if [ "$rc" = 5 ] && [ ! -s "$TMP/b18b.out" ] && cmp -s "$FXE/a/f00.c" "$TMP/b18.orig" && grep -q -- '--edit-plan cannot answer from a partial index' "$TMP/b18b.err"; then
    ok "(B18b) --edit-plan --apply over a partial parse refuses (exit 5), nothing written"
else
    no "(B18b) rc=$rc unchanged=$( cmp -s "$FXE/a/f00.c" "$TMP/b18.orig" && echo 1 || echo 0 ) stderr: $( grep '^ripwire' "$TMP/b18b.err" | head -c 250 )"
fi
printf '%s\n' "{\"jsonrpc\":\"2.0\",\"id\":2,\"method\":\"tools/call\",\"params\":{\"name\":\"replace_symbol_body\",\"arguments\":{\"path\":\"$FXE\",\"symbol\":\"a_00\",\"new_body\":\"int a_00( int x ) { return x + 1; }\"}}}" \
    | RIPWIRE_TEST_MEMGUARD=parse:10 mcp_call "$TMP" >"$TMP/b18c.out"
case "$( mcp_field "$TMP/b18c.out" 2 error )" in *"cannot answer from a partial index"*)
        if cmp -s "$FXE/a/f00.c" "$TMP/b18.orig"; then ok "(B18c) MCP replace_symbol_body over a cut index refuses, file byte-unchanged"
        else no "(B18c) refused but the file changed"; fi;;
    *) no "(B18c) id=2 no refusal: $( head -c 300 "$TMP/b18c.out" )";; esac
# (B19) --pin-census writes the resolver census to a file with no header to carry the cut: refused, nothing written
run_trip parse:10 "$FX" --no-cache --pin-census="$TMP/b19.census" >"$TMP/b19.out" 2>"$TMP/b19.err"; rc=$?
if [ "$rc" = 5 ] && [ ! -e "$TMP/b19.census" ] && grep -q '^ripwire: .*--pin-census cannot answer from a partial index' "$TMP/b19.err"; then
    ok "(B19) --pin-census over a partial parse refuses (exit 5), no census file"
else
    no "(B19) rc=$rc census=$( [ -e "$TMP/b19.census" ] && echo written || echo absent ) stderr: $( grep '^ripwire:' "$TMP/b19.err" | head -c 250 )"
fi
# (B20) memory_parsed=K counts the first K slots of the parse's work order, and the order is what the legend says
#       (review CR2): cold, cache misses largest first (z/big.c); every grammar file an ingest-cache hit, path order
#       (a/f00.c); one changed file makes it a miss again and it leads (a/f01.c)
FXO="$TMP/fxo"; mkdir -p "$FXO/a" "$FXO/z"
for i in 0 1 2; do printf 'int a_%s( int x ) { return x; }\n' "$i" >"$FXO/a/f0$i.c"; done
for i in $( seq 1 40 ); do printf 'int z_%s( int x ) { return x + %s; }\n' "$i" "$i"; done >"$FXO/z/big.c"
"$BIN" "$FXO" --cache="$TMP/b20.cache" >/dev/null 2>&1   # a whole run warms the cache (a cut run never writes it)
kept(){ grep -oE '<f p="[^"]*"' "$1" | tr '\n' ' '; }
run_trip parse:1 "$FXO" --no-cache >"$TMP/b20a.out" 2>/dev/null
run_trip parse:1 "$FXO" --cache="$TMP/b20.cache" >"$TMP/b20b.out" 2>/dev/null
printf 'int a_1( int x ) { return x * 2; }\n' >"$FXO/a/f01.c"
run_trip parse:1 "$FXO" --cache="$TMP/b20.cache" >"$TMP/b20c.out" 2>/dev/null
if [ "$( kept "$TMP/b20a.out" )" = '<f p="z/big.c" ' ] && [ "$( kept "$TMP/b20b.out" )" = '<f p="a/f00.c" ' ] \
   && [ "$( kept "$TMP/b20c.out" )" = '<f p="a/f01.c" ' ]; then
    ok "(B20) parse:1 keeps the largest miss cold, the first path when all hit, and the one changed file when it misses"
else
    no "(B20) cold='$( kept "$TMP/b20a.out" )' warm='$( kept "$TMP/b20b.out" )' one-miss='$( kept "$TMP/b20c.out" )'"
fi
# (B14) a workspace checks the hard line after EACH root (review CR3). hard:1 makes the FIRST hard-line reading of the
#       run read as over — a real footprint reading is timing-dependent (on a slow runner the 5 s soft line cuts root 1
#       first and the hard line is only crossed after the merge). With the per-root check that first reading is the
#       one after root 1; without it, it is the post-merge one, whose line names "the ingest" alone. Root 2 is never
#       ingested: each root's whole ingest writes its own cache blob under TMPDIR, so exactly one blob exists afterwards.
mkdir -p "$TMP/b14r1" "$TMP/b14r2" "$TMP/b14tmp"
printf 'int one( void ) { return 1; }\n' >"$TMP/b14r1/a.c"; printf 'int two( void ) { return 2; }\n' >"$TMP/b14r2/b.c"
TMPDIR="$TMP/b14tmp" RIPWIRE_TEST_MEMGUARD=hard:1 "$BIN" "$TMP/b14r1" "$TMP/b14r2" >"$TMP/b14.out" 2>"$TMP/b14.err"; rc=$?
blobs="$( find "$TMP/b14tmp" -type f -name 'ripwire-*.bin' | wc -l | tr -d ' ' )"
if [ "$rc" = 5 ] && [ ! -s "$TMP/b14.out" ] && grep -q '^ripwire: memory limit reached during the ingest of workspace root 1 of 2 (b14r1)' "$TMP/b14.err" \
   && [ "$( grep -c '^ripwire:' "$TMP/b14.err" )" = 1 ] && [ "$blobs" = 1 ]; then
    ok "(B14) a two-root workspace over the hard line stops after root 1 of 2 (exit 5, one line), root 2 never ingested"
else
    no "(B14) rc=$rc cache_blobs=$blobs (want 1) stderr: $( grep '^ripwire:' "$TMP/b14.err" | head -c 250 )"
fi
# (B15) the JSON map header of a cut ingest carries the floor marker (review CR4)
run_trip parse:10 "$FX" --no-cache --json >"$TMP/b15.out" 2>/dev/null; rc=$?
if [ "$rc" = 0 ] && grep -q '"counts_floor":true' "$TMP/b15.out" && grep -q '"memory_stop":"parse"' "$TMP/b15.out" \
   && python3 -c 'import json,sys; json.load(open(sys.argv[1]))' "$TMP/b15.out" 2>/dev/null; then
    ok "(B15) --json over a partial parse: counts_floor:true beside memory_stop, valid JSON"
else
    no "(B15) rc=$rc head: $( head -c 250 "$TMP/b15.out" )"
fi
"$BIN" "$FX" --no-cache --json >"$TMP/b15b.out" 2>/dev/null
if grep -q '"counts_floor"\|"memory_' "$TMP/b15b.out"; then
    no "(B15b) a normal --json map carries counts_floor/memory_"
else
    ok "(B15b) a normal --json map carries neither counts_floor nor memory_*"
fi

# (B11) a verb's non-zero verdict from a partial ingest still gets the line; --html and --index-out never pass silently
run_trip crawl:30 "$FX" --no-cache --html >/dev/null 2>"$TMP/b11.err"; rc=$?
if [ "$rc" = 5 ] && grep -q '^ripwire: .*--html cannot answer from a partial index' "$TMP/b11.err"; then
    ok "(B11) --html over a partial ingest refuses (exit 5, names --html)"
else
    no "(B11) rc=$rc stderr: $( grep '^ripwire:' "$TMP/b11.err" | head -c 200 )"
fi
run_trip parse:10 "$FX" --no-cache --index-out="$TMP/idx" >/dev/null 2>"$TMP/b11b.err"; rc=$?
if [ "$rc" = 5 ] && grep -q '^ripwire: the memory guard stopped an ingest this answer depends on' "$TMP/b11b.err"; then
    ok "(B11b) --index-out over a cut parse: rc=$rc and the memory line (not only 'failed to write')"
else
    no "(B11b) rc=$rc stderr: $( grep '^ripwire:' "$TMP/b11b.err" | head -c 250 )"
fi

# (B12) a REAL parse stop keeps what it parsed (review D1). eager:1 only drops the 5 s time gate — the footprint reading,
#       the parse line and the cut rule are the real ones. The big files sort LAST (z/), and the parse order is largest
#       first, so a rule that kept a prefix of the SORTED list would keep nothing here (rc 5, "nothing built"); the
#       claimed-prefix rule keeps the z/ files it parsed. The line crossed is named: the parse line, half the limit.
#   HEADROOM (0.6.6): a plain build runs at the 64M floor, not 128M. Measured on a 10-core macOS host, with the pool size forced to
#       3/4/10/16 workers and each run foreground and under `taskpolicy -b`: this fixture's footprint roughly DOUBLES
#       between the parse stop and the graph build (the parsed facts are merged, then graphed), so the post-stop peak is
#       about the limit minus what does not double (the process base and the trees in flight at the stop): a headroom
#       that does NOT scale with the limit. Raising limit and fixture together (256M + twice the z/ files) keeps
#       that ratio and measured WORSE (1/6 under taskpolicy -b at 10 workers, against 1/4 at 128M); the floor gives the
#       fixed headroom the largest share (10 workers 7/7 fg+bg; 3 and 16 workers 7/7 each). One shape stays marginal (4
#       workers under taskpolicy -b: 5 of 11 attempts), so an attempt that ends on the REAL hard line after its parse stop (rc 5,
#       "memory limit reached during the <phase>"), or that never reaches the parse line (rc 0, no memory_stop=), is an
#       ENVIRONMENT outcome, not the property: it is re-run, up to 6 attempts, and the arm passes only on an attempt that
#       shows the whole property. Anything else fails at once — the D1 shape (rc 5, "before anything was built"), a stop
#       that keeps no z/ file, a wrong line. Six environment outcomes in a row fail too: the arm never passes blind.
# (the fixture, $EG, is built above B8, which shares it)
# ASan quarantine inflates the footprint past the hard line before the soft parse stop is visible (review G1:
#   peak 498 MB under ASan vs 82 MB plain); a plain binary ignores the option. A sanitizer build keeps 128M: its runtime
#   carries a fixed footprint of its own that does not double after the stop (measured with llvm@22 ASan: 64M ends on
#   the hard line during the ingest 3/3, 128M passes), which is the headroom the floor buys a plain build.
B12LIM=64M
LC_ALL=C grep -q -a '__asan_init' "$BIN" 2>/dev/null && B12LIM=128M
b12="" b12env=""
for attempt in 1 2 3 4 5 6; do
    ASAN_OPTIONS="${ASAN_OPTIONS:+$ASAN_OPTIONS:}quarantine_size_mb=0" RIPWIRE_TEST_MEMGUARD=eager:1 "$BIN" "$EG" --no-cache --max-memory=$B12LIM --top-k=3 >"$TMP/b12.out" 2>"$TMP/b12.err"; rc=$?
    hdr="$( grep -oE '<!-- files=[^>]*-->' "$TMP/b12.out" | head -1 )"
    parsed="$( printf '%s' "$hdr" | grep -oE 'memory_parsed=[0-9]+' | grep -oE '[0-9]+' )"
    if [ "$rc" = 0 ] && case "$hdr" in *"memory_stop=parse"*) true;; *) false;; esac && [ "${parsed:-0}" -ge 2 ] && grep -q 'p="z/' "$TMP/b12.out"; then
        b12=pass; break
    fi
    if { [ "$rc" = 5 ] && grep -q '^ripwire: memory limit reached during the ' "$TMP/b12.err" && ! grep -q 'before anything was built' "$TMP/b12.err"; } \
       || { [ "$rc" = 0 ] && ! grep -q 'memory_stop=' "$TMP/b12.out"; }; then
        b12env="$b12env [attempt $attempt: rc=$rc $( grep '^ripwire:' "$TMP/b12.err" | tail -1 | head -c 70 )]"
        continue
    fi
    break
done
[ -n "$b12env" ] && printf '  ..    (B12) environment outcome(s) re-run:%s\n' "$b12env"
if [ "$b12" = pass ]; then
    ok "(B12) a real parse stop ($B12LIM, eager readings) answers from the $parsed files it parsed — the big z/ files, first in the parse order (attempt $attempt)"
else
    no "(B12) rc=$rc header: $hdr stderr: $( grep '^ripwire:' "$TMP/b12.err" | head -c 200 )"
fi
if [ "$b12" = pass ] && grep -q "^ripwire: the memory guard stopped the parse at the parse line (half of the $B12LIM limit)" "$TMP/b12.err"; then
    ok "(B12b) the stop line names the parse line (half of the limit), not the limit it did not reach"
else
    no "(B12b) stderr: $( grep '^ripwire:' "$TMP/b12.err" | head -c 250 )"
fi

echo "=== (C) a default run is byte-identical to the guard made huge ==="
for tree in "$FX" "$ROOT/test/fixture"; do
    "$BIN" "$tree" --no-cache >"$TMP/c_def.out" 2>&1
    "$BIN" "$tree" --no-cache --max-memory=1024G >"$TMP/c_big.out" 2>&1
    RIPWIRE_MAX_MEMORY=1024G "$BIN" "$tree" --no-cache >"$TMP/c_env.out" 2>&1
    if cmp -s "$TMP/c_def.out" "$TMP/c_big.out" && cmp -s "$TMP/c_def.out" "$TMP/c_env.out"; then
        ok "(C) $( basename "$tree" ): default == --max-memory=1024G == RIPWIRE_MAX_MEMORY=1024G"
    else
        no "(C) $( basename "$tree" ): the guard's limit changed a normal run's bytes"
    fi
    if grep -q 'memory_' "$TMP/c_def.out"; then
        no "(C) a default run mentions memory_"
    else
        ok "(C) no memory_ attribute on a normal run"
    fi
done

echo "=== (D) bad values are refused with a message ==="
for v in "" abc 0 10 64K -5 5X 1.5G 99999999999999999999G; do
    "$BIN" "$FX" --max-memory="$v" >/dev/null 2>"$TMP/d.err"; rc=$?
    if [ "$rc" = 1 ] && grep -q -- '--max-memory' "$TMP/d.err"; then
        ok "(D) --max-memory='$v' refused (exit 1, names the flag)"
    else
        no "(D) --max-memory='$v' rc=$rc stderr: $( head -c 200 "$TMP/d.err" )"
    fi
done
RIPWIRE_MAX_MEMORY=abc "$BIN" "$FX" >/dev/null 2>"$TMP/d2.err"; rc=$?
if [ "$rc" = 1 ] && grep -q 'RIPWIRE_MAX_MEMORY' "$TMP/d2.err"; then
    ok "(D) RIPWIRE_MAX_MEMORY=abc refused (exit 1, names the variable)"
else
    no "(D) RIPWIRE_MAX_MEMORY=abc rc=$rc stderr: $( head -c 200 "$TMP/d2.err" )"
fi
"$BIN" "$FX" --max-memory=64M >/dev/null 2>&1; rc=$?
if [ "$rc" = 0 ]; then
    ok "(D) the floor itself (64M) is accepted"
else
    no "(D) --max-memory=64M rc=$rc"
fi

echo
[ "$fail" = 0 ] && echo "memguardcheck: PASS" || echo "memguardcheck: FAIL"
exit "$fail"
