#!/usr/bin/env bash
# editplanpayloadconfinecheck.sh — A5: an edit plan may only read payloads that sit beside it, and the
# dry-run receipt shows which bytes each operation will read. Plus A7: a QUOTED version is not numeric 1.
#
# THE BUG THIS GATE PINS (A5). editplan::siblingPath returned the payload verbatim when it was absolute, and
# otherwise joined it to the plan's directory with no normalization. So a plan could say
#
#   {"op":"replace_symbol_body","target":"alpha","payload":"../../../../etc/hosts"}
#
# and that file's bytes were spliced into a source file, reported as an ordinary success. This is a READ
# escape only — no write ever lands outside the crawl root, which is why it is LOW and not a write hole —
# but a plan arriving from a shared repo, a PR, or another agent could quietly bake a secret into a file the
# next commit publishes. And the --dry-run receipt, the thing a human reads BEFORE --apply, named the op,
# the target and the file, but never the payload, so the review could not have caught it either.
#
# ARMS:
#   1. a "../" escape refuses, and the message names the path it actually RESOLVED (not the spelling the
#      plan wrote, which is the whole point — the spelling is what disguised it).
#   2. an ABSOLUTE payload path refuses.
#   3. a SYMLINK sitting inside the plan directory but pointing out of it refuses — the case a purely
#      lexical check would wave through.
#   4. a NON-EXISTENT escape refuses as an escape, not as a mere read failure — the case realpath cannot
#      judge, so a purely realpath-based check would mis-report it.
#   5. an ordinary payload beside the plan still works, under BOTH a relative and an absolute plan path
#      (the symlinked-prefix false positive: /tmp vs /private/tmp must not read as an escape).
#   6. the dry-run receipt carries payload_path for every operation.
#   7. every refusal leaves the corpus byte-identical, and no secret byte reaches it.
#   8. (A7) {"version":"1"} — the JSON string — is refused, as the spec and the refusal text both say
#      NUMERIC 1. findRawValue strips quotes, so `1` and `"1"` both arrived as text=="1" and the string
#      form slipped through a rule the message claimed to enforce.
#   9. a directory symlink inside the plan dir plus a `..` payload that resolves out of the plan dir refuses,
#      naming the resolved path, with nothing from outside reaching the corpus; an in-root dir symlink + `..`
#      control is still accepted.
#  10. PROBE: a program compiled against src/pathguard.h alone drives rw::pathguard::readWholeBeneathNoFollow —
#      the read parseEdit uses — directly. Anchored at a directory, it reads a regular file beneath it, and
#      refuses a path whose intermediate component beneath the anchor is a symlink (even to a real directory),
#      a final symlink, a `..` component, a path outside the anchor and a FIFO (without blocking). A contrast
#      plain open of the same intermediate-symlink path DOES read the outside file, so the refusal rows can fail.
#      A source row pins that parseEdit reads through it, anchored at the plan's own directory.
#
# Usage: test/editplanpayloadconfinecheck.sh [BIN]
set -u
ROOT="$( cd "$( dirname "$0" )/.." && pwd )"
BIN="${1:-${RIPWIRE_BIN:-$ROOT/build/ripwire}}"
[ "${BIN#/}" = "$BIN" ] && BIN="$ROOT/$BIN"
TMP="$( mktemp -d )"; trap 'rm -rf "$TMP"' EXIT
fail=0
ok(){ printf '  PASS  %s\n' "$*" || { fail=1; printf '  FAIL  could not write the PASS line for: %s\n' "$*"; }; return 0; }
no(){ printf '  FAIL  %s\n' "$*"; fail=1; }
[ -x "$BIN" ] || { echo "no ripwire binary at $BIN — build first"; exit 2; }
command -v python3 >/dev/null 2>&1 || { echo "python3 required"; exit 2; }

echo "editplanpayloadconfinecheck: BIN=$BIN"

hashcorpus(){ ( cd "$1" && find . -type f -print | LC_ALL=C sort | xargs shasum -a 256 ) | shasum -a 256; }

D="$TMP/w"
mkdir -p "$D/corpus" "$D/plans" "$D/secret"
printf 'def alpha( x ):\n    return x + 1\n' >"$D/corpus/a.py"
printf 'RIPWIRE_GATE_SECRET_MARKER=abc123\n' >"$D/secret/creds.txt"
printf 'def alpha( x ):\n    return 42\n' >"$D/plans/good"
ln -s ../secret/creds.txt "$D/plans/link"

