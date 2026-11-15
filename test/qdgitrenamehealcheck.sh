#!/usr/bin/env bash
# qdgitrenamehealcheck.sh — gate for QD-GIT-RENAME-HEAL (quality.h healIdentity, cloneGroupHeldAcrossRenames): a file rename git
# recorded keeps every symbol's identity in --quality-delta in a repo WITHOUT a .ripwire_quality_acks ledger, including functions
# whose body has an identical twin (which the body-identity rule, ContentMoves, refuses to pair).
#
# Measured problem (QD-RENAME-IDENTITY follow-up, envoy probe 2026-11-14): healIdentity returned before reading git's rename record
# whenever the ledger was empty, so a whole-file `git mv` healed nothing; the moved functions read as new code (new-symbol rows)
# and a clone group with a moved member read as new duplication (gating), on main and on the rename lane alike.
#
# Per language (Python, TypeScript, Go, C++, Rust), in git-backed temp repos with no ack ledger. The baseline: the main file holds
# methods Box.alpha and Box.beta (identical twins) and the over-bar big_fn; a second file holds Other.gamma, a third twin. Each arm moves the main file
# with `git mv`; a failing arm names every row it saw.
#   P. PREMISES, counted, each FAILS on zero: no ledger file; the baseline holds one clone group naming alpha, beta and gamma.
#   M. the move alone (staged, working-tree form): no row, exit 0, and renames= on the root (the git record was the route).
#   R. the move committed, --quality-delta=HEAD~1..HEAD (the ref-pair form reads the record over the range): no row, exit 0.
#   N. the move plus a neutral edit (a local renamed in big_fn, so no body is unchanged to pair by content): no row, exit 0.
#   W. the move plus a real worsening of big_fn: its complexity row still prints.
#   C. the move plus a new fourth twin in the moved file: the duplication row still prints and gates (exit 2).
#
# Usage:  bash test/qdgitrenamehealcheck.sh [BIN]
set -u
ROOT="$( cd "$( dirname "$0" )/.." && pwd )"
. "$ROOT/test/lib/clean-env.sh"
BIN="${1:-${RIPWIRE_BIN:-$ROOT/build/ripwire}}"
[ "${BIN#/}" = "$BIN" ] && BIN="$ROOT/$BIN"
fail=0
ok(){ printf '  PASS  %s\n' "$*" || { fail=1; printf '  FAIL  could not write the PASS line for: %s\n' "$*"; }; return 0; }
no(){ printf '  FAIL  %s\n' "$*"; fail=1; }
[ -x "$BIN" ] || { echo "no ripwire binary at $BIN — build first"; exit 2; }
command -v git >/dev/null 2>&1 || { echo "  SKIP  qdgitrenamehealcheck (git required for the rename record)"; exit 0; }
command -v perl >/dev/null 2>&1 || { echo "  SKIP  qdgitrenamehealcheck (perl required for the neutral edit)"; exit 0; }

WORK="$( mktemp -d )"; trap 'rm -rf "$WORK"' EXIT
export HOME="$WORK/home" TMPDIR="$WORK/tmp"; mkdir -p "$HOME" "$TMPDIR"
echo "qdgitrenamehealcheck: BIN=$BIN  (temp git corpora, no ack ledger)"

newrepo(){ mkdir -p "$1"; ( cd "$1" && git init -q && git config user.email t@t && git config user.name t ); }
commitall(){ ( cd "$1" && git add -A >/dev/null 2>&1 && git commit -qm "$2" >/dev/null 2>&1 ); }
run(){ OUT="$( cd "$1" && "$BIN" . "${2:---quality-delta}" --no-cache 2>"$WORK/err" )"; RC=$?; }
rows(){ printf '%s' "$1" | tr '>' '\n' | grep '<r kind="'; }
nrows(){ rows "$1" | grep -c . | tr -d ' '; }
crashed(){ case "$RC" in 0|2) return 1;; *) no "$1: ripwire exited rc=$RC (crash or refusal); stderr: $( head -c 300 "$WORK/err" )"; return 0;; esac; }
flat(){ rows "$1" | tr '\n' ' '; }
clean(){ if [ "$RC" = 0 ] && [ "$( nrows "$OUT" )" = 0 ]; then ok "$1 prints no row (exit 0)"; else no "$1 must read as nothing (rc=$RC rows: $( flat "$OUT" ))"; fi; }

