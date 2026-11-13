#!/usr/bin/env bash
# qddegradecheck.sh — #387 follow-up: --quality-delta=A..B ANSWERS under memory pressure instead of refusing.
#
# THE DEFECT. A tripped memory guard in the range form gives exit 5 and nothing on stdout. On a large repository a
# 4-file change cannot get even the findings that need only those 4 files.
#
# THE CONTRACT these arms pin. Why a kind is LOCAL: every per-symbol baseline key is path-qualified (quality.h qualityKey)
# and so is the canonical id, so an UNCHANGED file yields the same keys and metrics in both trees and no row of such a kind:
#   * The 12 kinds split by input scope. LOCAL kinds (api-surface, complexity, error-masking, nesting, params,
#     placeholder, verbosity) need only the changed files' trees. defect-shape is LOCAL when the changed files define
#     the same C-family macro names on both sides and either the base's whole macro set was read (P1) or no changed
#     file is C++ (P0); otherwise it is skipped. WHOLE-TREE kinds (dead-code, duplication, new-clone-of-reused-helper)
#     need every file. short-horizon-churn is unavailable in the range form.
#   * When the base commit fit but the target phase is projected past the limit (P1), when the guard stopped a commit's
#     full ingest (P0), or when it stopped the target's ingest or graph after the projection said it fits (P1-late),
#     the range form ingests only the changed files of BOTH commits (never through a cache) and runs the kinds that can
#     run there. Every kind it does not run is NAMED (kinds_skipped=, skipped_why="memory"), with the limit
#     (memory_limit=), the projected need (memory_need="NM") or, after a stop, the stop (memory_stop=) and
#     memory_need="unmeasured", the whole-answer facts not computed (also_skipped=), and a replay (kinds_next=) that
#     runs exactly the skipped kinds.
#   * Exit: 2 when a row of a kind that ran gates (the skipped kinds can only add rows); otherwise 6 = a partial answer
#     with no gating row (never 0). Exit 5 with nothing on stdout only when even the changed files do not fit, or when
#     the changed files cannot stand in for the trees (a symlink, an export attribute) — named on one line.
#   * When memory suffices the degraded path is unreachable: output byte-identical to the build before it (L, T).
#   * --quality-kinds=K[,K] (range form only) runs exactly those kinds (the replay's selector): kinds_skipped=
#     skipped_why="selector"; stale acks are checked for the selected kinds only.
#
# SEAMS (RIPWIRE_TEST_MEMGUARD, memguard.h): crawl:N and parse:N count per INGEST (each ingest's own Watch), so (E) depends
# on the changed-file subsets staying under 12 crawl entries, directories included; project:N = the Nth projection
# reading says "does not fit" (one per range run); ingest:N = the Nth ingest of the process is cut at its first crawl
# entry; peak:N = the Nth post-answer peak reading reads as over the limit; hard:N = the Nth and later hard-line readings.
#
# Arms (RED on the build before this lane, except the guards (A), (G) A..A, (K) unpressured --json, (L) and (T)):
#   (A) premise: the fixture's unpressured answer has a row of each of the 11 kinds the range form measures.
#   (B) P1 forced (project:1): the degraded answer's header, exit code, stderr line, three ingests.
#   (C) P1: each LOCAL kind's rows equal the same kind's rows of (A); no row of a skipped kind.
#   (D) the kinds_next= replay yields exactly the skipped kinds' rows, not degraded again; union with (B) = (A).
#   (E) P0 (crawl seam cuts the base's FULL ingest): answers from the changed files; defect-shape skipped (a changed
#       C++ file and no whole macro set); memory_stop=, memory_need="unmeasured"; (E2) a Python-only change keeps it.
#   (F) even the changed files do not fit (hard line after the base ingest, and every later reading): exit 5; the
#       pre-check refusal says the changed files were NOT tried, never that they "did not fit" (review C3).
#   (G) near misses under project:1: an empty diff, a rename-only diff, a non-code-only diff, and A..A.
#   (H) --quality-kinds: unknown kind refused naming the 12; refused beside --quality-ack and on the bare form; each
#       single kind = (A)'s rows of that kind; all 12 named = byte-identical to no flag.
#   (I) --quality-ack is never pre-empted by the projection (review C2: project:1 acks in full, the same ledger as an
#       unpressured ack); a real stop (crawl:12) refuses it (exit 5) and leaves the ledger untouched.
#   (J) --scope naming an unchanged file under pressure is not refused as "names nothing indexed".
#   (K) legend + JSON: --legend=full defines every new attribute and parses as XML; --json carries the twins.
#   (L) guard: a projection seam index past the run's one projection reading changes nothing (byte-identical).
#   --- round 2 (gates review R1-R9) ---
#   (M) R1 defect-shape: a new site whose text also sits in an UNCHANGED file keeps its gating row under P1 and P0.
#   (N) R2 the changed set: an unchanged symlink, an export-ignore flip and an export-subst tree refuse by name (exit 5);
#       an unchanged export-ignore attribute and a CMakeCache.txt-pruned directory answer like the full run.
#       A git grep that FAILS (exit 128, through a PATH shim) refuses (exit 1), never "no export attribute".
#   (O) R3 acks: a legacy-scheme ack on a name two files define (one changed) suppresses the same rows as the full run;
#       on a name one file defines, the degraded answer names ack-healing as skipped and shows the row.
#   (P) R4 cache isolation: P1 with the cache on leaves the HEAD ingest-cache blob untouched; a cached run after it is
#       byte-identical to (A).
#   (Q) R5 the target-phase stop (ingest:2 cuts the target's full ingest): a degraded answer naming the target's stop.
#   (R) R7b a peak over the limit (peak:1) is disclosed on a full answer, rc and rows unchanged; R7c a selection the
#       changed files cannot answer refuses under a stop (exit 5), never an empty pass, and is never pre-empted by the
#       projection (the replay runs in full).
#   (S) R9 --quality-kinds=complexity reports no false finding-gone for a dead-code ack.
#   (T) S2 fits near the line: --max-memory at 2x the measured full peak answers in full, byte-identical (guard).
#   (V) R8 a degraded answer with rows and no gating row exits 6, not 2 and not 0.
#   --- fix round 1 (final review C1) ---
#   (W) --quality-kinds with a LOCAL kind under pressure: the kinds the caller left out are skipped_why="selector",
#       never memory cuts; memory's share (memory_skipped=, skipped_why="selector,memory") is exactly what kinds_next=
#       replays; no stderr line ends in an empty "skipped" list.
#
# Usage: bash test/qddegradecheck.sh [BIN]
set -u
ROOT="$( cd "$( dirname "$0" )/.." && pwd )"
. "$ROOT/test/lib/clean-env.sh"
BIN="${1:-${RIPWIRE_BIN:-$ROOT/build/ripwire}}"
[ "${BIN#/}" = "$BIN" ] && BIN="$ROOT/$BIN"
fail=0
ok(){ printf '  PASS  %s\n' "$*" || { fail=1; printf '  FAIL  could not write the PASS line for: %s\n' "$*"; }; return 0; }
no(){ printf '  FAIL  %s\n' "$*"; fail=1; }
[ -x "$BIN" ] || { echo "no ripwire binary at $BIN — build first"; exit 2; }
command -v git >/dev/null 2>&1 || { echo "  SKIP  qddegradecheck (git not available)"; exit 0; }
command -v python3 >/dev/null 2>&1 || { echo "  SKIP  qddegradecheck (python3 not available)"; exit 0; }
WORK="$( mktemp -d )"; trap 'rm -rf "$WORK"' EXIT
mkdir -p "$WORK/tmp"
echo "qddegradecheck: BIN=$BIN"

LOCAL_KINDS="api-surface complexity defect-shape error-masking nesting params placeholder verbosity"
LOCAL_CSV="$( echo "$LOCAL_KINDS" | tr ' ' ',' )"
WHOLE_KINDS="dead-code,duplication,new-clone-of-reused-helper"
ALL12="api-surface,complexity,dead-code,defect-shape,duplication,error-masking,nesting,new-clone-of-reused-helper,params,placeholder,short-horizon-churn,verbosity"

g(){ git -C "$1" -c user.name=t -c user.email=t@example.com "${@:2}"; }

