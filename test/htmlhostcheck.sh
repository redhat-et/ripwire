#!/usr/bin/env bash
# htmlhostcheck.sh — gate for H1: `--html[=FILE]` must never be accepted and silently ignored.
#
# THE DEFECT. `writeHtml` is called from exactly ONE place (runDefaultMap), and every navigation /
# report verb pre-empts the default map in main()'s dispatch chain. So
#
#     ripwire <dir> --around=writeHtml --html=/tmp/h.html
#
# exited 0, wrote nothing to stdout, wrote nothing to /tmp/h.html, and said nothing on stderr —
# measured on this tree at 93c8edaa for --around / --callers / --impact / --for / --lint / --hotspots.
# The same argv without the verb writes a 59 KB page. That is the "accepted and silently ignored"
# class this repo has closed three times over (§B9, §B9.2, capture-audit H3), and repo
# non-negotiable #3 says a silent nothing is a bug: a caller cannot tell a no-op from a typo.
#
# The reverse guard already existed and was loud — `--color-by` without `--html` refuses and names
# --html (cli.h validateModifierGuards). This gate pins the mirror.
#
# THE CONTRACT PINNED HERE. For every flag F in the CLI universe, `ripwire <dir> F --html=OUT` ends
# in exactly one of two buckets:
#
#     WRITE    OUT exists and is non-empty — the run honoured --html
#     REFUSE   exit code is non-zero — the run said no, out loud
#
# A third outcome — exit 0 with no OUT — is the silent class and FAILS BY NAME. That is deliberately
# a property of the BINARY'S BEHAVIOUR and not of a table in src/: every previous closure of this
# family was done by enumerating members and re-opened on the member nobody enumerated. The verb
# added tomorrow is swept tomorrow, because the sweep derives its flag list from src/cli.h
# (test/flaguniverse.py), exactly as test/shapingflagcheck.sh arm (F) does.
#
# ARMS
#   (A) the six verbs the defect was measured on, each named, each asserted to refuse AND to name
#       --html in the refusal (a bare non-zero exit with no explanation is not the fix)
#   (B) CONTROL for (A) — the default map and --query must still WRITE the file at exit 0. Without
#       this, (A) passes on a binary that refuses --html unconditionally, which is not the contract.
#   (C) the derived UNIVERSE sweep described above
#   (D) MUTATION CONTROL for (C) — a stub binary that exits 0 and writes nothing must be classified
#       SILENT by the same classifier. An arm that cannot see the defect it exists for is vacuous,
#       and this is the cheapest way to prove this one is not.
#   (E) --color-by rides along: `--around=SYM --html=F --color-by=cx` must refuse for the --html
#       reason, not only for the --color-by one, so the message names the right mistake.
#   (F) the gate leaves the tree unmodified.
#
# Usage:
#   test/htmlhostcheck.sh                          # uses build/ripwire
#   RIPWIRE_BIN=asan/ripwire test/htmlhostcheck.sh
#
# Exit: 0 = clean · 1 = at least one arm failed · 2 = usage / missing prerequisite

set -u
ROOT="$( cd "$( dirname "$0" )/.." && pwd )"
BIN="${1:-${RIPWIRE_BIN:-$ROOT/build/ripwire}}"
[ "${BIN#/}" = "$BIN" ] && BIN="$ROOT/$BIN"
TMP="$( mktemp -d )"; trap 'rm -rf "$TMP"' EXIT
fail=0

ok(){ printf '  PASS  %s\n' "$*"; }
no(){ printf '  FAIL  %s\n' "$*"; fail=1; }

[ -x "$BIN" ] || { echo "no ripwire binary at $BIN — build first (cmake --build build -j)"; exit 2; }
command -v python3 >/dev/null 2>&1 || { echo "htmlhostcheck: python3 required (flaguniverse.py)"; exit 2; }

echo "htmlhostcheck: BIN=$BIN"

cd "$ROOT"
git status --porcelain 2>/dev/null | grep -vE '^\?\? (build|asan|tsan)' | sort > "$TMP/status.before"

