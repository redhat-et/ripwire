#!/usr/bin/env bash
# verbfscheck.sh — VERB-FS (src/verbfs.h): the file-system work a served --for repeated on every call, kept per index.
#
# THE COST (results/A1_WARM_PROFILE_1125 §2, llvm-project, served warm --for, main fec2ab27c): sys 19.9 s against user
# 4.1 s, and three verb-time passes over the disk inside runForLensPass —
#   (1) the literal scan (search.h grepCollectEach) read every indexed file        893 ms main-thread wait
#   (2) findClones (clones.h) re-read every file holding a shared clone key           343 ms
#   (3) the manifest probe (formanifest.h) symlink_status'd 3 names per directory     109 ms
# Each is now a lookup in a record kept in the cache directory (ripwire-verbfs-<part>-<rootKey>.bin), validated per use:
#   (1) a per-file trigram Bloom filter, keyed by the file's stat signature (dev, inode, size, mtime, ctime) and the racy
#       rule: a file is skipped only when no pattern can occur in it AND its signature still matches;
#   (2) the clone groups, keyed by a digest of every input the pass reads from the model AND the stat signature of every
#       file it read;
#   (3) each probed directory's entry kinds, keyed by the directory's own lstat signature (an entry cannot appear,
#       vanish or change kind without moving it); a symlink is never stored, it is probed live.
#
# THE ARMS. Identity arms compare stdout (+ rc) of a served call against RIPWIRE_NO_VERBFS=1 (the record neither read nor
# written) and against --no-cache (no cache of any kind). An identity arm passes on code with no record at all, so each
# kind is paired with (i) a COUNTER arm that is red on fec2ab27c (the `[verbfs]` RIPWIRE_STATS line is absent there, and
# the counts prove the record was used) and (ii) a MUTATION arm (non-NDEBUG fault switch) that breaks one rule of the
# record and must turn the identity arm red.
#   G1  the grep record is written once the fixture leaves the racy window
#   G2  COUNTER: a served --grep for a rare literal opens fewer files than it indexes (skipped > 0, prefilter=on)
#   G3  IDENTITY: an adversarial literal set through --grep — tokens spanning spaces and punctuation, mixed case, non-ASCII
#       (a 3-byte UTF-8 character, a lone continuation byte), 1-2 byte literals, regex-shaped text, a newline — equals both
#       references; 1-2 byte literals report the fallback (why=short) on the stats line, never in the answer
#   G3r --regex falls back to the full scan (why=regex), answer identical
#   G4  IDENTITY: --for tasks whose literal block scans (quoted, CONST_SHAPED, dotted, message) equal both references
#   G5  EDITED AFTER THE INDEX: a literal appended inside the racy window; a same-size edit whose mtime is put back
#       (touch -r: only ctime moves); a file replaced by rename (new inode, same size and mtime): each is found
#   G6  a record of another version, or one with a flipped payload byte, is refused (why=version / why=checksum), the
#       answer is unchanged, and the next run writes a valid one
#   GM  MUTATION: RIPWIRE_FAULT_VERBFS_GREP_SKIPALL=1 (skip every recorded file) turns G3 red;
#       RIPWIRE_FAULT_VERBFS_GREP_NOSTAT=1 (trust an entry whose signature moved) turns G5 red
#   C1  COUNTER: an unchanged warm run serves the clone groups (served=1)
#   C2..C5 IDENTITY after: nothing changed; one member of a clone pair edited; a new clone added; a member file deleted
#   CM  MUTATION: RIPWIRE_FAULT_VERBFS_CLONE_ANYDIGEST=1 (serve whatever groups are stored) turns C3..C5 red
#   M1  COUNTER: a served manifest probe answers from the record (served > 0, live probes < probes)
#   M2..M9 IDENTITY after each file-kind change of a probed name: deleted, created, regular → symlink, symlink retargeted,
#       the link's TARGET edited in another directory (the link's own directory unchanged), the target turned into a
#       directory, the target deleted (dangling), a directory at the name, a link out of the root
#   MM  MUTATION: RIPWIRE_FAULT_VERBFS_DIRS_NOSTAT=1 (serve without the directory check) turns M2..M9 red;
#       RIPWIRE_FAULT_VERBFS_DIRS_LINKS=1 (store a link's resolved kind) turns M7 (the target became a directory) red
#   KB  the BUILD: with RIPWIRE_BIN_OTHER (the other build type of this tree), neither build serves the other's grep
#       record (why=shape) and the answer equals the serving build's --no-cache; SKIP without it
#   D   determinism: two served calls are byte-identical
#
# Usage:  bash test/verbfscheck.sh [BIN]   |   RIPWIRE_BIN=build/ripwire bash test/verbfscheck.sh

