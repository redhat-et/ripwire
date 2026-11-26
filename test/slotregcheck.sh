#!/usr/bin/env bash
# slotregcheck.sh — SLOTREG-PERSIST (src/verbfs_slotreg.h): the two query-independent indexes a served --for rebuilt on
# every call are kept per index in the VERB-FS record family (src/verbfs.h) and served while the model they were built
# from holds.
#
# THE COST (results/PHASESPLIT_1125, llvm-project, served warm --for, lane 5b d76c740fb): two splices of the compact route
# rebuilt a whole-index structure for every question —
#   rw::spliceSlotJoinRows (forslots.h)   324 ms   of which the C-family #include adjacency a header-static question walks
#                                                  (valuerefindex.h headerStaticVisibleFrom: header -> its includers) is
#                                                  the one query-independent piece (the value index itself is NARROW: it
#                                                  keeps the shown functions' values, so it is per question);
#   rw::spliceRegRows (regindex.h)        235 ms   RegIndex::build — every registry key, its sites and consumers, and the
#                                                  re-export names cut — none of which reads the question.
# Each is now served from `ripwire-verbfs-<rootKey>-{slotjoin,regindex}-<hex>.bin` when the IngestResult is the model the
# warm snapshot identifies (its tree key, options key and this build's source identity), and rebuilt as before otherwise.
#
# THE ARMS. Identity arms compare stdout (+ rc) of a served call against RIPWIRE_NO_VERBFS=1 (no record read or written)
# and --no-cache. An identity arm passes on code with no record at all, so every arm is paired with a COUNTER (the
# `[verbfs] slotreg` RIPWIRE_STATS line, which d76c740fb does not print: red there) and with a MUTATION run (a non-NDEBUG
# fault switch) that breaks the rule the arm relies on and must differ from --no-cache.
#   S1  COUNTER: a served --for serves both indexes (index=regindex served=1, index=slotjoin served=1); the premise: the
#       answers carry a <reg> row and slot_by=, so the served indexes are read
#   S2  IDENTITY: the registry question, the slot question and --uses=row_cmp (a full value index, same seam) equal both
#       references, and each of those three calls is itself a served hit (regindex / slotjoin / slotjoin served=1)
#   S3  a served adjacency prints the `[stats] header_static_adj` line its build prints (scope= is derived from the rows)
#   I1  EDIT (slotjoin input): c/table.h stops including row.h — t2.c no longer sees the header static: slot_by= goes
#   I2  EDIT (regindex input): a receiver renamed in py/db/__init__.py — the <reg> row lists the new name
#   I3  ADD A SYMBOL: a third receiver in a new file — n="3", flush_logs listed
#   I4  REMOVE ONE: close_caches and its connect deleted — n="2", close_caches gone
#   I5  A FLAG THAT CHANGES THE INDEX: --exclude=extra drops the flush_logs registration — n="1": no row at all
#       each of I1..I5: the stats line says served=0 why=key (built=1 wrote=1), the answer equals both references, and the
#       ANYKEY mutant (serve the newest stored entry whatever model it was built from) differs from --no-cache
#   I6  DAMAGED: one payload byte of the regindex record flipped — why=checksum, the very next call is served again, and the
#       refusal call's own answer equals both references
#   I7  VERSION: the slotjoin record's header version bumped — why=version, then the same two checks
#   I8  FOREIGN: the regindex record copied over the slotjoin record's name (another part) — why=shape, identity
#       I6..I8 mutant: EMPTYREFUSED (a refused record answers as an EMPTY index instead of a rebuild) differs from --no-cache
#   E   an #include into another dialect (scope=all, the whole-corpus adjacency): served, same stats line, identical
#   K   RIPWIRE_NO_VERBFS=1: no `[verbfs] slotreg` line at all; --no-cache: none either (both calls exit 0)
#   V   the plain build DASSERTs every served index equals a fresh build of the same IngestResult (the guard against a
#       pass that edits the model in place after ingest()); STALEROWS (served rows one site / one edge short) must abort.
#       Each arm is attributed to ONE check: the registry question never reaches the adjacency (no slotjoin line), and the
#       slot question runs on a C-only root with no registry key, so the registrar's check has no site to lose
#   D   determinism: two served calls are byte-identical (stdout and stderr), both exit 0, bracketed by two served hits on
#       the same cache key   X  xmllint well-formed
#
# The fault arms (IM, RM, V) run only where --version's build-type token says NDEBUG is off; there a fault switch that
# does not report itself is a FAIL, never a skip.
#
# Usage:  bash test/slotregcheck.sh [BIN]   |   RIPWIRE_BIN=asan/ripwire bash test/slotregcheck.sh