# The sweep runs in a THROWAWAY git copy of test/fixture, never in this tree: several verbs write when
# they run (--note-add, --quality-baseline, --index-out, --cache), and (F) is what catches a probe this
# list forgot. git-init it so the churn/co-change/ownership verbs have history to mine.
CORPUS="$TMP/corpus"
cp -R "$ROOT/test/fixture" "$CORPUS"
( cd "$CORPUS" && git init -q . && git add -A && git -c user.name=gate -c user.email=gate@gate commit -qm fixture ) >/dev/null 2>&1
( cd "$CORPUS" && "$BIN" . >/dev/null 2>&1 ) || true   # one warm ingest for the whole sweep

# ── (A) the six measured verbs must refuse, out loud, naming --html ──────────────────────────────────
for probe in "--around=total_area" "--callers=total_area" "--impact=total_area" "--for=area of a triangle" "--lint" "--hotspots"; do
    OUT="$TMP/a.html"; rm -f "$OUT"
    # shellcheck disable=SC2086
    ( cd "$CORPUS" && "$BIN" . $probe "--html=$OUT" >/dev/null 2>"$TMP/a.err" </dev/null ); rc=$?
    if [ "$rc" -eq 0 ] && [ ! -s "$OUT" ]; then
        no "(A) '$probe --html=F': exit 0, no file, stderr $( wc -c <"$TMP/a.err" | tr -d ' ' ) B — accepted and silently ignored"
    elif [ "$rc" -ne 0 ] && grep -q -- '--html' "$TMP/a.err"; then
        ok "(A) '$probe --html=F' refuses (rc=$rc) and names --html"
    elif [ -s "$OUT" ]; then
        ok "(A) '$probe --html=F' honours --html (wrote $( wc -c <"$OUT" | tr -d ' ' ) B)"
    else
        no "(A) '$probe --html=F': rc=$rc, no file, and the message does not name --html"
        sed 's/^/        /' "$TMP/a.err" | head -3
    fi
done

# ── (B) CONTROL for (A): the hosts that DO honour --html must keep honouring it ───────────────────────
#     Without this arm, (A) is satisfied by a binary that refuses --html on every input.
for probe in "" "--query=area"; do
    OUT="$TMP/b.html"; rm -f "$OUT"
    # shellcheck disable=SC2086
    ( cd "$CORPUS" && "$BIN" . $probe "--html=$OUT" >/dev/null 2>"$TMP/b.err" </dev/null ); rc=$?
    label="${probe:-<default map>}"
    if [ "$rc" -eq 0 ] && [ -s "$OUT" ] && grep -q 'const NODES' "$OUT"; then
        ok "(B) control: '$label --html=F' still writes a real page (rc=0, $( wc -c <"$OUT" | tr -d ' ' ) B)"
    else
        no "(B) control: '$label --html=F' no longer writes a page (rc=$rc) — the guard over-refused its own host"
        sed 's/^/        /' "$TMP/b.err" | head -3
    fi
done

# ── (C) the DERIVED universe sweep ───────────────────────────────────────────────────────────────────
python3 "$ROOT/test/flaguniverse.py" "$ROOT/src/cli.h" > "$TMP/universe.tsv"
UROWS="$( grep -c . "$TMP/universe.tsv" )"
[ "$UROWS" -ge 190 ] && ok "(C) derived $UROWS flag rows from src/cli.h" \
                     || no "(C) only $UROWS rows derived — the scrape broke, so the sweep below asserts nothing"

printf 'layer test = /no-such-path-xyz/\ndeny test -> render\n' > "$TMP/arch.txt"
printf '#0 total_area at geometry.cpp:3\n' > "$TMP/htrace.txt"
printf 'not a scip index\n' > "$TMP/probe.scip"