set -u
ROOT="$( cd "$( dirname "$0" )/.." && pwd )"
. "$ROOT/test/lib/clean-env.sh"
BIN="${1:-${RIPWIRE_BIN:-$ROOT/build/ripwire}}"
[ "${BIN#/}" = "$BIN" ] && BIN="$ROOT/$BIN"
fail=0
ok(){ printf '  PASS  %s\n' "$*" || { fail=1; printf '  FAIL  could not write the PASS line for: %s\n' "$*"; }; return 0; }
no(){ printf '  FAIL  %s\n' "$*"; fail=1; }

[ -x "$BIN" ] || { echo "no ripwire binary at $BIN — build first (cmake --build build -j)"; exit 2; }
echo "verbfscheck: BIN=$BIN"

TMP="$( mktemp -d )"; trap 'chmod -R u+rwx "$TMP" 2>/dev/null; rm -rf "$TMP"' EXIT
FIX="$TMP/fix"; mkdir -p "$FIX/src" "$FIX/gen" "$FIX/pkg" "$FIX/tools" "$FIX/cm" "$FIX/alt" "$TMP/home" "$TMP/t" "$TMP/outside"
export HOME="$TMP/home"
export TMPDIR="$TMP/t"
unset RIPWIRE_NO_VERBFS RIPWIRE_STATS RIPWIRE_NO_WARMSNAP

# ── the fixture ───────────────────────────────────────────────────────────────────────────────────────────────────
CLONEBODY='{
    int total = 0;
    for( int i = 0; i < n; ++i )
    {
        if( values[i] > limit )
        {
            total += values[i] * scale - offset;
        }
        else
        {
            total -= values[i] + offset;
        }
    }
    return total + scale * limit - offset;
}'
printf 'int alpha_sum( const int* values, int n, int limit, int scale, int offset )\n%s\n\nint alpha_total( const int* values, int n, int limit, int scale, int offset )\n%s\n' "$CLONEBODY" "$CLONEBODY" >"$FIX/src/alpha.c"
printf 'int beta_acc( const int* values, int n, int limit, int scale, int offset )\n%s\n' "$CLONEBODY" >"$FIX/src/beta.c"
cat >"$FIX/src/strings.c" <<'C'
#define ERR_IDLE_TIMEOUT 408
static const char* kMsg = "connection idle timeout exceeded";
static const char* kUtf = "naïve café 日本語テキスト";
static const char* kKey = "server.idle.limit";
static const char* kPct = "50% done";
int arrow( struct s* x ) { return x->y; }
int scope( void ) { return a::b; }
int call( void ) { return foo(bar); }
int MixedCaseToken = 1;
int tabbed	= 2;
C
for i in $( seq 1 60 ); do
    printf 'int fn_%s( void )\n{\n    return %s; /* unique_token_%s */\n}\n' "$i" "$i" "$i" >"$FIX/gen/file$i.c"
done
cat >"$FIX/pkg/go.mod" <<'G'
module example.com/acme/gizmo

go 1.22
G
printf 'package main\n\nfunc main() {}\n' >"$FIX/pkg/main.go"
printf '[metadata]\nname = widgetkit\n' >"$FIX/tools/setup.cfg"
printf 'def tool():\n    return 1\n' >"$FIX/tools/tool.py"
printf 'cmake_minimum_required(VERSION 3.20)\nproject(cmdemo C)\nadd_executable(meterd main.c)\n' >"$FIX/cm/CMakeLists.txt"
printf 'int main(void) { return 0; }\n' >"$FIX/cm/main.c"
printf 'module example.com/acme/sprocket\n\ngo 1.22\n' >"$FIX/alt/sprocket.mod"
printf 'module example.com/acme/flywheel\n\ngo 1.22\n' >"$FIX/alt/flywheel.mod"
printf 'package alt\n' >"$FIX/alt/alt.go"
printf 'module example.com/acme/outsider\n\ngo 1.22\n' >"$TMP/outside/go.mod"