# ── the fixture: a base commit and a target commit with one change per kind, beside UNCHANGED files ─────────────
# The unchanged files make the full tree larger than the changed set, so a crawl seam can cut the full ingest while the
# changed-files ingest stays under it (E).
mkfx(){
    local R="$1"; rm -rf "$R"; mkdir -p "$R/src" "$R/py"
    git -C "$R" init -q
    for k in 1 2 3 4 5 6; do
        printf 'int keep_%s( int v ) { return v + %s; }\n' "$k" "$k" >"$R/src/u$k.cpp"
        printf 'def keep_%s(v):\n    return v * %s\n' "$k" "$k" >"$R/py/u$k.py"
    done
    printf '#pragma once\ninline int api_scale( int a ) { return a * 2; }\n' >"$R/src/api.h"
    {
        printf '#include <cstdio>\n#include "api.h"\n'
        printf 'int helper( int a, int b ) { int s = 0; for( int i = 0; i < a; ++i ) { s += i * b; if( s > 100 ) { s -= b; } } return s + a - b; }\n'
        printf 'int use1( int x ) { return helper( x, 1 ); }\nint use2( int x ) { return helper( x, 2 ); }\nint use3( int x ) { return helper( x, 3 ); }\n'
        printf 'int legacy_used( int x ) { return x + 7; }\n'
        printf 'int wide( int a, int b, int c, int d, int e ) { return a + b + c + d + e; }\n'
        printf 'void risky() {}\nvoid handle() { try { risky(); } catch( ... ) { std::puts( "logged" ); } }\n'
        printf 'int grow( int x )\n{\n    if( x > 1 ) { return 1; }\n    return 0;\n}\n'
        printf 'int chatty( int x )\n{\n    int r = x;\n    r += 1;\n    r += 2;\n    return r;\n}\n'
        printf 'int drive( int x ) { return use1( x ) + use2( x ) + use3( x ) + legacy_used( x ) + wide( 1, 2, 3, 4, 5 ) + grow( x ) + api_scale( x ) + chatty( x ); }\n'
    } >"$R/src/core.cpp"
    printf 'def other():\n    return 1\n\ndef greet(name):\n    return "hello {}".format(name)\n' >"$R/py/mod.py"
    printf 'notes\n' >"$R/NOTES.txt"
    g "$R" add -A; g "$R" commit -qm base
}
# target: complexity+nesting (grow), verbosity (chatty), params (wide 5->6), api-surface (api_scale 1->2, a header),
# error-masking (an emptied catch), dead-code (legacy_used loses its caller), duplication + new-clone-of-reused-helper
# (helper, fan-in 3, copied), placeholder (a TODO, a NotImplementedError stub), defect-shape (a .format arity miss)
mktarget(){
    local R="$1"
    printf '#pragma once\ninline int api_scale( int a, int b ) { return a * b; }\n' >"$R/src/api.h"
    {
        printf '#include <cstdio>\n#include "api.h"\n'
        printf 'int helper( int a, int b ) { int s = 0; for( int i = 0; i < a; ++i ) { s += i * b; if( s > 100 ) { s -= b; } } return s + a - b; }\n'
        printf 'int use1( int x ) { return helper( x, 1 ); }\nint use2( int x ) { return helper( x, 2 ); }\nint use3( int x ) { return helper( x, 3 ); }\n'
        printf 'int legacy_used( int x ) { return x + 7; }\n'
        printf 'int wide( int a, int b, int c, int d, int e, int f ) { return a + b + c + d + e + f; }\n'
        printf 'void risky() {}\nvoid handle() { try { risky(); } catch( ... ) {} }\n'
        printf 'int grow( int x )\n{\n    int r = 0;\n    for( int i = 0; i < x; ++i ) {\n        if( i %% 2 ) {\n            while( r < i ) {\n'
        printf '                if( r %% 3 ) {\n                    for( int j = 0; j < 3; ++j ) {\n'
        printf '                        if( j && r ) { r += j; } else if( r > 9 ) { r -= 1; } else { r += 2; }\n                    }\n'
        printf '                } else if( r %% 5 ) { r += 3; } else { r += 4; }\n            }\n'
        printf '        } else if( i %% 7 ) { r -= 1; } else if( i %% 11 ) { r += 5; } else { r -= 2; }\n'
        printf '        if( r > 1000 && i > 3 ) { break; }\n        if( r < -1000 || i > 900 ) { continue; }\n    }\n    return r;\n}\n'
        printf 'int chatty( int x )\n{\n    int r = x;\n'
        for i in $( seq 1 69 ); do printf '    r += %s;\n' "$i"; done
        printf '    return r;\n}\n'
        printf 'int drive( int x ) { return use1( x ) + use2( x ) + use3( x ) + wide( 1, 2, 3, 4, 5, 6 ) + grow( x ) + api_scale( x, 2 ) + chatty( x ); }\n'
    } >"$R/src/core.cpp"
    printf 'int helper_copy( int a, int b ) { int s = 0; for( int i = 0; i < a; ++i ) { s += i * b; if( s > 100 ) { s -= b; } } return s + a - b; }\n' >"$R/src/copy.cpp"
    printf 'def other():\n    # TODO: wire this up\n    return 1\n\ndef greet(name):\n    return "hello {} {}".format(name)\n\ndef later():\n    raise NotImplementedError\n' >"$R/py/mod.py"
    g "$R" add -A; g "$R" commit -qm target
}