# The probe VALUE for a value-taking flag. Same table as test/shapingflagcheck.sh's fprobeFor and kept
# deliberately parallel to it: two sweeps over one universe should disagree about a flag's runnable
# form only on purpose. `return 1` skips a row (the servers, usage, and --html itself).
hprobeFor()
{
    case "$1" in
        --query=)        printf '%s' '--query=area' ;;
        --recall=)       printf '%s' '--recall=notes' ;;
        --for=)          printf '%s' '--for=area' ;;
        --pack-task=)    printf '%s' '--pack-task=area' ;;
        --exemplar=)     printf '%s' '--exemplar=area' ;;
        --around=)       printf '%s' '--around=total_area' ;;
        --path=)         printf '%s' '--path=total_area,area_of_triangle' ;;
        --connect=)      printf '%s' '--connect=total_area,area_of_triangle' ;;
        --edit-check=)   printf '%s' '--edit-check=total_area' ;;
        --expand=)       printf '%s' '--expand=total_area' ;;
        --outline=)      printf '%s' '--outline=total_area' ;;
        --at=)           printf '%s' '--at=geometry.cpp:3' ;;
        --from-trace=)   printf '%s' "--from-trace=$TMP/htrace.txt" ;;
        --cache=)        printf '%s' "--cache=$TMP/probe.cache" ;;
        --scip=)         printf '%s' "--scip=$TMP/probe.scip" ;;
        --index-out=)    printf '%s' "--index-out=$TMP/probe.idx" ;;
        --pin-census=)   printf '%s' "--pin-census=$TMP/probe.tsv" ;;
        --run-trace=)    printf '%s' '--run-trace=true' ;;
        --note-add=)     printf '%s' '--note-add=total_area: probe' ;;
        --scan-skill=)   printf '%s' "--scan-skill=$ROOT/skills/ripwire-orient/SKILL.md" ;;
        --plan-lint=)    printf '%s' "--plan-lint=$ROOT/CONTRIBUTING.md" ;;
        --arch=)         printf '%s' "--arch=$TMP/arch.txt" ;;
        --affected=)     printf '%s' '--affected=geometry.cpp' ;;
        --test-gate=)    printf '%s' '--test-gate=geometry.cpp' ;;
        --situ=)         printf '%s' '--situ=geometry.cpp' ;;
        --help-task=)    printf '%s' '--help-task=review' ;;
        --verify=)       printf '%s' '--verify=calls(total_area,area_of_triangle)' ;;
        --layout=)       printf '%s' '--layout=Point' ;;
        --field-affinity=) printf '%s' '--field-affinity=Point' ;;
        --lego=)         printf '%s' '--lego=Point' ;;
        --whereis=)      printf '%s' '--whereis=total_area' ;;
        --owners=)       printf '%s' '--owners=total_area' ;;
        --graph-query=)  printf '%s' '--graph-query=kind(all,fn)' ;;
        --callers=|--callees=|--uses=|--impact=|--mentions=|--safe-delete=) printf '%s' "${1}total_area" ;;
        --quality-ack=)  printf '%s' '--quality-ack=probe' ;;
        --order=)        printf '%s' '--order=stable' ;;
        --rank-by=)      printf '%s' '--rank-by=churn' ;;
        --format=)       printf '%s' '--format=columnar' ;;
        --color-by=)     printf '%s' '--color-by=lang' ;;
        --grep-scope=)   printf '%s' '--grep-scope=file' ;;
        --grep-in=)      printf '%s' '--grep-in=any' ;;
        --legend=)       printf '%s' '--legend=compact' ;;
        --slice-flow=)   printf '%s' '--slice-flow=back' ;;
        --agent=)        printf '%s' '--agent=codex' ;;
        --export=)       printf '%s' '--export=cc.json' ;;
        --quality-panel=) printf '%s' '--quality-panel=default' ;;
        --limit=)        printf '%s' '--limit=3' ;;
        --offset=)       printf '%s' '--offset=1' ;;
        --max-file-size=) printf '%s' '--max-file-size=1M' ;;
        --pack-budget-bytes=) printf '%s' '--pack-budget-bytes=1000' ;;
        --html|--html=)  return 1 ;;                          # the host under test, not a co-flag
        --mcp|--listen=|--help|--version) return 1 ;;         # servers and usage
        *=)              printf '%s' "${1}zzqq9" ;;
        *)               printf '%s' "$1" ;;
    esac
}

# THE CLASSIFIER, factored out so (D) can run the identical code over a deliberately broken binary.
# Echoes exactly one of: WRITE | REFUSE | SILENT.
classify()
{
    local bin="$1" out="$2"; shift 2
    rm -f "$out"
    ( cd "$CORPUS" && "$bin" . "$@" "--html=$out" >/dev/null 2>/dev/null </dev/null ); local rc=$?
    if [ -s "$out" ]; then printf 'WRITE'
    elif [ "$rc" -ne 0 ]; then printf 'REFUSE'
    else printf 'SILENT'; fi
}