# (9) a DIRECTORY symlink inside the plan dir, pointing OUT, plus a `..` payload. The lexical fold cancels
# `dirlink/..` to an in-dir spelling, while the kernel resolving the unfolded path follows dirlink out of the
# tree first and only then applies `..`; the confinement check must judge the same path the read will open.
# Its own out-of-plan file, with a neutral marker, so the corpus-poison check is unambiguous.
mkdir -p "$D/outside/sub"
printf 'RIPWIRE_GATE_OUTSIDE_MARKER=zzz999\n' >"$D/outside/data.txt"
ln -s ../outside/sub "$D/plans/dirlink"
# (9-ctrl) the same shape, but the dir symlink stays INSIDE the plan dir: `indirlink/../good` is a legitimate
# in-dir payload that must still be ALLOWED — the fix must reject the out-of-plan case without rejecting this.
mkdir -p "$D/plans/indir"
ln -s indir "$D/plans/indirlink"

plan(){ printf '{"version":%s,"edits":[{"op":"replace_symbol_body","target":"alpha","payload":"%s"}]}\n' "$2" "$3" >"$D/plans/$1.json"; }
plan escape 1 '../secret/creds.txt'
plan abs     1 '/etc/hosts'
plan sym     1 'link'
plan gone    1 '../../../nope'
plan good    1 'good'
plan qver    '"1"' 'good'
plan dirsym  1 'dirlink/../data.txt'
plan dirctrl 1 'indirlink/../good'

BEFORE="$( hashcorpus "$D/corpus" )"
POISONED=0

# Run a plan against a PRISTINE corpus and leave stdout/stderr in $TMP/<tag>.{out,err}; echo the exit code.
#
# The reset is not tidiness. Against the pre-fix binary the very first arm SUCCEEDS and splices a secret into
# a.py, which deletes the symbol every later arm targets — so without this every subsequent arm fails with
# "symbol 'alpha' not found" and the gate's red output says nothing about the property it was testing. Each
# arm must be independently diagnosable on a broken binary, or its red state is not evidence. Any arm that
# leaves the corpus changed sets POISONED, which arm 7 reports.
# Sets the globals RC and POISONED. Deliberately NOT called through $( ... ): a command substitution is a
# subshell, so the POISONED write would be discarded and arm 7 would report clean over a corpus that had
# just been overwritten — verified while writing this gate.
RC=0
runplan(){
    tag="$1"; planpath="$2"; mode="$3"
    printf 'def alpha( x ):\n    return x + 1\n' >"$D/corpus/a.py"
    ( cd "$D" && "$BIN" corpus --edit-plan="$planpath" "$mode" ) >"$TMP/$tag.out" 2>"$TMP/$tag.err"
    RC=$?
    [ "$BEFORE" = "$( hashcorpus "$D/corpus" )" ] || POISONED=1
    grep -rq 'RIPWIRE_GATE_SECRET_MARKER' "$D/corpus" && POISONED=2
    return 0
}

echo
echo "=== 1. a '../' escape refuses, naming the RESOLVED path ==="
runplan escape plans/escape.json --apply
[ "$RC" != 0 ] \
    && ok "the '../' escape refuses" \
    || no "the '../' escape was accepted"
grep -q 'outside the plan' "$TMP/escape.err" \
    && ok "the refusal explains the rule" \
    || no "the refusal does not explain the rule: $( head -1 "$TMP/escape.err" )"
grep -q "resolves to '/.*secret/creds.txt'" "$TMP/escape.err" \
    && ok "the refusal names the path it actually resolved" \
    || no "the refusal does not name the resolved path: $( head -1 "$TMP/escape.err" )"

echo
echo "=== 2. an absolute payload path refuses ==="
runplan abs plans/abs.json --apply
[ "$RC" != 0 ] \
    && ok "an absolute payload path refuses" \
    || no "an absolute payload path was accepted"
grep -q 'outside the plan' "$TMP/abs.err" \
    && ok "the absolute-path refusal explains the rule" \
    || no "the absolute-path refusal does not explain the rule"

echo
echo "=== 3. a symlink inside the plan dir pointing outside refuses ==="
runplan sym plans/sym.json --apply
[ "$RC" != 0 ] \
    && ok "a symlinked payload escaping the plan dir refuses" \
    || no "a symlinked payload escaped the plan dir"
grep -q "resolves to '/.*secret/creds.txt'" "$TMP/sym.err" \
    && ok "the refusal names the symlink's real target" \
    || no "the refusal does not name the symlink's target: $( head -1 "$TMP/sym.err" )"

echo
echo "=== 4. a non-existent escape refuses AS an escape ==="
runplan gone plans/gone.json --apply
[ "$RC" != 0 ] \
    && ok "a non-existent escaping payload refuses" \
    || no "a non-existent escaping payload was accepted"
grep -q 'outside the plan' "$TMP/gone.err" \
    && ok "it refuses as an escape, not as a plain read failure" \
    || no "it refuses for the wrong reason: $( head -1 "$TMP/gone.err" )"