FX="$WORK/fx"; mkfx "$FX"; mktarget "$FX"
BASE="$( git -C "$FX" rev-parse HEAD~1 )"; TGT="$( git -C "$FX" rev-parse HEAD )"
# run [ENV=VAL ...] -- ARGS: stdout/stderr to $WORK/o, $WORK/e; rc in $RC
qd(){ ( cd "$FX" && env TMPDIR="$WORK/tmp" RIPWIRE_CACHE_STATS=1 "$@" >"$WORK/o" 2>"$WORK/e" ); RC=$?; }
# the same in another repo: qdin REPO [ENV=VAL ...] BIN ARGS
qdin(){ local R="$1"; shift; ( cd "$R" && env TMPDIR="$WORK/tmp" RIPWIRE_CACHE_STATS=1 "$@" >"$WORK/o" 2>"$WORK/e" ); RC=$?; }
# rows: every <r .../> and <sa .../> element on its own line, sorted (the union rule: rows compare as SORTED sets)
rows(){ python3 - "$1" "${2:-}" <<'PY'
import re, sys
doc = open(sys.argv[1], encoding="utf-8", errors="replace").read()
want = set(k for k in sys.argv[2].split(",") if k)
out = []
for m in re.finditer(r'<(r|sa) [^>]*/>', doc):
    k = re.search(r' kind="([^"]*)"', m.group(0))
    if k and (not want or k.group(1) in want):
        out.append(m.group(0))
print("\n".join(sorted(out)))
PY
}
# the root attribute NAMED $2 — space-led, so gating= never reads scoped-out-gating= (the greedy match takes the last)
attr(){ sed -n 's/.*<quality-delta [^>]* '"$2"'="\([^"]*\)".*/\1/p' "$1" | head -n 1; }
hasattr(){ grep -q "<quality-delta [^>]* $2=\"" "$1"; }
ingests(){ grep -c '^ripwire: cache-stats ' "$WORK/e"; }
memlines(){ grep -c '^ripwire: memory limit ' "$WORK/e"; }
isnum(){ case "$1" in ''|*[!0-9]*) return 1;; *) return 0;; esac; }
# R8: the exact exit code of a degraded answer — 2 when a row gates, else 6 (a partial answer with no gating row).
# Read only off a document whose gating= is a number; anything else is no exit code at all.
degrc(){ local gt; gt="$( attr "$1" gating )"; isnum "$gt" || { echo "none"; return; }; [ "$gt" -gt 0 ] && echo 2 || echo 6; }
validxml(){ python3 -c 'import sys,xml.dom.minidom as m; m.parse(sys.argv[1])' "$1" 2>/dev/null; }
fnv(){ python3 -c '
import sys
h = 0xcbf29ce484222325
for b in sys.argv[1].encode():
    h ^= b; h = (h * 0x100000001b3) & 0xFFFFFFFFFFFFFFFF
print("%016x" % h)' "$1"; }

# ── (A) the premise ───────────────────────────────────────────────────────────────────────────────────────────
qd "$BIN" . --quality-delta=HEAD~1..HEAD --no-cache; cp "$WORK/o" "$WORK/A.xml"; cp "$WORK/e" "$WORK/A.err"; ARC=$RC
missing=""
for k in api-surface complexity dead-code defect-shape duplication error-masking nesting new-clone-of-reused-helper params placeholder verbosity; do
    [ -n "$( rows "$WORK/A.xml" "$k" )" ] || missing="$missing $k"
done
if [ "$ARC" = 2 ] && [ -z "$missing" ]; then ok "(A) premise: the unpressured answer has a row of each of the 11 measured kinds (rc=2)"
else no "(A) premise: rc=$ARC, kinds with no row:$missing — every arm below compares against this answer, so it proves nothing"; fi
AGATE="$( attr "$WORK/A.xml" gating )"

# ── (B) P1 forced: the base fit, the target phase is projected past the limit ───────────────────────────────────
qd RIPWIRE_TEST_MEMGUARD=project:1 "$BIN" . --quality-delta=HEAD~1..HEAD --no-cache; cp "$WORK/o" "$WORK/B.xml"; cp "$WORK/e" "$WORK/B.err"; BRC=$RC; BING="$( ingests )"
bgate="$( attr "$WORK/B.xml" gating )"; need="$( attr "$WORK/B.xml" memory_need )"; needn="${need%M}"
wantrc="$( degrc "$WORK/B.xml" )"
bnext="$( attr "$WORK/B.xml" kinds_next )"
if [ -s "$WORK/B.xml" ] && validxml "$WORK/B.xml" \
   && [ "$( attr "$WORK/B.xml" kinds_skipped )" = "$WHOLE_KINDS" ] && [ "$( attr "$WORK/B.xml" skipped_why )" = memory ] \
   && [ "$( attr "$WORK/B.xml" ingest_scope )" = changed-files ] && hasattr "$WORK/B.xml" memory_limit \
   && isnum "$needn" && [ "$( attr "$WORK/B.xml" also_skipped )" = "config-warnings,stale-acks" ] && ! hasattr "$WORK/B.xml" stale \
   && ! hasattr "$WORK/B.xml" memory_stop && ! hasattr "$WORK/B.xml" register-macro-excluded && isnum "$bgate" && [ "$BRC" = "$wantrc" ]; then
    ok "(B) P1: a degraded answer (rc=$BRC, gating=$bgate) names kinds_skipped=$WHOLE_KINDS, the limit, need=${need}, also_skipped, no stale=/dead-code counts"
else
    no "(B) P1: rc=$BRC (want $wantrc) gating=$bgate kinds_skipped=$( attr "$WORK/B.xml" kinds_skipped ) why=$( attr "$WORK/B.xml" skipped_why ) scope=$( attr "$WORK/B.xml" ingest_scope ) need=$need stdout=$( wc -c <"$WORK/B.xml" | tr -d ' ' )B"
fi
# R7c: the replay's --max-memory is strictly above the projected need (in whole MiB) and clears the parser's 64M floor.
# CodeRabbit #413 (by-design change of this pin, rule 4): it is also never below the limit this run used — a replay under
# a lower limit than the one that degraded cannot answer in full — and above twice the ingest need (the parse line; on
# this fixture far under the limit, so the limit term decides). The old reading (above need, at least 64M) still holds.
blim="$( attr "$WORK/B.xml" memory_limit )"; blimn="${blim%M}"
replaymb=""; isnum "$needn" && isnum "$blimn" && { replaymb=$(( needn > blimn ? needn + 1 : blimn + 1 )); [ "$replaymb" -lt 64 ] && replaymb=64; }
if [ -n "$replaymb" ] && [ "$replaymb" -gt "$needn" ] && [ "$bnext" = "--quality-delta=$BASE..$TGT --quality-kinds=$WHOLE_KINDS --max-memory=${replaymb}M" ]; then
    ok "(B) kinds_next= replays exactly the skipped kinds at --max-memory=${replaymb}M (above need=${need} and the ${blim} limit, at least the 64M floor)"
else no "(B) kinds_next='$bnext' (want --max-memory=${replaymb:-?}M: above need=${need} and limit=${blim})"; fi
if [ "$( memlines )" = 1 ] && grep -q "^ripwire: memory limit .*dead-code, duplication, new-clone-of-reused-helper" "$WORK/B.err" && [ "$BING" = 3 ]; then
    ok "(B) one stderr line names the skipped kinds; three ingests (the base in full, then both commits' changed files)"
else no "(B) memory lines=$( memlines ) ingests=$BING stderr: $( grep '^ripwire: [^c]' "$WORK/B.err" | head -c 300 )"; fi

# ── (C) P1: LOCAL kinds equal the unpressured answer, kind by kind ─────────────────────────────────────────────
if [ -n "$( attr "$WORK/B.xml" kinds_skipped )" ]; then
    for k in $LOCAL_KINDS; do
        if [ "$( rows "$WORK/B.xml" "$k" )" = "$( rows "$WORK/A.xml" "$k" )" ] && [ -n "$( rows "$WORK/A.xml" "$k" )" ]; then ok "(C) P1 $k: rows identical to the unpressured answer"
        else no "(C) P1 $k: rows differ: $( diff <( rows "$WORK/A.xml" "$k" ) <( rows "$WORK/B.xml" "$k" ) | head -c 300 )"; fi
    done
    if [ -z "$( rows "$WORK/B.xml" "$WHOLE_KINDS" )" ]; then ok "(C) P1: no row of a skipped kind"; else no "(C) P1: a skipped kind has rows"; fi
    if [ "$( attr "$WORK/B.xml" api-new-surface )" = "$( attr "$WORK/A.xml" api-new-surface )" ]; then ok "(C) P1: api-new-surface= equal"; else no "(C) api-new-surface differs"; fi
else
    no "(C) P1: premise — (B) is not a degraded answer (no kinds_skipped=), so per-kind identity proves nothing"
fi

# ── (D) the replay ─────────────────────────────────────────────────────────────────────────────────────────────
if [ -n "$bnext" ]; then
    # shellcheck disable=SC2086
    qd "$BIN" . $bnext --no-cache; cp "$WORK/o" "$WORK/D.xml"; DRC=$RC
    dgate="$( attr "$WORK/D.xml" gating )"
    if [ "$( rows "$WORK/D.xml" )" = "$( rows "$WORK/A.xml" "$WHOLE_KINDS" )" ] && [ -n "$( rows "$WORK/D.xml" )" ]; then ok "(D) the replay's rows are exactly (A)'s skipped-kind rows"
    else no "(D) replay rc=$DRC rows differ: $( diff <( rows "$WORK/A.xml" "$WHOLE_KINDS" ) <( rows "$WORK/D.xml" ) | head -c 300 )"; fi
    if [ "$( { rows "$WORK/B.xml"; rows "$WORK/D.xml"; } | sort )" = "$( rows "$WORK/A.xml" )" ]; then ok "(D) union of the degraded answer and the replay = the unpressured answer (as sorted rows)"
    else no "(D) union differs from (A)"; fi
    if isnum "$bgate" && isnum "$dgate" && isnum "$AGATE" && [ $(( bgate + dgate )) = "$AGATE" ]; then ok "(D) gating= adds up: $bgate + $dgate = $AGATE"
    else no "(D) gating: B=$bgate D=$dgate A=$AGATE"; fi
    if [ "$( attr "$WORK/D.xml" skipped_why )" = selector ]; then ok "(D) the replay says its kinds were selected (skipped_why=selector)"; else no "(D) replay skipped_why=$( attr "$WORK/D.xml" skipped_why )"; fi
    # R7c: the replay's --max-memory clears the parser floor and is above the projection that degraded — it is accepted
    # (not exit 1) and answers in full (no ingest_scope=), with the exit code its own rows decide
    dwant=0; isnum "$dgate" && [ "$dgate" -gt 0 ] && dwant=2
    if [ "$DRC" = "$dwant" ] && [ -s "$WORK/D.xml" ] && ! hasattr "$WORK/D.xml" ingest_scope && ! hasattr "$WORK/D.xml" memory_stop; then
        ok "(D) the replay is accepted at its --max-memory and is not degraded again (rc=$DRC)"
    else no "(D) the replay rc=$DRC (want $dwant) or it degraded again: scope=$( attr "$WORK/D.xml" ingest_scope ) stderr: $( grep '^ripwire: [^c]' "$WORK/e" | head -c 300 )"; fi
else
    no "(D) premise: no kinds_next= to replay"
fi

# ── (E) P0: the guard cut the base commit's FULL ingest (crawl seam: the full tree has more entries than the changed set) ─
qd RIPWIRE_TEST_MEMGUARD=crawl:12 "$BIN" . --quality-delta=HEAD~1..HEAD --no-cache; cp "$WORK/o" "$WORK/E.xml"; cp "$WORK/e" "$WORK/E.err"; ERC=$RC
if [ -s "$WORK/E.xml" ] && [ "$( attr "$WORK/E.xml" kinds_skipped )" = "dead-code,defect-shape,duplication,new-clone-of-reused-helper" ] \
   && [ "$( attr "$WORK/E.xml" ingest_scope )" = changed-files ] && [ "$( ingests )" = 3 ] && [ "$ERC" = "$( degrc "$WORK/E.xml" )" ]; then
    ok "(E) P0: the cut full ingest is never scored; the changed files answer (rc=$ERC); defect-shape skipped (a changed C++ file)"
else
    no "(E) P0: rc=$ERC (want $( degrc "$WORK/E.xml" )) kinds_skipped=$( attr "$WORK/E.xml" kinds_skipped ) ingests=$( ingests ) stderr: $( grep '^ripwire: [^c]' "$WORK/E.err" | head -c 300 )"
fi
if [ -n "$( attr "$WORK/E.xml" kinds_skipped )" ]; then
    for k in api-surface complexity error-masking nesting params placeholder verbosity; do
        if [ "$( rows "$WORK/E.xml" "$k" )" = "$( rows "$WORK/A.xml" "$k" )" ]; then ok "(E) P0 $k: rows identical"; else no "(E) P0 $k: rows differ"; fi
    done
    # R7a: a soft stop does not show the need exceeds the limit — the stop is named, the need is not claimed
    if [ "$( attr "$WORK/E.xml" memory_stop )" = crawl ] && [ "$( attr "$WORK/E.xml" memory_need )" = unmeasured ]; then
        ok "(E) P0: memory_stop=\"crawl\" names the stop; memory_need=\"unmeasured\" (a crawl stop does not measure the need)"
    else no "(E) P0 memory_stop=$( attr "$WORK/E.xml" memory_stop ) memory_need=$( attr "$WORK/E.xml" memory_need )"; fi
else
    no "(E) P0: premise — not a degraded answer"
fi
# (E2) a Python-only change: no changed C++ file, so defect-shape runs on the changed files and equals the unpressured rows
FX2="$WORK/fx2"; mkfx "$FX2"
printf 'def other():\n    return 1\n\ndef greet(name):\n    return "hello {} {}".format(name)\n' >"$FX2/py/mod.py"; g "$FX2" add -A; g "$FX2" commit -qm py
( cd "$FX2" && TMPDIR="$WORK/tmp" "$BIN" . --quality-delta=HEAD~1..HEAD --no-cache >"$WORK/E2a.xml" 2>/dev/null )
( cd "$FX2" && TMPDIR="$WORK/tmp" RIPWIRE_TEST_MEMGUARD=crawl:12 "$BIN" . --quality-delta=HEAD~1..HEAD --no-cache >"$WORK/E2.xml" 2>/dev/null ); e2rc=$?
if [ "$( attr "$WORK/E2.xml" kinds_skipped )" = "$WHOLE_KINDS" ] && [ -n "$( rows "$WORK/E2a.xml" defect-shape )" ] \
   && [ "$( rows "$WORK/E2.xml" defect-shape )" = "$( rows "$WORK/E2a.xml" defect-shape )" ] && [ "$e2rc" = "$( degrc "$WORK/E2.xml" )" ]; then
    ok "(E2) P0, Python-only change: defect-shape runs on the changed files and its rows equal the unpressured ones (rc=$e2rc)"
else
    no "(E2) rc=$e2rc (want $( degrc "$WORK/E2.xml" )) kinds_skipped=$( attr "$WORK/E2.xml" kinds_skipped ) unpressured defect rows=$( rows "$WORK/E2a.xml" defect-shape | grep -c . )"
fi

# (E3) langfacts-fold (train 29): which changed file extensions need the base's whole macro set. Only a C++-family file does
# (.cc / .hpp / .h read as C++): a changed C file (.c) or Objective-C file (.m) leaves defect-shape local under P0.
# Pinned as the answer today; src/verbs_quality.h reads it from the language-facts row (defectShapeNeedsMacroSet).
for ext in c m h cc hpp; do
    FX3="$WORK/fx3$ext"; rm -rf "$FX3"; mkdir -p "$FX3/src" "$FX3/py"; git -C "$FX3" init -q
    for k in 1 2 3 4 5 6; do
        printf 'int keep_%s( int v ) { return v + %s; }\n' "$k" "$k" >"$FX3/src/u$k.cpp"
        printf 'def keep_%s(v):\n    return v * %s\n' "$k" "$k" >"$FX3/py/u$k.py"
    done
    printf 'int one( int v ) { return v; }\n' >"$FX3/src/x.$ext"; g "$FX3" add -A; g "$FX3" commit -qm base
    printf 'int one( int v ) { return v + 1; }\n' >"$FX3/src/x.$ext"; g "$FX3" add -A; g "$FX3" commit -qm target
    ( cd "$FX3" && TMPDIR="$WORK/tmp" RIPWIRE_TEST_MEMGUARD=crawl:12 "$BIN" . --quality-delta=HEAD~1..HEAD --no-cache >"$WORK/E3.xml" 2>/dev/null )
    want="$WHOLE_KINDS"; why="defect-shape stays local"
    case "$ext" in c|m) ;; *) want="dead-code,defect-shape,duplication,new-clone-of-reused-helper"; why="defect-shape needs the whole macro set" ;; esac
    if [ "$( attr "$WORK/E3.xml" kinds_skipped )" = "$want" ]; then
        ok "(E3) P0, a changed .$ext file: kinds_skipped=\"$want\" ($why)"
    else no "(E3) P0, a changed .$ext file: kinds_skipped=\"$( attr "$WORK/E3.xml" kinds_skipped )\", want \"$want\""; fi
