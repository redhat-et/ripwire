#!/usr/bin/env bash
# cachesplitcheck.sh — ONE-PARSE gate (kCacheVersion 56, #729): ONE warm-by-default parse blob per root serves BOTH verb
# classes, and a lean verb's facts taken from it are exactly a lean parse's.
#
# Background. A4-P4 split the auto-cache by verb class: the rich class (--for/--metrics/--uses/--exemplar and the other
# needsValueUses verbs, captureValueUses=true) and the lean class (the map and the nav/read verbs) each kept its own blob,
# stamped with its own parser number, because one shared file was re-parsed and rewritten on every class switch. The split
# cost a second cold parse instead: a --for straight after a map re-parsed every file (cached_records=0). Since format 56
# every record is the rich one (the value-use rows, marked RawRef::valueUse, and each def's subtoken stats) whoever wrote
# it, and a lean ingest drops the rich-only rows after the blob is written (ingest_parsepool.h dropRichOnlyFacts). This
# gate holds both halves: one blob, shared without a re-parse, and the projection equal to a lean parse.
#
# The corpus is every test/*fix directory copied into one tree (C, C++, ObjC, Python, JS/TS, Ruby, Go, ...): the value-use
# pass is armed for C++/ObjC/Python, so the rich rows exist to be dropped. XDG_CACHE_HOME is redirected (TMPDIR unset) so
# the auto-cache lands in a directory this gate owns.
#
# ARMS (each negative arm counts what it saw and FAILs on zero)
#   (a) rich then lean: exactly ONE parse blob (`ripwire-<16hex>-c<format>p<parser>.bin`) exists, and no `-lean-` or
#       `-rich-` blob. The lean run read every record a rich run wrote: reparsed=0, cached_records = the file count > 0.
#   (b) lean then rich, in a fresh cache directory: the same one blob, and the rich run re-parsed nothing (the case the
#       split cost a cold parse: a --for straight after a map).
#   (c) PROJECTION: the lean model a run assembles from the shared blob has every family the size a lean parse gives it
#       (`--no-cache`, which parses lean): the RIPWIRE_STATS `[mem] family` lines are equal, after a rich-written blob and
#       after a lean-written one. Premise: the rich model holds MORE references than the lean one (zero rich-only rows
#       would make the comparison vacuous), and the lean model holds no subtoken stats.
#   (d) BYTE-IDENTITY: after the alternation, every lean verb below answers byte-identically to --no-cache (map, --deps,
#       --callers, --expand), and so does a rich one (--for).
#
# Usage:
#   bash test/cachesplitcheck.sh [BIN]
#   RIPWIRE_BIN=build_w2a/ripwire bash test/cachesplitcheck.sh
#
# Exits non-zero on any failure; prints PASS/FAIL per check; prints ALL PASS on success.

set -u
ROOT="$( cd "$( dirname "$0" )/.." && pwd )"
. "$ROOT/test/lib/clean-env.sh"
BIN="${1:-${RIPWIRE_BIN:-$ROOT/build/ripwire}}"
[ "${BIN#/}" = "$BIN" ] && BIN="$ROOT/$BIN"          # allow a repo-relative RIPWIRE_BIN
TMP="$( mktemp -d )" && [ -n "$TMP" ] && [ -d "$TMP" ] || { echo "cachesplitcheck: mktemp -d failed"; exit 2; }
trap 'rm -rf "$TMP"' EXIT
fail=0
ok(){ printf '  PASS  %s\n' "$*" || { fail=1; printf '  FAIL  could not write the PASS line for: %s\n' "$*"; }; return 0; }
no(){ printf '  FAIL  %s\n' "$*"; fail=1; }

[ -x "$BIN" ] || { echo "no ripwire binary at $BIN — build first (cmake --build build -j)"; exit 2; }
echo "cachesplitcheck: BIN=$BIN  TMP=$TMP"