# ── runners ───────────────────────────────────────────────────────────────────────────────────────────────────────
# run TAG MODE ARGS... : MODE warm = the served path (--cache=C); novfs = RIPWIRE_NO_VERBFS=1 (its own cache: the variable
# is keyed into the snapshot's options); nocache = --no-cache. stdout/stderr/rc into $TMP/TAG.{out,err,rc}.
run(){
    local tag="$1" mode="$2"; shift 2
    case "$mode" in
        warm)    ( cd "$FIX" && "$BIN" "$FIX" --cache="$TMP/c.bin" "$@" </dev/null >"$TMP/$tag.out" 2>"$TMP/$tag.err" ) ;;
        novfs)   ( cd "$FIX" && RIPWIRE_NO_VERBFS=1 "$BIN" "$FIX" --cache="$TMP/n.bin" "$@" </dev/null >"$TMP/$tag.out" 2>"$TMP/$tag.err" ) ;;
        nocache) ( cd "$FIX" && "$BIN" "$FIX" --no-cache "$@" </dev/null >"$TMP/$tag.out" 2>"$TMP/$tag.err" ) ;;
    esac
    echo $? >"$TMP/$tag.rc"
}
statrun(){ local tag="$1"; shift; RIPWIRE_STATS=1 run "$tag" warm "$@"; }
# field TAG PART KEY : the value of KEY= on the LAST `[verbfs] PART` stats line of TAG
field(){ grep "^\[verbfs\] $2 " "$TMP/$1.err" | tail -1 | grep -oE "(^| )$3=[^ ]+" | head -1 | cut -d= -f2; }
same(){ cmp -s "$TMP/$1.out" "$TMP/$2.out" && cmp -s "$TMP/$1.rc" "$TMP/$2.rc"; }
# ident LABEL ARGS... : the served answer equals both references; returns 0 when it does
ident(){
    local label="$1"; shift
    run "id.w" warm "$@"; run "id.n" novfs "$@"; run "id.c" nocache "$@"
    if [ "$( cat "$TMP/id.c.rc" )" != 0 ]; then
        no "$label: the --no-cache reference exited $( cat "$TMP/id.c.rc" )"
        printf '        stderr tail: %s\n' "$( tail -c 600 "$TMP/id.c.err" 2>/dev/null | tr '\n' ' ' )"   # an abort's reason, in the CI log
        return 1
    fi
    if same id.w id.c && same id.n id.c; then return 0; fi
    no "$label: served / no-verbfs / no-cache differ: $( diff "$TMP/id.w.out" "$TMP/id.c.out" | head -4 | tr '\n' ' ' )"
    return 1
}
recordOf(){ find "$TMP/t/ripwire" -name "ripwire-verbfs-*-$1-*.bin" 2>/dev/null | head -1; }

# ── prime: one racy run, leave the window, then the recording run ────────────────────────────────────────────────
run prime0 warm --grep=connection
sleep 3
statrun prime1 --grep=connection
GREC="$( recordOf grep )"
if [ -n "$GREC" ] && [ "$( field prime1 grep wrote )" = 1 ]; then ok "G1 the grep record is written once the fixture is out of the racy window ($( basename "$GREC" ))"
else no "G1 no grep record after the recording run (wrote=$( field prime1 grep wrote ), file='${GREC}'): $( grep '^\[verbfs\]' "$TMP/prime1.err" | head -3 | tr '\n' ' ' )"; fi

# ── G2: the counter ───────────────────────────────────────────────────────────────────────────────────────────────
statrun g2 --grep=unique_token_37
files="$( field g2 grep files )"; opened="$( field g2 grep opened )"; skipped="$( field g2 grep skipped )"; pre="$( field g2 grep prefilter )"
if [ "${pre:-}" = on ] && [ "${files:-0}" -gt 0 ] && [ "${opened:-999999}" -lt "${files:-0}" ] && [ "${skipped:-0}" -gt 0 ]; then
    ok "G2 a served --grep opens ${opened} of ${files} indexed files (skipped=${skipped})"
else
    no "G2 counter: prefilter='${pre:-absent}' files='${files:-absent}' opened='${opened:-absent}' skipped='${skipped:-absent}' (fec2ab27c has no [verbfs] line at all)"
