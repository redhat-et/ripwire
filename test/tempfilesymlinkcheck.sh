#!/usr/bin/env bash
# tempfilesymlinkcheck.sh — the TEMP file of a tmp+rename publish is created exclusively, refusing an
# existing entry at its own name (rw::pathguard::createExclTempFile).
#
# THE PROPERTY THIS GATE ASSERTS. Three "atomic" publish writers reach their final name only through a
# rename() of a temp file they create beside it:
#
#     mcpedit::atomicWrite        (an edited source file)
#     quality::atomicWriteFile    (.ripwire_quality_acks, qsnap / qbody / …)
#     ingest::saveCache           (an in-tree --cache= / --index-out= blob)
#
# Each now creates that temp through rw::pathguard::createExclTempFile, which draws a CSPRNG suffix and opens
# each candidate name with openExclNoFollow (O_CREAT|O_EXCL|O_NOFOLLOW|O_CLOEXEC). The temp lives next to the
# target (a rename is atomic only within one filesystem). What each part of this gate proves, and no more:
#
#   (a)-(d) BEHAVIOURAL, over the three writers through the real binary. The temp-name shape the writers used
#       before is derived from the WRITER's getpid(), and a shell that `exec`s ripwire keeps its pid, so a
#       fixture that places `ln -s outside <path>.$$.tmp` and then execs the tool has put an existing entry at a
#       name of that exact shape (atomicWriteFile also appends a process-wide counter that the same run's cache
#       writes advance, so the ack arm covers its low range). These arms prove the writers no longer open that
#       name through the link and still publish normally. They do NOT drive a collision at the random name the
#       writer actually draws — that name cannot be chosen from outside without a hook in product code.
#       (a) the outside file the temp-name symlink points at is byte-identical after the writer runs
#       (b) the outside file's MODE is unchanged (mcpedit fchmods the temp; it must not reach the link target)
#       (c) the target is a REGULAR file afterwards, not a symlink left in place over it
#       (d) POSITIVE CONTROL: with no symlink present, the same writer still publishes its file with real content
#   (e) CENSUS: the two cache-dir writers route their temp through the shared helper (source).
#   (e2) CENSUS: the three stream writers close their stream as a standalone statement after releaseFd(),
#       never inside || / && after the write; a mutation control shows the scan flags the short-circuit form.
#   (f) PROBE: a small program compiled against src/pathguard.h alone drives the product primitives directly —
#       openExclNoFollow refuses an existing symlink, dangling symlink and regular file at the exact name it is
#       given (EEXIST, nothing followed, nothing changed), and createExclTempFile yields a fresh regular file of
#       the documented name shape that its RAII holder removes unless committed. A contrast open with the
#       old O_CREAT|O_TRUNC flags on the same fixture DOES change the outside file, so the probe's checks can
#       fail. The retry loop on EEXIST inside createExclTempFile is not driven (its name is random); a source
#       row pins that it opens every candidate through openExclNoFollow and nothing else, and
#       sidecarsymlinkcheck (f6) pins that primitive's flags.
#
# Red on main, green after.
#
# Usage:  bash test/tempfilesymlinkcheck.sh [BIN]   |   RIPWIRE_BIN=asan/ripwire bash test/tempfilesymlinkcheck.sh

set -u
ROOT="$( cd "$( dirname "$0" )/.." && pwd )"
. "$ROOT/test/lib/statcompat.sh"
BIN="${1:-${RIPWIRE_BIN:-$ROOT/build/ripwire}}"
[ "${BIN#/}" = "$BIN" ] && BIN="$ROOT/$BIN"          # allow repo-relative RIPWIRE_BIN
fail=0
ok(){ printf '  PASS  %s\n' "$*" || { fail=1; printf '  FAIL  could not write the PASS line for: %s\n' "$*"; }; return 0; }
no(){ printf '  FAIL  %s\n' "$*"; fail=1; }