set -u
export RIPWIRE_NO_CORE_LEGEND=1 RIPWIRE_NO_ROWLINES=1   # the rows as elements (regsitecheck.sh's posture)
ROOT="$( cd "$( dirname "$0" )/.." && pwd )"
. "$ROOT/test/lib/clean-env.sh"
BIN="${1:-${RIPWIRE_BIN:-$ROOT/build/ripwire}}"
[ "${BIN#/}" = "$BIN" ] && BIN="$ROOT/$BIN"
fail=0
ok(){ printf '  PASS  %s\n' "$*" || { fail=1; printf '  FAIL  could not write the PASS line for: %s\n' "$*"; }; return 0; }
no(){ printf '  FAIL  %s\n' "$*"; fail=1; }

[ -x "$BIN" ] || { echo "no ripwire binary at $BIN — build first (cmake --build build -j)"; exit 2; }
command -v python3 >/dev/null 2>&1 || { echo "python3 required"; exit 2; }
echo "slotregcheck: BIN=$BIN"

TMP="$( mktemp -d )"; trap 'rm -rf "$TMP"' EXIT
FIX="$TMP/fix"
mkdir -p "$FIX/py/dispatch" "$FIX/py/core" "$FIX/py/db" "$FIX/py/http" "$FIX/py/tests" "$FIX/c" "$TMP/home" "$TMP/t"
export HOME="$TMP/home"
export TMPDIR="$TMP/t"
unset RIPWIRE_NO_VERBFS RIPWIRE_STATS RIPWIRE_NO_WARMSNAP RIPWIRE_NO_REG_ROWS RIPWIRE_NO_SLOT_JOIN_ROWS RIPWIRE_SLOT_INDEX_FULL

# ── the fixture: regsitecheck.sh P1's signal registry beside headerstaticadjcheck.sh's header static ─────────────────
cat >"$FIX/py/dispatch/dispatcher.py" <<'EOF'
class Signal:
    def __init__(self):
        self.receivers = []

    def connect(self, receiver, sender=None, weak=True, dispatch_uid=None):
        lookup_key = (id(receiver), id(sender))
        self.receivers.append((lookup_key, receiver, sender))

    def send(self, sender, **named):
        return [r(sender) for _, r, _ in self.receivers]
EOF
printf 'from dispatch.dispatcher import Signal\n' >"$FIX/py/dispatch/__init__.py"
printf 'from dispatch import Signal\n\nrequest_finished = Signal()\n' >"$FIX/py/core/signals.py"
printf 'from core import signals\n\ndef close_old_connections(**kwargs):\n    pass\n\nsignals.request_finished.connect(close_old_connections)\n' >"$FIX/py/db/__init__.py"
printf 'from core.signals import request_finished\n\ndef close_caches(**kwargs):\n    pass\n\nrequest_finished.connect(close_caches)\n' >"$FIX/py/core/cache.py"
printf 'from core import signals\n\nclass HttpResponseBase:\n    def close(self):\n        signals.request_finished.send(sender=self)\n' >"$FIX/py/http/response.py"
printf 'from core.signals import request_finished\n\ndef on_done(**kw):\n    pass\n\nrequest_finished.connect(on_done)\n' >"$FIX/py/tests/test_client.py"
printf '#ifndef ROW_H\n#define ROW_H\nstatic inline int row_cmp(const void *a, const void *b) { return a == b; }\n#endif\n' >"$FIX/c/row.h"
printf 'int vec_index(void *v, void *x, int (*cmp)(const void *, const void *));\n' >"$FIX/c/vec.h"
printf '#include "vec.h"\nint vec_index(void *v, void *x, int (*cmp)(const void *, const void *)) { return cmp(v, x); }\n' >"$FIX/c/vec.c"
printf '#include "row.h"\n' >"$FIX/c/table.h"
printf '#include "table.h"\n#include "vec.h"\nint t2(void *v, void *x) { return vec_index(v, x, row_cmp); }\n' >"$FIX/c/t2.c"
QR='which receivers run when request_finished is sent'
QS='how does row_cmp compare rows'