cWrite=0; cRefuse=0; cSilent=0
while IFS="$( printf '\t' )" read -r flag kind example policy; do
    [ -n "$flag" ] || continue
    case "$kind" in int) probe="${flag}2" ;; *) probe="$( hprobeFor "$flag" )" || continue ;; esac
    # shellcheck disable=SC2086
    verdict="$( classify "$BIN" "$TMP/c.html" $probe )"
    case "$verdict" in
        WRITE)  cWrite=$(( cWrite + 1 )) ;;
        REFUSE) cRefuse=$(( cRefuse + 1 )) ;;
        *)      cSilent=$(( cSilent + 1 ))
                no "(C) '$probe --html=F': SILENT — exit 0, no file, nothing on stderr: accepted and ignored" ;;
    esac
done < "$TMP/universe.tsv"
[ "$cSilent" -eq 0 ] && ok "(C) every flag x --html is WRITE or REFUSE (write=$cWrite refuse=$cRefuse)" \
                     || no "(C) $cSilent flag x --html combinations are SILENT (write=$cWrite refuse=$cRefuse)"
{ [ "$cWrite" -ge 10 ] && [ "$cRefuse" -ge 20 ]; } \
    && ok "(C) both buckets are populated (the sweep measured something: write=$cWrite refuse=$cRefuse)" \
    || no "(C) a bucket is implausibly small (write=$cWrite refuse=$cRefuse) — the sweep is not covering the universe"

# ── (D) MUTATION CONTROL for (C): a binary that exits 0 and writes nothing must read as SILENT ───────
#     This is the defect (C) exists to catch, injected on purpose. If the classifier calls it anything
#     else, (C)'s zero above means "the arm cannot see it", not "the defect is gone".
STUB="$TMP/stub-silent"
printf '#!/bin/sh\nexit 0\n' > "$STUB"; chmod +x "$STUB"
mutVerdict="$( classify "$STUB" "$TMP/d.html" --around=total_area )"
if [ "$mutVerdict" = "SILENT" ]; then
    ok "(D) mutation control: a stub that exits 0 writing nothing is classified SILENT — (C) can see the defect"
else
    no "(D) mutation control VACUOUS: the injected silent no-op classified as $mutVerdict, so (C) proves nothing"
fi
STUB2="$TMP/stub-refuse"
printf '#!/bin/sh\nexit 3\n' > "$STUB2"; chmod +x "$STUB2"
mut2="$( classify "$STUB2" "$TMP/d2.html" --around=total_area )"
[ "$mut2" = "REFUSE" ] && ok "(D) mutation control: a stub that exits non-zero is classified REFUSE (the classifier separates the two)" \
                       || no "(D) mutation control: a non-zero-exit stub classified as $mut2, not REFUSE"

# ── (E) the refusal names the right mistake when --color-by rides along ──────────────────────────────
OUT="$TMP/e.html"; rm -f "$OUT"
( cd "$CORPUS" && "$BIN" . --around=total_area "--html=$OUT" --color-by=cx >/dev/null 2>"$TMP/e.err" </dev/null ); rc=$?
if [ -s "$OUT" ]; then
    ok "(E) '--around --html --color-by' honours --html"
elif [ "$rc" -ne 0 ] && grep -q -- '--html' "$TMP/e.err" && grep -qi 'around\|default map\|node/' "$TMP/e.err"; then
    ok "(E) '--around --html --color-by' refuses for the --html reason and points somewhere useful"
else
    no "(E) '--around --html --color-by' (rc=$rc) does not explain the --html half of the mistake"
    sed 's/^/        /' "$TMP/e.err" | head -3
fi

# ── (F) the harness must not mutate the tree ─────────────────────────────────────────────────────────
cd "$ROOT"
git status --porcelain 2>/dev/null | grep -vE '^\?\? (build|asan|tsan)' | sort > "$TMP/status.after"
STRAY="$( comm -13 "$TMP/status.before" "$TMP/status.after" 2>/dev/null | head -5 )"
[ -z "$STRAY" ] && ok "(F) gate left the tree unmodified" \
                || { no "(F) gate MUTATED the tree:"; printf '%s\n' "$STRAY" | sed 's/^/        /'; }

echo
if [ "$fail" -eq 0 ]; then
    echo "ALL PASS"
    exit 0
else
    echo "SOME CHECKS FAILED"
    exit 1
fi