. "$ROOT/test/lib/qdlangsrc.sh"   # LANG_pair / LANG_big, src_of, mainfile

# twins in a class: classof LANG CLASS NAME... — each NAME a method with the clone-pair body (a scoped key, so the clone group's
# member ids carry the path: a scope-less function's id is the bare name and never moved)
classof(){
    l=$1; c=$2; shift 2
    case $l in
        py)  printf 'class %s:\n' "$c"; for n in "$@"; do py_pair "$n" | sed 's/^/    /'; done ;;
        ts)  printf 'export class %s {\n' "$c"; for n in "$@"; do ts_pair "$n" | sed 's/^function //; s/^/  /'; done; printf '}\n\n' ;;
        go)  printf 'type %s struct{}\n\n' "$c"; for n in "$@"; do go_pair "$n" | sed "s/^func /func (b $c) /"; done ;;
        cpp) printf 'struct %s\n{\n' "$c"; for n in "$@"; do cpp_pair "$n" | sed 's/^/    /'; done; printf '};\n\n' ;;
        rs)  printf 'pub struct %s;\n\nimpl %s {\n' "$c" "$c"; for n in "$@"; do rs_pair "$n" | sed 's/^/    /'; done; printf '}\n\n' ;;
    esac
}
header(){ case $1 in go) printf 'package lib\n\n';; cpp) printf '#include <set>\n#include <vector>\n\n';; esac; }
# main_src LANG [worse] [extra twin]: class Box (alpha, beta[, extra]) + the over-bar big_fn + its caller
main_src(){
    l=$1; header "$l"; classof "$l" Box alpha beta ${3:+"$3"}; "${l}_big" big_fn "${2:-}"
    case $l in
        py)  printf 'def use_all():\n    return big_fn([1], 2, [3], 4, 5, 6)\n' ;;
        ts)  printf 'export function useAll(): number {\n  return big_fn([1], 2, [3], 4, 5, 6);\n}\n' ;;
        go)  printf 'func UseAll() int {\n\treturn big_fn([]int{1}, 2, []int{3}, 4, 5, 6)\n}\n' ;;
        cpp) printf 'int useAll()\n{\n    return big_fn( { 1 }, 2, { 3 }, 4, 5, 6 );\n}\n' ;;
        rs)  printf 'pub fn use_all() -> i64 {\n    big_fn(&[1], 2, &[3], 4, 5, 6)\n}\n' ;;
    esac
}
otherfile(){ printf '%s/other.%s' "$( dirname "$( mainfile "$1" )" )" "$1"; }
movedfile(){ printf '%s/engine.%s' "$( dirname "$( mainfile "$1" )" )" "$1"; }

# fixture LANG DIR: the baseline committed (main file: Box.alpha, Box.beta, big_fn; other file: Other.gamma, a third twin), then
# the main file moved with `git mv` (staged).
fixture(){
    newrepo "$2"; f="$2/$( mainfile "$1" )"; mkdir -p "$( dirname "$f" )"
    [ "$1" = py ] && : > "$( dirname "$f" )/__init__.py"
    main_src "$1" > "$f"; { header "$1"; classof "$1" Other gamma; } > "$2/$( otherfile "$1" )"; commitall "$2" base
    ( cd "$2" && git mv "$( mainfile "$1" )" "$( movedfile "$1" )" )
}