# ── runners (verbfscheck.sh's) ──────────────────────────────────────────────────────────────────────────────────────
# run TAG MODE ARGS... : warm = the served path (--cache=C); novfs = RIPWIRE_NO_VERBFS=1 (its own cache: the variable is
# keyed into the snapshot's options); nocache = --no-cache. stdout/stderr/rc into $TMP/TAG.{out,err,rc}.
# RUNROOT / RUNCACHE pick another root and its own cache files (V's C-only root).
run(){
    local tag="$1" mode="$2"; shift 2
    local root="${RUNROOT:-$FIX}" cb="${RUNCACHE:-}"
    case "$mode" in
        warm)    ( cd "$root" && "$BIN" "$root" --cache="$TMP/c$cb.bin" "$@" </dev/null >"$TMP/$tag.out" 2>"$TMP/$tag.err" ) ;;
        novfs)   ( cd "$root" && RIPWIRE_NO_VERBFS=1 "$BIN" "$root" --cache="$TMP/n$cb.bin" "$@" </dev/null >"$TMP/$tag.out" 2>"$TMP/$tag.err" ) ;;
        nocache) ( cd "$root" && "$BIN" "$root" --no-cache "$@" </dev/null >"$TMP/$tag.out" 2>"$TMP/$tag.err" ) ;;
    esac
    echo $? >"$TMP/$tag.rc"
}
statrun(){ local tag="$1"; shift; RIPWIRE_STATS=1 run "$tag" warm "$@"; }
# field TAG INDEX KEY : KEY= on the FIRST `[verbfs] slotreg index=INDEX` line of TAG (a --for builds the slot join's value
# index more than once; the first use is the one that reads the record file, the later ones read what the first left loaded)
field(){ grep "^\[verbfs\] slotreg index=$2 " "$TMP/$1.err" | head -1 | grep -oE "(^| )$3=[^ ]+" | head -1 | cut -d= -f2; }
line(){ grep "^\[verbfs\] slotreg index=$2 " "$TMP/$1.err" | head -1; }
same(){ cmp -s "$TMP/$1.out" "$TMP/$2.out" && cmp -s "$TMP/$1.rc" "$TMP/$2.rc"; }
# identOf TAG LABEL ARGS... : the answer of the warm call TAG, already run, equals both references
identOf(){
    local tag="$1" label="$2"; shift 2
    run "id.n" novfs "$@"; run "id.c" nocache "$@"
    if [ "$( cat "$TMP/id.c.rc" )" != 0 ]; then no "$label: the --no-cache reference exited $( cat "$TMP/id.c.rc" )"; return 1; fi
    if same "$tag" id.c && same id.n id.c; then return 0; fi
    no "$label: served / no-verbfs / no-cache differ: $( diff "$TMP/$tag.out" "$TMP/id.c.out" | head -4 | tr '\n' ' ' )"
    return 1
}
# ident LABEL ARGS... : a fresh warm call's answer equals both references
ident(){
    local label="$1"; shift
    run "id.w" warm "$@"
    identOf id.w "$label" "$@"
}
# identServed LABEL INDEX ARGS... : ident, on a warm call that is itself a served hit of INDEX (its own stats line)
identServed(){
    local label="$1" index="$2"; shift 2
    statrun "id.w" "$@"
    if [ "$( field id.w "$index" served )" != 1 ]; then no "$label: the compared call is not a served $index hit: '$( line id.w "$index" )'"; return 1; fi
    identOf id.w "$label" "$@"
}
recordOf(){ find "$TMP/t/ripwire" -name "ripwire-verbfs-*-$1-*.bin" 2>/dev/null | head -1; }
regRow(){ grep -o '<reg [^>]*>' "$TMP/$1.out" | head -1; }

# ── prime: out of the racy window, then a recording run per question ─────────────────────────────────────────────
sleep 3
run prime0 warm --for="$QR"
run prime1 warm --for="$QS"

# ── S1: the counter, and the premise ─────────────────────────────────────────────────────────────────────────────
statrun s1r --for="$QR"
statrun s1s --for="$QS"
if [ "$( field s1r regindex served )" = 1 ] && [ "$( field s1s slotjoin served )" = 1 ]; then
    ok "S1 a served --for serves both indexes: $( line s1r regindex ) / $( line s1s slotjoin )"
else
    no "S1 counter: regindex='$( line s1r regindex )' slotjoin='$( line s1s slotjoin )' (d76c740fb prints no [verbfs] slotreg line)"