done

# ── (F) even the changed files do not fit ──────────────────────────────────────────────────────────────────────
qd RIPWIRE_TEST_MEMGUARD=hard:1 "$BIN" . --quality-delta=HEAD~1..HEAD --no-cache; FRC=$RC
if [ "$FRC" = 5 ] && [ ! -s "$WORK/o" ] && [ "$( grep -c '^ripwire: [^c]' "$WORK/e" )" = 1 ] \
   && grep -q '^ripwire: memory limit reached during the ingest of the base commit (limit .*changed files' "$WORK/e" \
   && grep -q 'after releasing the full tree, so the changed files were not tried' "$WORK/e" && ! grep '^ripwire: ' "$WORK/e" | grep -q 'did not fit'; then
    ok "(F) still over the limit after releasing the full tree: exit 5, nothing on stdout, one line naming the phase and that the changed files were not tried"
else
    no "(F) rc=$FRC stdout=$( wc -c <"$WORK/o" | tr -d ' ' )B stderr: $( grep '^ripwire: [^c]' "$WORK/e" | head -c 300 )"
fi

# ── (G) near misses under project:1 ────────────────────────────────────────────────────────────────────────────
nm(){ # $1 label, $2 repo; compares LOCAL rows with the unpressured run and requires the degraded header and the exact rc
    # S5: new-symbol= counts the rows of the kinds that RAN, so the degraded count equals the unpressured run's LOCAL rows
    # carrying origin="new-symbol" (a rename makes every moved symbol new in both modes); api-new-surface= equal outright.
    local L="$1" R="$2"
    ( cd "$R" && TMPDIR="$WORK/tmp" "$BIN" . --quality-delta=HEAD~1..HEAD --no-cache >"$WORK/nmA.xml" 2>/dev/null )
    ( cd "$R" && TMPDIR="$WORK/tmp" RIPWIRE_TEST_MEMGUARD=project:1 "$BIN" . --quality-delta=HEAD~1..HEAD --no-cache >"$WORK/nmB.xml" 2>"$WORK/nmB.err" ); local rc=$?
    local localnew; localnew="$( rows "$WORK/nmA.xml" "$LOCAL_CSV" | grep -c 'origin="new-symbol"' )"
    if [ "$( attr "$WORK/nmB.xml" kinds_skipped )" = "$WHOLE_KINDS" ] && [ "$( rows "$WORK/nmB.xml" "$LOCAL_CSV" )" = "$( rows "$WORK/nmA.xml" "$LOCAL_CSV" )" ] \
       && ! grep -q 'could not materialize' "$WORK/nmB.err" && [ "$rc" = "$( degrc "$WORK/nmB.xml" )" ] \
       && [ "$( attr "$WORK/nmB.xml" new-symbol )" = "$localnew" ] \
       && [ "$( attr "$WORK/nmB.xml" api-new-surface )" = "$( attr "$WORK/nmA.xml" api-new-surface )" ]; then
        ok "(G) $L: degraded answer (rc=$rc), LOCAL rows, new-symbol=$localnew (the LOCAL new-symbol rows) and api-new-surface= equal the unpressured run"
    else
        no "(G) $L: rc=$rc (want $( degrc "$WORK/nmB.xml" )) kinds_skipped=$( attr "$WORK/nmB.xml" kinds_skipped ) new-symbol want $localnew got $( attr "$WORK/nmB.xml" new-symbol ) stderr: $( head -c 300 "$WORK/nmB.err" )"
    fi
}
FE="$WORK/fe"; mkfx "$FE"; g "$FE" commit -q --allow-empty -m empty; nm "empty diff" "$FE"
FR="$WORK/fr"; mkfx "$FR"; g "$FR" mv py/u1.py py/u1_moved.py; g "$FR" commit -qm rename; nm "rename-only diff" "$FR"
FN="$WORK/fn"; mkfx "$FN"; printf 'more notes\n' >>"$FN/NOTES.txt"; g "$FN" add -A; g "$FN" commit -qm notes; nm "non-code-only diff" "$FN"
( cd "$FX" && TMPDIR="$WORK/tmp" "$BIN" . --quality-delta=HEAD..HEAD --no-cache >"$WORK/AA.xml" 2>"$WORK/AA.err" ); r1=$?
( cd "$FX" && TMPDIR="$WORK/tmp" RIPWIRE_TEST_MEMGUARD=project:1 "$BIN" . --quality-delta=HEAD..HEAD --no-cache >"$WORK/AAp.xml" 2>"$WORK/AAp.err" ); r2=$?
if [ "$r1" = "$r2" ] && cmp -s "$WORK/AA.xml" "$WORK/AAp.xml" && [ -s "$WORK/AA.xml" ]; then ok "(G) A..A: one tree, nothing to project — answered in full, byte-identical (rc=$r1)"
else no "(G) A..A: rc $r1 vs $r2 or the answers differ"; fi

# ── (H) --quality-kinds ───────────────────────────────────────────────────────────────────────────────────────
qd "$BIN" . --quality-delta=HEAD~1..HEAD --quality-kinds=complexity,dupe --no-cache
if [ "$RC" = 1 ] && [ ! -s "$WORK/o" ] && grep -q "dupe" "$WORK/e" && grep -q "new-clone-of-reused-helper" "$WORK/e" && grep -q "short-horizon-churn" "$WORK/e"; then
    ok "(H) an unknown kind is refused (exit 1) naming it and the 12 kinds"
else no "(H) unknown kind: rc=$RC stderr: $( head -c 300 "$WORK/e" )"; fi
qd "$BIN" . --quality-delta=HEAD~1..HEAD --quality-kinds=complexity --quality-ack --no-cache
if [ "$RC" = 1 ] && [ ! -e "$FX/.ripwire_quality_acks" ] && grep -q -- '--quality-kinds.*--quality-ack\|--quality-ack.*--quality-kinds' "$WORK/e" && ! grep -q 'unknown flag' "$WORK/e"; then
    ok "(H) --quality-kinds beside --quality-ack is refused (exit 1) naming both flags, no ledger written"
else no "(H) with --quality-ack rc=$RC stderr: $( head -c 300 "$WORK/e" )"; fi
# S3: the selector is the range form's (the bare form's MCP twin has no such field yet) — refused by name on the bare form
qd "$BIN" . --quality-delta --quality-kinds=complexity --no-cache
if [ "$RC" = 1 ] && [ ! -s "$WORK/o" ] && grep -q -- '--quality-kinds' "$WORK/e" && grep -q 'A\.\.B' "$WORK/e" && ! grep -q 'unknown flag' "$WORK/e"; then
    ok "(H) --quality-kinds on the bare (working-tree) form is refused (exit 1) naming the range form"
else no "(H) bare form: rc=$RC stderr: $( head -c 300 "$WORK/e" )"; fi
for k in api-surface complexity dead-code defect-shape duplication error-masking nesting new-clone-of-reused-helper params placeholder verbosity; do
    qd "$BIN" . --quality-delta=HEAD~1..HEAD "--quality-kinds=$k" --no-cache
    if [ "$( rows "$WORK/o" )" = "$( rows "$WORK/A.xml" "$k" )" ] && [ -n "$( rows "$WORK/o" )" ] && [ "$( attr "$WORK/o" skipped_why )" = selector ]; then ok "(H) --quality-kinds=$k: exactly (A)'s $k rows"
    else no "(H) --quality-kinds=$k: rc=$RC rows=$( rows "$WORK/o" | grep -c . ) want $( rows "$WORK/A.xml" "$k" | grep -c . ) why=$( attr "$WORK/o" skipped_why )"; fi
done
qd "$BIN" . --quality-delta=HEAD~1..HEAD "--quality-kinds=$ALL12" --no-cache
if [ "$RC" = "$ARC" ] && cmp -s "$WORK/o" "$WORK/A.xml"; then ok "(H) all 12 named: byte-identical to no selector"; else no "(H) all 12 named: rc=$RC or output differs from (A)"; fi

# ── (I) --quality-ack: the projection never pre-empts it (C2); a real stop refuses it ───────────────────────────
# Each run acks in its own copy of the fixture, so the ledgers compare. ackl: the ledger's ack lines (no header).
ackl(){ grep '^ack ' "$1/.ripwire_quality_acks" 2>/dev/null; }
FIA="$WORK/fia"; FIP="$WORK/fip"; FIS="$WORK/fis"; cp -R "$FX" "$FIA"; cp -R "$FX" "$FIP"; cp -R "$FX" "$FIS"
qdin "$FIA" "$BIN" . --quality-delta=HEAD~1..HEAD --quality-ack --no-cache; iarc=$RC
qdin "$FIP" RIPWIRE_TEST_MEMGUARD=project:1 "$BIN" . --quality-delta=HEAD~1..HEAD --quality-ack --no-cache
if [ -n "$( ackl "$FIA" )" ] && [ "$RC" = "$iarc" ] && [ "$( ackl "$FIP" )" = "$( ackl "$FIA" )" ] && [ "$( memlines )" = 0 ]; then
    ok "(I) --quality-ack under project:1 is not pre-empted: it acks in full, the same $( ackl "$FIA" | grep -c . ) ack line(s) as an unpressured ack (rc=$RC)"