[ -x "$BIN" ] || { echo "no ripwire binary at $BIN — build first (cmake --build build -j)"; exit 2; }
command -v git     >/dev/null 2>&1 || { echo "git required";     exit 2; }
command -v python3 >/dev/null 2>&1 || { echo "python3 required"; exit 2; }

TMP="$( mktemp -d )"; trap 'rm -rf "$TMP"' EXIT
export XDG_CACHE_HOME="$TMP/cache"; mkdir -p "$XDG_CACHE_HOME"   # never the user's cache, never the checkout
echo "tempfilesymlinkcheck: BIN=$BIN  TMP=$TMP"

OUTSIDE_BYTES='important user data'
OUTSIDE_MODE=700

# place_outside FILE — a distinctive file at a known mode, outside any tree the writer indexes.
place_outside(){ printf '%s' "$OUTSIDE_BYTES" > "$1"; chmod "$OUTSIDE_MODE" "$1"; }

# filemode FILE — permission bits in octal (GNU coreutils stat, else BSD / macOS stat).
filemode(){ mode_of "$1"; }

# assert_outside TAG OUTSIDE_FILE — (a) bytes and (b) mode are unchanged.
assert_outside(){
    local tag="$1" v="$2" got mode
    got="$( cat "$v" 2>/dev/null )"
    [ "$got" = "$OUTSIDE_BYTES" ] \
        && ok "($tag a) the outside file the temp-name symlink points at is byte-identical (never followed)" \
        || no "($tag a) the outside file was overwritten through the temp-name symlink: '$( printf '%s' "$got" | head -c 40 )'"
    mode="$( filemode "$v" )"
    [ "$mode" = "$OUTSIDE_MODE" ] \
        && ok "($tag b) the outside's mode is unchanged ($OUTSIDE_MODE)" \
        || no "($tag b) the outside's mode changed $OUTSIDE_MODE → $mode (an fchmod reached the link target)"
}

# ── writer 1: mcpedit::atomicWrite via --replace-symbol-body (temp <file>.<pid>.tmp) ──────────────────────
E="$TMP/edit"; mkdir -p "$E/tree"
printf 'int helper( int x ) { return x + 1; }\nint main( void ) { return helper( 1 ); }\n' > "$E/tree/a.c"; chmod 0644 "$E/tree/a.c"
printf 'int helper( int x ) { return x + 2; }\n' > "$E/payload.c"
place_outside "$E/outside"
( cd "$E" && sh -c 'ln -s "$1" "tree/a.c.$$.tmp" && exec "$2" tree --replace-symbol-body=helper --edit-payload=payload.c' _ "$E/outside" "$BIN" ) > "$E/out" 2> "$E/err"
assert_outside "mcpedit" "$E/outside"
[ -L "$E/tree/a.c" ] \
    && no "(mcpedit c) the edited file was left as a symlink to the outside (the temp link was renamed over it)" \
    || ok "(mcpedit c) the edited file is a regular file, not a symlink left over it"

# ── writer 2: quality::atomicWriteFile via --quality-ack (temp <ledger>.tmp.<pid>.0) ──────────────────────
Q="$TMP/ack"; mkdir -p "$Q/w"
printf 'def qComplex( a, b ):\n    if a > b:\n        return a\n    return b\n' > "$Q/w/q.py"
( cd "$Q/w" && git init -q && git config user.email t@t && git config user.name t && git add -A && git commit -qm init ) >/dev/null 2>&1
python3 - "$Q/w" <<'PY'
import sys, os
lines = [ "def qComplex( a, b ):" ]
for i in range( 24 ):
    lines += [ "    if a > %d and b < %d:" % ( i, i + 1 ), "        a = a + %d" % ( i + 2 ),
               "    elif a < %d or b > %d:" % ( i + 3, i ), "        b = b - %d" % ( i + 1 ) ]