fi
if regRow s1r | grep -q 'n="2"' && grep -q 'slot_by="*vec_index' "$TMP/s1s.out"; then ok "S1b the premise: the served answers carry the <reg> row (n=2) and slot_by=vec_index"
else no "S1b premise: reg='$( regRow s1r )' slot_by=$( grep -c 'slot_by' "$TMP/s1s.out" )"; fi

# ── S2: identity, nothing changed ─────────────────────────────────────────────────────────────────────────────────
s2=0
identServed "S2 registry question" regindex --for="$QR" && s2=$(( s2 + 1 ))
identServed "S2 slot question" slotjoin --for="$QS" && s2=$(( s2 + 1 ))
identServed "S2 --uses=row_cmp" slotjoin --uses=row_cmp && s2=$(( s2 + 1 ))
if [ "$s2" = 3 ]; then ok "S2 three served hits (regindex, slotjoin, slotjoin) equal no-verbfs and --no-cache"; fi

# ── S3: a served adjacency prints the stats line its build printed ───────────────────────────────────────────────
hsa(){ grep -F '[stats] header_static_adj' "$TMP/$1.err" | sort -u; }
( cd "$FIX" && RIPWIRE_STATS=1 "$BIN" "$FIX" --no-cache --for="$QS" </dev/null >/dev/null 2>"$TMP/s3c.err" )
if [ "$( field s1s slotjoin served )" = 1 ] && [ -n "$( hsa s3c )" ] && [ "$( hsa s1s )" = "$( hsa s3c )" ]; then ok "S3 the served adjacency's stats line equals the build's: $( hsa s3c )"
else no "S3 served '$( hsa s1s )' vs built '$( hsa s3c )'"; fi

# ── the mutants ───────────────────────────────────────────────────────────────────────────────────────────────────
# Whether the fault switches exist is the build's NDEBUG, read from --version's build-type token (CMakeLists defines NDEBUG
# for Release / RelWithDebInfo / MinSizeRel and nothing else) — never from the switch's own silence, which would let a plain
# build that stopped honouring a switch skip the arm it guards.
FLAVOUR="$( "$BIN" --version 2>/dev/null | sed -nE 's/^[^(]*\(([^,)]*).*/\1/p' )"
case "$FLAVOUR" in
    Release|RelWithDebInfo|MinSizeRel) MUT=0 ;;
    *) MUT=1 ;;
esac
if [ "$MUT" = 1 ]; then
    RIPWIRE_FAULT_SLOTREG_ANYKEY=1 statrun mprobe --for="$QR"
    if [ "$( field mprobe regindex fault )" = anykey ]; then ok "M this '${FLAVOUR:-unknown}' (non-NDEBUG) build honours the fault switches (fault=anykey reported)"
    else no "M this '${FLAVOUR:-unknown}' build is not NDEBUG, yet the ANYKEY switch is not reported: '$( line mprobe regindex )'"; fi