else no "(I) project:1 --quality-ack: rc=$RC (unpressured $iarc) acks=$( ackl "$FIP" | grep -c . ) want $( ackl "$FIA" | grep -c . ) stderr: $( grep '^ripwire: [^c]' "$WORK/e" | head -c 300 )"; fi
qdin "$FIS" RIPWIRE_TEST_MEMGUARD=crawl:12 "$BIN" . --quality-delta=HEAD~1..HEAD --quality-ack --no-cache
if [ "$RC" = 5 ] && [ ! -e "$FIS/.ripwire_quality_acks" ] && [ "$( grep -c '^ripwire: [^c]' "$WORK/e" )" = 1 ] && grep -q 'nothing was acked' "$WORK/e" && [ ! -s "$WORK/o" ]; then
    ok "(I) --quality-ack under a real stop (crawl:12) refuses (exit 5, one line), the ledger untouched"
else no "(I) crawl:12 --quality-ack: rc=$RC ledger=$( [ -e "$FIS/.ripwire_quality_acks" ] && echo written || echo absent ) stderr: $( grep '^ripwire: [^c]' "$WORK/e" | head -c 300 )"; fi

# ── (J) --scope naming an unchanged file under pressure ───────────────────────────────────────────────────────
qd "$BIN" . --quality-delta=HEAD~1..HEAD --scope=py/u2.py --no-cache; jA=$RC; cp "$WORK/o" "$WORK/JA.xml"
qd RIPWIRE_TEST_MEMGUARD=project:1 "$BIN" . --quality-delta=HEAD~1..HEAD --scope=py/u2.py --no-cache
if [ "$RC" != 1 ] && ! grep -q 'names nothing\|matches no indexed path' "$WORK/e" && [ -n "$( attr "$WORK/o" kinds_skipped )" ] \
   && [ "$RC" = "$( degrc "$WORK/o" )" ] && [ "$( rows "$WORK/o" )" = "$( rows "$WORK/JA.xml" "$LOCAL_CSV" )" ]; then
    ok "(J) --scope on an unchanged file under pressure: answered (rc=$RC, unpressured rc=$jA), not refused as naming nothing"
else no "(J) rc=$RC (want $( degrc "$WORK/o" ), unpressured $jA) stderr: $( grep '^ripwire: [^c]' "$WORK/e" | head -c 300 )"; fi
# the near miss: a scope naming NO path of the target commit is still refused under pressure (a typo is not a measurement)
qd RIPWIRE_TEST_MEMGUARD=project:1 "$BIN" . --quality-delta=HEAD~1..HEAD --scope=py/nosuch.py --no-cache
if [ "$RC" = 1 ] && [ ! -s "$WORK/o" ] && grep -q 'matches no indexed path' "$WORK/e"; then ok "(J) a scope naming no path of the target commit is still refused under pressure (exit 1)"
else no "(J) --scope=py/nosuch.py under pressure: rc=$RC stderr: $( grep '^ripwire: [^c]' "$WORK/e" | head -c 300 )"; fi

# ── (K) legend and JSON ───────────────────────────────────────────────────────────────────────────────────────
qd RIPWIRE_TEST_MEMGUARD=project:1 "$BIN" . --quality-delta=HEAD~1..HEAD --legend=full --no-cache
missing=""
for a in kinds_skipped= skipped_why= ingest_scope= memory_need= also_skipped= kinds_next=; do
    sed -n 's/^\(<!--.*-->\).*/\1/p' "$WORK/o" | grep -q -- "$a" || missing="$missing $a"
done
if [ -z "$missing" ] && validxml "$WORK/o"; then ok "(K) --legend=full defines every new attribute and parses as XML"
else no "(K) legend lacks:$missing (or invalid XML)"; fi
qd RIPWIRE_TEST_MEMGUARD=crawl:12 "$BIN" . --quality-delta=HEAD~1..HEAD --legend=full --no-cache
if sed -n 's/^\(<!--.*-->\).*/\1/p' "$WORK/o" | grep -q -- 'memory_stop=' && validxml "$WORK/o"; then ok "(K) --legend=full over a stop defines memory_stop= and parses as XML"
else no "(K) the P0 legend lacks memory_stop= (or invalid XML)"; fi
qd RIPWIRE_TEST_MEMGUARD=project:1 "$BIN" . --quality-delta=HEAD~1..HEAD --json --no-cache
if python3 - "$WORK/o" <<'PY'
import json, sys
d = json.load(open(sys.argv[1]))
assert d["kinds_skipped"] == ["dead-code", "duplication", "new-clone-of-reused-helper"], d.get("kinds_skipped")
assert d["skipped_why"] == "memory" and d["ingest_scope"] == "changed-files"
assert d["also_skipped"] == ["config-warnings", "stale-acks"] and "stale" not in d and "register-macro-excluded" not in d
assert d["kinds_next"].startswith("--quality-delta=") and "memory_need" in d and "memory_limit" in d
PY
then ok "(K) --json carries the twins (kinds_skipped list, skipped_why, ingest_scope, also_skipped, kinds_next, memory_*)"
else no "(K) --json twins missing or wrong: $( head -c 300 "$WORK/o" )"; fi
qd "$BIN" . --quality-delta=HEAD~1..HEAD --json --no-cache
if [ "$RC" = "$ARC" ] && [ -s "$WORK/o" ] && ! grep -q '"kinds_skipped"\|"ingest_scope"\|"kinds_next"\|"also_skipped"\|"memory_' "$WORK/o"; then
    ok "(K) an unpressured --json carries none of the degraded keys"
else no "(K) unpressured --json: rc=$RC (want $ARC), empty, or it carries a degraded-only key"; fi

# ── (L) guard: the projection seam past the run's one projection reading changes nothing ───────────────────────
qd RIPWIRE_TEST_MEMGUARD=project:2 "$BIN" . --quality-delta=HEAD~1..HEAD --no-cache
if [ "$RC" = "$ARC" ] && cmp -s "$WORK/o" "$WORK/A.xml" && [ "$( grep -v '^ripwire: cache-stats ' "$WORK/e" )" = "$( grep -v '^ripwire: cache-stats ' "$WORK/A.err" )" ]; then
    ok "(L) project:2 (past the one projection reading) is byte-identical to no seam (rc=$RC)"
else no "(L) project:2 rc=$RC (want $ARC) or the answer differs"; fi

# ══ round 2 — the gates review's R1-R9 ═══════════════════════════════════════════════════════════════════════════

# ── (M) R1: a new defect site whose text also sits in an UNCHANGED file ─────────────────────────────────────────
# defect-shape counts a site as new by its REPO-WIDE excess. Pairing a full base with a changed-files target would net the
# new copy against the unchanged one and lose a gating row; both sides' changed files cancel the unchanged copy exactly.
FM="$WORK/fm"; mkfx "$FM"
printf 'def old():\n    return "x {} {}".format(1)\n' >"$FM/py/old.py"; g "$FM" add -A; g "$FM" commit -qm old
printf 'def other():\n    return 1\n\ndef greet(name):\n    return "hello {}".format(name)\n\ndef dup():\n    return "x {} {}".format(1)\n' >"$FM/py/mod.py"
g "$FM" add -A; g "$FM" commit -qm dup
qdin "$FM" "$BIN" . --quality-delta=HEAD~1..HEAD --no-cache; cp "$WORK/o" "$WORK/MA.xml"; mrc=$RC
if [ "$mrc" = 2 ] && rows "$WORK/MA.xml" defect-shape | grep -q 'gating="1"'; then
    for seam in project:1 crawl:12; do
        qdin "$FM" RIPWIRE_TEST_MEMGUARD=$seam "$BIN" . --quality-delta=HEAD~1..HEAD --no-cache
        if [ -n "$( attr "$WORK/o" kinds_skipped )" ] && [ "$RC" = 2 ] && [ "$( rows "$WORK/o" defect-shape )" = "$( rows "$WORK/MA.xml" defect-shape )" ]; then
            ok "(M) $seam: the new site's gating defect-shape row survives beside an unchanged copy of its text (rc=2)"
        else no "(M) $seam: rc=$RC (want 2) kinds_skipped=$( attr "$WORK/o" kinds_skipped ) defect rows: $( rows "$WORK/o" defect-shape | head -c 200 )"; fi
    done
else
    no "(M) premise: the unpressured answer has no gating defect-shape row (rc=$mrc)"
fi

