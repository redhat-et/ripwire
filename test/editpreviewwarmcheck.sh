#!/usr/bin/env bash
# editpreviewwarmcheck.sh — the PRE-APPLY preview on a WARM index costs ONE file's parse, and answers exactly
# what the cold preview and the post-apply --edit-check answer.
#
#   ripwire <dir> --edit-check=SYM --edit-payload=FILE --dry-run
#
# WHY THIS GATE EXISTS. The preview splices the payload over SYM's definition span, re-parses that ONE file
# and re-derives the call graph over the merged model (src/editpreview.h). It used to parse the edited file
# TWICE: once with the payload spliced in (the answer's parse) and once AS IT IS ON DISK, only to read the
# file's parse-error count before the edit — a number the warm index already holds (FileHealth.errNodes,
# measured by the run's own ingest and carried by the content cache and the warm snapshot). On this repo's
# 1.2 MB src/graph.h that second parse was a measured share of a 15 s preview whose plain --edit-check
# answers in 0.25 s. Agents run the preview before every edit, so its cost is paid per edit.
#
# THE ARMS
#   (I) identity — three fixtures, one per answer class: a contract change with no broken caller (chg11, a
#       wider overload added), no change (pre01, body reordered), and a NEW caller break (chg01, a third
#       parameter the caller in app.cpp does not pass). For each: the warm preview is byte-identical to the
#       cold preview (--no-cache, no warm snapshot: every file parsed by the run's own ingest, nothing served
#       from a cache), and, after the same normalisations test/editpreviewcheck.sh registers, equal to the
#       post-apply document.
#       Each case also asserts its own class, so the three are not three copies of one answer.
#   (C) the counter — RIPWIRE_CACHE_STATS on a warm preview: the run's own ingest reparses 0 files (the index is
#       warm — presence guard) and the files parsed across the whole run sum to exactly 1. Red on the base
#       (2: the on-disk parse beside the spliced one). The preview's own RIPWIRE_STATS line
#       (`[stats] edit-preview parses=N error_baseline=index|parse`) must agree with the pool's count.
#   (K) the refusal still has its baseline — a payload that raises the file's parse errors still refuses on the
#       warm path, so reading the count off the index did not turn the delta into "no baseline, accept all".
#   (W) the preview writes nothing to the warm index — a plain run after it still reparses 0 files.
#   (H) after a one-file COMMIT, the first preview's HEAD-baseline ingest reparses 1 file, not the tree, and the
#       answer is byte-identical to a fully cold run. This is where the measured 15 s actually went: the HEAD
#       ingest cache is named by sha, so every commit used to start the baseline from nothing. Red on the base
#       (reparsed= every committed file).
#
# Operates entirely on private temp git repos and a private TMPDIR (the cache ladder's first rung); never touches
# the real repo or the user's caches. Needs git.
# Usage:  bash test/editpreviewwarmcheck.sh [BIN]   |   RIPWIRE_BIN=asan/ripwire bash test/editpreviewwarmcheck.sh

set -u
ROOT="$( cd "$( dirname "$0" )/.." && pwd )"
. "$ROOT/test/lib/clean-env.sh"
BIN="${1:-${RIPWIRE_BIN:-$ROOT/build/ripwire}}"
[ "${BIN#/}" = "$BIN" ] && BIN="$ROOT/$BIN"
FIX="$ROOT/test/editpreviewfix"
fail=0
ok(){ printf '  PASS  %s\n' "$*" || { fail=1; printf '  FAIL  could not write the PASS line for: %s\n' "$*"; }; return 0; }
no(){ printf '  FAIL  %s\n' "$*"; fail=1; }

[ -x "$BIN" ] || { echo "no ripwire binary at $BIN — build first"; exit 2; }
command -v git >/dev/null 2>&1 || { echo "git required"; exit 2; }
[ -f "$FIX/cases.tsv" ] || { echo "missing fixture table $FIX/cases.tsv"; exit 2; }

WORK="$( mktemp -d )"; trap 'rm -rf "$WORK"' EXIT
mkdir -p "$WORK/tmp"
export TMPDIR="$WORK/tmp"      # the cache ladder's first rung (quality.h cacheDirLadder): every cache this gate warms is private
unset RIPWIRE_NO_WARMSNAP RIPWIRE_STATS RIPWIRE_CACHE_STATS
echo "editpreviewwarmcheck: BIN=$BIN"