fi
# kmut LABEL ARGS... : the ANYKEY mutant, run BEFORE the honest call (the record still holds the previous state), must differ
kmut(){
    local label="$1"; shift
    [ "$MUT" = 1 ] || return 0
    run km.c nocache "$@"
    if [ "$( cat "$TMP/km.c.rc" )" != 0 ]; then no "IM $label: the --no-cache reference exited $( cat "$TMP/km.c.rc" ) (a failed oracle differs from anything)"; return 0; fi
    RIPWIRE_FAULT_SLOTREG_ANYKEY=1 run km.w warm "$@"
    if [ "$( cat "$TMP/km.w.rc" )" != 0 ]; then no "IM $label: the ANYKEY mutant exited $( cat "$TMP/km.w.rc" ) (a crash differs from anything: it proves nothing)"; return 0; fi
    if ! same km.w km.c; then ok "IM $label: serving a stale entry turns the identity red"; else no "IM $label: the ANYKEY mutant matched the reference: the arm cannot see a stale index"; fi
}
# rmut LABEL ARGS... : the EMPTYREFUSED mutant, on a record that is refused, must differ
rmut(){
    local label="$1"; shift
    [ "$MUT" = 1 ] || return 0
    run rm.c nocache "$@"
    if [ "$( cat "$TMP/rm.c.rc" )" != 0 ]; then no "RM $label: the --no-cache reference exited $( cat "$TMP/rm.c.rc" ) (a failed oracle differs from anything)"; return 0; fi
    RIPWIRE_FAULT_SLOTREG_EMPTYREFUSED=1 run rm.w warm "$@"
    if [ "$( cat "$TMP/rm.w.rc" )" != 0 ]; then no "RM $label: the EMPTYREFUSED mutant exited $( cat "$TMP/rm.w.rc" ) (a crash differs from anything: it proves nothing)"; return 0; fi
    if ! same rm.w rm.c; then ok "RM $label: answering a refused record as empty turns the identity red"; else no "RM $label: the EMPTYREFUSED mutant matched the reference"; fi
}
# invalidated LABEL INDEX TAG : the honest calls after a change rebuilt. TAG.p, the first, is never served (if it re-parsed the
# edited file the model has no snapshot identity yet, why=model and nothing written; if the parse cache already holds it, the
# stored entry is another model's, why=key). One of TAG.p / TAG then refuses the stored entry as another model's (why=key)
# and writes the fresh one.
invalidated(){
    local keyed=""
    for t in "$3.p" "$3"; do
        if [ -z "$keyed" ] && [ "$( field "$t" "$2" why )" = key ] && [ "$( field "$t" "$2" built )" = 1 ] && [ "$( field "$t" "$2" wrote )" = 1 ]; then keyed="$t"; fi
    done
    if [ "$( field "$3.p" "$2" served )" = 0 ] && [ "$( field "$3.p" "$2" built )" = 1 ] && [ -n "$keyed" ]; then
        ok "$1: the stored $2 index is not served after the change (first call why=$( field "$3.p" "$2" why )) and is rebuilt (why=key wrote=1)"
    else
        no "$1: expected a first call served=0 built=1, then why=key built=1 wrote=1; got '$( line "$3.p" "$2" )' / '$( line "$3" "$2" )'"
    fi
}

# ── I1: an edit to a slotjoin input ───────────────────────────────────────────────────────────────────────────────
printf '#define TABLE_ROWS 1\n' >"$FIX/c/table.h"
kmut "I1 table.h stops including row.h" --for="$QS"
statrun i1.p --for="$QS"; statrun i1 --for="$QS"
invalidated "I1 table.h edited" slotjoin i1
if ident "I1" --for="$QS"; then
    if grep -q 'slot_by' "$TMP/id.w.out"; then no "I1 slot_by= still printed after the include went"; else ok "I1 identical, slot_by= gone with the include"; fi
fi
printf '#include "row.h"\n' >"$FIX/c/table.h"
run i1back warm --for="$QS"

# ── I2: an edit to a regindex input ───────────────────────────────────────────────────────────────────────────────
printf 'from core import signals\n\ndef close_db_connections(**kwargs):\n    pass\n\nsignals.request_finished.connect(close_db_connections)\n' >"$FIX/py/db/__init__.py"
kmut "I2 a receiver renamed" --for="$QR"
statrun i2.p --for="$QR"; statrun i2 --for="$QR"
invalidated "I2 db/__init__.py edited" regindex i2
if ident "I2" --for="$QR"; then
    if grep -q 'close_db_connections' "$TMP/id.w.out" && ! grep -q 'sym="close_old_connections"' "$TMP/id.w.out"; then ok "I2 identical, the renamed receiver is listed"; else no "I2 the renamed receiver is not listed: $( regRow id.w )"; fi
fi

# ── I3: add a symbol ──────────────────────────────────────────────────────────────────────────────────────────────
mkdir -p "$FIX/py/extra"
printf 'from core.signals import request_finished\n\ndef flush_logs(**kwargs):\n    pass\n\nrequest_finished.connect(flush_logs)\n' >"$FIX/py/extra/flush.py"
kmut "I3 a receiver added" --for="$QR"
statrun i3.p --for="$QR"; statrun i3 --for="$QR"
invalidated "I3 a receiver added" regindex i3
if ident "I3" --for="$QR"; then
    if regRow id.w | grep -q 'n="3"' && grep -q 'flush_logs' "$TMP/id.w.out"; then ok "I3 identical, n=3 and flush_logs listed"; else no "I3 expected n=3 with flush_logs: $( regRow id.w )"; fi
fi