# ── (N) R2: paths git diff does not list but an archive or a crawl treats differently ──────────────────────────
refused_by(){ # $1 label, $2 repo, $3 the word the one line must name
    qdin "$2" RIPWIRE_TEST_MEMGUARD=project:1 "$BIN" . --quality-delta=HEAD~1..HEAD --no-cache
    if [ "$RC" = 5 ] && [ ! -s "$WORK/o" ] && [ "$( grep -c '^ripwire: [^c]' "$WORK/e" )" = 1 ] && grep -q "^ripwire: .*$3" "$WORK/e" && grep -q 'changed files' "$WORK/e"; then
        ok "(N) $1: the changed files cannot stand in for the trees — refused by name (exit 5, one line naming $3)"
    else no "(N) $1: rc=$RC stdout=$( wc -c <"$WORK/o" | tr -d ' ' )B stderr: $( grep '^ripwire: [^c]' "$WORK/e" | head -c 300 )"; fi
}
same_as_full(){ # $1 label, $2 repo: the degraded LOCAL rows equal the unpressured ones
    ( cd "$2" && TMPDIR="$WORK/tmp" "$BIN" . --quality-delta=HEAD~1..HEAD --no-cache >"$WORK/nfA.xml" 2>/dev/null )
    qdin "$2" RIPWIRE_TEST_MEMGUARD=project:1 "$BIN" . --quality-delta=HEAD~1..HEAD --no-cache
    if [ -n "$( attr "$WORK/o" kinds_skipped )" ] && [ "$RC" = "$( degrc "$WORK/o" )" ] && [ -n "$( rows "$WORK/nfA.xml" "$LOCAL_CSV" )" ] \
       && [ "$( rows "$WORK/o" "$LOCAL_CSV" )" = "$( rows "$WORK/nfA.xml" "$LOCAL_CSV" )" ]; then
        ok "(N) $1: degraded (rc=$RC), LOCAL rows equal the unpressured run"
    else no "(N) $1: rc=$RC kinds_skipped=$( attr "$WORK/o" kinds_skipped ) diff: $( diff <( rows "$WORK/nfA.xml" "$LOCAL_CSV" ) <( rows "$WORK/o" "$LOCAL_CSV" ) | head -c 300 ) stderr: $( grep '^ripwire: [^c]' "$WORK/e" | head -c 200 )"; fi
}
# an UNCHANGED symlink to a CHANGED file: the crawl follows it, so the full answer rows the link's path too
FS="$WORK/fs"; mkfx "$FS"; ln -s py/mod.py "$FS/link.py"; g "$FS" add -A; g "$FS" commit -qm link
printf 'def other():\n    # TODO: link\n    return 1\n' >"$FS/py/mod.py"; g "$FS" add -A; g "$FS" commit -qm todo
refused_by "an unchanged symlink to a changed file" "$FS" "symlink"
# an export-ignore FLIP: the target deletes .gitattributes, so gen/x.py (unchanged) appears in the target archive
FA="$WORK/fa"; mkfx "$FA"; mkdir -p "$FA/gen"; printf 'gen/** export-ignore\n' >"$FA/.gitattributes"
printf 'def gen():\n    # TODO: generated\n    return 1\n' >"$FA/gen/x.py"; g "$FA" add -A; g "$FA" commit -qm attrs
g "$FA" rm -q .gitattributes; printf 'def other():\n    # TODO: flip\n    return 1\n' >"$FA/py/mod.py"; g "$FA" add -A; g "$FA" commit -qm flip
refused_by "an export-ignore flip (.gitattributes deleted)" "$FA" ".gitattributes"
# export-subst rewrites archived bytes of files git calls unchanged
FU="$WORK/fu"; mkfx "$FU"; printf 'py/*.py export-subst\n' >"$FU/.gitattributes"; g "$FU" add -A; g "$FU" commit -qm subst
printf 'def other():\n    # TODO: subst\n    return 1\n' >"$FU/py/mod.py"; g "$FU" add -A; g "$FU" commit -qm todo
refused_by "an export-subst attribute" "$FU" "export-subst"
# the near miss: an UNCHANGED export-ignore attribute excludes the same paths from both sides — no refusal
FI="$WORK/fi"; mkfx "$FI"; mkdir -p "$FI/gen"; printf 'gen/** export-ignore\n' >"$FI/.gitattributes"
printf 'def gen():\n    # TODO: generated\n    return 1\n' >"$FI/gen/x.py"; g "$FI" add -A; g "$FI" commit -qm attrs
printf 'def gen():\n    # TODO: generated\n    # TODO: again\n    return 1\n' >"$FI/gen/x.py"
printf 'def other():\n    # TODO: kept\n    return 1\n' >"$FI/py/mod.py"; g "$FI" add -A; g "$FI" commit -qm todo
same_as_full "an unchanged export-ignore attribute (a changed export-ignored file)" "$FI"
# a directory the crawl prunes because it holds CMakeCache.txt (unchanged), with a changed file inside it
FC="$WORK/fc"; mkfx "$FC"; mkdir -p "$FC/bld"; printf 'CMAKE_BUILD_TYPE:STRING=Debug\n' >"$FC/bld/CMakeCache.txt"
printf 'def built():\n    return 1\n' >"$FC/bld/x.py"; g "$FC" add -A; g "$FC" commit -qm bld
printf 'def built():\n    # TODO: pruned\n    return 1\n' >"$FC/bld/x.py"
printf 'def other():\n    # TODO: seen\n    return 1\n' >"$FC/py/mod.py"; g "$FC" add -A; g "$FC" commit -qm todo
same_as_full "a changed file in a CMakeCache.txt-pruned directory" "$FC"
if grep -q 'bld/x.py' "$WORK/nfA.xml" || grep -q 'bld/x.py' "$WORK/o"; then no "(N) CMakeCache premise/result: a row names the pruned bld/x.py"
else ok "(N) CMakeCache: neither answer rows the pruned bld/x.py"; fi
# the export-attribute read FAILED (CodeRabbit, #413): a git whose `grep` exits 128 leaves the attribute question unanswered,
# and "could not read" is not "no attribute" — the degraded path refuses (exit 1, the git-could-not-list line), never a
# changed-files answer. The shim fails only `grep`; everything else reaches the real git.
GSHIM="$WORK/gshim"; mkdir -p "$GSHIM"; REALGIT="$( command -v git )"
printf '#!/bin/sh\nfor a in "$@"; do [ "$a" = grep ] && exit 128; done\nexec "%s" "$@"\n' "$REALGIT" >"$GSHIM/git"; chmod +x "$GSHIM/git"
qdin "$FU" PATH="$GSHIM:$PATH" RIPWIRE_TEST_MEMGUARD=project:1 "$BIN" . --quality-delta=HEAD~1..HEAD --no-cache
if [ "$RC" = 1 ] && [ ! -s "$WORK/o" ] && grep -q '^ripwire: .*git could not list the changed files' "$WORK/e"; then
    ok "(N) the export-attribute grep failed (exit 128): refused, never read as 'no attribute' (exit 1, nothing on stdout)"
else no "(N) a failed export-attribute grep: rc=$RC (want 1) stdout=$( wc -c <"$WORK/o" | tr -d ' ' )B stderr: $( grep '^ripwire: [^c]' "$WORK/e" | head -c 300 )"; fi
# its near miss, no shim: a pair with no .gitattributes at all, where git grep exits 1 (no hit) — still a clean answer
qdin "$FC" RIPWIRE_TEST_MEMGUARD=project:1 "$BIN" . --quality-delta=HEAD~1..HEAD --no-cache
if [ -n "$( attr "$WORK/o" kinds_skipped )" ] && [ "$RC" = "$( degrc "$WORK/o" )" ]; then ok "(N) control: exit 1 from git grep (no hit) still answers degraded (rc=$RC)"
else no "(N) control: rc=$RC kinds_skipped=$( attr "$WORK/o" kinds_skipped ) stderr: $( grep '^ripwire: [^c]' "$WORK/e" | head -c 200 )"; fi

# ── (O) R3: ack identity healing reads tree-wide uniqueness, which the changed files cannot see ─────────────────
# Legacy-scheme ack key of a scope-less name = fnv1a64( bare name ) (quality.h addSchemeAliases: canonicalId degrades to the
# bare name). The full run re-keys it only when ONE file defines the name; two definitions poison it.
mkacks(){ printf '# ripwire quality acks v1\nack placeholder %s 5 legacy-scheme row\n' "$( fnv dupname )" >"$1/.ripwire_quality_acks"; }
# the finding rows (<r>) of a kind — stale-ack <sa> rows are a whole-answer fact the degraded answer names as skipped
frows(){ rows "$1" "$2" | grep '^<r ' || true; }
FO="$WORK/fo"; mkfx "$FO"; printf 'def dupname():\n    return 1\n' >"$FO/py/a.py"; printf 'def dupname():\n    return 2\n' >"$FO/py/b.py"
g "$FO" add -A; g "$FO" commit -qm two; printf 'def dupname():\n    # TODO: one\n    return 1\n' >"$FO/py/a.py"; g "$FO" add -A; g "$FO" commit -qm todo; mkacks "$FO"
qdin "$FO" "$BIN" . --quality-delta=HEAD~1..HEAD --no-cache; cp "$WORK/o" "$WORK/OA.xml"
qdin "$FO" RIPWIRE_TEST_MEMGUARD=project:1 "$BIN" . --quality-delta=HEAD~1..HEAD --no-cache
if [ -n "$( frows "$WORK/OA.xml" placeholder )" ] && [ "$( frows "$WORK/o" placeholder )" = "$( frows "$WORK/OA.xml" placeholder )" ] \
   && [ "$( attr "$WORK/o" acked )" = "$( attr "$WORK/OA.xml" acked )" ] && case ",$( attr "$WORK/o" also_skipped )," in *,ack-healing,*) true;; *) false;; esac; then
    ok "(O) a legacy ack on a name two files define (one changed): the same placeholder rows and acked= as the full run; ack-healing named as skipped"
else no "(O) two definitions: rows full=$( frows "$WORK/OA.xml" placeholder | grep -c . ) degraded=$( frows "$WORK/o" placeholder | grep -c . ) acked $( attr "$WORK/OA.xml" acked )/$( attr "$WORK/o" acked ) also_skipped=$( attr "$WORK/o" also_skipped )"; fi
FO1="$WORK/fo1"; mkfx "$FO1"; printf 'def dupname():\n    return 1\n' >"$FO1/py/a.py"
g "$FO1" add -A; g "$FO1" commit -qm one; printf 'def dupname():\n    # TODO: one\n    return 1\n' >"$FO1/py/a.py"; g "$FO1" add -A; g "$FO1" commit -qm todo; mkacks "$FO1"
qdin "$FO1" "$BIN" . --quality-delta=HEAD~1..HEAD --no-cache; cp "$WORK/o" "$WORK/O1A.xml"
qdin "$FO1" RIPWIRE_TEST_MEMGUARD=project:1 "$BIN" . --quality-delta=HEAD~1..HEAD --no-cache
if [ "$( attr "$WORK/O1A.xml" acked )" = 1 ] && [ -z "$( frows "$WORK/O1A.xml" placeholder )" ] && [ -n "$( frows "$WORK/o" placeholder )" ] \
   && case ",$( attr "$WORK/o" also_skipped )," in *,ack-healing,*) true;; *) false;; esac && [ "$RC" = "$( degrc "$WORK/o" )" ]; then
    ok "(O) a legacy ack on a name one file defines: the full run re-keys it; the degraded run names ack-healing as skipped and shows the row (rc=$RC)"