for L in py ts go cpp rs; do
    echo "── $L"
    # ═══ P) PREMISES ══════════════════════════════════════════════════════════════════════════════════════════════
    R="$WORK/$L-p"; fixture "$L" "$R"; ( cd "$R" && git reset -q --hard HEAD )
    if [ -e "$R/.ripwire_quality_acks" ]; then no "P/$L: premise — the fixture has an ack ledger"; else ok "P/$L: no .ripwire_quality_acks in the fixture"; fi
    PG="$( cd "$R" && "$BIN" . --clones --no-cache 2>/dev/null | tr -d '\n' | sed 's#</group>#\n#g' | grep '<group ' | grep 'n="alpha"' | grep 'n="beta"' | grep -c 'n="gamma"' | tr -d ' ' )"   # status: output only — the premise FAILs on 0
    if [ "$PG" -ge 1 ]; then ok "P/$L: the baseline holds one clone group naming alpha, beta and gamma ($PG)"
    else no "P/$L: premise — --clones names no group holding alpha, beta and gamma at the baseline"; fi

    # ═══ M) THE MOVE ALONE, STAGED ═════════════════════════════════════════════════════════════════════════════════
    R="$WORK/$L-m"; fixture "$L" "$R"; run "$R"
    if ! crashed "M/$L"; then
        clean "M/$L: a whole-file git mv of twin-holding code"
        if printf '%s' "$OUT" | grep -q ' renames="[1-9]'; then ok "M/$L: the root names the rename record (renames= > 0)"
        else no "M/$L: no renames= on the root — the git record is the route this arm tests ($( printf '%s' "$OUT" | head -c 300 ))"; fi
    fi

    # ═══ R) THE MOVE COMMITTED, REF-PAIR FORM ══════════════════════════════════════════════════════════════════════
    R="$WORK/$L-r"; fixture "$L" "$R"; commitall "$R" move; run "$R" --quality-delta=HEAD~1..HEAD
    crashed "R/$L" || clean "R/$L: the committed move over HEAD~1..HEAD"

    # ═══ N) THE MOVE PLUS A NEUTRAL EDIT ═══════════════════════════════════════════════════════════════════════════
    R="$WORK/$L-n"; fixture "$L" "$R"; perl -pi -e 's/\bs\b/acc/g' "$R/$( movedfile "$L" )"
    NE="$( grep -c '\bacc\b' "$R/$( movedfile "$L" )" | tr -d ' ' )"
    run "$R"
    if ! crashed "N/$L"; then
        if [ "$NE" -lt 2 ]; then no "N/$L: premise — the neutral edit changed $NE lines"
        else clean "N/$L: a git mv plus a local renamed in big_fn ($NE lines)"; fi
    fi

    # ═══ W) THE MOVE PLUS A REAL WORSENING ═════════════════════════════════════════════════════════════════════════
    R="$WORK/$L-w"; fixture "$L" "$R"; main_src "$L" worse > "$R/$( movedfile "$L" )"; run "$R"
    if ! crashed "W/$L"; then
        if rows "$OUT" | grep 'kind="complexity"' | grep -q 'big_fn'; then ok "W/$L: a worsening carried in with the move still prints its complexity row"
        else no "W/$L: the worsening carried in with the move vanished (rc=$RC rows: $( flat "$OUT" ))"; fi
    fi

    # ═══ C) THE MOVE PLUS A NEW TWIN ═══════════════════════════════════════════════════════════════════════════════
    R="$WORK/$L-c"; fixture "$L" "$R"; main_src "$L" "" delta > "$R/$( movedfile "$L" )"; run "$R"
    if ! crashed "C/$L"; then
        ROW="$( rows "$OUT" | grep 'kind="duplication"' | grep 'delta' )"
        if [ "$RC" = 2 ] && [ -n "$ROW" ] && printf '%s' "$ROW" | grep -q 'gating="1"'; then ok "C/$L: a fourth twin added beside the move still gates as duplication (exit 2)"
        else no "C/$L: a new clone must still gate (rc=$RC rows: $( flat "$OUT" ))"; fi
    fi
done

[ "$fail" = 0 ] && echo "ALL PASS" || echo "FAILURES ABOVE"
exit $fail
