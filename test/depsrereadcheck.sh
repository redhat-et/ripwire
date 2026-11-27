#!/usr/bin/env bash
# depsrereadcheck.sh — DEPS-REREAD: a served warm run repeats the resolver's recorded file reads only where the file may
# have moved (src/warmsnap_graph.h depsStillAnswer).
#
# THE COST (results/PHASESPLIT_1125, llvm-project, served warm --for, B1): readGraph spent 132 ms of its 184 ms in
# depsStillAnswer, which re-read and digested, one after another, every file the graph's resolution had read outside the
# parse cache — 7,838 files on llvm (in-tree headers read through readConfigBytes), 999 on envoy, 214 on vscode.
#
# THE RULE (the one 5b's verbfs.h and the parse cache's stat gate use; not a new one): each content row of the GRAPH
# section carries the stat signature (device, inode, size, mtime, ctime) its file had right after the build read it, kept
# only when it was SETTLED — mtime and ctime both older than kRacySlackNs before the recording run began. A served run
# skips the read when the signature is unchanged; anything else (moved, unsettled, absent, unstatable) is read and
# digested exactly as before. A failed read must still refuse the graph exactly where main refused it.
#
# THE FIXTURE. A Go module (go.mod at the root, read through the WholeFile seam; a/go.mod absent, recorded absent) and a
# TS tsconfig extended from node_modules (read through the ConfigBytes seam, outside the crawl). Every copy is its own
# root with its own cache directory, so each arm starts from its own settled, served snapshot.
#
# The observables are two stderr lines:
#   ripwire: snapshot-stats ... graph=built|loaded ... graph_why=<refusal>      (RIPWIRE_SNAPSHOT_STATS=1)
#   [warmsnap] deps rows=N read=R probed=P skipped=K                           (RIPWIRE_STATS=1, one per graph check)
#
# ARMS
#   C   COUNTER: a served run on a settled snapshot skips at least one row, and read+probed+skipped == rows. Red on main
#       (fec2ab27c): it prints no [warmsnap] deps line at all.
#   I   IDENTITY: served map, --for and --callers on the settled copy equal a --no-cache run byte for byte.
#   Invalidation — each must refuse the graph as main does (graph=built graph_why=dep) and answer as --no-cache does:
#   R   RACY: go.mod rewritten (same bytes) just before the recording run, so its signature is too young to keep: the
#       next run reads it (read is one more, skipped one less, than C's copy); then a same-size rewrite with its mtime
#       put back to the first rewrite's (the same-granule case) is refused.
#   N   RENAME: go.mod replaced by rename — a new inode, same size, mtime put back with touch -r.
#   T   TOUCH -R: the node_modules tsconfig rewritten in place at the same size, its mtime restored (only ctime moves).
#   G   GONE: the node_modules tsconfig deleted.
#   A   APPEAR: a/go.mod created where the build recorded none.
#   L   RELINK: go.mod is a symlink; retargeted to another file of the same size and mtime.
#   U   UNCHANGED BYTES: go.mod touched, content kept: the read is repeated (read is one more) and the graph is SERVED,
#       as main serves it — the rule never refuses what main accepts.
#   Mutants (non-NDEBUG fault switches; SKIP on an NDEBUG binary, which compiles them out): each must turn its arm red.
#   MR  RIPWIRE_FAULT_WARMSNAP_DEPS_RACY=1      keeps an unsettled signature          -> R's counter
#   MN  RIPWIRE_FAULT_WARMSNAP_DEPS_SIZEMTIME=1 compares only size and mtime          -> N
#   MT  RIPWIRE_FAULT_WARMSNAP_DEPS_SIZEMTIME=1                                       -> T
#   MG  RIPWIRE_FAULT_WARMSNAP_DEPS_GONE=1      reads a failed stat as unchanged      -> G
#   MA  RIPWIRE_FAULT_WARMSNAP_DEPS_NOSIG=1     skips a row stored with no signature  -> A
#   ML  RIPWIRE_FAULT_WARMSNAP_DEPS_SIZEMTIME=1                                       -> L
#   REF (only with RIPWIRE_REF_BIN=<main's binary>): every invalidation and U arm is run on it too, and its verdict
#       must equal this binary's; and a snapshot it wrote (an older format) is refused here as why=version, answer intact.
#
#   bash test/depsrereadcheck.sh [BIN]   |   RIPWIRE_BIN=build/ripwire RIPWIRE_REF_BIN=/path/to/main/ripwire bash test/depsrereadcheck.sh
#
# Exits non-zero on any failure. Prints ALL PASS on success.