else no "(O) one definition: full acked=$( attr "$WORK/O1A.xml" acked ) rows full=$( frows "$WORK/O1A.xml" placeholder | grep -c . ) degraded=$( frows "$WORK/o" placeholder | grep -c . ) also_skipped=$( attr "$WORK/o" also_skipped ) rc=$RC"; fi
# no ledger: nothing to heal, so ack-healing is never named
if [ "$( attr "$WORK/B.xml" also_skipped )" = "config-warnings,stale-acks" ]; then ok "(O) with no ledger, ack-healing is not named (nothing to heal)"
else no "(O) no ledger: also_skipped=$( attr "$WORK/B.xml" also_skipped )"; fi

# ── (P) R4: a changed-files ingest never reads or writes an ingest cache ───────────────────────────────────────
# The target is HEAD, whose full ingest uses the HEAD ingest-cache family. Run with the cache ON.
PT="$WORK/ptmp"; mkdir -p "$PT"
blobsum(){ find "$PT" -type f -name '*.bin' -exec cksum {} + 2>/dev/null | sort; }
( cd "$FX" && TMPDIR="$PT" "$BIN" . --quality-delta=HEAD~1..HEAD >"$WORK/P1.xml" 2>/dev/null ); p1=$?
s1="$( blobsum )"
# QD-PAIR-BASE-CACHE: P1 cached the base side by sha; a hit has no base ingest to project from, so project:1 would never
# trip. Drop that one blob so P2 scores the base again (and rewrites it whole, deterministically: s1 = s2 still holds).
nqb="$( find "$PT" -type f -name 'ripwire-qbase-*.bin' | grep -c . )"
find "$PT" -type f -name 'ripwire-qbase-*.bin' -exec rm -f {} +
( cd "$FX" && TMPDIR="$PT" RIPWIRE_TEST_MEMGUARD=project:1 "$BIN" . --quality-delta=HEAD~1..HEAD >"$WORK/P2.xml" 2>/dev/null ); p2=$?
s2="$( blobsum )"
( cd "$FX" && TMPDIR="$PT" "$BIN" . --quality-delta=HEAD~1..HEAD >"$WORK/P3.xml" 2>/dev/null ); p3=$?
if [ -n "$s1" ] && [ "$nqb" = 1 ] && [ "$p1" = "$ARC" ] && cmp -s "$WORK/P1.xml" "$WORK/A.xml"; then
    if [ -n "$( attr "$WORK/P2.xml" kinds_skipped )" ] && [ "$p2" = "$( degrc "$WORK/P2.xml" )" ] && [ "$s1" = "$s2" ] && [ "$p3" = "$ARC" ] && cmp -s "$WORK/P3.xml" "$WORK/A.xml"; then
        ok "(P) P1 with the cache on: degraded (rc=$p2), every cache blob unchanged, and the next cached run is byte-identical to (A)"
    else no "(P) p2=$p2 degraded=$( attr "$WORK/P2.xml" ingest_scope ) blobs_unchanged=$( [ "$s1" = "$s2" ] && echo yes || echo no ) p3=$p3 identical=$( cmp -s "$WORK/P3.xml" "$WORK/A.xml" && echo yes || echo no )"; fi
else
    no "(P) premise: the cached unpressured run wrote no blob or differs from (A) (rc=$p1, blobs: $( echo "$s1" | grep -c . ), qbase: $nqb)"
fi

# ── (Q) R5: the target phase stops after the projection said it fits ───────────────────────────────────────────
# ingest:2 cuts the process's 2nd ingest (the target's full tree) at its first crawl entry: that ingest parses nothing and
# so prints no cache-stats line — 3 lines (base in full, both changed-file sets), and the stderr line names the target.
qd RIPWIRE_TEST_MEMGUARD=ingest:2 "$BIN" . --quality-delta=HEAD~1..HEAD --no-cache; cp "$WORK/o" "$WORK/Q.xml"
if [ "$( attr "$WORK/Q.xml" kinds_skipped )" = "$WHOLE_KINDS" ] && [ "$( attr "$WORK/Q.xml" memory_stop )" = crawl ] && [ "$( attr "$WORK/Q.xml" memory_need )" = unmeasured ] \
   && [ "$( ingests )" = 3 ] && grep -q '^ripwire: memory limit .*stopped the crawl of the target commit' "$WORK/e" \
   && [ "$RC" = "$( degrc "$WORK/Q.xml" )" ] && [ "$( rows "$WORK/Q.xml" "$LOCAL_CSV" )" = "$( rows "$WORK/A.xml" "$LOCAL_CSV" )" ]; then
    ok "(Q) a stop in the target's full ingest falls to the changed files (rc=$RC), LOCAL rows equal (A); defect-shape kept (the base's macro set was read)"
else no "(Q) rc=$RC kinds_skipped=$( attr "$WORK/Q.xml" kinds_skipped ) stop=$( attr "$WORK/Q.xml" memory_stop ) ingests=$( ingests ) stderr: $( grep '^ripwire: [^c]' "$WORK/e" | head -c 300 )"; fi

# ── (R) R7: a peak over the cap is said; a replay with nothing it can run refuses ──────────────────────────────
qd RIPWIRE_TEST_MEMGUARD=peak:1 "$BIN" . --quality-delta=HEAD~1..HEAD --no-cache
pk="$( attr "$WORK/o" memory_peak )"
if [ "$RC" = "$ARC" ] && isnum "${pk%M}" && [ "$( rows "$WORK/o" )" = "$( rows "$WORK/A.xml" )" ] && ! hasattr "$WORK/o" ingest_scope \
   && [ "$( grep -c '^ripwire: memory peak ' "$WORK/e" )" = 1 ] && ! hasattr "$WORK/A.xml" memory_peak; then
    ok "(R) a full answer whose peak went over the limit says so (memory_peak=\"$pk\" + one stderr line); rows and rc unchanged"
else no "(R) peak:1 rc=$RC (want $ARC) memory_peak=$pk stderr: $( grep '^ripwire: [^c]' "$WORK/e" | head -c 300 )"; fi
qd RIPWIRE_TEST_MEMGUARD=peak:1 "$BIN" . --quality-delta=HEAD~1..HEAD --legend=full --no-cache
if sed -n 's/^\(<!--.*-->\).*/\1/p' "$WORK/o" | grep -q -- 'memory_peak=' && validxml "$WORK/o"; then ok "(R) --legend=full defines memory_peak= when it rides, and parses as XML"
else no "(R) the legend lacks memory_peak= (or invalid XML)"; fi
# CodeRabbit #413: the peak sentence speaks for a changed-files answer too, never "complete" unconditionally. A degraded
# answer whose peak also went over is not reachable through one seam, so the wording is pinned here and the stderr
# twin keeps "the answer is complete" on the full answer above.
if sed -n 's/^\(<!--.*-->\).*/\1/p' "$WORK/o" | grep -q -- 'memory_peak=[^.]*(complete, or the changed-files answer ingest_scope= names)'; then
    ok "(R) the memory_peak= legend covers both a complete and a changed-files answer"
else no "(R) the memory_peak= legend still reads as complete-only"; fi
qd RIPWIRE_TEST_MEMGUARD=peak:1 "$BIN" . --quality-delta=HEAD~1..HEAD --no-cache
grep -q '^ripwire: memory peak .*: the answer is complete, but' "$WORK/e" \
    && ok "(R) a full answer's peak line still says the answer is complete" \
    || no "(R) the full answer's peak line: $( grep '^ripwire: memory peak' "$WORK/e" | head -c 200 )"
# A selection the changed files could not answer (whole-tree kinds, with or without defect-shape) is never pre-empted by
# the projection — it is the replay kinds_next= names, and degrading it could only refuse: it runs in full. A real stop
# still refuses it, by name, and so does a defect-shape-only selection whose changed files cannot decide defect-shape
# (found on this repository's own HEAD~20..HEAD: the replay degraded again and answered EMPTY with exit 6).
qd RIPWIRE_TEST_MEMGUARD=crawl:12 "$BIN" . --quality-delta=HEAD~1..HEAD "--quality-kinds=$WHOLE_KINDS" --no-cache
if [ "$RC" = 5 ] && [ ! -s "$WORK/o" ] && [ "$( grep -c '^ripwire: [^c]' "$WORK/e" )" = 1 ] && grep -q 'whole-tree' "$WORK/e"; then
    ok "(R) a whole-tree-only selection under a stop refuses (exit 5, one line naming why) — never an empty pass"
else no "(R) whole-tree-only selection under a stop: rc=$RC stdout=$( wc -c <"$WORK/o" | tr -d ' ' )B stderr: $( grep '^ripwire: [^c]' "$WORK/e" | head -c 300 )"; fi
qd RIPWIRE_TEST_MEMGUARD=crawl:12 "$BIN" . --quality-delta=HEAD~1..HEAD --quality-kinds=defect-shape --no-cache
if [ "$RC" = 5 ] && [ ! -s "$WORK/o" ] && [ "$( grep -c '^ripwire: [^c]' "$WORK/e" )" = 1 ] && grep -q 'defect-shape' "$WORK/e"; then
    ok "(R) a defect-shape-only selection the changed files cannot decide (a changed C++ file, no whole macro set) refuses (exit 5) — never an empty pass"