lines.append( "    return a + b" )
open( os.path.join( sys.argv[1], "q.py" ), "w" ).write( "\n".join( lines ) + "\n" )
PY
place_outside "$Q/outside"
( cd "$Q/w" && sh -c 'i=0; while [ $i -lt 64 ]; do ln -s "$1" ".ripwire_quality_acks.tmp.$$.$i" || exit 9; i=$(( i + 1 )); done; exec "$2" . --quality-delta --quality-ack=accepted' _ "$Q/outside" "$BIN" ) > "$Q/out" 2> "$Q/err"
assert_outside "acks" "$Q/outside"
[ -L "$Q/w/.ripwire_quality_acks" ] \
    && no "(acks c) the ack ledger was left as a symlink to the outside" \
    || ok "(acks c) the ack ledger is a regular file, not a symlink left over it"

# ── writer 3: ingest::saveCache via --cache= into the tree (temp <blob>.<pid>.tmp) ────────────────────────
C="$TMP/cache"; mkdir -p "$C/tree"
printf 'int f( void ) { return 1; }\n' > "$C/tree/a.c"
place_outside "$C/outside"
( cd "$C" && sh -c 'ln -s "$1" "tree/.rwcache.$$.tmp" && exec "$2" tree --cache=tree/.rwcache' _ "$C/outside" "$BIN" ) > "$C/out" 2> "$C/err"
assert_outside "savecache" "$C/outside"
[ -L "$C/tree/.rwcache" ] \
    && no "(savecache c) the cache blob was left as a symlink to the outside" \
    || ok "(savecache c) the cache blob is a regular file, not a symlink left over it"

# ── (d) POSITIVE CONTROLS: with NO symlink present, each writer still publishes a real file ───────────────
PE="$TMP/pos_edit"; mkdir -p "$PE/tree"
printf 'int helper( int x ) { return x + 1; }\nint main( void ) { return helper( 1 ); }\n' > "$PE/tree/a.c"
printf 'int helper( int x ) { return x + 5; }\n' > "$PE/payload.c"
( cd "$PE" && "$BIN" tree --replace-symbol-body=helper --edit-payload=payload.c ) > "$PE/out" 2> "$PE/err"
{ [ ! -L "$PE/tree/a.c" ] && grep -q 'return x + 5' "$PE/tree/a.c"; } \
    && ok "(mcpedit d) with no symlink, the edit still lands (a.c holds the new body)" \
    || no "(mcpedit d) the normal edit did not land: $( head -1 "$PE/err" )"

PC="$TMP/pos_cache"; mkdir -p "$PC/tree"
printf 'int f( void ) { return 1; }\n' > "$PC/tree/a.c"
( cd "$PC" && "$BIN" tree --cache=tree/.rwcache ) >/dev/null 2>&1
{ [ -f "$PC/tree/.rwcache" ] && [ ! -L "$PC/tree/.rwcache" ] && [ -s "$PC/tree/.rwcache" ]; } \
    && ok "(savecache d) with no symlink, the cache blob is written as a regular non-empty file" \
    || no "(savecache d) the cache blob was not written normally"

PQ="$TMP/pos_ack"; mkdir -p "$PQ/w"
cp "$Q/w/q.py" "$PQ/w/q.py"
( cd "$PQ/w" && git init -q && git config user.email t@t && git config user.name t && printf 'def qComplex( a, b ):\n    return a\n' > q0.py && git add q0.py && git commit -qm init && mv q0.py q.py 2>/dev/null; cp "$Q/w/q.py" q.py ) >/dev/null 2>&1
( cd "$PQ/w" && "$BIN" . --quality-delta --quality-ack=accepted ) >/dev/null 2> "$PQ/err"
{ [ -f "$PQ/w/.ripwire_quality_acks" ] && [ ! -L "$PQ/w/.ripwire_quality_acks" ] && grep -q 'ripwire quality acks' "$PQ/w/.ripwire_quality_acks"; } \
    && ok "(acks d) with no symlink, the ack ledger is written as a regular file with real content" \
    || no "(acks d) the ack ledger was not written normally: $( head -1 "$PQ/err" )"

