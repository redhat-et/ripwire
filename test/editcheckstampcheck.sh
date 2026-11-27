#!/usr/bin/env bash
# editcheckstampcheck.sh — card AT-STAMP-REUSE: --edit-check reads the at= stamp (gitstamp::stampAt: `rev-parse HEAD`,
# `status --porcelain`, the shallow probe) ONCE per answer. editCheckBundleText builds the verdict-only candidate and the
# full document in one call, and both carry at=. Before this card the candidate read the stamp and the full document read
# it again, so every --edit-check whose candidate was taken started a second `git status --porcelain` and two more
# rev-parse children for an answer the process already held. Nothing writes to the work tree between the two reads, so
# the second read can only repeat the first; the document now carries the first read's value.
#
# The probe is a PATH shim that records each git child's argv and then execs the real git (test/gitchildoptscheck.sh (F)
# uses the same shape). The fixture is a git repository generated here, never committed: target() in lib.py and 30
# callers in other files, so --edit-check=target's contract is unchanged with callers > 0, the candidate is taken, and
# leaving 30 rows out pays, so the verdict line ships on a clean tree.
#
# Arms:
#   V  clean tree, candidate taken (the verdict line ships): exactly one `status --porcelain` child, and at= is git's own
#      answer (the 9-hex HEAD, no +dirty). RED on a binary that reads the stamp twice: two status children.
#   D  dirty tree (an untracked file), candidate taken and refused on +dirty (the full document ships): one status child,
#      at= is HEAD+dirty, and the document lists its caller rows. RED likewise.
#   X  control, candidate not taken (--limit=2 pages the rows): one status child on any binary, so the shim's count is
#      live and the fixture reaches the stamp at all. Its at= is also git's answer.
#   S  every shape: the stamp's shallow probe (`rev-parse --is-shallow-repository`, asked by nothing else on these runs)
#      ran once, so the stamp's whole read — HEAD, status, shallow — happened once, not only its status. RED on V and D
#      likewise. (`rev-parse --verify HEAD` is not counted: the HEAD snapshot and the contract compare ask it too.)
#
# Usage: bash test/editcheckstampcheck.sh [BIN]      or   RIPWIRE_BIN=./build/ripwire bash test/editcheckstampcheck.sh
set -u
ROOT="$( cd "$( dirname "$0" )/.." && pwd )"
. "$ROOT/test/lib/clean-env.sh"
BIN="${1:-${RIPWIRE_BIN:-$ROOT/build/ripwire}}"
case "$BIN" in /*) ;; *) BIN="$PWD/$BIN" ;; esac
echo "editcheckstampcheck: BIN=$BIN  $( "$BIN" --version 2>/dev/null | head -1 )"
TMP="$( mktemp -d )"; trap 'rm -rf "$TMP"' EXIT
fail=0
ok(){ printf '  PASS  %s\n' "$*" || { fail=1; printf '  FAIL  could not write the PASS line for: %s\n' "$*"; }; return 0; }
no(){ fail=1; printf '  FAIL  %s\n' "$*"; return 0; }

if ! "$BIN" --version 2>/dev/null | grep -q '^ripwire '; then   # status: a binary that cannot run prints no version line, so the grep fails it
    echo "  FAIL  $BIN does not run"; echo "FAIL editcheckstampcheck"; exit 1
fi
REALGIT="$( command -v git 2>/dev/null )"
[ -n "$REALGIT" ] || { echo "  FAIL  git is required (the fixture is a repository)"; echo "FAIL editcheckstampcheck"; exit 1; }
export XDG_CACHE_HOME="$TMP/xdg" TMPDIR="$TMP/tmpdir"; mkdir -p "$XDG_CACHE_HOME" "$TMPDIR"

# ---- the shim: one line per git child, its argv joined by spaces ----
mkdir -p "$TMP/shim"
cat >"$TMP/shim/git" <<EOF
#!/bin/sh
printf '%s\n' "\$*" >>"\${GATE_GIT_LOG:-/dev/null}"
exec "$REALGIT" "\$@"
EOF
chmod +x "$TMP/shim/git"

# ---- the fixture ----
REPO="$TMP/repo"; mkdir -p "$REPO"
g(){ "$REALGIT" -C "$REPO" -c user.name=gate -c user.email=gate@example.invalid -c commit.gpgsign=false "$@" >/dev/null 2>&1; }
g init -q -b main || g init -q
printf 'def target( x ):\n    return x * 2\n' >"$REPO/lib.py"
for i in $( seq 1 30 ); do printf 'from lib import target\n\ndef use%s():\n    return target( %s )\n' "$i" "$i" >"$REPO/use$i.py"; done
g add -A; g commit -q -m one
HEAD9="$( "$REALGIT" -C "$REPO" rev-parse HEAD 2>/dev/null | cut -c1-9 )"
[ ${#HEAD9} -eq 9 ] || { echo "  FAIL  the fixture repository has no HEAD"; echo "FAIL editcheckstampcheck"; exit 1; }

# run NAME ARGS... -> NAME.out / .rc / .git (the children)
run(){ local name="$1"; shift; : >"$TMP/$name.git"
       ( cd "$REPO" && GATE_GIT_LOG="$TMP/$name.git" PATH="$TMP/shim:$PATH" "$BIN" "$REPO" --no-cache "$@" >"$TMP/$name.out" 2>"$TMP/$name.err" ); echo $? >"$TMP/$name.rc"; }
nstatus(){ grep -c ' status --porcelain' "$TMP/$1.git"; }
nshallow(){ grep -c ' rev-parse --is-shallow-repository' "$TMP/$1.git"; }
atof(){ grep -o '<edit-check [^>]*>' "$TMP/$1.out" | head -1 | sed -n 's/.* at="\([^"]*\)".*/\1/p'; }