# ── I4: remove one ────────────────────────────────────────────────────────────────────────────────────────────────
rm -f "$FIX/py/core/cache.py"
kmut "I4 a receiver removed" --for="$QR"
statrun i4.p --for="$QR"; statrun i4 --for="$QR"
invalidated "I4 a receiver removed" regindex i4
if ident "I4" --for="$QR"; then
    if regRow id.w | grep -q 'n="2"' && ! grep -q 'close_caches' "$TMP/id.w.out"; then ok "I4 identical, n=2 and close_caches gone"; else no "I4 expected n=2 without close_caches: $( regRow id.w )"; fi
fi

# ── I5: a flag that changes the index ─────────────────────────────────────────────────────────────────────────────
kmut "I5 --exclude=extra" --for="$QR" --exclude=extra
statrun i5.p --for="$QR" --exclude=extra; run i5.r warm --for="$QR" --exclude=extra; statrun i5 --for="$QR" --exclude=extra
if [ "$( field i5.p regindex served )" = 0 ] && [ "$( field i5.p regindex built )" = 1 ]; then ok "I5 --exclude=extra: the stored regindex is not served under the new flag ($( line i5.p regindex ))"
else no "I5 --exclude=extra: expected served=0 built=1 on the first call under the flag, got '$( line i5.p regindex )'"; fi
if [ "$( field i5 regindex served )" = 1 ]; then ok "I5 the flag's own entry is served on its next call (the plain run's entry kept beside it)"
else no "I5 the flag's own entry is not served on its next call: '$( line i5 regindex )'"; fi
if ident "I5" --for="$QR" --exclude=extra; then
    if grep -q '<reg ' "$TMP/id.w.out"; then no "I5 a <reg> row printed with one registration left: $( regRow id.w )"; else ok "I5 identical, no <reg> row (one registration left)"; fi
fi
run i5back warm --for="$QR"

# ── I6..I8: damaged, version-mismatched, foreign records ─────────────────────────────────────────────────────────
REC_R="$( recordOf regindex )"; REC_S="$( recordOf slotjoin )"
if [ -z "$REC_R" ] || [ -z "$REC_S" ]; then no "I6 no records to damage (regindex='$REC_R' slotjoin='$REC_S')"; else
    # I6: one payload byte flipped (the checksum is not repaired)
    python3 - "$REC_R" <<'PY'
import sys
p = sys.argv[1]; b = bytearray(open(p, 'rb').read()); b[len(b) - 1] ^= 0x5a; open(p, 'wb').write(bytes(b))
PY
    rmut "I6 a flipped payload byte" --for="$QR"
    statrun i6 --for="$QR"
    if [ "$( field i6 regindex served )" = 0 ] && [ "$( field i6 regindex why )" = checksum ]; then ok "I6 a flipped payload byte is refused (why=checksum)"; else no "I6 expected why=checksum, got '$( line i6 regindex )'"; fi
    statrun i6b --for="$QR"   # the very next call: only the refusal call can have rewritten the record
    if [ "$( field i6b regindex served )" = 1 ]; then ok "I6 the refused record was rewritten: the next call is served"; else no "I6 not served after the rewrite: '$( line i6b regindex )'"; fi
    identOf i6 "I6" --for="$QR" && ok "I6 the refusal call's answer equals both references"
    # I7: the header version bumped (u32 at byte 8)
    python3 - "$REC_S" <<'PY'
import struct, sys
p = sys.argv[1]; b = bytearray(open(p, 'rb').read()); v = struct.unpack_from('<I', b, 8)[0]; struct.pack_into('<I', b, 8, v + 1); open(p, 'wb').write(bytes(b))
PY
    rmut "I7 another format version" --for="$QS"
    statrun i7 --for="$QS"
    if [ "$( field i7 slotjoin served )" = 0 ] && [ "$( field i7 slotjoin why )" = version ]; then ok "I7 a record of another version is refused (why=version)"; else no "I7 expected why=version, got '$( line i7 slotjoin )'"; fi
    statrun i7b --for="$QS"   # the very next call: only the refusal call can have rewritten the record
    if [ "$( field i7b slotjoin served )" = 1 ]; then ok "I7 the refused record was rewritten: the next call is served"; else no "I7 not served after the rewrite: '$( line i7b slotjoin )'"; fi
    identOf i7 "I7" --for="$QS" && ok "I7 the refusal call's answer equals both references"
    # I8: a foreign record (the other part's bytes under this part's name)
    REC_R="$( recordOf regindex )"; REC_S="$( recordOf slotjoin )"
    cp "$REC_R" "$REC_S"
    rmut "I8 another part's record" --for="$QS"
    statrun i8 --for="$QS"
    if [ "$( field i8 slotjoin served )" = 0 ] && [ "$( field i8 slotjoin why )" = shape ]; then ok "I8 another part's record is refused (why=shape)"; else no "I8 expected why=shape, got '$( line i8 slotjoin )'"; fi
    ident "I8" --for="$QS" && ok "I8 identical after the refusal"