# ── (e) CENSUS: the cache-dir tmp+rename writers route through the shared exclusive helper ────────────────
# gitoracle::saveOracleCache and ingest_docpass::publishDocBridgeBlob publish to the per-user cache dir, so a
# behavioural CLI arm cannot address their sha-keyed temp name; a SOURCE census asserts each creates its temp
# through rw::pathguard::createExclTempFile and no longer opens a temp with std::fopen. (ingest_astquery's span
# memo is deliberately NOT folded — it streams structured POD through a std::ofstream rather than one blob, so
# it is not a mechanical swap; it too writes only inside the 0700 cache dir.)
census_writer(){
    local label="$1" file="$2" fn="$3"
    local body
    body="$( awk -v sig="$fn" 'index($0,sig){f=1} f{print} f&&/^}$/{exit}' "$ROOT/$file" )"
    if [ -z "$body" ]; then
        no "($label e) could not isolate $fn in $file — census void"
        return
    fi
    if printf '%s' "$body" | grep -q 'pathguard::createExclTempFile' \
       && ! printf '%s' "$body" | grep -qE 'std::fopen\(|std::ofstream'; then
        ok "($label e) $fn creates its temp via pathguard::createExclTempFile, with no std::fopen/ofstream temp open"
    else
        no "($label e) $fn does not route its temp through pathguard::createExclTempFile: $( printf '%s' "$body" | grep -nE 'std::fopen\(|std::ofstream|createExclTempFile' | head -3 | tr '\n' ';' )"
    fi
}
census_writer gitoracle src/gitoracle.h    'inline bool saveOracleCache('
census_writer docpass   src/ingest_docpass.h 'inline void publishDocBridgeBlob('

# (e2) CENSUS: after releaseFd() the stdio stream owns the descriptor, so each stream writer closes it on every
# path — fclose is its own statement, never an operand of || or && where a failed fwrite would short-circuit past
# it. A mutation control re-checks the pre-fix saveCache spelling and must be flagged.
fclose_shortcircuit_lines(){ awk -v sig="$2" 'index($0,sig){f=1} f{print} f&&/^}$/{exit}' "$1" | grep -E 'fclose' | grep -E '\|\||&&'; }
stream_close_row(){
    local label="$1" file="$2" sig="$3" body bad
    body="$( awk -v sig="$sig" 'index($0,sig){f=1} f{print} f&&/^}$/{exit}' "$ROOT/$file" )"
    if [ -z "$body" ] || ! printf '%s' "$body" | grep -q 'std::fclose( fp )'; then
        no "($label e2) could not find $sig with an fclose in $file — census void"
        return
    fi
    bad="$( fclose_shortcircuit_lines "$ROOT/$file" "$sig" )"
    if [ -z "$bad" ]; then
        ok "($label e2) $sig closes its stream as a standalone statement (no fclose inside || / &&)"
    else
        no "($label e2) $sig can skip fclose after a failed write: $( printf '%s' "$bad" | head -2 | tr '\n' ';' )"
    fi
}
stream_close_row savecache src/ingest_cache.h   'inline void saveCache('
stream_close_row gitoracle src/gitoracle.h      'inline bool saveOracleCache('
stream_close_row docpass   src/ingest_docpass.h 'inline void publishDocBridgeBlob('
printf 'inline void mutantSave()\n{\n    const bool wErr = wrote != w.b.size() || std::fclose( fp ) != 0;\n}\n' > "$TMP/fclose_mutant.h"
if [ -n "$( fclose_shortcircuit_lines "$TMP/fclose_mutant.h" 'inline void mutantSave(' )" ]; then
    ok "(e2) mutation control: the pre-fix short-circuit spelling is flagged by the same scan"
else
    no "(e2) mutation control: the short-circuit spelling was not flagged — the census cannot fail"
fi