echo
echo "=== 5. an ordinary payload beside the plan still works, relative AND absolute plan path ==="
runplan good plans/good.json --dry-run
[ "$RC" = 0 ] \
    && ok "a payload beside the plan is accepted (relative plan path)" \
    || no "a legitimate payload was refused: $( head -1 "$TMP/good.err" )"
runplan goodabs "$D/plans/good.json" --dry-run
[ "$RC" = 0 ] \
    && ok "a payload beside the plan is accepted (absolute plan path)" \
    || no "a legitimate payload was refused under an absolute plan path: $( head -1 "$TMP/goodabs.err" )"

echo
echo "=== 6. the dry-run receipt shows what each operation will READ ==="
python3 - "$TMP/good.out" >"$TMP/6.v" <<'PY'
import json, sys
raw = open(sys.argv[1], encoding="utf-8").read().strip()
if not raw:
    print("MISSING (the plan produced no receipt at all)"); raise SystemExit
r = json.loads(raw)
ops = r.get("operations", [])
paths = [o.get("payload_path") for o in ops]
print("OK " + ",".join(map(str, paths)) if ops and all(p for p in paths) else "MISSING " + repr(paths))
PY
grep -q '^OK' "$TMP/6.v" \
    && ok "every operation names its resolved payload path ($( cat "$TMP/6.v" ))" \
    || no "the receipt does not name the payload each op will read: $( cat "$TMP/6.v" )"

echo
echo "=== 7. across every arm above, no refused plan wrote anything ==="
# POISONED is set by runplan itself, immediately after each invocation, so a write is attributed to the arm
# that made it rather than to whatever happens to run last.
case "$POISONED" in
    0) ok "no plan in this gate changed the corpus";;
    2) no "a plan spliced the secret marker into the corpus";;
    *) no "a plan modified the corpus";;
esac

echo
echo "=== 9. a dir-symlink + '..' out-of-plan payload refuses; an in-root dir-symlink + '..' is allowed ==="
runplan dirsym plans/dirsym.json --apply
[ "$RC" != 0 ] \
    && ok "the dir-symlink + '..' out-of-plan payload refuses" \
    || no "the dir-symlink + '..' out-of-plan payload was accepted"
grep -q "resolves to '/.*outside/data.txt'" "$TMP/dirsym.err" \
    && ok "the refusal names the resolved path the read would have opened" \
    || no "the refusal does not name the resolved out-of-plan target: $( head -1 "$TMP/dirsym.err" )"
grep -rq 'RIPWIRE_GATE_OUTSIDE_MARKER' "$D/corpus" \
    && no "an out-of-plan byte from the dir-symlink payload reached the corpus" \
    || ok "no out-of-plan byte from the dir-symlink payload reached the corpus"
runplan dirctrl plans/dirctrl.json --dry-run
[ "$RC" = 0 ] \
    && ok "an in-root dir-symlink + '..' payload is still accepted (the fix does not over-refuse)" \
    || no "an in-root dir-symlink + '..' payload was wrongly refused: $( head -1 "$TMP/dirctrl.err" )"

echo
echo "=== 8. (A7) a QUOTED version is not numeric 1 ==="
runplan qver plans/qver.json --dry-run
[ "$RC" != 0 ] \
    && ok '{"version":"1"} refuses' \
    || no '{"version":"1"} was accepted where the spec says numeric 1'
grep -q 'numeric version 1' "$TMP/qver.err" \
    && ok "the refusal names the numeric-version rule" \
    || no "the refusal does not name the rule: $( head -1 "$TMP/qver.err" )"

echo
echo "=== 10. PROBE: the anchored payload read, driven directly ==="
CXX="${CXX:-c++}"
. "$ROOT/scripts/cxxstd.sh"
CXXSTD="$( ripwire_cxx_std_flag "$CXX" )"
PB="$TMP/probe"; mkdir -p "$PB/work"
cat > "$PB/probe.cpp" <<'CPP'
#include "pathguard.h"

#include <climits>
#include <cstdio>
#include <cstdlib>
#include <fstream>
#include <iterator>
#include <string>
#include <sys/stat.h>
#include <unistd.h>

static int failures = 0;
static void row( bool okRow, const char* what ) { std::printf( "%s %s\n", okRow ? "PROBE-PASS" : "PROBE-FAIL", what ); failures += okRow ? 0 : 1; }
static void spit( const std::string& p, const std::string& b ) { std::ofstream( p, std::ios::binary ) << b; }