set -u
ROOT="$( cd "$( dirname "$0" )/.." && pwd )"
. "$ROOT/test/lib/clean-env.sh"
BIN="${1:-${RIPWIRE_BIN:-$ROOT/build/ripwire}}"
[ "${BIN#/}" = "$BIN" ] && BIN="$ROOT/$BIN"
REF="${RIPWIRE_REF_BIN:-}"
[ -x "$BIN" ] || { echo "no ripwire binary at $BIN — build first (cmake --build build -j)"; exit 2; }
fail=0
ok(){ printf '  PASS  %s\n' "$*" || { fail=1; printf '  FAIL  could not write the PASS line for: %s\n' "$*"; }; return 0; }
no(){ printf '  FAIL  %s\n' "$*"; fail=1; }
echo "depsrereadcheck: BIN=$BIN${REF:+ REF=$REF}"

TMP="$( mktemp -d )"; trap 'rm -rf "$TMP"' EXIT
mkdir -p "$TMP/home" "$TMP/fx" "$TMP/t/nc" "$TMP/out"   # every TMPDIR exists before its first call: a missing one changes the answer
export HOME="$TMP/home"
unset RIPWIRE_STATS RIPWIRE_SNAPSHOT_STATS RIPWIRE_NO_WARMSNAP RIPWIRE_NO_VERBFS RIPWIRE_FAULT_WARMSNAP_DEPS_RACY \
      RIPWIRE_FAULT_WARMSNAP_DEPS_SIZEMTIME RIPWIRE_FAULT_WARMSNAP_DEPS_GONE RIPWIRE_FAULT_WARMSNAP_DEPS_NOSIG
FLAVOUR="$( "$BIN" --version 2>/dev/null | sed -nE 's/^[^(]*\(([^,)]*).*/\1/p' )"
case "$FLAVOUR" in Release|RelWithDebInfo|MinSizeRel) FAULTS=0 ;; *) FAULTS=1 ;; esac

TSCFG='web/node_modules/@acme/cfg/tsconfig.json'
# mkfix DIR LINK : the fixture; LINK=1 makes go.mod a symlink to mods/g1.mod
mkfix(){
    local d="$1" link="$2"
    mkdir -p "$d/a" "$d/mods" "$d/web/src/lib" "$d/web/src/alt" "$d/web/node_modules/@acme/cfg"
    if [ "$link" = 1 ]; then
        printf 'module example.com/m\n\ngo 1.21\n' >"$d/mods/g1.mod"
        printf 'module example.com/n\n\ngo 1.21\n' >"$d/mods/g2.mod"
        ln -s mods/g1.mod "$d/go.mod"
    else
        printf 'module example.com/m\n\ngo 1.21\n' >"$d/go.mod"
    fi
    printf 'package a\n\n// Hello returns the greeting of module a.\nfunc Hello() string { return "hi" }\n' >"$d/a/a.go"
    printf 'package main\n\nimport "example.com/m/a"\n\nfunc main() { println(a.Hello()) }\n' >"$d/main.go"
    printf '{ "extends": "@acme/cfg/tsconfig.json" }\n' >"$d/web/tsconfig.json"
    printf '{ "compilerOptions": { "baseUrl": ".", "paths": { "@lib/*": ["src/lib/*"] } } }\n' >"$d/$TSCFG"
    printf '{ "name": "@acme/cfg" }\n' >"$d/web/node_modules/@acme/cfg/package.json"
    printf 'export function helper(): number { return 1; }\n' >"$d/web/src/lib/util.ts"
    printf 'export function helper(): number { return 2; }\n' >"$d/web/src/alt/util.ts"
    printf 'import { helper } from "@lib/util";\nexport function run(): number { return helper(); }\n' >"$d/web/src/app.ts"
    ( cd "$d" && git init -q . && git add -A && git -c user.email=gate@example.invalid -c user.name=gate commit -qm fixture ) >/dev/null 2>&1
}