# check NAME WANT-AT WANT-ROWS(yes|no|any) LABEL
check()
{
    local name="$1" want="$2" rows="$3" label="$4" n a
    n="$( nstatus "$name" )"; a="$( atof "$name" )"
    if [ "$( cat "$TMP/$name.rc" )" != 0 ]; then
        no "$label: --edit-check rc $( cat "$TMP/$name.rc" ): $( head -c 300 "$TMP/$name.err" )"
    elif [ "$a" != "$want" ]; then
        no "$label: at=\"$a\", want git's own answer \"$want\""
    elif [ "$rows" = yes ] && ! grep -q '<c n="use1"' "$TMP/$name.out"; then
        no "$label: premise: the full document should list the caller rows (no <c n=\"use1\">)"
    elif [ "$rows" = no ] && { grep -q '<c n="use' "$TMP/$name.out" || ! grep -q 'rows_next=' "$TMP/$name.out"; }; then
        no "$label: premise: the verdict line should ship (it lists caller rows, or carries no rows_next=)"
    elif [ "$n" -ne 1 ]; then
        no "$label: $n \`git status --porcelain\` children (want 1: the stamp is read once per answer)"
    else
        ok "$label: one status child, at=\"$a\" is git's answer"
    fi
    local r; r="$( nshallow "$name" )"
    if [ "$( cat "$TMP/$name.rc" )" != 0 ] || [ "$n" -lt 1 ]; then no "S[$name]: not read: the run failed or never reached the stamp ($n status children)"
    elif [ "$r" -ne 1 ]; then no "S[$name]: $r shallow-probe children (want 1: the stamp is read once)"; else ok "S[$name]: one shallow-probe child: the stamp's whole read ran once"; fi
}

run v --edit-check=target
check v "$HEAD9" no "V clean, verdict line"
run x --edit-check=target --limit=2
check x "$HEAD9" any "X control, candidate not taken"
printf 'scratch\n' >"$REPO/notes.txt"
run d --edit-check=target
check d "$HEAD9+dirty" yes "D dirty, full document"

if [ "$fail" -eq 0 ]; then echo "PASS editcheckstampcheck"; exit 0; fi
echo "FAIL editcheckstampcheck"; exit 1