fi
if grep -q 'unique_token_37' "$TMP/g2.out"; then ok "G2b the one file holding it is still found"; else no "G2b the hit is missing: $( head -c 300 "$TMP/g2.out" )"; fi

# ── G3: adversarial literals ─────────────────────────────────────────────────────────────────────────────────────
LITS=( 'connection idle timeout exceeded' 'Connection Idle' 'MixedCaseToken' 'mixedcasetoken' 'x->y' 'a::b' 'foo(bar' '50%' 'server.idle.limit'
       'naïve' 'café' '日' '日本語' "$( printf '\xa5' )" 'x' '%' '->' 'ab' 'a.*b' '[a-z]+' '(foo|bar)' '\d+' 'unique_token_37' 'fn_5' 'fn_'
       "$( printf ';\n}' )" ' idle ' "$( printf 'tabbed\t=' )" 'return total + scale' 'offset;' 'absent_literal_zz9' )
compared=0
for lit in "${LITS[@]}"; do
    if ident "G3 --grep=$( printf '%q' "$lit" )" --grep="$lit"; then compared=$(( compared + 1 )); fi
done
if [ "$compared" -eq "${#LITS[@]}" ]; then ok "G3 all ${compared} adversarial literals: served == no-verbfs == no-cache"; else no "G3 only ${compared} of ${#LITS[@]} literals were identical"; fi
statrun g3s --grep=ab
if [ "$( field g3s grep prefilter )" = off ] && [ "$( field g3s grep why )" = short ]; then ok "G3b a 2-byte literal falls back to the full scan, visibly (prefilter=off why=short)"
else no "G3b the short-literal fallback is not on the stats line: $( grep '^\[verbfs\] grep' "$TMP/g3s.err" | tail -1 )"; fi
statrun g3r --regex='unique_token_3[0-9]'
if [ "$( field g3r grep why )" = regex ] && ident "G3r --regex" --regex='unique_token_3[0-9]'; then ok "G3r --regex falls back (why=regex) and is identical"
else no "G3r regex fallback: $( grep '^\[verbfs\] grep' "$TMP/g3r.err" | tail -1 )"; fi

# ── G4: --for literal tasks ──────────────────────────────────────────────────────────────────────────────────────
TASKS=( 'where is "connection idle timeout exceeded" raised' 'what sets ERR_IDLE_TIMEOUT' 'who reads server.idle.limit'
        'connection idle timeout exceeded' 'how is the alpha sum computed' )
compared=0
for t in "${TASKS[@]}"; do
    if ident "G4 --for=$t" --for="$t"; then compared=$(( compared + 1 )); fi
done
statrun g4s --for="${TASKS[0]}"
if [ "$compared" -eq "${#TASKS[@]}" ] && [ -n "$( field g4s grep files )" ]; then ok "G4 ${compared} --for literal tasks identical, and the --for scan reports through the record ($( grep '^\[verbfs\] grep' "$TMP/g4s.err" | tail -1 ))"
else no "G4 ${compared} of ${#TASKS[@]} --for tasks identical; stats: $( grep '^\[verbfs\] grep' "$TMP/g4s.err" | tail -1 )"; fi

# ── G5: edited after the index ───────────────────────────────────────────────────────────────────────────────────
printf '/* appended_marker_q7 */\n' >>"$FIX/gen/file12.c"
statrun g5a --grep=appended_marker_q7
if ident "G5a appended inside the racy window" --grep=appended_marker_q7 && grep -q appended_marker_q7 "$TMP/id.w.out"; then ok "G5a a literal appended after the index is found (opened=$( field g5a grep opened ))"; else no "G5a the appended literal: $( head -c 200 "$TMP/id.w.out" )"; fi
cp -p "$FIX/gen/file20.c" "$TMP/ref20"
sed 's/unique_token_20/swappd_token_20/' "$TMP/ref20" >"$FIX/gen/file20.c"   # unique_token_20 -> swappd_token_20: same length
touch -r "$TMP/ref20" "$FIX/gen/file20.c"                                       # mtime put back: only ctime says it moved
if [ "$( wc -c <"$FIX/gen/file20.c" )" = "$( wc -c <"$TMP/ref20" )" ] && ident "G5b same-size edit, mtime restored" --grep=swappd_token_20 && grep -q swappd_token_20 "$TMP/id.w.out"; then
    ok "G5b a same-size edit whose mtime was put back is found"