fi
[ "$MUT" = 1 ] || printf '  INFO  IM/RM this %s build defines NDEBUG (fault switches compiled out); the mutation arms run on the plain-flavour leg\n' "$FLAVOUR"

# ── E: an include into another dialect widens the build to the whole corpus; served, it still says so ─────────────
printf '#include "../py/core/signals.py"\n#include "table.h"\nint t5(void *v, void *x) { return vec_index(v, x, row_cmp); }\n' >"$FIX/c/gen.c"
run e0 warm --for="$QS"; run e0b warm --for="$QS"; statrun e1 --for="$QS"   # a new file is parsed, then recorded, then served
( cd "$FIX" && RIPWIRE_STATS=1 "$BIN" "$FIX" --no-cache --for="$QS" </dev/null >/dev/null 2>"$TMP/e1c.err" )
if [ "$( field e1 slotjoin served )" = 1 ] && hsa e1c | grep -q 'scope=all' && [ "$( hsa e1 )" = "$( hsa e1c )" ]; then ok "E an escaping include is served with its scope=all line: $( hsa e1 )"
else no "E escape: served='$( line e1 slotjoin )' '$( hsa e1 )' vs built '$( hsa e1c )'"; fi
ident "E" --for="$QS" && ok "E identical with the whole-corpus adjacency served"
rm -f "$FIX/c/gen.c"
run eback warm --for="$QR"; run eback2 warm --for="$QR"

# ── K: the kill switch and --no-cache print no slotreg line ──────────────────────────────────────────────────────
( cd "$FIX" && RIPWIRE_STATS=1 RIPWIRE_NO_VERBFS=1 "$BIN" "$FIX" --cache="$TMP/n.bin" --for="$QR" </dev/null >/dev/null 2>"$TMP/k1.err" ); k1rc=$?
( cd "$FIX" && RIPWIRE_STATS=1 "$BIN" "$FIX" --no-cache --for="$QR" </dev/null >/dev/null 2>"$TMP/k2.err" ); k2rc=$?
if [ "$k1rc" != 0 ] || [ "$k2rc" != 0 ]; then no "K a disabled call failed before SLOTREG could run (kill switch rc=$k1rc, --no-cache rc=$k2rc): its silence proves nothing"
elif ! grep -q '^\[verbfs\] slotreg' "$TMP/k1.err" && ! grep -q '^\[verbfs\] slotreg' "$TMP/k2.err"; then ok "K RIPWIRE_NO_VERBFS=1 and --no-cache neither read nor write the record (no slotreg line)"
else no "K a slotreg line under the kill switch or --no-cache: $( grep -h '^\[verbfs\] slotreg' "$TMP/k1.err" "$TMP/k2.err" | head -2 | tr '\n' ' ' )"; fi