# The mutant of a copy: every RIPWIRE_* variable is keyed into the snapshot's options (warmsnap.h optionsKeyOf), so a
# fault switch is set on EVERY run of its copy — recording and served alike — never on one run alone.
fault_of(){ case "$1" in R) echo RACY ;; N|T|L) echo SIZEMTIME ;; G) echo GONE ;; A) echo NOSIG ;; *) echo "fault_of: no mutant for arm $1" >&2; return 1 ;; esac; }
faultenv(){ case "$1" in m?) echo "RIPWIRE_FAULT_WARMSNAP_DEPS_$( fault_of "${1#m}" )=1" ;; *) echo "RIPWIRE_DEPSREREAD_GATE=1" ;; esac; }
# run TAG COPY BINARY ARGS... : a cached run of COPY with its own cache dir; stdout/stderr/rc to $TMP/out/TAG.*
run(){
    local tag="$1" copy="$2" bin="$3"; shift 3
    mkdir -p "$TMP/t/$copy"
    ( cd "$TMP/fx/$copy" && env TMPDIR="$TMP/t/$copy" RIPWIRE_STATS=1 RIPWIRE_SNAPSHOT_STATS=1 "$( faultenv "$copy" )" \
        "$bin" "$TMP/fx/$copy" "$@" </dev/null >"$TMP/out/$tag.out" 2>"$TMP/out/$tag.err" )
    echo $? >"$TMP/out/$tag.rc"
}
nocache(){ local tag="$1" copy="$2"; shift 2; ( cd "$TMP/fx/$copy" && env TMPDIR="$TMP/t/nc" RIPWIRE_DEPSREREAD_GATE=1 "$BIN" "$TMP/fx/$copy" --no-cache "$@" </dev/null >"$TMP/out/$tag.out" 2>/dev/null ); echo $? >"$TMP/out/$tag.rc"; }
# verdict TAG : "graph=<built|loaded> graph_why=<why>" from the snapshot-stats line
verdict(){ grep '^ripwire: snapshot-stats ' "$TMP/out/$1.err" | tail -1 | grep -oE '(graph|graph_why)=[^ ]+' | tr '\n' ' ' | sed 's/ $//'; }
# dep TAG KEY : KEY= on the last [warmsnap] deps line of TAG
dep(){ grep '^\[warmsnap\] deps ' "$TMP/out/$1.err" | tail -1 | grep -oE "(^| )$2=[0-9]+" | head -1 | cut -d= -f2; }
same(){ cmp -s "$TMP/out/$1.out" "$TMP/out/$2.out" && cmp -s "$TMP/out/$1.rc" "$TMP/out/$2.rc"; }
mt_save(){ mkdir -p "$TMP/ref"; touch -r "$1" "$TMP/ref/$2"; }
mt_put(){ touch -r "$TMP/ref/$2" "$1"; }

# ── the copies, then one settle pause for all of them ───────────────────────────────────────────────────────────
ARMS="R N T G A L U"
COPIES="base"
for a in $ARMS; do COPIES="$COPIES h$a"; [ -n "$REF" ] && COPIES="$COPIES r$a"; done
[ "$FAULTS" = 1 ] && for a in R N T G A L; do COPIES="$COPIES m$a"; done
[ -n "$REF" ] && COPIES="$COPIES vref"
for c in $COPIES; do
    case "$c" in *L) mkfix "$TMP/fx/$c" 1 ;; *) mkfix "$TMP/fx/$c" 0 ;; esac
done
sleep 3   # kRacySlackNs is 2 s: every fixture byte is now settled for the recording runs below

binof(){ case "$1" in r*|vref) echo "$REF" ;; *) echo "$BIN" ;; esac; }
# record COPY : the cold run, which records the graph (warmsnap.h recordsWhatItBuilt: a run that opened with no blob
# stores what it built), then two more runs. R copies rewrite go.mod just BEFORE the cold run, so its signature is too
# young when the graph is recorded. A binary that still records on run 2 (main before the warm-serve lane) records within
# the same 2 s, since run 1 on this fixture takes well under that.
record(){
    local c="$1" bin; bin="$( binof "$1" )"
    case "$c" in
        ?R) printf 'module example.com/m\n\ngo 1.21\n' >"$TMP/fx/$c/go.mod"; mt_save "$TMP/fx/$c/go.mod" "$c" ;;
    esac
    run "$c.1" "$c" "$bin"
    run "$c.2" "$c" "$bin"
    run "$c.3" "$c" "$bin"
}
for c in $COPIES; do record "$c"; done