mkcorpus(){
    mkdir -p "$1"
    cp "$FIX"/corpus/* "$1/"
    ( cd "$1" && git init -q && git config user.email t@t && git config user.name t \
      && git add -A && git commit -qm init ) >/dev/null 2>&1
}
BASE="$WORK/base"; mkcorpus "$BASE"

# test/editpreviewcheck.sh's five normalisations, verbatim (see that file for why each exists, and why no other)
norm(){ printf '%s' "$1" | perl -0pe 's/<overwrite [^>]*><!\[CDATA\[.*?\]\]><\/overwrite>//s' | sed -e 's/<!--.*-->//' -e 's/ at="[^"]*"//g' -e 's/ preview="1"//g' -e 's/ est_tokens="[0-9]*"//g'; }
statusOf(){ printf '%s' "$1" | sed -e 's/<!--.*-->//' | grep -oE 'status="[a-z-]+"' | head -1; }

warmrun(){ ( cd "$BASE" && "$BIN" . --edit-check=lib.h:scale "$@" >/dev/null 2>&1 ); }
preview(){ # $1 selector  $2 payload  [...] extra flags — the WARM preview (the index and the warm snapshot this gate warmed)
    local sel="$1" pay="$2"; shift 2
    ( cd "$BASE" && "$BIN" . --edit-check="$sel" --edit-payload="$pay" --dry-run --legend=full --limit=40 "$@" 2>/dev/null )
}
coldpreview(){ # the COLD preview: no content cache, no warm snapshot, and a FRESH cache ladder, so the HEAD baseline is built
               # from nothing too — every file of both trees parsed by this run
    local sel="$1" pay="$2" t="$WORK/cold.$RANDOM"; shift 2
    mkdir -p "$t"
    ( cd "$BASE" && TMPDIR="$t" RIPWIRE_NO_WARMSNAP=1 "$BIN" . --edit-check="$sel" --edit-payload="$pay" --dry-run --no-cache --legend=full --limit=40 "$@" 2>/dev/null )
    rm -rf "$t"
}
applied(){ # $1 name  $2 file  $3 payload → the POST-apply --edit-check document, on a fresh corpus (test/editpreviewcheck.sh applied())
    local w="$WORK/apply.$RANDOM"
    mkcorpus "$w"
    ( cd "$w" && "$BIN" . --replace-symbol-body="$1" --edit-target-file="$2" --edit-payload="$3" ) >/dev/null 2>&1
    ( cd "$w" && "$BIN" . --edit-check="$2:$1" --no-cache --legend=full --limit=40 2>/dev/null )
    rm -rf "$w"
}
sumReparsed(){ grep -oE 'cache-stats reparsed=[0-9]+' "$1" | sed 's/.*=//' | awk '{ s += $1 } END { print s + 0 }'; }

# warm the index: the first run parses and writes the content cache + the warm snapshot + the HEAD qsnap; the second
# proves it is warm (reparsed=0) before any arm below relies on it
warmrun; warmrun
( cd "$BASE" && RIPWIRE_CACHE_STATS=1 "$BIN" . --edit-check=lib.h:scale >/dev/null 2>"$WORK/w.err" )
if grep -q 'cache-stats reparsed=0 ' "$WORK/w.err"; then
    ok "the index is warm before the preview runs (a plain run reparses 0 files)"
else
    no "the index is not warm after two runs — every arm below would measure a cold preview"; sed -n 1,3p "$WORK/w.err"
fi

# ── (I) identity, one fixture per answer class ───────────────────────────────────────────────────────
icase(){ # $1 id  $2 name  $3 file  $4 expected-class (change|unchanged|break)
    local id="$1" name="$2" file="$3" want="$4" P="$FIX/payloads/$1.txt"
    local warm cold post
    warm="$( preview "$file:$name" "$P" )"
    cold="$( coldpreview "$file:$name" "$P" )"
    post="$( applied "$name" "$file" "$P" )"
    if [ -z "$warm" ] || ! printf '%s' "$warm" | grep -q '<edit-check '; then
        no "(I) $id: the warm preview is not an <edit-check> document (${#warm} bytes) — the arm proved nothing"
        return
    fi
    [ "$warm" = "$cold" ] && ok "(I) $id: warm preview is byte-identical to the cold preview (${#warm} bytes)" \
                          || { no "(I) $id: warm preview != cold preview"; printf '        warm: %s\n        cold: %s\n' "$( printf '%s' "$warm" | sed 's/<!--.*-->//' | cut -c1-300 )" "$( printf '%s' "$cold" | sed 's/<!--.*-->//' | cut -c1-300 )"; }
    [ "$( norm "$warm" )" = "$( norm "$post" )" ] && ok "(I) $id: warm preview == the post-apply --edit-check (registered normalisations)" \
                                                  || { no "(I) $id: warm preview != post-apply"; printf '        pre : %s\n        post: %s\n' "$( norm "$warm" | cut -c1-300 )" "$( norm "$post" | cut -c1-300 )"; }
    local st inc
    st="$( statusOf "$warm" )"
    inc="$( printf '%s' "$warm" | sed -e 's/<!--.*-->//' | grep -oE '<edit-check [^>]*' | grep -oE ' incompatible="[0-9]+"' | head -1 )"
    case "$want" in
        change)    { [ "$st" != 'status="unchanged"' ] && [ "$inc" = ' incompatible="0"' ]; } \
                       && ok "(I) $id: class holds — a contract change ($st) with no broken caller" \
                       || no "(I) $id: expected a contract change with incompatible=\"0\", got $st$inc" ;;
        unchanged) [ "$st" = 'status="unchanged"' ] && ok "(I) $id: class holds — unchanged" \
                       || no "(I) $id: expected status=\"unchanged\", got $st" ;;
        break)     { [ -n "$inc" ] && [ "$inc" != ' incompatible="0"' ]; } \
                       && ok "(I) $id: class holds — a new caller break ($st$inc)" \
                       || no "(I) $id: expected a flagged caller, got $st$inc" ;;
    esac
}
icase chg11 scale lib.h change
icase pre01 scale lib.h unchanged
icase chg01 scale lib.h break

# ── (C) the counter: one file parsed on a warm preview ───────────────────────────────────────────────
( cd "$BASE" && RIPWIRE_CACHE_STATS=1 "$BIN" . --edit-check=lib.h:scale --edit-payload="$FIX/payloads/chg01.txt" --dry-run \
    >"$WORK/c.out" 2>"$WORK/c.err" ); rc=$?
lines="$( grep -c 'cache-stats reparsed=' "$WORK/c.err" )"
mainWarm="$( grep -m1 -oE 'cache-stats reparsed=[0-9]+ reused=[0-9]+ files=[0-9]+' "$WORK/c.err" )"
parsed="$( sumReparsed "$WORK/c.err" )"
if [ "$rc" != 0 ] || ! grep -q '<edit-check ' "$WORK/c.out"; then
    no "(C) the counted preview did not answer (rc=$rc) — the counter proved nothing"
elif [ "$lines" -lt 2 ]; then
    no "(C) presence guard: $lines cache-stats line(s) — the run's own ingest AND the preview's parse must each report one"
else
    case "$mainWarm" in
        "cache-stats reparsed=0 "*) ok "(C) presence guard: the run's own ingest was warm ($mainWarm)";;
        *) no "(C) presence guard: the run's own ingest was not warm ($mainWarm)";;
    esac
    [ "$parsed" = 1 ] && ok "(C) a warm preview parses exactly 1 file across the whole run ($lines ingest(s) reported)" \
                      || no "(C) a warm preview parsed $parsed files across the run (want 1: the spliced file only)"
fi
# the preview's own RIPWIRE_STATS line must say the same thing the parse pool's counters say, and name where the
# before-edit error count came from (the index on a warm run)
( cd "$BASE" && RIPWIRE_STATS=1 RIPWIRE_CACHE_STATS=1 "$BIN" . --edit-check=lib.h:scale --edit-payload="$FIX/payloads/chg01.txt" --dry-run \
    >/dev/null 2>"$WORK/s.err" )
statLine="$( grep -m1 -oE '\[stats\] edit-preview parses=[0-9]+ error_baseline=[a-z]+' "$WORK/s.err" )"
pooled="$( sumReparsed "$WORK/s.err" )"
case "$statLine" in
    "[stats] edit-preview parses=1 error_baseline=index")
        [ "$pooled" = 1 ] && ok "(C) RIPWIRE_STATS: $statLine, and the parse pool counted $pooled" \
                          || no "(C) RIPWIRE_STATS says parses=1 but the parse pool counted $pooled — the two counters disagree" ;;
    "") no "(C) RIPWIRE_STATS printed no edit-preview line (parse pool counted $pooled)" ;;
    *)  no "(C) RIPWIRE_STATS: $statLine (want parses=1 error_baseline=index; parse pool counted $pooled)" ;;
esac

# ── (K) the parse-error refusal keeps its baseline on the warm path ──────────────────────────────────
( cd "$BASE" && "$BIN" . --edit-check=lib.h:scale --edit-payload="$FIX/payloads/inv02.txt" --dry-run >"$WORK/k.out" 2>"$WORK/k.err" ); rc=$?
{ [ "$rc" != 0 ] && [ ! -s "$WORK/k.out" ] && grep -q 'parse errors from' "$WORK/k.err"; } \
    && ok "(K) a payload that raises the file's parse errors still refuses on the warm path ($( grep -oE 'from [0-9]+ to [0-9]+' "$WORK/k.err" ))" \
    || { no "(K) the warm preview did not refuse a parse-breaking payload (rc=$rc)"; head -2 "$WORK/k.err"; }

# ── (W) the preview leaves the warm index as it found it ─────────────────────────────────────────────
( cd "$BASE" && RIPWIRE_CACHE_STATS=1 "$BIN" . --edit-check=lib.h:scale >/dev/null 2>"$WORK/w2.err" )
grep -q 'cache-stats reparsed=0 ' "$WORK/w2.err" \
    && ok "(W) a plain run after the previews still reparses 0 files" \
    || { no "(W) the previews disturbed the warm index"; sed -n 1,3p "$WORK/w2.err"; }

# ── (H) the first preview after a COMMIT reparses what the commit changed, not the HEAD tree ───────────
# The HEAD baseline's ingest cache is named by HEAD sha; a new sha used to start from nothing and reparse every committed
# file (quality.h seedHeadSnapCache). One file changes in this commit, so the HEAD ingest must reparse exactly that one.
nfiles="$( cd "$BASE" && git ls-files | wc -l | tr -d ' ' )"
perl -0pi -e 's/\}\s*\z/}\n\nint trimTwice( int a, int b )\n{\n    return trim( trim( a, b ), b );\n}\n/' "$BASE/lib.cpp"
( cd "$BASE" && git commit -qam "one-file commit" ) >/dev/null 2>&1
( cd "$BASE" && RIPWIRE_CACHE_STATS=1 "$BIN" . --edit-check=lib.h:scale --edit-payload="$FIX/payloads/chg01.txt" --dry-run --legend=full --limit=40 \
    >"$WORK/h.out" 2>"$WORK/h.err" ); rc=$?
headLine="$( grep -oE "cache-stats reparsed=[0-9]+ reused=[0-9]+ files=$nfiles " "$WORK/h.err" | sed -n 2p )"
if [ "$rc" != 0 ] || ! grep -q '<edit-check ' "$WORK/h.out"; then
    no "(H) the post-commit preview did not answer (rc=$rc)"
elif [ -z "$headLine" ]; then
    no "(H) presence guard: no HEAD-tree ingest line (files=$nfiles) after the commit — the HEAD baseline was not rebuilt, so the arm proved nothing"; sed -n 1,6p "$WORK/h.err"
else
    case "$headLine" in
        "cache-stats reparsed=1 "*) ok "(H) the first preview after a one-file commit reparses 1 HEAD file ($headLine)";;
        *) no "(H) the first preview after a one-file commit rebuilt the HEAD tree from nothing ($headLine; want reparsed=1)";;
    esac
fi
cold="$( coldpreview lib.h:scale "$FIX/payloads/chg01.txt" )"
[ -n "$cold" ] && [ "$( cat "$WORK/h.out" )" = "$cold" ] && ok "(H) the post-commit preview is byte-identical to a fully cold one" \
    || no "(H) the post-commit preview differs from a fully cold one"

if [ "$fail" = 0 ]; then echo "editpreviewwarmcheck: PASS"; exit 0; fi
echo "editpreviewwarmcheck: FAIL"; exit 1
