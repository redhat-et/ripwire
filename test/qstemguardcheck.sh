#!/bin/bash
# qstemguardcheck — QSTEM-GUARDED: the query-side stemmer ships ON, and its evidence is NAME-FIELD only.
#   (a) an inflected question word ("sensors", "handled", "parsing") reaches the symbol whose NAME carries the stem,
#       in Python, TypeScript and C++ — default run, no env; RIPWIRE_QSTEM=0 is the off switch (control: absent).
#   (b) a stem-only BODY hit never outranks an exact hit: symbols whose bodies call handle() many times do not rise
#       above the symbol whose name says "handled" (the unguarded stemmer folded that body mass into the exact word).
#   (c) a file the question names keeps its candidates: body-only stem mass from other files does not push the
#       subject file's symbols out of the top of the list.
#   (d) postings parity: cached (persisted-stats) and --no-cache (scan) answers are byte-identical with the stemmer on.
# Every absence arm has a positive twin; every run's exit code is checked, so a crash or empty answer is red.
# Red-first: on the pre-lane binary (stemmer off by default; on = unguarded fold) (a) and (b)/(c) fail.
set -u
BIN="${1:-${RIPWIRE_BIN:-./build/ripwire}}"
TMP="$(mktemp -d "${TMPDIR:-/tmp}/qstemguard.XXXXXX")"
trap 'rm -rf "$TMP"' EXIT
FAIL=0
ok(){ echo "  PASS  $1" || { FAIL=1; echo "  FAIL  could not write the PASS line for: $1"; }; return 0; }
no(){ echo "  FAIL  $1"; FAIL=1; }
mkdir -p "$TMP/xdg"
# run OUT ARGS... : runs the binary with a private cache home; red (and the file emptied) on a nonzero exit or no output
# QSTEMGUARD_BASE_FLIP=1 (red-first proof only): "default" runs get RIPWIRE_QSTEM=1, i.e. a pre-lane binary with its
# default flipped to the UNGUARDED stemmer. Otherwise an inherited RIPWIRE_QSTEM is stripped so default means default.
FLIP=(); [ "${QSTEMGUARD_BASE_FLIP:-0}" = 1 ] && FLIP=(RIPWIRE_QSTEM=1)
run(){ local out="$1"; shift
       if env -u TMPDIR -u RIPWIRE_QSTEM XDG_CACHE_HOME="$TMP/xdg" ${FLIP[@]+"${FLIP[@]}"} "$@" > "$out" 2>"$out.err" && [ -s "$out" ]; then return 0; fi
       no "command failed or printed nothing: ${*:2}"; : > "$out"; return 1; }
runq(){ local out="$1" q="$2"; shift 2; local v="$1"; shift
        if [ "$v" = default ]; then run "$out" "$BIN" "$@" --for="$q" --format=candidates
        else run "$out" env RIPWIRE_QSTEM="$v" "$BIN" "$@" --for="$q" --format=candidates; fi; }
# rank FILE NAME : the candidate rank of the first row whose n= is exactly NAME (999 if absent)
rank(){ local r; r=$(tr '<' '\n' < "$1" | grep -E "^cand r=\"[0-9]+\" " | grep -F " n=\"$2\"" | head -1 | sed -E 's/^cand r="([0-9]+)".*/\1/')
        echo "${r:-999}"; }
# file_in_top FILE PATHFRAG K : how many of the top-K candidates sit in a path containing PATHFRAG
file_in_top(){ tr '<' '\n' < "$1" | grep -E '^cand r="[0-9]+" ' | awk -v k="$3" -F'"' '$2+0 <= k+0' | grep -cF "$2"; }

# ── (a) inflection → the stem's NAME, three languages; noise carries every non-lever query token ──────────────
# each noise word names three symbols (lower idf than the target's one carrier), one query word per noise symbol
A="$TMP/a"; mkdir -p "$A/py" "$A/ts" "$A/cpp"
cat > "$A/py/sensor_registry.py" <<'EOF'
def sensor_registry(table):
    return table.entries()
EOF
cat > "$A/py/noise.py" <<'EOF'
def keep_box(box):
    return box
def keep_bag(box):
    return box
def keep_bin(box):
    return box
def platform_box(box):
    return box
def platform_bag(box):
    return box
def platform_bin(box):
    return box
def modules_box(box):
    return box