else no "(R) defect-shape-only under a stop: rc=$RC stdout=$( wc -c <"$WORK/o" | tr -d ' ' )B stderr: $( grep '^ripwire: [^c]' "$WORK/e" | head -c 300 )"; fi
REPLAY_KINDS="dead-code,defect-shape,duplication,new-clone-of-reused-helper"
qd RIPWIRE_TEST_MEMGUARD=project:1 "$BIN" . --quality-delta=HEAD~1..HEAD "--quality-kinds=$REPLAY_KINDS" --no-cache
if [ -s "$WORK/o" ] && ! hasattr "$WORK/o" ingest_scope && [ "$( rows "$WORK/o" )" = "$( rows "$WORK/A.xml" "$REPLAY_KINDS" )" ] && [ -n "$( rows "$WORK/o" )" ] \
   && { [ "$RC" = 0 ] || [ "$RC" = 2 ]; }; then
    ok "(R) the replay's selection is not pre-empted by the projection (project:1): answered in full, exactly (A)'s rows of those kinds (rc=$RC)"
else no "(R) replay selection under project:1: rc=$RC scope=$( attr "$WORK/o" ingest_scope ) rows=$( rows "$WORK/o" | grep -c . ) want $( rows "$WORK/A.xml" "$REPLAY_KINDS" | grep -c . )"; fi

# ── (S) R9: stale acks under --quality-kinds are checked for the selected kinds only ───────────────────────────
FSS="$WORK/fss"; cp -R "$FX" "$FSS"
( cd "$FSS" && TMPDIR="$WORK/tmp" "$BIN" . --quality-delta=HEAD~1..HEAD --quality-ack --ack-only=dead-code --no-cache >/dev/null 2>&1 )
if grep -q '^ack dead-code' "$FSS/.ripwire_quality_acks" 2>/dev/null; then
    qdin "$FSS" "$BIN" . --quality-delta=HEAD~1..HEAD --quality-kinds=complexity --show-stale --no-cache
    if { [ "$RC" = 0 ] || [ "$RC" = 2 ]; } && [ -s "$WORK/o" ] && [ -n "$( rows "$WORK/o" complexity )" ] && ! grep -q '<sa [^>]*kind="dead-code' "$WORK/o"; then
        ok "(S) --quality-kinds=complexity: a dead-code ack is not reported finding-gone (stale acks checked for the selected kinds only; rc=$RC)"
    else no "(S) rc=$RC sa rows: $( grep -o '<sa [^>]*>' "$WORK/o" | head -c 300 )"; fi
else
    no "(S) premise: --quality-ack --ack-only=dead-code wrote no dead-code ack"
fi

# ── (T) S2: a limit near (above) the measured peak answers in full ─────────────────────────────────────────────
peak_mb=""
if /usr/bin/time -l true >/dev/null 2>&1; then
    ( cd "$FX" && TMPDIR="$WORK/tmp" /usr/bin/time -l "$BIN" . --quality-delta=HEAD~1..HEAD --no-cache >/dev/null 2>"$WORK/t.err" )
    peak_mb="$( awk '/peak memory footprint/ { printf "%d", $1 / 1048576 + 1 }' "$WORK/t.err" )"
    [ -n "$peak_mb" ] || peak_mb="$( awk '/maximum resident set size/ { printf "%d", $1 / 1048576 + 1 }' "$WORK/t.err" )"
elif /usr/bin/time -v true >/dev/null 2>&1; then
    ( cd "$FX" && TMPDIR="$WORK/tmp" /usr/bin/time -v "$BIN" . --quality-delta=HEAD~1..HEAD --no-cache >/dev/null 2>"$WORK/t.err" )
    peak_mb="$( awk -F: '/Maximum resident set size/ { printf "%d", $2 / 1024 + 1 }' "$WORK/t.err" )"
fi
if isnum "$peak_mb"; then
    lim=$(( peak_mb * 2 )); [ "$lim" -lt 64 ] && lim=64
    qd "$BIN" . --quality-delta=HEAD~1..HEAD "--max-memory=${lim}M" --no-cache
    if [ "$RC" = "$ARC" ] && cmp -s "$WORK/o" "$WORK/A.xml"; then ok "(T) --max-memory=${lim}M (2x the measured ${peak_mb}M peak): answered in full, byte-identical to (A)"
    else no "(T) --max-memory=${lim}M rc=$RC scope=$( attr "$WORK/o" ingest_scope ) — the projection degraded a run that fits"; fi
else
    printf '  SKIP  (T) no /usr/bin/time that reports a peak (-l or -v) — the near-the-line arm needs a measured peak\n'
fi

# ── (V) R8: a degraded answer with rows and no gating row exits 6 ──────────────────────────────────────────────
FV="$WORK/fv"; mkfx "$FV"; printf 'def other():\n    # TODO: later\n    return 1\n' >"$FV/py/mod.py"; g "$FV" add -A; g "$FV" commit -qm todo
qdin "$FV" RIPWIRE_TEST_MEMGUARD=project:1 "$BIN" . --quality-delta=HEAD~1..HEAD --no-cache
if [ "$RC" = 6 ] && [ "$( attr "$WORK/o" gating )" = 0 ] && [ -n "$( rows "$WORK/o" placeholder )" ] && [ -n "$( attr "$WORK/o" kinds_skipped )" ]; then
    ok "(V) a degraded answer with a placeholder row and gating=0 exits 6 (partial, nothing gating), stdout non-empty"
else no "(V) rc=$RC gating=$( attr "$WORK/o" gating ) rows=$( rows "$WORK/o" | grep -c . )"; fi

# ── (W) C1: a selector's exclusions are not memory cuts ─────────────────────────────────────────────────────────
others(){ echo "$ALL12" | tr ',' '\n' | grep -vx -e "$1" -e "${2:-}" | paste -sd, -; }   # the 12 kinds without $1 (and $2)
emptyskip(){ grep -q 'skipped *$' "$WORK/e"; }
qd RIPWIRE_TEST_MEMGUARD=project:1 "$BIN" . --quality-delta=HEAD~1..HEAD --quality-kinds=complexity --no-cache
if [ "$( attr "$WORK/o" ingest_scope )" = changed-files ] && [ "$( attr "$WORK/o" kinds_skipped )" = "$( others complexity )" ] \
   && [ "$( attr "$WORK/o" skipped_why )" = selector ] && ! hasattr "$WORK/o" memory_skipped && ! hasattr "$WORK/o" kinds_next \
   && [ "$( rows "$WORK/o" )" = "$( rows "$WORK/A.xml" complexity )" ] && [ "$RC" = "$( degrc "$WORK/o" )" ] \
   && ! emptyskip && [ "$( memlines )" = 1 ] && grep -q '^ripwire: memory limit .*every selected kind ran' "$WORK/e"; then
    ok "(W) project:1 --quality-kinds=complexity: the 11 left out are skipped_why=selector, no memory share, no kinds_next=, stderr says every selected kind ran (rc=$RC)"
else no "(W) complexity: rc=$RC why=$( attr "$WORK/o" skipped_why ) skipped=$( attr "$WORK/o" kinds_skipped ) next=$( attr "$WORK/o" kinds_next ) stderr: $( grep '^ripwire: [^c]' "$WORK/e" | od -c | tail -n 3 | head -c 300 )"; fi
qd RIPWIRE_TEST_MEMGUARD=project:1 "$BIN" . --quality-delta=HEAD~1..HEAD --quality-kinds=complexity,dead-code --no-cache
wnext="$( attr "$WORK/o" kinds_next )"
if [ "$( attr "$WORK/o" ingest_scope )" = changed-files ] && [ "$( attr "$WORK/o" kinds_skipped )" = "$( others complexity )" ] \
   && [ "$( attr "$WORK/o" skipped_why )" = selector,memory ] && [ "$( attr "$WORK/o" memory_skipped )" = dead-code ] \
   && case "$wnext" in "--quality-delta=$BASE..$TGT --quality-kinds=dead-code --max-memory="*M) true;; *) false;; esac \
   && [ "$( rows "$WORK/o" )" = "$( rows "$WORK/A.xml" complexity )" ] && ! emptyskip \
   && grep -q '^ripwire: memory limit .*; skipped dead-code — run them with ' "$WORK/e"; then
    ok "(W) project:1 --quality-kinds=complexity,dead-code: skipped_why=selector,memory, memory_skipped=dead-code = exactly what kinds_next= replays"
else no "(W) complexity,dead-code: why=$( attr "$WORK/o" skipped_why ) memory_skipped=$( attr "$WORK/o" memory_skipped ) next='$wnext' stderr: $( grep '^ripwire: [^c]' "$WORK/e" | head -c 300 )"; fi
qd RIPWIRE_TEST_MEMGUARD=project:1 "$BIN" . --quality-delta=HEAD~1..HEAD --quality-kinds=complexity,dead-code --legend=full --no-cache
if sed -n 's/^\(<!--.*-->\).*/\1/p' "$WORK/o" | grep -q 'memory_skipped=' && validxml "$WORK/o"; then ok "(W) --legend=full defines memory_skipped= when it rides, and parses as XML"
else no "(W) the legend lacks memory_skipped= (or invalid XML)"; fi
qd RIPWIRE_TEST_MEMGUARD=project:1 "$BIN" . --quality-delta=HEAD~1..HEAD --quality-kinds=complexity --legend=full --no-cache
if [ -s "$WORK/o" ] && ! sed -n 's/^\(<!--.*-->\).*/\1/p' "$WORK/o" | grep -q 'memory_skipped=' && validxml "$WORK/o"; then ok "(W) present-only: no memory_skipped= sentence when only the selector skipped"
else no "(W) the selector-only legend defines memory_skipped= (or invalid XML / no output)"; fi
# (no --json arm: --json is refused beside --quality-kinds, so memory_skipped= — which rides only beside a selector — has
# no JSON surface yet; the JSON twin is written by the same kindsDisclosure as the XML)

[ "$fail" = 0 ] && echo "qddegradecheck: ALL PASS" || echo "qddegradecheck: FAIL"
exit "$fail"