else no "G5b same-size edit: $( head -c 200 "$TMP/id.w.out" )"; fi
cp -p "$FIX/gen/file30.c" "$TMP/new30"
sed 's/unique_token_30/renamed_token_30/' "$FIX/gen/file30.c" >"$TMP/new30b"; cat "$TMP/new30b" >"$TMP/new30"
touch -r "$FIX/gen/file30.c" "$TMP/new30"; mv "$TMP/new30" "$FIX/gen/file30.c"
if ident "G5c replaced by rename" --grep=renamed_token_30 && grep -q renamed_token_30 "$TMP/id.w.out"; then ok "G5c a file replaced by rename is found"; else no "G5c rename: $( head -c 200 "$TMP/id.w.out" )"; fi
sleep 3
statrun g5d --grep=swappd_token_20
if ident "G5d after the window" --grep=swappd_token_20 && grep -q swappd_token_20 "$TMP/id.w.out"; then ok "G5d the edits are still found once out of the racy window"; else no "G5d after the window"; fi

# ── G6: an old or damaged record ─────────────────────────────────────────────────────────────────────────────────
GREC="$( recordOf grep )"
if [ -n "$GREC" ]; then
    cp "$GREC" "$TMP/grec.good"
    python3 - "$GREC" <<'PY'
import sys
p = sys.argv[1]; b = bytearray(open(p, 'rb').read())
b[8] ^= 0x7f                                  # the version field (u32 after the 8-byte magic)
open(p, 'wb').write(bytes(b))
PY
    statrun g6v --grep=unique_token_37
    v1="$( field g6v grep why )"
    ident "G6v version" --grep=unique_token_37 && vi=1 || vi=0
    cp "$TMP/grec.good" "$GREC"
    python3 - "$GREC" <<'PY'
import sys, os
p = sys.argv[1]; b = bytearray(open(p, 'rb').read())
b[len(b) - 9] ^= 0x01                          # one payload byte near the end (a filter word)
open(p, 'wb').write(bytes(b))
PY
    statrun g6c --grep=unique_token_37
    c1="$( field g6c grep why )"
    ident "G6c checksum" --grep=unique_token_37 && ci=1 || ci=0
    statrun g6n --grep=unique_token_37
    if [ "$v1" = version ] && [ "$c1" = checksum ] && [ "$vi$ci" = 11 ] && [ "$( field g6n grep why )" = ok ]; then ok "G6 another version and a flipped payload byte are refused (why=version, why=checksum), the answer is unchanged, the next run reads a valid record"
    else no "G6 refusals: version why='$v1' identical=$vi, checksum why='$c1' identical=$ci, next why='$( field g6n grep why )'"; fi
else no "G6 no grep record to damage"; fi

# ── GM: mutation controls (the binary carries fault switches unless it is NDEBUG) ───────────────────────────────
RIPWIRE_FAULT_VERBFS_GREP_SKIPALL=1 statrun gmprobe --grep=connection
if [ "$( field gmprobe grep fault )" = skipall ]; then
    RIPWIRE_FAULT_VERBFS_GREP_SKIPALL=1 run gm1 warm --grep='connection idle timeout exceeded'; run gm1c nocache --grep='connection idle timeout exceeded'
    if ! same gm1 gm1c; then ok "GM1 skipping every recorded file turns the G3 identity red"; else no "GM1 the skip-all mutant still matched the reference: G3 cannot see a wrong skip"; fi
    printf '/* nostat_marker_k2 */\n' >>"$FIX/gen/file44.c"
    RIPWIRE_FAULT_VERBFS_GREP_NOSTAT=1 run gm2 warm --grep=nostat_marker_k2; run gm2c nocache --grep=nostat_marker_k2
    if ! same gm2 gm2c; then ok "GM2 trusting an entry whose signature moved turns the G5 identity red"; else no "GM2 the no-stat mutant still found the edit: G5 cannot see a stale entry"; fi
else
    printf '  INFO  GM this binary compiles fault switches out (NDEBUG); the mutation arms run on the plain-flavour leg\n'
fi

