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
#       references
#   S3  a served adjacency prints the `[stats] header_static_adj` line its build prints (scope= is derived from the rows)
#   I1  EDIT (slotjoin input): c/table.h stops including row.h — t2.c no longer sees the header static: slot_by= goes
#   I2  EDIT (regindex input): a receiver renamed in py/db/__init__.py — the <reg> row lists the new name
#   I3  ADD A SYMBOL: a third receiver in a new file — n="3", flush_logs listed
#   I4  REMOVE ONE: close_caches and its connect deleted — n="2", close_caches gone
#   I5  A FLAG THAT CHANGES THE INDEX: --exclude=extra drops the flush_logs registration — n="1": no row at all
#       each of I1..I5: the stats line says served=0 why=key (built=1 wrote=1), the answer equals both references, and the
#       ANYKEY mutant (serve the newest stored entry whatever model it was built from) differs from --no-cache
#   I6  DAMAGED: one payload byte of the regindex record flipped — why=checksum, identity, and the next call is served again
#   I7  VERSION: the slotjoin record's header version bumped — why=version, identity, and the next call is served again
#   I8  FOREIGN: the regindex record copied over the slotjoin record's name (another part) — why=shape, identity
#       I6..I8 mutant: EMPTYREFUSED (a refused record answers as an EMPTY index instead of a rebuild) differs from --no-cache
#   E   an #include into another dialect (scope=all, the whole-corpus adjacency): served, same stats line, identical
#   K   RIPWIRE_NO_VERBFS=1: no `[verbfs] slotreg` line at all; --no-cache: none either
#   V   the plain build DASSERTs every served index equals a fresh build of the same IngestResult (the guard against a
#       pass that edits the model in place after ingest()); STALEROWS (served rows one site / one edge short) must abort
#   D   determinism: two served calls are byte-identical (stdout and stderr)   X  xmllint well-formed
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
# field TAG INDEX KEY : KEY= on the FIRST `[verbfs] slotreg index=INDEX` line of TAG (a --for builds the slot join's value
# index more than once; the first use is the one that reads the record file, the later ones read what the first left loaded)
field(){ grep "^\[verbfs\] slotreg index=$2 " "$TMP/$1.err" | head -1 | grep -oE "(^| )$3=[^ ]+" | head -1 | cut -d= -f2; }
line(){ grep "^\[verbfs\] slotreg index=$2 " "$TMP/$1.err" | head -1; }
same(){ cmp -s "$TMP/$1.out" "$TMP/$2.out" && cmp -s "$TMP/$1.rc" "$TMP/$2.rc"; }
# ident LABEL ARGS... : the served answer equals both references
ident(){
    local label="$1"; shift
    run "id.w" warm "$@"; run "id.n" novfs "$@"; run "id.c" nocache "$@"
    if [ "$( cat "$TMP/id.c.rc" )" != 0 ]; then no "$label: the --no-cache reference exited $( cat "$TMP/id.c.rc" )"; return 1; fi
    if same id.w id.c && same id.n id.c; then return 0; fi
    no "$label: served / no-verbfs / no-cache differ: $( diff "$TMP/id.w.out" "$TMP/id.c.out" | head -4 | tr '\n' ' ' )"
    return 1
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
ident "S2 registry question" --for="$QR" && s2=$(( s2 + 1 ))
ident "S2 slot question" --for="$QS" && s2=$(( s2 + 1 ))
ident "S2 --uses=row_cmp" --uses=row_cmp && s2=$(( s2 + 1 ))
if [ "$s2" = 3 ]; then ok "S2 three served answers equal no-verbfs and --no-cache"; fi

# ── S3: a served adjacency prints the stats line its build printed ───────────────────────────────────────────────
hsa(){ grep -F '[stats] header_static_adj' "$TMP/$1.err" | sort -u; }
( cd "$FIX" && RIPWIRE_STATS=1 "$BIN" "$FIX" --no-cache --for="$QS" </dev/null >/dev/null 2>"$TMP/s3c.err" )
if [ "$( field s1s slotjoin served )" = 1 ] && [ -n "$( hsa s3c )" ] && [ "$( hsa s1s )" = "$( hsa s3c )" ]; then ok "S3 the served adjacency's stats line equals the build's: $( hsa s3c )"
else no "S3 served '$( hsa s1s )' vs built '$( hsa s3c )'"; fi

# ── the mutants ───────────────────────────────────────────────────────────────────────────────────────────────────
MUT=0
RIPWIRE_FAULT_SLOTREG_ANYKEY=1 statrun mprobe --for="$QR"
[ "$( field mprobe regindex fault )" = anykey ] && MUT=1
# kmut LABEL ARGS... : the ANYKEY mutant, run BEFORE the honest call (the record still holds the previous state), must differ
kmut(){
    local label="$1"; shift
    [ "$MUT" = 1 ] || return 0
    run km.c nocache "$@"
    RIPWIRE_FAULT_SLOTREG_ANYKEY=1 run km.w warm "$@"
    if [ "$( cat "$TMP/km.w.rc" )" != 0 ]; then no "IM $label: the ANYKEY mutant exited $( cat "$TMP/km.w.rc" ) (a crash differs from anything: it proves nothing)"; return 0; fi
    if ! same km.w km.c; then ok "IM $label: serving a stale entry turns the identity red"; else no "IM $label: the ANYKEY mutant matched the reference: the arm cannot see a stale index"; fi
}
# rmut LABEL ARGS... : the EMPTYREFUSED mutant, on a record that is refused, must differ
rmut(){
    local label="$1"; shift
    [ "$MUT" = 1 ] || return 0
    run rm.c nocache "$@"
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
    ident "I6" --for="$QR" && ok "I6 identical after the refusal"
    statrun i6b --for="$QR"
    if [ "$( field i6b regindex served )" = 1 ]; then ok "I6 the refused record was rewritten: the next call is served"; else no "I6 not served after the rewrite: '$( line i6b regindex )'"; fi
    # I7: the header version bumped (u32 at byte 8)
    python3 - "$REC_S" <<'PY'
import struct, sys
p = sys.argv[1]; b = bytearray(open(p, 'rb').read()); v = struct.unpack_from('<I', b, 8)[0]; struct.pack_into('<I', b, 8, v + 1); open(p, 'wb').write(bytes(b))
PY
    rmut "I7 another format version" --for="$QS"
    statrun i7 --for="$QS"
    if [ "$( field i7 slotjoin served )" = 0 ] && [ "$( field i7 slotjoin why )" = version ]; then ok "I7 a record of another version is refused (why=version)"; else no "I7 expected why=version, got '$( line i7 slotjoin )'"; fi
    ident "I7" --for="$QS" && ok "I7 identical after the refusal"
    statrun i7b --for="$QS"
    if [ "$( field i7b slotjoin served )" = 1 ]; then ok "I7 the refused record was rewritten: the next call is served"; else no "I7 not served after the rewrite: '$( line i7b slotjoin )'"; fi
    # I8: a foreign record (the other part's bytes under this part's name)
    REC_R="$( recordOf regindex )"; REC_S="$( recordOf slotjoin )"
    cp "$REC_R" "$REC_S"
    rmut "I8 another part's record" --for="$QS"
    statrun i8 --for="$QS"
    if [ "$( field i8 slotjoin served )" = 0 ] && [ "$( field i8 slotjoin why )" = shape ]; then ok "I8 another part's record is refused (why=shape)"; else no "I8 expected why=shape, got '$( line i8 slotjoin )'"; fi
    ident "I8" --for="$QS" && ok "I8 identical after the refusal"
fi
[ "$MUT" = 1 ] || printf '  INFO  IM/RM this binary compiles fault switches out (NDEBUG); the mutation arms run on the plain-flavour leg\n'

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
( cd "$FIX" && RIPWIRE_STATS=1 RIPWIRE_NO_VERBFS=1 "$BIN" "$FIX" --cache="$TMP/n.bin" --for="$QR" </dev/null >/dev/null 2>"$TMP/k1.err" )
( cd "$FIX" && RIPWIRE_STATS=1 "$BIN" "$FIX" --no-cache --for="$QR" </dev/null >/dev/null 2>"$TMP/k2.err" )
if ! grep -q '^\[verbfs\] slotreg' "$TMP/k1.err" && ! grep -q '^\[verbfs\] slotreg' "$TMP/k2.err"; then ok "K RIPWIRE_NO_VERBFS=1 and --no-cache neither read nor write the record (no slotreg line)"
else no "K a slotreg line under the kill switch or --no-cache: $( grep -h '^\[verbfs\] slotreg' "$TMP/k1.err" "$TMP/k2.err" | head -2 | tr '\n' ' ' )"; fi

# ── V: the plain build proves every served index against a fresh build; an index that no longer matches the model fires ──
# What it stands for: a pass that edited the model IN PLACE after ingest() returned (same arrays, same sizes) would keep the noted
# identity and serve a stale index. Every served call of a plain-flavour run (every arm above) re-builds both indexes and DASSERTs
# equality; STALEROWS serves rows one site / one edge short, which is what such an edit would leave, and must abort the call.
VMUT=""
for q in "$QR" "$QS"; do
    RIPWIRE_FAULT_SLOTREG_STALEROWS=1 statrun v.p --for="$q"; RIPWIRE_FAULT_SLOTREG_STALEROWS=1 statrun v.r --for="$q"
    RIPWIRE_FAULT_SLOTREG_STALEROWS=1 statrun v --for="$q"
    if [ -z "$VMUT" ]; then grep -q 'fault=stalerows' "$TMP/v.p.err" "$TMP/v.r.err" "$TMP/v.err" && VMUT=1 || VMUT=0; fi
    if [ "$VMUT" = 0 ]; then printf '  INFO  V this binary compiles fault switches out (NDEBUG): the served-vs-fresh check is a plain-build check\n'; break; fi
    run v.h warm --for="$q"   # the same served call, honest: it answers (the check passes on an index that matches)
    # 133 = 128 + SIGTRAP: the DASSERT's trap (its banner goes to the render's captured stream, so the status is the signal)
    if [ "$( cat "$TMP/v.rc" )" = 133 ] && [ "$( cat "$TMP/v.h.rc" )" = 0 ]; then ok "V stale served rows trap the plain build (rc=133), the honest served call answers (rc=0)"
    else no "V a served index that differs from the model was not caught (mutant rc=$( cat "$TMP/v.rc" ), honest rc=$( cat "$TMP/v.h.rc" ))"; fi
done

# ── D, X ──────────────────────────────────────────────────────────────────────────────────────────────────────────
statrun d0 --for="$QR"; run d1 warm --for="$QR"; run d2 warm --for="$QR"   # RIPWIRE_STATS prints memory readings: the pair runs without it
if [ "$( field d0 regindex served )" = 1 ] && same d1 d2 && cmp -s "$TMP/d1.err" "$TMP/d2.err"; then ok "D two served calls are byte-identical (stdout and stderr)"; else no "D served calls differ (or were not served: '$( line d0 regindex )')"; fi
if command -v xmllint >/dev/null 2>&1; then
    if xmllint --noout "$TMP/d1.out" 2>/dev/null && xmllint --noout "$TMP/s1s.out" 2>/dev/null; then ok "X well-formed XML"; else no "X xmllint rejects a served answer"; fi
fi

[ "$fail" = 0 ] && echo "slotregcheck: PASS" || echo "slotregcheck: FAIL"
exit "$fail"