def modules_bag(box):
    return box
def modules_bin(box):
    return box
def cleanly_box(box):
    return box
def cleanly_bag(box):
    return box
def cleanly_bin(box):
    return box
def which_box(box):
    return box
def which_bag(box):
    return box
def which_bin(box):
    return box
EOF
cat > "$A/ts/dispatch.ts" <<'EOF'
export function handleSignal(sig: number): number { return sig + 1; }
EOF
cat > "$A/ts/noise.ts" <<'EOF'
export function queuedBox(box: number): number { return box; }
export function queuedBag(box: number): number { return box; }
export function queuedBin(box: number): number { return box; }
export function messagesBox(box: number): number { return box; }
export function messagesBag(box: number): number { return box; }
export function messagesBin(box: number): number { return box; }
export function cleanlyBox(box: number): number { return box; }
export function cleanlyBag(box: number): number { return box; }
export function cleanlyBin(box: number): number { return box; }
export function whereBox(box: number): number { return box; }
export function whereBag(box: number): number { return box; }
export function whereBin(box: number): number { return box; }
export function areBox(box: number): number { return box; }
export function areBag(box: number): number { return box; }
export function areBin(box: number): number { return box; }
EOF
cat > "$A/cpp/header.cpp" <<'EOF'
int parseHeader( const char* text ) { return text[0]; }
EOF
cat > "$A/cpp/noise.cpp" <<'EOF'
int framesBox( int box ) { return box; }
int framesBag( int box ) { return box; }
int framesBin( int box ) { return box; }
int readBox( int box ) { return box; }
int readBag( int box ) { return box; }
int readBin( int box ) { return box; }
int cleanlyBox( int box ) { return box; }
int cleanlyBag( int box ) { return box; }
int cleanlyBin( int box ) { return box; }
int streamsBox( int box ) { return box; }
int streamsBag( int box ) { return box; }
int streamsBin( int box ) { return box; }
int whileBox( int box ) { return box; }
int whileBag( int box ) { return box; }
int whileBin( int box ) { return box; }
EOF
check_a(){ local lang="$1" q="$2" target="$3"
    runq "$TMP/a_$lang.on" "$q" default "$A/$lang" || return
    runq "$TMP/a_$lang.off" "$q" 0 "$A/$lang" || return
    local on off; on=$(rank "$TMP/a_$lang.on" "$target"); off=$(rank "$TMP/a_$lang.off" "$target")
    if [ "$on" -le 3 ]; then ok "(a-$lang) default: '$q' reaches $target at r=$on"; else no "(a-$lang) default: $target r=$on for '$q' (want <= 3)"; fi
    if [ "$off" -gt 3 ]; then ok "(a-$lang-ctl) RIPWIRE_QSTEM=0: $target r=$off (the stem, not ambient rank, did the work)"; else no "(a-$lang-ctl) RIPWIRE_QSTEM=0: $target already r=$off — fixture no longer proves the stem"; fi
}
check_a py  "which sensors keep platform modules cleanly" sensor_registry
check_a ts  "where are queued messages handled cleanly" handleSignal
check_a cpp "frames read cleanly from streams while parsing" parseHeader

# ── (b) an exact NAME hit is not outranked by stem-only BODY hits (Python and TypeScript) ──────────────────────
# handle() is called but never defined in the corpus: the decoys carry the stem only in their BODIES and callee
# names, so a stem NAME carrier (arm a's job) cannot be what outranks the exact hit here.
B="$TMP/b"; mkdir -p "$B/py" "$B/ts"
cat > "$B/py/events.py" <<'EOF'
def mark_handled(flag):
    return not flag

def dispatch_event(e):
    handle(e); handle(e); handle(e); handle(e); handle(e); handle(e); handle(e); handle(e)

def route_event(e):
    handle(e); handle(e); handle(e); handle(e); handle(e); handle(e); handle(e); handle(e)

def queue_event(e):
    handle(e); handle(e); handle(e); handle(e); handle(e); handle(e); handle(e); handle(e)
