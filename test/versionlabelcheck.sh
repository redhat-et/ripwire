#!/usr/bin/env bash
# versionlabelcheck.sh — gate for DEV-VERSION-LABEL (0.7.0 rehearsal on the M5, 2026-11-14).
#
# A dev build of main 46 commits past v0.6.10 reported plain `0.6.10`, so a reader (and the 0.7.0 table's rung labels)
# could not tell a tag build from a build of main. cmake/version_stamp.cmake now stamps kRipwireVersionLabel:
#   on the tag v<VERSION>, clean          -> <VERSION>
#   on the tag v<VERSION>, dirty tree     -> <VERSION>+dirty
#   N first-parent commits past the tag   -> <VERSION>-dev.N+g<sha9>        (+ .dirty when the tree is dirty)
#   a git checkout with no v<VERSION> tag -> <VERSION>-dev+g<sha9>          (a shallow CI clone; a version bump before its tag)
#   no git at all (an exported tarball)   -> <VERSION>-dev                  (unknown provenance is never called a release)
# and every surface that prints the version prints that ONE label.
#
# Arms (each counts its premise and FAILS on zero):
#   (T)  tag build          — a fixture repo whose HEAD is tagged v9.9.9 stamps exactly 9.9.9
#   (T2) tag build, dirty   — the same repo with a tracked edit stamps 9.9.9+dirty
#   (D)  dev build          — 2 first-parent commits past the tag (one a merge of a 3-commit side branch) stamps
#                             9.9.9-dev.2+g<sha9>: the count is main's own commits, not the side branch's
#   (N)  no matching tag    — only v9.9.8 exists: 9.9.9-dev+g<sha9>, no invented count
#   (G)  no git             — a plain directory stamps 9.9.9-dev
#   (B)  this binary        — --version's second token is the label the stamp computes for this checkout, and the MCP
#                             serverInfo, the LSP serverInfo, the --html page's VERSION and the --doctor stale hint print
#                             the same label
#
# Usage: bash test/versionlabelcheck.sh [BIN]     Exit 0 ALL PASS, 1 a FAIL, 2 setup error.

set -u
ROOT="$( cd "$( dirname "$0" )/.." && pwd )"
BIN="${1:-${RIPWIRE_BIN:-$ROOT/build/ripwire}}"
[ "${BIN#/}" = "$BIN" ] && BIN="$ROOT/$BIN"
[ -x "$BIN" ] || { echo "no ripwire binary at $BIN — build first (cmake --build build -j)"; exit 2; }
command -v git >/dev/null 2>&1 || { echo "versionlabelcheck needs git"; exit 2; }
CMAKE="${CMAKE:-cmake}"
command -v "$CMAKE" >/dev/null 2>&1 || { echo "versionlabelcheck needs cmake"; exit 2; }
echo "versionlabelcheck: BIN=$BIN"

fail=0
ok(){ printf '  PASS  %s\n' "$*" || { fail=1; printf '  FAIL  could not write the PASS line for: %s\n' "$*"; }; return 0; }
no(){ printf '  FAIL  %s\n' "$*"; fail=1; }

TMP="$( mktemp -d "${TMPDIR:-/tmp}/versionlabel.XXXXXX" )" || exit 2
trap 'rm -rf "$TMP"' EXIT
export GIT_CEILING_DIRECTORIES="$TMP"   # a fixture dir must never resolve to an enclosing repo
export GIT_CONFIG_GLOBAL=/dev/null GIT_CONFIG_NOSYSTEM=1
G(){ git -C "$1" -c user.name=t -c user.email=t@t -c commit.gpgsign=false -c tag.gpgsign=false "${@:2}"; }

# stamp DIR VERSION -> the label cmake/version_stamp.cmake writes for a checkout at DIR ("" when it wrote none)
stamp(){
    local out="$TMP/stamp.$RANDOM.h"
    "$CMAKE" -DRIPWIRE_SOURCE_DIR="$1" -DRIPWIRE_OUTPUT="$out" -DRIPWIRE_VERSION="$2" -DRIPWIRE_BUILD_TYPE=dev \
             -DRIPWIRE_COMPILER_ID=X -DRIPWIRE_COMPILER_VER=0 -P "$ROOT/cmake/version_stamp.cmake" >/dev/null 2>&1 || return 0
    sed -nE 's/^inline constexpr const char\* kRipwireVersionLabel *= "([^"]*)";$/\1/p' "$out"
}

# ── fixture repo: C0 tagged v9.9.9 ──────────────────────────────────────────────────────────────────────
R="$TMP/repo"; mkdir -p "$R"
G "$R" init -q -b main
echo a >"$R/f"; G "$R" add f; G "$R" commit -q -m c0; G "$R" tag -a v9.9.9 -m v9.9.9
[ "$( G "$R" describe --tags --exact-match 2>/dev/null )" = "v9.9.9" ] || { echo "setup: fixture HEAD is not on v9.9.9"; exit 2; }

L="$( stamp "$R" 9.9.9 )"
if [ "$L" = "9.9.9" ]; then ok "(T) tag build: HEAD on v9.9.9 stamps exactly '9.9.9'"; else no "(T) tag build stamps '$L', expected '9.9.9'"; fi