# every copy's third run must be served — otherwise no arm below is testing the graph check at all
for c in $COPIES; do
    [ "$c" = vref ] && continue
    v="$( verdict "$c.3" )"
    case "$v" in "graph=loaded graph_why=ok") : ;; *) no "setup $c: the third run was not served ($v) — the arms below would be vacuous" ;; esac
done

# ── C: the counter ──────────────────────────────────────────────────────────────────────────────────────────────
rows="$( dep base.3 rows )"; rd="$( dep base.3 read )"; pr="$( dep base.3 probed )"; sk="$( dep base.3 skipped )"
if [ -n "$rows" ] && [ -n "$rd" ] && [ -n "$pr" ] && [ -n "$sk" ] && [ "$sk" -ge 1 ] && [ $(( rd + pr + sk )) -eq "$rows" ]; then
    ok "C a served run on a settled snapshot skips $sk of $rows recorded reads (read=$rd probed=$pr)"
else
    no "C counter: rows='${rows:-absent}' read='${rd:-absent}' probed='${pr:-absent}' skipped='${sk:-absent}' (main has no [warmsnap] deps line)"
fi
n_dep_lines="$( grep -c '^\[warmsnap\] deps ' "$TMP/out/base.3.err" )"
if [ "$n_dep_lines" = 1 ]; then ok "C one [warmsnap] deps line per served call"; else no "C expected one [warmsnap] deps line on the served call, saw $n_dep_lines"; fi
if [ -n "$(cat "$TMP/out/base.1.err" | grep '^\[warmsnap\] deps ')" ]; then no "C the cold run (no snapshot) printed a deps line"; else ok "C the cold run (nothing stored) prints no deps line"; fi

# ── I: byte identity of the served answer ───────────────────────────────────────────────────────────────────────
ident(){
    local label="$1"; shift
    run "id.w0" base "$BIN" "$@"; run "id.w1" base "$BIN" "$@"   # a verb with its own options key records its own snapshot first
    run "id.w" base "$BIN" "$@"; nocache "id.c" base "$@"
    local v; v="$( verdict id.w )"
    if [ "$v" != "graph=loaded graph_why=ok" ]; then no "I $label: not served ($v)"; return; fi
    if [ "$( cat "$TMP/out/id.c.rc" )" != 0 ]; then no "I $label: the --no-cache reference exited $( cat "$TMP/out/id.c.rc" )"; return; fi
    if same id.w id.c; then ok "I $label: served == --no-cache ($( wc -c <"$TMP/out/id.w.out" | tr -d ' ' ) B, skipped=$( dep id.w skipped ))"; else no "I $label: served differs from --no-cache: $( diff "$TMP/out/id.w.out" "$TMP/out/id.c.out" | head -3 | tr '\n' ' ' )"; fi
}
ident "map"
ident "--for" --for="where is the greeting of module a returned"
ident "--callers=Hello" --callers=Hello

# ── the edits ───────────────────────────────────────────────────────────────────────────────────────────────────
mutate(){
    local c="$1" d="$TMP/fx/$1"
    case "$c" in
        ?R) printf 'module example.com/n\n\ngo 1.21\n' >"$d/go.mod"; mt_put "$d/go.mod" "$c" ;;
        ?N) printf 'module example.com/n\n\ngo 1.21\n' >"$d/go.mod.new"; touch -r "$d/go.mod" "$d/go.mod.new"; mv "$d/go.mod.new" "$d/go.mod" ;;
        ?T) mt_save "$d/$TSCFG" "$c"; printf '{ "compilerOptions": { "baseUrl": ".", "paths": { "@lib/*": ["src/alt/*"] } } }\n' >"$d/$TSCFG"; mt_put "$d/$TSCFG" "$c" ;;
        ?G) rm -f "$d/$TSCFG" ;;
        ?A) printf 'module other.com/a\n\ngo 1.21\n' >"$d/a/go.mod" ;;
        ?L) touch -r "$d/mods/g1.mod" "$d/mods/g2.mod"; ln -sfn mods/g2.mod "$d/go.mod" ;;
        ?U) touch "$d/go.mod" ;;
    esac
}
for a in $ARMS; do
    mutate "h$a"; run "h$a.4" "h$a" "$BIN"; nocache "h$a.c" "h$a"
    [ -n "$REF" ] && { mutate "r$a"; run "r$a.4" "r$a" "$REF"; }
done