# ── (f) PROBE: the product primitives, driven directly through a program compiled against pathguard.h ──────
CXX="${CXX:-c++}"
. "$ROOT/scripts/cxxstd.sh"
CXXSTD="$( ripwire_cxx_std_flag "$CXX" )"
PR="$TMP/probe"; mkdir -p "$PR/work"
cat > "$PR/probe.cpp" <<'CPP'
#include "pathguard.h"

#include <cerrno>
#include <cstdio>
#include <fstream>
#include <iterator>
#include <string>
#include <sys/stat.h>
#include <unistd.h>

static int failures = 0;
static void row( bool okRow, const char* what ) { std::printf( "%s %s\n", okRow ? "PROBE-PASS" : "PROBE-FAIL", what ); failures += okRow ? 0 : 1; }
static std::string slurp( const std::string& p ) { std::ifstream in( p, std::ios::binary ); return std::string( std::istreambuf_iterator<char>( in ), {} ); }
static void spit( const std::string& p, const std::string& b ) { std::ofstream( p, std::ios::binary ) << b; }
static mode_t modeOf( const std::string& p ) { struct stat st{}; return ::lstat( p.c_str(), &st ) == 0 ? ( st.st_mode & 07777 ) : 0; }
static bool isLink( const std::string& p ) { struct stat st{}; return ::lstat( p.c_str(), &st ) == 0 && S_ISLNK( st.st_mode ); }
static bool isReg( const std::string& p ) { struct stat st{}; return ::lstat( p.c_str(), &st ) == 0 && S_ISREG( st.st_mode ); }