W="$TMP/w"; mkdir -p "$W"
for d in "$ROOT"/test/*fix; do cp -R "$d" "$W/" 2>/dev/null; done
NF="$( find "$W" -type f | wc -l | tr -d ' ' )"
echo "cachesplitcheck: corpus $NF files"
FOR='distance between two points'

# run XDG ARGS... — the auto-cache under $XDG/ripwire; stdout to $TMP/o, stderr to $TMP/e
run(){ local xdg="$1"; shift; ( cd "$W" && env -u TMPDIR XDG_CACHE_HOME="$xdg" RIPWIRE_CACHE_STATS=1 "$BIN" . "$@" >"$TMP/o" 2>"$TMP/e" </dev/null ); }
blobs(){ find "$1/ripwire" -maxdepth 2 -type f -name 'ripwire-*.bin' 2>/dev/null | grep -E '/ripwire-[0-9a-f]{16}-c[0-9]+p[0-9]+\.bin$' | wc -l | tr -d ' '; }
classblobs(){ find "$1/ripwire" -maxdepth 2 -type f \( -name 'ripwire-*-lean*.bin' -o -name 'ripwire-*-rich*.bin' \) 2>/dev/null | wc -l | tr -d ' '; }
stats(){ grep -o 'cache-stats reparsed=[0-9]* reused=[0-9]* files=[0-9]* cached_records=[0-9]*' "$TMP/e" | head -1; }
# shared NAME XDG: the run just made re-parsed nothing and read every crawled file's record
shared()
{
    local s; s="$( stats )"
    local rep="${s#*reparsed=}"; rep="${rep%% *}"
    local files="${s#*files=}"; files="${files%% *}"
    local rec="${s#*cached_records=}"; rec="${rec%% *}"
    if [ -z "$s" ]; then
        no "$1: no cache-stats line — the share cannot be read, and an absent line must never read as a hit"
    elif [ "$rep" = 0 ] && [ "$files" -gt 0 ] && [ "$rec" = "$files" ]; then
        ok "$1: read every record the other class wrote ($s)"
    else
        no "$1: did not share the blob ($s)"
    fi
}
oneblob()
{
    local n c; n="$( blobs "$2" )"; c="$( classblobs "$2" )"
    [ "$n" = 1 ] && [ "$c" = 0 ] && ok "$1: exactly one parse blob, no -lean-/-rich- class blob" \
        || no "$1: expected one parse blob and no class blob, found $n parse blob(s) and $c class blob(s): $( find "$2/ripwire" -maxdepth 2 -name 'ripwire-*.bin' -exec basename {} \; | tr '\n' ' ' )"
}

# ── (a) rich, then lean ───────────────────────────────────────────────────────────────────────────────
XA="$TMP/xa"; mkdir -p "$XA"
run "$XA" --for="$FOR"   # status: the blob census (shared/oneblob) is the verdict; a failed run writes no blob and those arms FAIL
run "$XA"   # status: the blob census (shared/oneblob) is the verdict; a failed run writes no blob and those arms FAIL
shared "(a) lean after rich" "$XA"
oneblob "(a) rich then lean" "$XA"

# ── (b) lean, then rich, fresh directory ─────────────────────────────────────────────────────────────
XB="$TMP/xb"; mkdir -p "$XB"
run "$XB"   # status: the blob census (shared/oneblob) is the verdict; a failed run writes no blob and those arms FAIL
run "$XB" --for="$FOR"   # status: the blob census (shared/oneblob) is the verdict; a failed run writes no blob and those arms FAIL
shared "(b) rich after lean (a --for straight after a map)" "$XB"
oneblob "(b) lean then rich" "$XB"

# ── (c) projection: every lean family the size a lean parse gives it ─────────────────────────────────
fam(){ grep -E '^\[mem\] (family|bindings by kind)' "$TMP/e" | sed -E 's/ cap=[0-9]+//; s/ cap_mib=[0-9.]+//'; }
( cd "$W" && RIPWIRE_STATS=1 "$BIN" . --no-cache >/dev/null 2>"$TMP/e" </dev/null ); fam >"$TMP/fam.cold"   # status: the [mem] family lines are the verdict; a failed run prints none and the (c) premise FAILs
( cd "$W" && RIPWIRE_STATS=1 "$BIN" . --no-cache --for="$FOR" >/dev/null 2>"$TMP/e" </dev/null ); fam >"$TMP/fam.rich"   # status: the [mem] family lines are the verdict; a failed run prints none and the (c) premise FAILs
( cd "$W" && env -u TMPDIR XDG_CACHE_HOME="$XA" RIPWIRE_STATS=1 RIPWIRE_NO_WARMSNAP=1 "$BIN" . >/dev/null 2>"$TMP/e" </dev/null ); fam >"$TMP/fam.a"   # status: the [mem] family lines are the verdict; a failed run prints none and the (c) premise FAILs
( cd "$W" && env -u TMPDIR XDG_CACHE_HOME="$XB" RIPWIRE_STATS=1 RIPWIRE_NO_WARMSNAP=1 "$BIN" . >/dev/null 2>"$TMP/e" </dev/null ); fam >"$TMP/fam.b"   # status: the [mem] family lines are the verdict; a failed run prints none and the (c) premise FAILs
refs(){ grep -o 'family references size=[0-9]*' "$1" | grep -o '[0-9]*$'; }
lex(){ grep -o 'family lexTokenHashes size=[0-9]*' "$1" | grep -o '[0-9]*$'; }
NL="$( wc -l <"$TMP/fam.cold" | tr -d ' ' )"; RL="$( refs "$TMP/fam.cold" )"; RR="$( refs "$TMP/fam.rich" )"
if [ "$NL" -ge 17 ] && [ -n "$RL" ] && [ -n "$RR" ] && [ "$RR" -gt "$RL" ] && [ "$( lex "$TMP/fam.cold" )" = 0 ] && [ "$( lex "$TMP/fam.rich" )" -gt 0 ]; then
    ok "(c) premise: $NL family lines; the rich model holds $RR references against the lean $RL, and subtoken stats the lean one does not"
else
    no "(c) premise: $NL family lines, references rich=${RR:-?} lean=${RL:-?}, lexTokenHashes rich=$( lex "$TMP/fam.rich" ) lean=$( lex "$TMP/fam.cold" ) — no rich-only row to drop, the projection arm is vacuous"
fi
for k in a b; do
    if cmp -s "$TMP/fam.cold" "$TMP/fam.$k"; then
        ok "(c) projection ($k): every lean family from the shared blob is the size a lean parse gives it ($NL lines equal)"
    else
        no "(c) projection ($k): a lean family from the shared blob differs from a lean parse"; diff "$TMP/fam.cold" "$TMP/fam.$k" | head -6
    fi
done

# ── (d) byte identity after the alternation ──────────────────────────────────────────────────────────
( cd "$W" && "$BIN" . --no-cache >"$TMP/map.cold" 2>/dev/null </dev/null )   # status: the --no-cache reference; the cmp against it below is the verdict
SYM="$( grep -o '<s [^>]*n="[A-Za-z_][A-Za-z0-9_]*"' "$TMP/map.cold" | head -1 | sed -E 's/.*n="([^"]*)".*/\1/' )"
[ -n "$SYM" ] || SYM=distance
checks=0
for args in "" "--deps" "--callers=$SYM" "--expand=$SYM" "--for=$FOR"; do
    a=(); [ -n "$args" ] && a=( "$args" )
    for x in "$XA" "$XB"; do
        run "$x" ${a[@]+"${a[@]}"}; wrc=$?; cp "$TMP/o" "$TMP/warm"
        ( cd "$W" && "$BIN" . --no-cache ${a[@]+"${a[@]}"} >"$TMP/cold" 2>/dev/null </dev/null ); crc=$?
        checks=$(( checks + 1 ))
        if [ "$wrc" != 0 ] || [ "$crc" != 0 ]; then
            no "(d) '${args:-map}' ($( basename "$x" )): exit status warm=$wrc --no-cache=$crc"
        elif [ -s "$TMP/cold" ] && cmp -s "$TMP/cold" "$TMP/warm"; then
            ok "(d) '${args:-map}' on the shared blob ($( basename "$x" )) == --no-cache ($( wc -c <"$TMP/cold" | tr -d ' ' ) B)"
        else
            no "(d) '${args:-map}' on the shared blob ($( basename "$x" )) diverges from --no-cache (or is empty)"; diff "$TMP/cold" "$TMP/warm" | head -6
        fi
    done
done
[ "$checks" -ge 10 ] || no "(d) ran $checks comparisons, expected 10"

[ "$fail" = 0 ] && echo "ALL PASS" || echo "FAILURES ABOVE"
exit $fail