expect="graph=built graph_why=dep"
for a in R N T G A L; do
    v="$( verdict "h$a.4" )"
    if [ "$v" = "$expect" ]; then ok "$a refused as main refuses ($v)"; else no "$a expected '$expect', got '$v'"; fi
    if same "h$a.4" "h$a.c"; then ok "$a the answer after the edit equals --no-cache"; else no "$a the answer after the edit differs from --no-cache"; fi
done
v="$( verdict hU.4 )"
if [ "$v" = "graph=loaded graph_why=ok" ]; then ok "U touched, bytes kept: still served ($v), as main serves it"; else no "U expected the graph served, got '$v'"; fi
if [ "$( dep hU.4 read )" = $(( rd + 1 )) ]; then ok "U the touched file was read again (read=$( dep hU.4 read ))"; else no "U expected read=$(( rd + 1 )), got '$( dep hU.4 read )'"; fi
if same hU.4 hU.c; then ok "U the served answer equals --no-cache"; else no "U the served answer differs from --no-cache"; fi

# R's counter: the racy row is read, every other settled row still skipped
if [ "$( dep hR.3 read )" = $(( rd + 1 )) ] && [ "$( dep hR.3 skipped )" = $(( sk - 1 )) ]; then
    ok "R the row recorded inside the racy window is read (read=$( dep hR.3 read ) skipped=$( dep hR.3 skipped ))"
else
    no "R expected read=$(( rd + 1 )) skipped=$(( sk - 1 )) after a racy recording, got read='$( dep hR.3 read )' skipped='$( dep hR.3 skipped )'"
fi

# ── REF: main's verdicts, and an older-format snapshot ─────────────────────────────────────────────────────────
if [ -n "$REF" ]; then
    for a in $ARMS; do
        if [ "$( verdict "r$a.4" )" = "$( verdict "h$a.4" )" ]; then ok "REF $a verdict equals main's ($( verdict "r$a.4" ))"; else no "REF $a: main says '$( verdict "r$a.4" )', this binary '$( verdict "h$a.4" )'"; fi
    done
    run vref.4 vref "$BIN"; nocache vref.c vref
    case "$( grep '^ripwire: snapshot-stats ' "$TMP/out/vref.4.err" | tail -1 )" in
        *why=version*) ok "REF a snapshot main wrote is refused here as why=version" ;;
        *) no "REF main's snapshot was not refused by version: $( grep '^ripwire: snapshot-stats ' "$TMP/out/vref.4.err" | tail -1 )" ;;
    esac
    if same vref.4 vref.c; then ok "REF the answer over main's snapshot equals --no-cache"; else no "REF the answer over main's snapshot differs from --no-cache"; fi
else
    printf '  INFO  REF arms not run: set RIPWIRE_REF_BIN to main'"'"'s binary to measure its verdicts beside these\n'
fi

# ── mutants ─────────────────────────────────────────────────────────────────────────────────────────────────────
if [ "$FAULTS" = 1 ]; then
    # red = the racy row skipped: the mutant's counter is the settled copy's, not R's
    if [ -n "$rd" ] && [ "$( dep mR.3 read )" = "$rd" ] && [ "$( dep mR.3 skipped )" = "$sk" ]; then
        ok "MR keeping an unsettled signature turns R's counter red (the racy row is skipped: read=$rd skipped=$sk)"
    else
        no "MR expected the racy row skipped under the mutant (read=${rd:-?} skipped=${sk:-?}), got read='$( dep mR.3 read )' skipped='$( dep mR.3 skipped )'"
    fi
    for a in N T G A L; do
        f="$( fault_of "$a" )"
        mutate "m$a"; run "m$a.4" "m$a" "$BIN"
        v="$( verdict "m$a.4" )"
        # red = the WRONG acceptance itself: the edited dependency served as if unchanged (anything else is not this mutant)
        if [ "$v" = "graph=loaded graph_why=ok" ]; then ok "M$a RIPWIRE_FAULT_WARMSNAP_DEPS_$f turns $a red (the edited graph is served: $v)"; else no "M$a the $f mutant did not serve the stale graph ($v): $a cannot see that rule"; fi
    done
else
    printf '  SKIP  mutants: this %s binary compiles fault switches out (NDEBUG); the plain-flavour leg proves them\n' "$FLAVOUR"
fi

if [ "$fail" -eq 0 ]; then echo "depsrereadcheck: ALL PASS"; exit 0; fi
echo "depsrereadcheck: FAILED"; exit 1