int main( int argc, char** argv )
{
    if( argc != 2 ) { return 2; }
    const std::string w = argv[ 1 ];
    const std::string outside = w + "/outside.txt";
    const std::string bytes   = "outside file bytes";

    // (f1) an existing symlink at the exact name: refused with EEXIST, the link target untouched in bytes and mode
    spit( outside, bytes ); ::chmod( outside.c_str(), 0700 );
    const std::string lnk = w + "/name-link.tmp";
    ::symlink( outside.c_str(), lnk.c_str() );
    errno = 0;
    int fd = rw::pathguard::openExclNoFollow( lnk.c_str(), 0666 );
    const int e1 = errno;
    if( fd >= 0 ) { ::write( fd, "X", 1 ); ::close( fd ); }
    row( fd < 0 && e1 == EEXIST, "(f1) openExclNoFollow refuses an existing symlink at its name with EEXIST" );
    row( slurp( outside ) == bytes && modeOf( outside ) == 0700 && isLink( lnk ), "(f1) the link and the file it points at are unchanged" );

    // (f2) a dangling symlink at the exact name: refused, and nothing is created at the link's target
    const std::string dangTarget = w + "/never-created.txt";
    const std::string dang       = w + "/name-dangling.tmp";
    ::symlink( dangTarget.c_str(), dang.c_str() );
    errno = 0;
    fd = rw::pathguard::openExclNoFollow( dang.c_str(), 0666 );
    const int e2 = errno;
    if( fd >= 0 ) { ::close( fd ); }
    row( fd < 0 && e2 == EEXIST && ::access( dangTarget.c_str(), F_OK ) != 0, "(f2) openExclNoFollow refuses a dangling symlink and creates nothing at its target" );

    // (f3) an existing regular file at the exact name: refused, its bytes unchanged
    const std::string reg = w + "/name-regular.tmp";
    spit( reg, "existing" );
    errno = 0;
    fd = rw::pathguard::openExclNoFollow( reg.c_str(), 0666 );
    const int e3 = errno;
    if( fd >= 0 ) { ::close( fd ); }
    row( fd < 0 && e3 == EEXIST && slurp( reg ) == "existing", "(f3) openExclNoFollow refuses an existing regular file and leaves it unchanged" );

    // (f4) createExclTempFile: a fresh regular file of shape prefix + 24 hex + suffix, removed unless committed
    std::string made;
    {
        rw::pathguard::ExclTempFile t = rw::pathguard::createExclTempFile( w + "/target.", ".tmp", 0600 );
        made = t.path();
        bool shape = t.ok() && made.size() == ( w + "/target." ).size() + 24 + 4 && made.compare( made.size() - 4, 4, ".tmp" ) == 0;
        for( std::size_t i = ( w + "/target." ).size(); shape && i < made.size() - 4; ++i )
        {
            const char c = made[ i ];
            shape = ( c >= '0' && c <= '9' ) || ( c >= 'a' && c <= 'f' );
        }
        row( shape && isReg( made ), "(f4) createExclTempFile yields a regular file named prefix + 24 hex + suffix" );
    }
    row( !made.empty() && ::access( made.c_str(), F_OK ) != 0, "(f4) the RAII holder removes an uncommitted temp" );

    // (f5) commit(): the bytes land at the final name and the temp is gone
    {
        rw::pathguard::ExclTempFile t = rw::pathguard::createExclTempFile( w + "/final.", ".tmp", 0644 );
        made = t.path();
        const bool wrote = t.write( "published" );
        row( wrote && t.commit( w + "/final.txt" ), "(f5) write + commit succeed" );
    }
    row( slurp( w + "/final.txt" ) == "published" && ::access( made.c_str(), F_OK ) != 0, "(f5) the final name holds the bytes and the temp is gone" );

    // (contrast) the old O_CREAT|O_TRUNC flags on the same fixture DO change the outside file: the checks above can fail
    const std::string outside2 = w + "/outside2.txt";
    const std::string lnk2     = w + "/contrast-link.tmp";
    spit( outside2, bytes );
    ::symlink( outside2.c_str(), lnk2.c_str() );
    fd = ::open( lnk2.c_str(), O_WRONLY | O_CREAT | O_TRUNC, 0644 );
    if( fd >= 0 ) { ::write( fd, "X", 1 ); ::close( fd ); }
    row( slurp( outside2 ) != bytes, "(contrast) an O_CREAT|O_TRUNC open through the same kind of link changes the outside file" );

    return failures == 0 ? 0 : 1;
}
CPP
if "$CXX" "$CXXSTD" -O1 -I"$ROOT/src" -I"$ROOT/src/infra" -I"$ROOT/third_party" "$PR/probe.cpp" -o "$PR/probe" 2> "$PR/cc.log"; then
    "$PR/probe" "$PR/work" > "$PR/out.txt" 2>&1
    PROBE_RC=$?
    PROBE_ROWS="$( grep -c '^PROBE-' "$PR/out.txt" )"
    [ "$PROBE_ROWS" -eq 9 ] \
        && ok "(f) presence: the probe reported all 9 rows" \
        || no "(f) the probe reported $PROBE_ROWS of 9 rows (rc=$PROBE_RC): $( head -c 300 "$PR/out.txt" )"
    while IFS= read -r prow; do
        case "$prow" in
            PROBE-PASS\ *) ok "${prow#PROBE-PASS }" ;;
            PROBE-FAIL\ *) no "${prow#PROBE-FAIL }" ;;
        esac
    done < "$PR/out.txt"
else
    no "(f) the pathguard probe did not compile with $CXX: $( head -5 "$PR/cc.log" | tr '\n' ' ' )"
fi

# (f6) source: createExclTempFile opens each candidate through openExclNoFollow and holds no other open
CET="$( awk 'index($0,"inline ExclTempFile createExclTempFile("){f=1} f{print} f&&/^}$/{exit}' "$ROOT/src/pathguard.h" )"
if [ -n "$CET" ] && printf '%s' "$CET" | grep -q 'openExclNoFollow(' && ! printf '%s' "$CET" | grep -qE '::open(at)?\('; then
    ok "(f6) createExclTempFile opens every candidate name through openExclNoFollow and nothing else"
else
    no "(f6) createExclTempFile does not open its candidates solely through openExclNoFollow"
fi

[ "$fail" = 0 ] && echo "ALL PASS" || { echo "FAILURES ABOVE"; exit 1; }