echo b >>"$R/f"
L="$( stamp "$R" 9.9.9 )"
if [ "$L" = "9.9.9+dirty" ]; then ok "(T2) tag build with a tracked edit stamps '9.9.9+dirty'"; else no "(T2) dirty tag build stamps '$L', expected '9.9.9+dirty'"; fi
G "$R" checkout -q -- f

# ── (D): C1 on main, a 3-commit side branch merged back (M) — first-parent distance 2, total distance 5 ────
echo c1 >"$R/g"; G "$R" add g; G "$R" commit -q -m c1
G "$R" checkout -q -b side
for i in 1 2 3; do echo "s$i" >"$R/s$i"; G "$R" add "s$i"; G "$R" commit -q -m "s$i"; done
G "$R" checkout -q main
G "$R" merge -q --no-ff side -m merge
FP="$( G "$R" rev-list --first-parent --count v9.9.9..HEAD )"; ALL="$( G "$R" rev-list --count v9.9.9..HEAD )"
SHA="$( G "$R" rev-parse --short=9 HEAD )"
{ [ "$FP" = 2 ] && [ "$ALL" = 5 ]; } || { echo "setup: expected first-parent 2 / all 5 past the tag, got $FP / $ALL"; exit 2; }
L="$( stamp "$R" 9.9.9 )"
if [ "$L" = "9.9.9-dev.2+g$SHA" ]; then ok "(D) dev build: 2 first-parent commits past v9.9.9 (5 in all) stamps '$L'"; else no "(D) dev build stamps '$L', expected '9.9.9-dev.2+g$SHA'"; fi
echo d >>"$R/g"
L="$( stamp "$R" 9.9.9 )"
if [ "$L" = "9.9.9-dev.2+g$SHA.dirty" ]; then ok "(D2) dirty dev build stamps '$L'"; else no "(D2) dirty dev build stamps '$L', expected '9.9.9-dev.2+g$SHA.dirty'"; fi
G "$R" checkout -q -- g

# ── (N): the version was bumped before its tag exists (or a tagless shallow clone) ───────────────────────
R2="$TMP/repo2"; mkdir -p "$R2"
G "$R2" init -q -b main; echo a >"$R2/f"; G "$R2" add f; G "$R2" commit -q -m c0; G "$R2" tag v9.9.8
echo b >"$R2/f"; G "$R2" commit -q -am c1
SHA2="$( G "$R2" rev-parse --short=9 HEAD )"
[ -z "$( G "$R2" tag -l v9.9.9 )" ] && [ -n "$( G "$R2" tag -l v9.9.8 )" ] || { echo "setup: repo2 tags wrong"; exit 2; }
L="$( stamp "$R2" 9.9.9 )"
if [ "$L" = "9.9.9-dev+g$SHA2" ]; then ok "(N) no v9.9.9 tag (only v9.9.8): stamps '$L', no invented count"; else no "(N) no matching tag stamps '$L', expected '9.9.9-dev+g$SHA2'"; fi

# ── (G): an exported tree with no git ───────────────────────────────────────────────────────────────────
P="$TMP/plain"; mkdir -p "$P"; echo a >"$P/f"
git -C "$P" rev-parse HEAD >/dev/null 2>&1 && { echo "setup: $P resolves to a git repo"; exit 2; }
L="$( stamp "$P" 9.9.9 )"
if [ "$L" = "9.9.9-dev" ]; then ok "(G) no git: stamps '9.9.9-dev' (unknown provenance is not a release)"; else no "(G) no-git build stamps '$L', expected '9.9.9-dev'"; fi

# ── (B): every surface of THIS binary prints the one label ──────────────────────────────────────────────
CMAKE_VER="$( grep -oE 'project\(ripwire VERSION [0-9]+\.[0-9]+\.[0-9]+' "$ROOT/CMakeLists.txt" | grep -oE '[0-9]+\.[0-9]+\.[0-9]+' )"
VLINE="$( "$BIN" --version 2>/dev/null )"; vrc=$?
if [ "$vrc" -ne 0 ]; then no "(B) --version exited $vrc"; fi
BLABEL="$( printf '%s' "$VLINE" | awk '{print $2}' )"
BUILT="$( printf '%s' "$VLINE" | sed -nE 's/.*built_from=([^)]*)\).*/\1/p' )"
HEAD9="$( git -C "$ROOT" rev-parse --short=9 HEAD 2>/dev/null || true )"
if [ -n "$HEAD9" ] && [ "${BUILT%+dirty}" = "$HEAD9" ]; then
    WANT="$( stamp "$ROOT" "$CMAKE_VER" )"
    # the tree's dirtiness may have moved since the build; compare with the build's own +dirty
    case "$BUILT" in *+dirty) case "$WANT" in *dirty) ;; *+*) WANT="$WANT.dirty";; *) WANT="$WANT+dirty";; esac;;
                     *) WANT="${WANT%.dirty}"; WANT="${WANT%+dirty}";; esac
    if [ -n "$WANT" ] && [ "$BLABEL" = "$WANT" ]; then ok "(B) --version prints '$BLABEL', the label the stamp computes for this checkout"; else no "(B) --version prints '$BLABEL', the stamp computes '$WANT' ($VLINE)"; fi