int main( int argc, char** argv )
{
    if( argc != 2 ) { return 2; }
    char buf[ PATH_MAX ];
    if( ::realpath( argv[ 1 ], buf ) == nullptr ) { return 2; }
    const std::string w      = buf;
    const std::string anchor = w + "/plans";
    ::mkdir( anchor.c_str(), 0755 );
    ::mkdir( ( anchor + "/real" ).c_str(), 0755 );
    ::mkdir( ( w + "/outside" ).c_str(), 0755 );
    spit( anchor + "/real/ok.txt", "inside bytes" );
    spit( w + "/outside/data.txt", "outside bytes" );
    ::symlink( ( w + "/outside" ).c_str(), ( anchor + "/linkdir" ).c_str() );   // intermediate symlink, pointing out
    ::symlink( ( anchor + "/real" ).c_str(), ( anchor + "/indirlink" ).c_str() );  // intermediate symlink, pointing in
    ::symlink( ( w + "/outside/data.txt" ).c_str(), ( anchor + "/finallink.txt" ).c_str() );
    ::mkfifo( ( anchor + "/fifo" ).c_str(), 0644 );

    std::string out;
    row( rw::pathguard::readWholeBeneathNoFollow( anchor, anchor + "/real/ok.txt", out ) && out == "inside bytes",
         "(10a) a regular file beneath the anchor is read" );
    out = "unchanged";
    row( !rw::pathguard::readWholeBeneathNoFollow( anchor, anchor + "/linkdir/data.txt", out ) && out.empty(),
         "(10b) an intermediate component that is a symlink out of the anchor is refused, nothing read" );
    row( !rw::pathguard::readWholeBeneathNoFollow( anchor, anchor + "/indirlink/ok.txt", out ) && out.empty(),
         "(10c) an intermediate symlink is refused even when it points at a directory beneath the anchor" );
    row( !rw::pathguard::readWholeBeneathNoFollow( anchor, anchor + "/finallink.txt", out ) && out.empty(),
         "(10d) a final-component symlink is refused" );
    row( !rw::pathguard::readWholeBeneathNoFollow( anchor, anchor + "/real/../real/ok.txt", out ) && out.empty(),
         "(10e) a `..` component is refused" );
    row( !rw::pathguard::readWholeBeneathNoFollow( anchor, w + "/outside/data.txt", out ) && out.empty(),
         "(10f) a path outside the anchor is refused" );
    row( !rw::pathguard::readWholeBeneathNoFollow( anchor, anchor + "-sibling/x.txt", out ) && out.empty(),
         "(10g) a sibling whose name merely starts with the anchor's is refused" );
    row( !rw::pathguard::readWholeBeneathNoFollow( anchor, anchor + "/fifo", out ) && out.empty(),
         "(10h) a FIFO beneath the anchor is refused without blocking" );

    std::ifstream plain( anchor + "/linkdir/data.txt", std::ios::binary );
    std::string   through( ( std::istreambuf_iterator<char>( plain ) ), std::istreambuf_iterator<char>() );
    row( through == "outside bytes", "(contrast) a plain open of the intermediate-symlink path does read the outside file" );
    return failures == 0 ? 0 : 1;
}
CPP
if "$CXX" "$CXXSTD" -O1 -I"$ROOT/src" -I"$ROOT/src/infra" -I"$ROOT/third_party" "$PB/probe.cpp" -o "$PB/probe" 2> "$PB/cc.log"; then
    "$PB/probe" "$PB/work" > "$PB/out.txt" 2>&1
    PBRC=$?
    PBROWS="$( grep -c '^PROBE-' "$PB/out.txt" )"
    [ "$PBROWS" -eq 9 ] && [ "$PBRC" -eq 0 ] \
        && ok "presence: the probe reported all 9 rows and exited 0" \
        || no "the probe reported $PBROWS of 9 rows (rc=$PBRC): $( head -c 300 "$PB/out.txt" )"
    while IFS= read -r prow; do
        case "$prow" in
            PROBE-PASS\ *) ok "${prow#PROBE-PASS }" ;;
            PROBE-FAIL\ *) no "${prow#PROBE-FAIL }" ;;
        esac
    done < "$PB/out.txt"
else
    no "the pathguard probe did not compile with $CXX: $( head -5 "$PB/cc.log" | tr '\n' ' ' )"
fi
PE_BODY="$( awk 'index($0,"inline bool parseEdit("){f=1} f{print} f&&/^}$/{exit}' "$ROOT/src/editplan.h" )"
if printf '%s' "$PE_BODY" | grep -q 'readWholeBeneathNoFollow( planDirAbs( planPath ), edit.payloadPath' \
   && ! printf '%s' "$PE_BODY" | grep -qE 'readFileBytes\(|readWholeNoFollow\('; then
    ok "(10i) parseEdit reads the payload through readWholeBeneathNoFollow anchored at the plan's own directory"
else
    no "(10i) parseEdit does not read the payload through the anchored read"
fi

[ "$fail" -eq 0 ] && echo "ALL PASS" || echo "FAILURES ABOVE"
exit "$fail"