# ── clones ────────────────────────────────────────────────────────────────────────────────────────────────────────
statrun c0 --clones
statrun c1 --clones
if [ "$( field c1 clones served )" = 1 ]; then ok "C1 an unchanged warm run serves the clone groups from the record ($( grep '^\[verbfs\] clones' "$TMP/c1.err" | tail -1 ))"
else no "C1 counter: $( grep '^\[verbfs\] clones' "$TMP/c1.err" | tail -1 ) (fec2ab27c has no [verbfs] line)"; fi
cloneIdent(){   # LABEL [NAME] : --clones (NAME listed, when given) and a --for whose lens reads clone=, both against the references
    ident "$1 --clones" --clones || return 1
    if [ -n "${2:-}" ] && ! grep -q "$2" "$TMP/id.w.out"; then no "$1: $2 is not listed by --clones"; return 1; fi
    ident "$1 --for" --for='how is the alpha sum computed'
}
if cloneIdent C2 alpha_total; then ok "C2 nothing changed: identical"; fi
CLONEMUT=0
statrun c2probe --clones
RIPWIRE_FAULT_VERBFS_CLONE_ANYDIGEST=1 statrun c2fault --clones
[ "$( field c2fault clones fault )" = anydigest ] && CLONEMUT=1
cmut(){   # LABEL : the any-digest mutant must differ from --no-cache on this step
    [ "$CLONEMUT" = 1 ] || return 0
    run cm.c nocache --clones
    RIPWIRE_FAULT_VERBFS_CLONE_ANYDIGEST=1 run cm.w warm --clones
    if ! same cm.w cm.c; then ok "CM $1: serving any stored groups turns the identity red"; else no "CM $1: the any-digest mutant matched the reference: the arm cannot see a stale group"; fi
    run cm.fix warm --clones   # the honest binary rewrites the record for the state that now holds
}
cp "$FIX/src/beta.c" "$TMP/beta.orig"
printf 'int beta_acc( const int* values, int n, int limit, int scale, int offset )\n{\n    return n;\n}\n' >"$FIX/src/beta.c"
cmut "C3 a member edited"
if cloneIdent C3; then ok "C3 one member of the clone group edited: identical"; fi
printf 'int gamma_fold( const int* values, int n, int limit, int scale, int offset )\n%s\n' "$CLONEBODY" >"$FIX/src/gamma.c"
cmut "C4 a clone added"
if cloneIdent C4 gamma_fold; then ok "C4 a new clone added: identical, and it is listed"; fi
rm -f "$FIX/src/alpha.c"
cmut "C5 a member file deleted"
if cloneIdent C5; then ok "C5 a member file deleted: identical"; fi
[ "$CLONEMUT" = 1 ] || printf '  INFO  CM this binary compiles fault switches out (NDEBUG)\n'
printf 'int alpha_sum( const int* values, int n, int limit, int scale, int offset )\n%s\n\nint alpha_total( const int* values, int n, int limit, int scale, int offset )\n%s\n' "$CLONEBODY" "$CLONEBODY" >"$FIX/src/alpha.c"
cp "$TMP/beta.orig" "$FIX/src/beta.c"