EOF
cat > "$B/ts/events.ts" <<'EOF'
export function markHandled(flag: boolean): boolean { return !flag; }
export function dispatchEvent(e: number): void { run(e); run(e); run(e); run(e); run(e); run(e); run(e); run(e); }
export function routeEvent(e: number): void { run(e); run(e); run(e); run(e); run(e); run(e); run(e); run(e); }
export function queueEvent(e: number): void { run(e); run(e); run(e); run(e); run(e); run(e); run(e); run(e); }
function run(e: number): number { return handle(e) + handle(e) + handle(e) + handle(e); }
EOF
check_b(){ local lang="$1" target="$2" decoy="$3" q="where is the event handled"
    runq "$TMP/b_$lang.on" "$q" default "$B/$lang" || return
    runq "$TMP/b_$lang.off" "$q" 0 "$B/$lang" || return
    local t d t0; t=$(rank "$TMP/b_$lang.on" "$target"); d=$(rank "$TMP/b_$lang.on" "$decoy"); t0=$(rank "$TMP/b_$lang.off" "$target")
    if [ "$t0" -eq 1 ]; then ok "(b-$lang-twin) RIPWIRE_QSTEM=0: exact hit $target is r=1 (the fixture's exact ranking)"; else no "(b-$lang-twin) RIPWIRE_QSTEM=0: $target r=$t0, want 1 — fixture broken"; fi
    if [ "$t" -eq 1 ]; then ok "(b-$lang) default: exact hit $target stays r=1"; else no "(b-$lang) default: $target r=$t — a stem-only body hit outranked it"; fi
    if [ "$d" -ne 999 ] && [ "$d" -gt "$t" ]; then ok "(b-$lang) default: body-stem decoy $decoy present (r=$d) and below the exact hit"; else no "(b-$lang) default: decoy $decoy r=$d vs exact r=$t (want present and below)"; fi
}
check_b py mark_handled dispatch_event
check_b ts markHandled dispatchEvent

# ── (c) the subject-named file keeps its candidates (C++) ──────────────────────────────────────────────────────
C="$TMP/c"; mkdir -p "$C/src"
cat > "$C/src/loader.cpp" <<'EOF'
int loaderOpen( int fd ) { return fd; }
int loaderClose( int fd ) { return fd - 1; }
int loaderErrors( int fd ) { return fd * 2; }
EOF
for n in 1 2 3 4 5 6; do
cat > "$C/src/worker$n.cpp" <<EOF
int reportStage$n( int x ) { return parse( x ) + parse( x ) + parse( x ) + parse( x ) + parse( x ) + parse( x ) + parse( x ) + parse( x ); }
EOF
done
cat > "$C/src/parse.cpp" <<'EOF'
int parse( int x ) { return x; }
EOF
Q_C="how does loader.cpp report errors while parsing"
runq "$TMP/c.on" "$Q_C" default "$C" && runq "$TMP/c.off" "$Q_C" 0 "$C" && {
    on=$(file_in_top "$TMP/c.on" "src/loader.cpp" 3); off=$(file_in_top "$TMP/c.off" "src/loader.cpp" 3)
    if [ "$off" -ge 3 ]; then ok "(c-twin) RIPWIRE_QSTEM=0: loader.cpp holds $off of the top-3"; else no "(c-twin) RIPWIRE_QSTEM=0: loader.cpp holds $off of top-3, want 3 — fixture broken"; fi
    if [ "$on" -ge 3 ]; then ok "(c) default: loader.cpp keeps $on of the top-3"; else no "(c) default: loader.cpp holds $on of top-3 — body stem mass displaced the subject file"; fi
    w=$(file_in_top "$TMP/c.on" "src/worker" 50)
    if [ "$w" -ge 1 ]; then ok "(c) default: the worker files are still candidates ($w rows), only ranked below"; else no "(c) default: worker files vanished entirely (want present below)"; fi
}

# ── (d) postings parity with the stemmer on (default) ─────────────────────────────────────────────────────────
run "$TMP/d_warm.xml" "$BIN" "$A/py" --for="which sensors keep platform modules cleanly" \
 && run "$TMP/d_scan.xml" "$BIN" "$A/py" --for="which sensors keep platform modules cleanly" --no-cache && {
    if cmp -s "$TMP/d_warm.xml" "$TMP/d_scan.xml"; then ok "(d) parity: scan and persisted-stats answers byte-identical, stemmer on"; else no "(d) parity: branches diverge with the stemmer on"; fi; }

if [ "$FAIL" -eq 0 ]; then echo "qstemguardcheck: ALL PASS"; else echo "qstemguardcheck: FAILURES"; fi
exit "$FAIL"