else
    no "(B) $BIN was not built from this checkout's HEAD ($BUILT vs $HEAD9) — rebuild before running this gate"
fi
case "$BLABEL" in "$CMAKE_VER"|"$CMAKE_VER"[-+]*) ok "(B) the label starts with CMakeLists.txt's VERSION $CMAKE_VER";;
                  *) no "(B) the label '$BLABEL' does not start with $CMAKE_VER";; esac

MINIT='{"jsonrpc":"2.0","id":0,"method":"initialize","params":{"protocolVersion":"2025-11-25","capabilities":{},"clientInfo":{"name":"t","version":"1"}}}'
printf '%s\n' "$MINIT" >"$TMP/mcp.in"
MOUT="$( cd "$ROOT/test/fixture" && "$BIN" --mcp <"$TMP/mcp.in" 2>/dev/null )"; mrc=$?
if [ "$mrc" -ne 0 ]; then no "(B) --mcp exited $mrc on initialize + EOF"; fi
MVER="$( printf '%s' "$MOUT" | grep -oE '"serverInfo":\{"name":"ripwire","version":"[^"]*"' | sed -E 's/.*"version":"([^"]*)"/\1/' )"
if [ -n "$MVER" ] && [ "$MVER" = "$BLABEL" ]; then ok "(B) MCP serverInfo.version is '$MVER'"; else no "(B) MCP serverInfo.version is '$MVER', --version says '$BLABEL'"; fi

LINIT="{\"jsonrpc\":\"2.0\",\"id\":1,\"method\":\"initialize\",\"params\":{\"rootUri\":\"file://$ROOT/test/fixture\",\"capabilities\":{}}}"
LEXIT='{"jsonrpc":"2.0","id":2,"method":"shutdown"}'
{ printf 'Content-Length: %d\r\n\r\n%s' "${#LINIT}" "$LINIT"; printf 'Content-Length: %d\r\n\r\n%s' "${#LEXIT}" "$LEXIT"; } >"$TMP/lsp.in"
LOUT="$( "$BIN" --lsp <"$TMP/lsp.in" 2>/dev/null )"; lrc=$?
if [ "$lrc" -ne 0 ]; then no "(B) --lsp exited $lrc on initialize + shutdown + EOF"; fi
LVER="$( printf '%s' "$LOUT" | grep -oE '"serverInfo":\{"name":"ripwire","version":"[^"]*"' | sed -E 's/.*"version":"([^"]*)"/\1/' )"
if [ -n "$LVER" ] && [ "$LVER" = "$BLABEL" ]; then ok "(B) LSP serverInfo.version is '$LVER'"; else no "(B) LSP serverInfo.version is '$LVER', --version says '$BLABEL'"; fi

HCORP="$TMP/hcorp"; cp -R "$ROOT/test/fixture" "$HCORP"
( cd "$HCORP" && "$BIN" . --html --no-cache >"$TMP/page.html" 2>/dev/null ); hrc=$?
if [ "$hrc" -ne 0 ]; then no "(B) --html exited $hrc"; fi
HVER="$( sed -nE 's/.*const VERSION = "([^"]*)";.*/\1/p' "$TMP/page.html" | head -1 )"
if [ -n "$HVER" ] && [ "$HVER" = "$BLABEL" ]; then ok "(B) --html page VERSION is '$HVER'"; else no "(B) --html page VERSION is '$HVER', --version says '$BLABEL'"; fi

OLDDIR="$TMP/olderripwire"; mkdir -p "$OLDDIR"
printf '%s\n' '#!/bin/sh' 'case "$1" in --version) echo "ripwire 0.0.1 (Release, X 0, emit=std::print, built_from=000000000)";; esac' >"$OLDDIR/ripwire"
chmod +x "$OLDDIR/ripwire"; mkdir -p "$TMP/dcache"
DOUT="$( PATH="$OLDDIR:$PATH" TMPDIR="$TMP/dcache" "$BIN" "$HCORP" --doctor --no-cache 2>/dev/null )"; drc=$?
if [ "$drc" -gt 1 ]; then no "(B) --doctor exited $drc (1 is its verdict for the failed binary-path row this arm plants)"; fi
DROW="$( printf '%s' "$DOUT" | grep -oE '<c n="binary-path"[^<]*/>' )"
if [ -z "$DROW" ]; then no "(B) --doctor printed no binary-path row (premise)"; fi
if printf '%s' "$DROW" | grep -qF "(ripwire $BLABEL)"; then ok "(B) --doctor's version-mismatch hint names this binary as 'ripwire $BLABEL'"; else no "(B) --doctor's hint does not name 'ripwire $BLABEL': $DROW"; fi

[ "$fail" -eq 0 ] && { echo "versionlabelcheck: ALL PASS"; exit 0; }
echo "versionlabelcheck: FAIL"; exit 1