# ── manifests ─────────────────────────────────────────────────────────────────────────────────────────────────────
MT='which package defines the gizmo module, the sprocket module, the flywheel module, the turbine module, the outsider module, the widgetkit name and the meterd target'
sleep 3
statrun m0 --for="$MT"
statrun m1 --for="$MT"
probes="$( field m1 dirs probes )"; live="$( field m1 dirs live )"; served="$( field m1 dirs served )"
if [ "${served:-0}" -gt 0 ] && [ "${live:-999999}" -lt "${probes:-0}" ] && grep -q 'acme/gizmo' "$TMP/m1.out"; then ok "M1 the manifest probe answers ${served} of ${probes} names from the record (live=${live}), and the gizmo module prints"
else no "M1 counter: probes='${probes:-absent}' served='${served:-absent}' live='${live:-absent}' gizmo=$( grep -c acme/gizmo "$TMP/m1.out" )"; fi
DIRSMUT=0
RIPWIRE_FAULT_VERBFS_DIRS_NOSTAT=1 statrun mprobe --for="$MT"
[ "$( field mprobe dirs fault )" = nostat ] && DIRSMUT=1
mstep(){   # LABEL EXPECT : identity after a kind change; EXPECT a string the answer must (or, with !, must not) hold
    local label="$1" expect="$2"
    if ident "$label" --for="$MT"; then
        case "$expect" in
            !*) if grep -q "${expect#!}" "$TMP/id.w.out"; then no "$label: '${expect#!}' still printed"; else ok "$label: identical, '${expect#!}' gone"; fi ;;
            *)  if grep -q "$expect" "$TMP/id.w.out"; then ok "$label: identical, '$expect' printed"; else no "$label: '$expect' missing"; fi ;;
        esac
    fi
}
mmut(){   # LABEL FAULT : the mutant (served under FAULT) must differ from --no-cache in the state that now holds
    [ "$DIRSMUT" = 1 ] || return 0
    run mm.c nocache --for="$MT"
    ( cd "$FIX" && env "$2=1" "$BIN" "$FIX" --cache="$TMP/c.bin" --for="$MT" </dev/null >"$TMP/mm.w.out" 2>/dev/null ); mmrc=$?
    # The mutant must RUN to an answer: a crash or refusal would also "differ", and the arm would pass on nothing.
    if [ "$mmrc" != 0 ]; then no "MM $1: the $2 mutant exited $mmrc, so its difference proves nothing"
    elif ! same mm.w mm.c; then ok "MM $1: $2 turns the identity red"; else no "MM $1: the $2 mutant matched the reference"; fi
}
mv "$FIX/pkg/go.mod" "$TMP/go.mod.saved"
mmut "M2 go.mod deleted" RIPWIRE_FAULT_VERBFS_DIRS_NOSTAT   # before the honest run: the record still says pkg/go.mod is a regular file
mstep "M2 go.mod deleted" '!acme/gizmo'
cp "$TMP/go.mod.saved" "$FIX/pkg/go.mod"
mstep "M3 go.mod created" 'acme/gizmo'
rm "$FIX/pkg/go.mod"; ln -s ../alt/sprocket.mod "$FIX/pkg/go.mod"
mstep "M4 regular -> symlink in the root" 'acme/sprocket'
rm "$FIX/pkg/go.mod"; ln -s ../alt/flywheel.mod "$FIX/pkg/go.mod"
mstep "M5 symlink retargeted" 'acme/flywheel'
sleep 3; run m5r warm --for="$MT"; run m5r2 warm --for="$MT"   # a record written while the link stands
printf 'module example.com/acme/turbine\n\ngo 1.22\n' >"$FIX/alt/flywheel.mod"
mstep "M6 the link's target edited (its own directory unchanged)" 'acme/turbine'
if [ "$DIRSMUT" = 1 ]; then
    # MM-links: a mutant that STORES a link's resolved kind (written out of the racy window), then the target goes away
    sleep 3
    rm -f "$( recordOf dirs )"   # the mutant must LEARN the link (an honest record would hand it Live and it would never resolve it)
    ( cd "$FIX" && RIPWIRE_FAULT_VERBFS_DIRS_LINKS=1 "$BIN" "$FIX" --cache="$TMP/c.bin" --for="$MT" </dev/null >/dev/null 2>&1 )
    ( cd "$FIX" && RIPWIRE_FAULT_VERBFS_DIRS_LINKS=1 "$BIN" "$FIX" --cache="$TMP/c.bin" --for="$MT" </dev/null >/dev/null 2>&1 )
    rm "$FIX/alt/flywheel.mod"; mkdir "$FIX/alt/flywheel.mod"   # the target becomes a directory: no read, no unread count
    mmut "M7 the link's target became a directory" RIPWIRE_FAULT_VERBFS_DIRS_LINKS
    rm -f "$( recordOf dirs )"   # the mutant's record is poisoned by design: the honest arms below start from none
else
    rm "$FIX/alt/flywheel.mod"; mkdir "$FIX/alt/flywheel.mod"
fi
mstep "M7 the link's target became a directory" '!acme/turbine'
rmdir "$FIX/alt/flywheel.mod"
mstep "M7b the target deleted (a dangling link)" '!acme/turbine'
rm "$FIX/pkg/go.mod"; mkdir "$FIX/pkg/go.mod"
mstep "M8 a directory at the name" '!acme/gizmo'
rmdir "$FIX/pkg/go.mod"; ln -s "$TMP/outside/go.mod" "$FIX/pkg/go.mod"
mstep "M9 a link out of the root" '!acme/outsider'
[ "$DIRSMUT" = 1 ] || printf '  INFO  MM this binary compiles fault switches out (NDEBUG)\n'

