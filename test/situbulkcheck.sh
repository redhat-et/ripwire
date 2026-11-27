#!/usr/bin/env bash
# situbulkcheck.sh — card SITU-BULK-DISCLOSE: --situ's co-change section [3] mines its commits with gitCommitFileSets,
# which keeps a commit only when it touched 1..30 indexed files. A commit over 30 is dropped, and before this card nothing
# said so: commits= counted only the kept commits, and a window whose every commit was bulk printed "no git history
# reached it". The cut is a cut, so it is disclosed — bulk_skipped="N" on the [3] header and "cochange_bulk_skipped":N in
# the MCP situational_awareness twin, both present only when N > 0 (the spelling --pack-task's <partners> uses, #786).
#
# Fixtures are git repositories generated here, never committed. Each is cross-checked against git itself before any arm.
#   MIX: a.c and b.c committed together four times (a partner with support 4), then a 31-file commit (a.c + 30 new files,
#        over the cut) and a 30-file commit (a.c + 29 of them, at the cut, so kept).
#   ALL: one commit, a.c + 30 more files: the whole window is bulk.
#   NONE: a.c and b.c, four commits: no commit near the cut.
#
# Arms:
#   M1  MIX: --situ=a.c's [3] header says commits="5" bulk_skipped="1" (six commits hold indexed files; the 31-file one is
#       out, the 30-file one is in) and still names b.c. RED on a binary without the census: no bulk_skipped=.
#   M2  MIX: the MCP twin's JSON carries "cochange_commits":5 and "cochange_bulk_skipped":1. RED likewise.
#   A1  ALL: [3] says commits="0" bulk_skipped="1", and the empty line says the window's commits were all over the cut —
#       not "no git history reached it", which is false here. RED on a binary that prints the no-history line.
#   A2  ALL: the MCP twin carries "cochange_bulk_skipped":1.
#   N1  NONE: no bulk_skipped= in [3] and no cochange_bulk_skipped key in the MCP twin. Its premise: the same run's [3]
#       names b.c and says commits="4", so the header the silence is read from is the right one.
#
# Usage: bash test/situbulkcheck.sh [BIN]      or   RIPWIRE_BIN=./build/ripwire bash test/situbulkcheck.sh
set -u
ROOT="$( cd "$( dirname "$0" )/.." && pwd )"
. "$ROOT/test/lib/clean-env.sh"
BIN="${1:-${RIPWIRE_BIN:-$ROOT/build/ripwire}}"
case "$BIN" in /*) ;; *) BIN="$PWD/$BIN" ;; esac
echo "situbulkcheck: BIN=$BIN  $( "$BIN" --version 2>/dev/null | head -1 )"
TMP="$( mktemp -d )"; trap 'rm -rf "$TMP"' EXIT
fail=0
ok(){ printf '  PASS  %s\n' "$*" || { fail=1; printf '  FAIL  could not write the PASS line for: %s\n' "$*"; }; return 0; }
no(){ fail=1; printf '  FAIL  %s\n' "$*"; return 0; }

if ! "$BIN" --version 2>/dev/null | grep -q '^ripwire '; then   # status: a binary that cannot run prints no version line, so the grep fails it
    echo "  FAIL  $BIN does not run"; echo "FAIL situbulkcheck"; exit 1
fi
command -v git >/dev/null 2>&1 || { echo "  FAIL  git is required (the fixtures are repositories)"; echo "FAIL situbulkcheck"; exit 1; }
command -v python3 >/dev/null 2>&1 || { echo "  FAIL  python3 is required (the MCP arms parse JSON)"; echo "FAIL situbulkcheck"; exit 1; }
export XDG_CACHE_HOME="$TMP/xdg" TMPDIR="$TMP/tmpdir"; mkdir -p "$XDG_CACHE_HOME" "$TMPDIR"

# gc REPO MSG — commit everything staged-or-not, as a human author (bot authors are left out of co-change, #777)
gc(){ git -C "$1" add -A >/dev/null 2>&1 && git -C "$1" -c user.name=gate -c user.email=gate@example.invalid -c commit.gpgsign=false commit -q -m "$2" >/dev/null 2>&1; }
newrepo(){ mkdir -p "$1"; git -C "$1" init -q -b main >/dev/null 2>&1 || git -C "$1" init -q >/dev/null 2>&1; }
cfile(){ printf 'int %s( int x ) { return x + %s; }\n' "$2" "$3" >"$1"; }   # PATH NAME VALUE
pair4(){ local r="$1" i; cfile "$r/a.c" fa 0; cfile "$r/b.c" fb 0; gc "$r" pair0; for i in 1 2 3; do cfile "$r/a.c" fa "$i"; cfile "$r/b.c" fb "$i"; gc "$r" "pair$i"; done; }
# files-per-commit as git sees them, oldest first, e.g. "2 2 2 2 31 30"
shape(){ git -C "$1" log --reverse --format=%x00 --name-only | awk 'BEGIN{RS="\0"} NR>1{n=0; k=split($0,L,"\n"); for(i=1;i<=k;i++) if(L[i]!="") n++; printf "%s%d", (NR>2?" ":""), n}'; }

MIX="$TMP/mix"; newrepo "$MIX"; pair4 "$MIX"
cfile "$MIX/a.c" fa 4; for i in $( seq -w 1 30 ); do cfile "$MIX/f$i.c" "f$i" 0; done; gc "$MIX" bulk31
cfile "$MIX/a.c" fa 5; for i in $( seq -w 1 29 ); do cfile "$MIX/f$i.c" "f$i" 1; done; gc "$MIX" edge30
ALL="$TMP/all"; newrepo "$ALL"
cfile "$ALL/a.c" fa 0; for i in $( seq -w 1 30 ); do cfile "$ALL/f$i.c" "f$i" 0; done; gc "$ALL" bulk31
NONE="$TMP/none"; newrepo "$NONE"; pair4 "$NONE"

for spec in "mix:$MIX:2 2 2 2 31 30" "all:$ALL:31" "none:$NONE:2 2 2 2"; do
    name="${spec%%:*}"; rest="${spec#*:}"; repo="${rest%%:*}"; want="${rest#*:}"
    got="$( shape "$repo" )"
    if [ "$got" != "$want" ]; then
        echo "  FAIL  fixture $name: files per commit are [$got], want [$want] (git's own count)"; echo "FAIL situbulkcheck"; exit 1
    fi
done
ok "fixtures: files per commit as git counts them — MIX [2 2 2 2 31 30], ALL [31], NONE [2 2 2 2]"

# situ NAME REPO — the CLI report; h3 NAME — its [3] header line
situ(){ ( cd "$2" && "$BIN" "$2" --no-cache --situ=a.c >"$TMP/$1.out" 2>"$TMP/$1.err" ); echo $? >"$TMP/$1.rc"; }
h3(){ grep -m1 '^  \[3\] co-change' "$TMP/$1.out"; }
# mcp NAME REPO — the situational_awareness twin; key NAME KEY prints the inner JSON's value, or __MISSING__
mcp(){ printf '%s\n' '{"jsonrpc":"2.0","id":1,"method":"initialize"}' \
           '{"jsonrpc":"2.0","id":2,"method":"tools/call","params":{"name":"situational_awareness","arguments":{"path":"'"$2"'","diff":"a.c"}}}' \
       | "$BIN" --mcp >"$TMP/$1.json" 2>/dev/null; echo $? >"$TMP/$1.rc"; }
key(){ python3 - "$TMP/$1.json" "$2" <<'PYEOF'
import json, sys
lines = [l for l in open(sys.argv[1], errors="replace") if l.strip()]
try:
    inner = json.loads(json.loads(lines[-1])["result"]["content"][0]["text"])
except Exception:
    print("__NOJSON__"); raise SystemExit
print(inner.get(sys.argv[2], "__MISSING__"))
PYEOF
}

situ mix "$MIX"; mcp mixm "$MIX"
situ all "$ALL"; mcp allm "$ALL"
situ none "$NONE"; mcp nonem "$NONE"
# every run under test exited 0 and every MCP answer parsed, so no arm below reads the empty text of a crashed run
bad=""
for r in mix mixm all allm none nonem; do [ "$( cat "$TMP/$r.rc" )" = 0 ] || bad="$bad $r:rc=$( cat "$TMP/$r.rc" )"; done
for r in mixm allm nonem; do [ "$( key "$r" cochange_window )" != __NOJSON__ ] || bad="$bad $r:no-json"; done
if [ -n "$bad" ]; then no "runs: a run under test failed or answered no JSON:$bad"; else ok "runs: three --situ runs and three MCP answers exited 0, and each MCP answer parsed"; fi

# ---- M1 ----
H="$( h3 mix )"
if [ "$( cat "$TMP/mix.rc" )" != 0 ] || [ -z "$H" ]; then
    no "M1: premise: --situ=a.c on MIX rc $( cat "$TMP/mix.rc" ), [3] header ${H:-absent}"
elif ! grep -q '^        b\.c ' "$TMP/mix.out"; then
    no "M1: premise: [3] does not name b.c (the four-commit partner): $H"
else
    case "$H" in
        *' commits="5"'*' bulk_skipped="1"'*) ok "M1: MIX [3] says commits=\"5\" bulk_skipped=\"1\" — the 31-file commit is out and disclosed, the 30-file one is in" ;;
        *) no "M1: MIX [3] header lacks commits=\"5\" … bulk_skipped=\"1\": $H" ;;
    esac
fi
# ---- M2 ----
c="$( key mixm cochange_commits )"; b="$( key mixm cochange_bulk_skipped )"
if [ "$c" = 5 ] && [ "$b" = 1 ]; then ok "M2: the MCP twin says cochange_commits 5, cochange_bulk_skipped 1"; else no "M2: MCP twin cochange_commits=$c (want 5) cochange_bulk_skipped=$b (want 1)"; fi

# ---- A1 ----
H="$( h3 all )"
case "$H" in
    *' commits="0"'*' bulk_skipped="1"'*)
        if grep -q 'no git history reached it' "$TMP/all.out"; then
            no "A1: ALL's empty line still says no git history reached the window, which held one (bulk) commit"
        elif ! grep -q 'over 30 indexed files' "$TMP/all.out"; then
            no "A1: ALL's empty line does not say the window's commits were over the 30-file cut: $( grep -A1 '^  \[3\]' "$TMP/all.out" | tail -1 )"
        else
            ok "A1: ALL [3] says commits=\"0\" bulk_skipped=\"1\" and its empty line names the cut, not missing history"
        fi ;;
    *) no "A1: ALL [3] header lacks commits=\"0\" … bulk_skipped=\"1\": ${H:-absent}" ;;
esac
# ---- A2 ----
b="$( key allm cochange_bulk_skipped )"
if [ "$b" = 1 ]; then ok "A2: the MCP twin says cochange_bulk_skipped 1 on the all-bulk window"; else no "A2: MCP twin cochange_bulk_skipped=$b (want 1)"; fi

# ---- N1 ----
H="$( h3 none )"
if ! grep -q '^        b\.c ' "$TMP/none.out" || [ "${H#*commits=\"4\"}" = "$H" ]; then
    no "N1: premise: NONE's [3] does not say commits=\"4\" and name b.c: ${H:-absent}"
elif [ "${H#*bulk_skipped}" != "$H" ]; then
    no "N1: NONE's [3] carries bulk_skipped= with no bulk commit: $H"
elif [ "$( key nonem cochange_bulk_skipped )" != __MISSING__ ] || [ "$( key nonem cochange_commits )" != 4 ]; then
    no "N1: NONE's MCP twin: cochange_bulk_skipped=$( key nonem cochange_bulk_skipped ) (want absent), cochange_commits=$( key nonem cochange_commits ) (want 4)"
else
    ok "N1: no bulk commit, no bulk_skipped= in [3] or the MCP twin (commits=\"4\", b.c named)"
fi

if [ "$fail" -eq 0 ]; then echo "PASS situbulkcheck"; exit 0; fi
echo "FAIL situbulkcheck"; exit 1