# ── V: the plain build proves every served index against a fresh build; an index that no longer matches the model fires ──
# What it stands for: a pass that edited the model IN PLACE after ingest() returned (same arrays, same sizes) would keep the noted
# identity and serve a stale index. Every served call of a plain-flavour run (every arm above) re-builds both indexes and DASSERTs
# equality; STALEROWS serves rows one site / one edge short, which is what such an edit would leave, and must abort the call.
# The DASSERT's trap is __builtin_trap: `brk` on arm64 (SIGTRAP, 128+5=133), `ud2` on x86-64 (SIGILL, 128+4=132). Its banner
# goes to the render's captured stream, so the status is the signal; any other status (a crash, an exit) is not this check.
# Both checks run in one compact --for, so each arm is placed where only ONE of them can see a short row:
#   registrar  the registry question on the fixture; its honest call prints no slotjoin line (the adjacency is not reached)
#   adjacency  the slot question on a C-only root: no registry key (keys=0), so STALEROWS has no registrar site to drop
FIXC="$TMP/fixc"; mkdir -p "$FIXC/c"; cp "$FIX"/c/row.h "$FIX"/c/vec.h "$FIX"/c/vec.c "$FIX"/c/table.h "$FIX"/c/t2.c "$FIXC/c/"
# varm LABEL INDEX OTHER ARGS... : STALEROWS on a served INDEX traps; the honest served call answers, and OTHER is not in play.
# The arm runs only on a non-NDEBUG build, and there it demands the trap: a switch that stopped working is a FAIL, not a skip.
# (No fault= marker is asked for: the slot question uses the adjacency twice per call, the second use is served from what the
# first left loaded, so every STALEROWS call traps before the render's captured stderr is written.)
varm(){
    local label="$1" index="$2" other="$3"; shift 3
    run v.h0 warm "$@"; run v.h1 warm "$@"; statrun v.h "$@"
    RIPWIRE_FAULT_SLOTREG_STALEROWS=1 statrun v.p "$@"; RIPWIRE_FAULT_SLOTREG_STALEROWS=1 statrun v.r "$@"
    RIPWIRE_FAULT_SLOTREG_STALEROWS=1 statrun v "$@"
    local vrc hrc; vrc="$( cat "$TMP/v.rc" )"; hrc="$( cat "$TMP/v.h.rc" )"
    if [ "$hrc" != 0 ] || [ "$( field v.h "$index" served )" != 1 ]; then no "V $label: the honest call is not a served $index hit (rc=$hrc, '$( line v.h "$index" )')"; return 0; fi
    case "$other" in
        noslotjoin) if [ -n "$( line v.h slotjoin )" ]; then no "V $label: the adjacency is in play too ('$( line v.h slotjoin )'): the trap is not the registrar's alone"; return 0; fi ;;
        nokeys)     local k; k="$( field v.h regindex keys )"; if [ -n "$k" ] && [ "$k" != 0 ]; then no "V $label: the registrar has keys here ('$( line v.h regindex )'): the trap is not the adjacency's alone"; return 0; fi ;;
    esac
    if [ "$vrc" = 133 ] || [ "$vrc" = 132 ]; then ok "V $label: stale served rows trap the plain build (rc=$vrc); the honest served call answers (rc=0, served=1)"
    else no "V $label: a served index that differs from the model was not caught (mutant rc=$vrc)"; fi
}
case "$FLAVOUR" in
    Release|RelWithDebInfo|MinSizeRel)
        printf '  INFO  V this %s build defines NDEBUG: the served-vs-fresh check is a plain-build check\n' "$FLAVOUR" ;;
    *)
        varm "registrar" regindex noslotjoin --for="$QR"
        RUNROOT="$FIXC" RUNCACHE=v varm "adjacency" slotjoin nokeys --for="$QS" ;;
esac

# ── D, X ──────────────────────────────────────────────────────────────────────────────────────────────────────────
# One honest call first. Every RIPWIRE_* variable is in the options key, so V's fault-switch calls recorded entries of their
# own and (a record keeps two) pushed the honest one out. D is about two SERVED calls, so it re-records the honest entry first.
# RIPWIRE_STATS prints memory readings, so the compared pair runs without it; RIPWIRE_STATS is an observer the options key
# leaves out (warmsnap.h kObservers), so d0, d1, d2 and d3 share one cache key, and the served hits d0 and d3 bracket the pair.
run d_rec warm --for="$QR"
statrun d0 --for="$QR"; run d1 warm --for="$QR"; run d2 warm --for="$QR"; statrun d3 --for="$QR"
if [ "$( cat "$TMP/d1.rc" )" != 0 ] || [ "$( cat "$TMP/d2.rc" )" != 0 ]; then no "D a compared call failed (rc=$( cat "$TMP/d1.rc" ) / $( cat "$TMP/d2.rc" )): two equal failures prove nothing"
elif [ "$( field d0 regindex served )" != 1 ] || [ "$( field d3 regindex served )" != 1 ]; then no "D the pair is not bracketed by served hits: '$( line d0 regindex )' / '$( line d3 regindex )'"
elif same d1 d2 && cmp -s "$TMP/d1.err" "$TMP/d2.err"; then ok "D two served calls are byte-identical (stdout and stderr, rc=0)"
else no "D served calls differ"; fi
if command -v xmllint >/dev/null 2>&1; then
    if xmllint --noout "$TMP/d1.out" 2>/dev/null && xmllint --noout "$TMP/s1s.out" 2>/dev/null; then ok "X well-formed XML"; else no "X xmllint rejects a served answer"; fi
fi

[ "$fail" = 0 ] && echo "slotregcheck: PASS" || echo "slotregcheck: FAIL"
exit "$fail"