# ── KB: the BUILD that wrote a record ─────────────────────────────────────────────────────────────────────────────
# The producer identity names the sources only, so a dev and a Release build of one tree shared every record. The warm
# snapshot refuses the other build's file (warmsnap.h layoutKey, src/buildkey.h); a VERB-FS record is refused the same way
# (verbfs.h layoutKey folds kBuildKey), as why=shape. Needs the other flavour of THIS tree: RIPWIRE_BIN_OTHER=<path>.
# Premise: the two `--version` lines differ in the build type and in nothing else, so a refusal can only be the build's.
OTHER="${RIPWIRE_BIN_OTHER:-}"
[ -z "$OTHER" ] || [ "${OTHER#/}" != "$OTHER" ] || OTHER="$ROOT/$OTHER"
if [ -z "$OTHER" ]; then
    printf '  SKIP  KB needs the other build flavour of this tree: RIPWIRE_BIN_OTHER=<path> (a Release binary beside a dev one)\n'
elif [ ! -x "$OTHER" ]; then no "KB RIPWIRE_BIN_OTHER=$OTHER is not an executable"
else
    kver(){ "$1" --version 2>/dev/null | head -1; }
    kb_a="$( kver "$BIN" )"; kb_b="$( kver "$OTHER" )"
    kb_ta="$( printf '%s' "$kb_a" | sed -n 's/^[^(]*(\([^,]*\),.*/\1/p' )"; kb_tb="$( printf '%s' "$kb_b" | sed -n 's/^[^(]*(\([^,]*\),.*/\1/p' )"
    if [ -z "$kb_ta" ] || [ "$kb_ta" = "$kb_tb" ] || [ "${kb_a/"($kb_ta,"/(T,}" != "${kb_b/"($kb_tb,"/(T,}" ]; then
        no "KB premise: the two binaries must be one tree in two build types: '$kb_a' vs '$kb_b'"
    else
        ok "KB premise: one tree, two builds ($kb_ta / $kb_tb)"
        for kdir in fwd rev; do
            kr="$BIN"; ks="$OTHER"; [ "$kdir" = rev ] && { kr="$OTHER"; ks="$BIN"; }
            kc="$TMP/kb-$kdir.bin"
            for kp in 1 2; do ( cd "$FIX" && "$kr" "$FIX" --cache="$kc" --grep=connection </dev/null >/dev/null 2>&1 ); done
            ( cd "$FIX" && RIPWIRE_STATS=1 "$kr" "$FIX" --cache="$kc" --grep=connection </dev/null >"$TMP/kbp.out" 2>"$TMP/kbp.err" )
            if [ "$( field kbp grep why )" != ok ]; then no "KB ($kdir) VACUOUS: the recording build never served its own record (why='$( field kbp grep why )')"; continue; fi
            ( cd "$FIX" && RIPWIRE_STATS=1 "$ks" "$FIX" --cache="$kc" --grep=connection </dev/null >"$TMP/kbs.out" 2>"$TMP/kbs.err" ); echo $? >"$TMP/kbs.rc"
            ( cd "$FIX" && "$ks" "$FIX" --no-cache --grep=connection </dev/null >"$TMP/kbf.out" 2>/dev/null ); echo $? >"$TMP/kbf.rc"
            kw="$( field kbs grep why )"
            if [ "$kw" = shape ]; then ok "KB ($kdir) the other build refuses the record (why=shape)"; else no "KB ($kdir) the other build's record was not refused as another build's: why='${kw:-absent}'"; fi
            if same kbs kbf; then ok "KB ($kdir) ...and its answer == its own --no-cache"; else no "KB ($kdir) the answer differs from the serving build's --no-cache"; fi
        done
    fi
fi

# ── D: determinism ────────────────────────────────────────────────────────────────────────────────────────────────
run d1 warm --for="$MT"; run d2 warm --for="$MT"
if same d1 d2 && cmp -s "$TMP/d1.err" "$TMP/d2.err"; then ok "D two served calls are byte-identical"; else no "D the served answer is not deterministic"; fi

[ "$fail" = 0 ] && echo "verbfscheck: PASS" || echo "verbfscheck: FAIL"
exit "$fail"
