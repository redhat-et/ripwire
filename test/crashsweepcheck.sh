#!/usr/bin/env bash
# crashsweepcheck.sh — process crashes, hangs and descriptor leaks reachable from input ripwire does not control,
# and the STATIC rules that keep their three shapes from being written again.
#
# THE DEFECTS, each reproduced on the base before its fix (the arm that shows it red is named):
#   (B1) A FILE* LEAKED ON EVERY SHORT READ. ingest_crawl.h's readFile closed its stream inside
#        `( got == want ) && ( std::fclose( fp ) == 0 )`: a file that came up short (truncated between the size
#        probe and the read) skipped the close. A long-lived server re-ingesting such a tree ran out of
#        descriptors, and from then on every file it could not open dropped out of the answer with exit 0.
#        Measured with the interposed short-read shim below: 300 of 600 short-read streams were never closed, and
#        under `ulimit -n 200` all 20 ordinary files vanished from a --grep answer. Fixed by an owner type,
#        rw::OwnedFile (src/infra/ownedfile.h), whose destructor closes on every path.
#   (B2) A FIXED-NAME FILE THAT IS NOT A REGULAR FILE. `.ripwire_config` and `.ripwire_quality_acks` were read
#        with a blocking open on the name. A FIFO there hung --quality-delta before any output (timeout 124); a
#        committed symlink from the ledger to /dev/zero or /dev/urandom never reached end of file (hang); a
#        DIRECTORY at `.ripwire_config` opens on Linux, and where a directory's seek reports LLONG_MAX (overlayfs)
#        the string that length asks for aborts — the shape ingest_crawl.h's PathShape note measured for
#        --cache=<dir>. Both now go through docparse::detail::readRegularFile: open O_NONBLOCK, ask the
#        descriptor, refuse anything that is not a regular file with a stderr line, and read it as absent. Red on
#        the base: the FIFO and device-link shapes hang (killed at 30 s); every shape is read without disclosure.
#   (B3) A TIMESTAMP PAST 2262. `tv_sec * 1000000000 + tv_nsec` overflowed `long long` for a file ext4, XFS,
#        tmpfs or a tar restore dates later than 2262-04-11: signed overflow — undefined behaviour in release,
#        an abort in the sanitizer build (reproduced on Linux tmpfs: "runtime error: signed integer overflow:
#        10000000000 * 1000000000"). Both stat readers now call rw::saturatingNanoseconds (infra/statclock.h).
#        APFS clamps timestamps at 2262, so on macOS the arm cannot build its input and says so.
#
# THE STATIC RULES — could these have been caught before they shipped? Three of the crash shapes are visible in
# the source, so each is now a rule, run with ripwire's own structural query (--match) over src/:
#   (S1) AN ALLOCATION SIZED BY A DECODED COUNT IS BOUNDED FIRST. In any function that decodes bytes through a
#        reader primitive (qsnapGet, pod, u8..u64, i32/i64, varint, lenDelim, view), a reserve/resize or a
#        std::vector/std::string size constructor whose size names a variable must be preceded, in the same
#        function, by a bound on it: countFits/qsnapCountFits/min/clamp over it, or a relational or equality
#        comparison against something that is not a literal 0 (one level of derivation is followed:
#        `need = n * width; if( left < need )`). Loop headers do not count — `i < n` walks a count, it does
#        not bound it. Red on the base: quality.h deserializeSnapshot `n` and deserializeRawCommitStream
#        `nCommits`/`nPaths` — the counts that reached reserve() straight from a checksum-valid blob.
#        CATCHES a count decoded and allocated in one function, alone or inside a larger size expression (sizeof
#        and .size() terms are stripped, not taken as proof). MISSES a count decoded in one function and allocated
#        in another, a primitive not in the list, a bound that is textually present but wrong, and a sizeof or
#        .size() term whose parentheses nest (its identifiers are then judged like any other).
#   (S2) EVERY RAW STREAM OR DESCRIPTOR ACQUISITION IS ACCOUNTED FOR. Each fopen/open/fdopen/openat/opendir/
#        open_memstream/popen call site must appear in the registry below with the fact that makes it safe
#        (owned by a destructor, closed on every return, or handed to a closer). A call passed straight to an owner
#        type's constructor — `OwnedFd fd( ::open( … ) )`, `OwnedFile fp( ::fdopen( … ) )` — is owned and needs no
#        row. A NEW raw site fails: wrap it in
#        rw::OwnedFile — `rw::openOwnedFile( path, mode )`, or `rw::OwnedFile f( ::fdopen( fd, mode ) )` — or
#        register it with its reason. And one shape is refused outright, registry or not: a close call as the
#        right operand of && or ||, or an arm of ?: — the exact expression that leaked (B1). Red on the base:
#        ingest_crawl.h readFile. A registry row that no longer matches a site also fails, so the list cannot
#        rot into permission for code that is gone. CATCHES a new raw acquisition and the short-circuited close.
#        MISSES a registered site whose body later grows an early return (the reason goes stale silently — the
#        owner type is the durable fix), and a throw between open and close, which only an owner prevents.
#   (S3) THREAD WORK DOES NOT THROW. A throw escaping a std::thread body is std::terminate, and in the MCP
#        server that turns one bad request into a dead server. Every lambda handed to a thread — `std::thread( [..] )`,
#        or `emplace_back` into a std::vector<std::thread>, inline or through a named local — must be declared
#        noexcept, or its body must be one try block. There is no templated pool to static_assert
#        std::is_nothrow_invocable in, so the rule reads the call sites. Red on the base: eight bare bodies.
#        CATCHES a new bare thread body. MISSES a thread started through a helper this query does not name.
#
# NON-VACUITY. Every static rule runs twice: over src/ (the verdict) and over a synthetic probe tree that holds
# one violation and one compliant twin per rule, where the violation must fire and the twin must not. A scan
# that reached the engine's hit cap, or ran against a binary that answered nothing, FAILS as partial.
#
# RUNTIME CHECKS. None of B1-B3 trips an assertion a debug build already has: an input-sized count is not an
# invariant (ASSUME on external data is forbidden), a short read is legal, and the timestamp overflow is seen
# only by the sanitizer build — which is why B3's red needs RIPWIRE_ASAN_BIN.
#
# Usage:  bash test/crashsweepcheck.sh [BIN]      RIPWIRE_ASAN_BIN=asan/ripwire bash test/crashsweepcheck.sh
set -u
ROOT="$( cd "$( dirname "$0" )/.." && pwd )"
BIN="${1:-${RIPWIRE_BIN:-$ROOT/build/ripwire}}"
[ "${BIN#/}" = "$BIN" ] && BIN="$ROOT/$BIN"
ASAN_BIN="${RIPWIRE_ASAN_BIN:-}"
[ -n "$ASAN_BIN" ] && [ "${ASAN_BIN#/}" = "$ASAN_BIN" ] && ASAN_BIN="$ROOT/$ASAN_BIN"
SRC="${RIPWIRE_CRASHSWEEP_SRC:-$ROOT/src}"   # the tree the static rules read; a red-first run points it at a base checkout
TMP="$( mktemp -d )"; trap 'chmod -R u+w "$TMP" 2>/dev/null; rm -rf "$TMP"' EXIT
fail=0

ok(){ printf '  PASS  %s\n' "$*" || { fail=1; printf '  FAIL  could not write the PASS line for: %s\n' "$*"; }; return 0; }
no(){ printf '  FAIL  %s\n' "$*"; fail=1; }
note(){ printf '  NOTE  %s\n' "$*"; }
skip(){ printf '  SKIP  %s\n' "$*"; }
bounded_run(){ if command -v timeout >/dev/null 2>&1; then timeout 30 "$@"; else perl -e 'alarm 30; exec @ARGV' "$@"; fi; }
is_hang(){ [ "$1" -eq 124 ] || [ "$1" -eq 142 ]; }
is_sanitized(){ LC_ALL=C grep -q -a '__asan_init' "$1" 2>/dev/null; }
bin_tag(){ is_sanitized "$1" && printf 'asan' || printf 'plain'; }

[ -x "$BIN" ] || { echo "no ripwire binary at $BIN — build first (cmake --build build -j)"; exit 2; }
command -v python3 >/dev/null 2>&1 || { echo "python3 required"; exit 2; }
command -v git >/dev/null 2>&1 || { echo "git required"; exit 2; }
echo "crashsweepcheck: BIN=$BIN  ASAN_BIN=${ASAN_BIN:-none}  SRC=$SRC"
RUN_BINS=( "$BIN" )   # the behavioural arms run once per distinct binary
[ -n "$ASAN_BIN" ] && [ "$ASAN_BIN" != "$BIN" ] && RUN_BINS+=( "$ASAN_BIN" )

# ═══════════════════════════════════════════════════════════════════════════════════════════════════
echo
echo "=== static rules S1-S3 (ripwire --match over the source) ==="
# ═══════════════════════════════════════════════════════════════════════════════════════════════════
cat > "$TMP/scan.py" <<'SCANPY'
# static scan driver: python3 scan.py BIN SRC OUT
import html, os, re, subprocess, sys
from collections import Counter, defaultdict

BIN, SRC, OUT = sys.argv[1], sys.argv[2], sys.argv[3]
os.makedirs(OUT, exist_ok=True)

def match(query):
    """Run one --match over SRC; return [(file, line, fn, text)] and fail loudly if the scan was partial."""
    # A sanitizer job may route reports to a log file (log_path=…); the scan's own runs report on stderr instead,
    # so a sanitizer abort here names its cause in the gate output rather than as a bare rc=-6.
    env = dict(os.environ)
    for key in ("ASAN_OPTIONS", "UBSAN_OPTIONS", "LSAN_OPTIONS"):
        env[key] = (env[key] + ":" if env.get(key) else "") + "log_path=stderr"
    proc = subprocess.run([BIN, SRC, "--match=" + query, "--limit=5000"], capture_output=True, text=True, env=env)
    root = re.search(r"<match [^>]*>", proc.stdout)
    if proc.returncode != 0 or root is None:
        print("SCANFAIL rc=%d query=%s stderr=%s" % (proc.returncode, query[:80], proc.stderr[-1200:]))
        sys.exit(3)
    if 'hits_capped="1"' in root.group(0):
        print("SCANFAIL engine hit cap reached — the scan is partial: " + query[:80])
        sys.exit(3)
    rows = []
    for p, fn, text in re.findall(r'<m p="([^"]*)" in="([^"]*)">(.*?)</m>', proc.stdout, re.S):
        f, _, ln = p.rpartition(":")
        rows.append((f, int(ln), html.unescape(fn), html.unescape(text)))
    return rows

def pairs(rows):
    """Queries below bind a predicate capture then the payload capture: rows arrive in that order, two per match."""
    if len(rows) % 2:
        print("SCANFAIL odd row count for a two-capture query"); sys.exit(3)
    return [(a[0], a[1], a[2], a[3], b[3]) for a, b in zip(rows[0::2], rows[1::2])]

lines_cache = {}
def lines_of(f):
    if f not in lines_cache:
        with open(os.path.join(SRC, f), encoding="utf-8", errors="replace") as fh:
            lines_cache[f] = fh.read().split("\n")
    return lines_cache[f]

# ── S1: an allocation sized by a count a byte reader decoded must be bounded first ────────────────────────────
READERS = "^(qsnapGet|pod|u8|u16|u32|u64|i32|i64|varint|lenDelim|view)$"
readerFns = set()
for f, ln, fn, text in match('(call_expression function: [(identifier) @r (qualified_identifier name: (identifier) @r) '
                             '(field_expression field: (field_identifier) @r) (template_function name: (identifier) @r) '
                             '(field_expression field: (template_method name: (field_identifier) @r))] (#match? @r "%s"))' % READERS):
    readerFns.add((f, fn))
allocs  = pairs(match('(call_expression function: (field_expression field: (field_identifier) @_m) arguments: (argument_list . (_) @size) '
                      '(#match? @_m "^(reserve|resize)$"))'))
allocs += pairs(match('(declaration type: [(qualified_identifier) (template_type)] @_t declarator: (init_declarator value: (argument_list . (_) @size)) '
                      '(#match? @_t "^std::(vector|string|basic_string)"))'))
fnStarts = defaultdict(list)
for f, ln, fn, name in match('(function_definition declarator: (function_declarator declarator: (_) @name))'):
    fnStarts[(f, name.split("::")[-1])].append(ln)

# Terms that size by an in-memory container or a type. They are STRIPPED from the size expression, not used to
# excuse it: `reserve( n * sizeof( T ) )` still has to bound `n`.
SAFE_TERM = re.compile(r"\bsizeof\s*\([^()]*\)|\bsizeof\s+[A-Za-z_]\w*|[A-Za-z_][\w.\[\]]*\s*(\.|->)\s*(size|length)\(\s*\)")
def bound_in(f, fn, ident, allocLine):
    starts = [s for s in fnStarts.get((f, fn), []) if s <= allocLine]
    start = max(starts) if starts else max(1, allocLine - 200)
    text = lines_of(f)[start - 1:allocLine]
    names = {ident}
    for line in text:                                    # one level of derivation: `need = n * width;`
        for m in re.finditer(r"\b([A-Za-z_]\w*)\s*=\s*[^;=]*\b" + re.escape(ident) + r"\b", line):
            names.add(m.group(1))
    for line in text:
        if re.search(r"\bfor\s*\(", line):
            continue                                     # a loop header's `i < n` walks the count, it does not bound it
        for name in names:
            n = re.escape(name)
            if re.search(r"\b(countFits|qsnapCountFits|min|clamp)\s*\([^;]*\b" + n + r"\b", line):
                return True
            if re.search(r"\b" + n + r"\b\s*(<=|>=|==|!=|<(?![<=])|>(?![>=]))\s*(?!0\b)[A-Za-z_(]", line):
                return True
            if re.search(r"[A-Za-z_)\]]\s*(?<![-<>])(<=|>=|==|!=|<|>)\s*(std::size_t\s*\(\s*)?\b" + n + r"\b", line):
                return True
    return False

with open(os.path.join(OUT, "s1.tsv"), "w") as out:
    for f, ln, fn, _kind, size in allocs:
        if (f, fn) not in readerFns:
            continue
        rest = SAFE_TERM.sub(" ", size)
        idents = [i for i in re.findall(r"\b[A-Za-z_]\w*\b", rest) if not re.match(r"^(k[A-Z]\w*|std|size_t|static_cast|uint32_t|uint64_t|int)$", i)]
        if not idents:
            continue
        unbounded = [i for i in idents if not bound_in(f, fn, i, ln)]
        if unbounded:
            out.write("%s\t%s\t%s\t%d\n" % (f, fn, unbounded[0], ln))

# ── S2: raw stream/descriptor acquisitions, and a close hidden behind a short-circuit ────────────────────────
# src/infra/os.h is THE seam (see its own header comment): every call site elsewhere now spells these openers
# os::X or rw::os::X, so the regex accepts that prefix too — a call keeps the same registry row (file, fn, opener
# name) whichever spelling it uses, via the kind.split("::")[-1] normalisation below. os.h's OWN wrapper
# DEFINITIONS are the one place the bare libc call still appears; that is the seam working as designed, not an
# unregistered site, so this one file is exempt by name (not by widening the pattern that finds sites elsewhere).
OS_SEAM_HEADER = "infra/os.h"
OPENERS = "^(std::|::|os::|rw::os::)?(fopen|open|fdopen|openat|opendir|open_memstream|popen)$"
sites = Counter()
for f, ln, fn, kind, _call in pairs(match('(call_expression function: [(identifier) @f (qualified_identifier) @f] (#match? @f "%s")) @call' % OPENERS)):
    if f == OS_SEAM_HEADER:
        continue
    sites[(f, fn, kind.split("::")[-1])] += 1
# An acquisition handed straight to an owner type needs no registry row: `OwnedFd fd( ::open( … ) )`,
# `OwnedFile fp( ::fdopen( … ) )`, `return OwnedFile( std::fopen( … ) )`. The owner's destructor closes on every path.
OWNERS = "(^|::)(OwnedFd|OwnedFile)$"
owned = Counter()
for shape in ('(declaration type: [(type_identifier) (qualified_identifier)] @_t declarator: (init_declarator value: (argument_list . '
              '(call_expression function: [(identifier) (qualified_identifier)] @f))) (#match? @_t "%s") (#match? @f "%s"))',
              '(call_expression function: [(identifier) (qualified_identifier)] @_t arguments: (argument_list . '
              '(call_expression function: [(identifier) (qualified_identifier)] @f)) (#match? @_t "%s") (#match? @f "%s"))'):
    for f, ln, fn, _owner, kind in pairs(match(shape % (OWNERS, OPENERS))):
        if f == OS_SEAM_HEADER:
            continue
        owned[(f, fn, kind.split("::")[-1])] += 1
for key, n in owned.items():
    sites[key] -= n
    if sites[key] <= 0:
        del sites[key]
with open(os.path.join(OUT, "s2_sites.tsv"), "w") as out:
    for (f, fn, kind), n in sorted(sites.items()):
        out.write("%s\t%s\t%s\t%d\n" % (f, fn, kind, n))
CLOSERS = "^(std::|::)?(fclose|pclose|close|closedir)$"
shortCircuit = []
for shape in ('(binary_expression operator: ["&&" "||"] right: (call_expression function: (_) @c) (#match? @c "%s"))',
              '(binary_expression operator: ["&&" "||"] right: (binary_expression left: (call_expression function: (_) @c)) (#match? @c "%s"))',
              '(binary_expression operator: ["&&" "||"] right: (parenthesized_expression (binary_expression left: (call_expression function: (_) @c))) (#match? @c "%s"))',
              '(binary_expression operator: ["&&" "||"] right: (unary_expression argument: (call_expression function: (_) @c)) (#match? @c "%s"))',
              '(conditional_expression consequence: (call_expression function: (_) @c) (#match? @c "%s"))',
              '(conditional_expression alternative: (call_expression function: (_) @c) (#match? @c "%s"))'):
    for f, ln, fn, text in match(shape % CLOSERS):
        shortCircuit.append((f, fn, ln))
with open(os.path.join(OUT, "s2_shortcircuit.tsv"), "w") as out:
    for f, fn, ln in sorted(set(shortCircuit)):
        out.write("%s\t%s\t%d\n" % (f, fn, ln))

# ── S3: every lambda handed to a std::thread is declared noexcept, or is one try block ───────────────────────
def lambda_text(f, ln, name):
    """The text of `auto name = [..](..) ... {` .. `}` declared at or above line `ln` of f."""
    ls = lines_of(f)
    for i in range(ln - 1, max(0, ln - 400), -1):
        if re.search(r"\bauto\s+" + re.escape(name) + r"\s*=\s*\[", ls[i]):
            return "\n".join(ls[i:i + 400])
    return None

def compliant(text):
    brace = text.find("{")
    if brace < 0:
        return False
    head = text[:brace]
    body = re.sub(r"^(\s|//[^\n]*\n)*", "", text[brace + 1:])
    return "noexcept" in head or body.startswith("try")

threadFiles = set(f for f, ln, fn, t in match('(template_argument_list (type_descriptor type: (qualified_identifier) @_t) (#match? @_t "^std::thread$"))'))
bodies = []
for f, ln, fn, _e, arg in pairs(match('(call_expression function: (field_expression field: (field_identifier) @_e) arguments: (argument_list . (_) @arg .) '
                                      '(#match? @_e "^emplace_back$"))')):
    if f not in threadFiles:
        continue
    if arg.lstrip().startswith("["):
        bodies.append((f, fn, ln, arg))
    elif re.match(r"^[A-Za-z_]\w*$", arg.strip()):
        text = lambda_text(f, ln, arg.strip())
        if text is not None:
            bodies.append((f, fn, ln, text))
for f, ln, fn, _t, lam in pairs(match('(call_expression function: (qualified_identifier) @_t arguments: (argument_list (lambda_expression) @lam) '
                                      '(#match? @_t "^std::thread$"))')):
    bodies.append((f, fn, ln, lam))
with open(os.path.join(OUT, "s3.tsv"), "w") as out:
    for f, fn, ln, text in sorted(bodies, key=lambda r: (r[0], r[2])):
        out.write("%s\t%s\t%d\t%s\n" % (f, fn, ln, "ok" if compliant(text) else "bare"))
print("SCANOK readers=%d allocs=%d openers=%d threadbodies=%d" % (len(readerFns), len(allocs), sum(sites.values()), len(bodies)))
SCANPY

cat > "$TMP/registry.tsv" <<'REGISTRY'
ccjson.h	ccCountLoc	fopen	1	closes	the only early exit is the failed open; nothing between open and fclose allocates
clones.h	findClones	fopen	1	closes	skips only a failed open; fclose right after the sized read
clones.h	findClonesType3	fopen	1	closes	same shape as findClones
crossref.h	evalStray	fopen	1	closes	returns only on a failed open; fclose after the read loop
crossref.h	streamBlobs	fopen	1	closes	returns only on a failed open; fclose after the list is written
crossref.h	streamBlobs	popen	1	closes	the read loop leaves by break/continue only; pclose then unlink
darkflags.h	readWhole	fopen	1	closes	fclose before the size-cap return and before the final return
docparse.h	openRegularFileStream	fdopen	1	owned	stored straight into pathguard::NoFollowRead, whose destructor fcloses it
docparse.h	openRegularFileStream	open	1	owned	fdopen'd into NoFollowRead; ::close only when fdopen declined it
docparse.h	runMarkitdown	popen	1	closes	no exit between popen and pclose
gitmine.h	gitCommandLines	popen	1	closes	status = pclose after the loop; no exit between
gitmine.h	gitFileAuthors	popen	1	closes	continue-only loop; pclose after it
gitmine.h	gitFileCommitCountsInDayWindow	popen	1	closes	continue-only loop; pclose after it
gitmine.h	gitLogDecayedFileMining	popen	1	closes	continue-only loop; pclose after the flush
gitmine.h	gitLogFileSets	popen	1	closes	continue-only loop; pclose after the flush
gitmine.h	gitLogNameOnlyRaw	popen	1	closes	continue-only loop; pclose after it
gitmine.h	popenTrimmed	popen	1	closes	no exit between popen and pclose
gitoracle.h	loadOracleCache	fopen	1	closes	returns only on a failed open; fclose after the read loop
gitoracle.h	saveOracleCache	fdopen	1	closes	adopts ExclTempFile's released fd; fclose on its own line; a failed fdopen ::closes the fd
gitoracle.h	walkGitPatch	popen	1	closes	break-only loops, a drain, then pclose; no return between
infra/emit.h	open	open_memstream	1	owned	rw::MemoryStream: the destructor fcloses a stream nobody finished and frees the buffer on every path; finish() closes exactly once
ingest_cache.h	openOnce	open	1	owned	ReadFd's destructor closes it
ingest_cache.h	saveCache	fdopen	1	closes	adopts ExclTempFile's released fd; fclose on its own line; a failed fdopen ::closes the fd
ingest_crawl.h	collectGitIgnored	popen	1	closes	the overflow break still reaches pclose
ingest_docpass.h	publishDocBridgeBlob	fdopen	1	closes	adopts ExclTempFile's released fd; fclose on its own line; a failed fdopen ::closes the fd
lintrules.h	loadLintRules	fopen	1	closes	skips only a failed open; fclose after the sized read
main.cpp	dispatchMain	fopen	1	closes	returns only on a failed open; fclose after the read loop
main.cpp	resolveRemoteRoot	popen	1	closes	no exit between popen and pclose
main.cpp	runDefaultMap	fopen	1	closes	returns only on a failed open; fclose after the render
main.cpp	scipIndexUnreadableReason	open	1	closes	close right after fstat, before every return
mcpedit.h	EditLock	open	1	owned	EditLock's destructor unlocks and closes
mcpindex.h	arm	open	1	owned	held in FsWatcher::dirFds, closed by reset and the destructor
mcpindex.h	readFileBytes	fopen	1	closes	fclose before both returns
mcpverbs.h	packConnect	fopen	1	closes	if-scoped; fclose after the read
mcpverbs.h	sliceText	fopen	1	closes	if-scoped; fclose after the read loop
naminglens.h	namingLensChecks	fopen	1	closes	if-scoped; fclose after the sized read
packtask.h	d1ReadSrcCached	fopen	1	closes	if-scoped; fclose after the read loop
pathguard.h	openExclNoFollow	open	1	transferred	returned to createExclTempFile, which adopts it into ExclTempFile (closes and unlinks)
pathguard.h	openNoFollowRead	fdopen	1	owned	adopted by NoFollowRead, whose destructor fcloses
pathguard.h	openNoFollowRead	open	1	owned	closed on every refusal; otherwise fdopen'd into NoFollowRead
pathguard.h	openNoFollowTruncate	open	1	transferred	every caller hands the descriptor to writeAllAndClose, which always closes
pathguard.h	randomTempSuffix	open	1	closes	::close after the read loop, before the only exit; only ::read runs between
pathguard.h	readWholeBeneathNoFollow	openat	1	transferred	the next statement's cur.reset( next ) adopts it into OwnedFd; the only return between is the failed open
pincensus.h	writePinCensus	fopen	1	closes	returns only on a failed open; one fclose before the return
planlint.h	gitBlameLineSha	popen	1	closes	no exit between popen and pclose
prcontext.h	numstatChangedPaths	popen	1	closes	rc = pclose after the loop; no exit between
quality.h	SidecarWriteLock	open	1	owned	SidecarWriteLock's destructor unlocks and closes
quality.h	gitBlameRangeWindowCommits	popen	1	closes	continue-only loop; pclose after it
quality.h	gitDiffHunksVsHead	popen	1	closes	continue-only loop; pclose after it
quality.h	gitRepoHasHistory	popen	1	closes	fgets-only loop, then pclose
quality.h	sweepStaleEditLocks	open	1	closes	skips only a failed open; close after flock and unlink
resolve.h	readConfigBytes	fopen	1	closes	returns only on a failed open; fclose before the return
scip.h	scipReadFile	fdopen	1	closes	fclose before each of the three returns
scip.h	scipReadFile	open	1	closes	::close when fstat, fcntl or fdopen fails; otherwise the stream owns it
serialize.h	collectJsonSigEntries	fopen	1	closes	skips only a failed open; fclose after the read loop
serialize.h	estimateExpandBodyTokens	fopen	1	closes	if-scoped; fclose after the read loop
serialize.h	openChargeBuffer	open_memstream	1	transferred	its only caller is openChargeStream, which hands it to rw::MemoryStream::openWith; the MemoryStream owns it from there
serialize.h	packBodies	fopen	1	closes	if-scoped; fclose after the read loop
serialize.h	packCandidates	fopen	1	closes	if-scoped; fclose after the read loop
serialize.h	packHops	fopen	1	closes	if-scoped; fclose after the read loop
serialize.h	packLego	fopen	1	closes	if-scoped; fclose after the read loop
serialize.h	packOutline	fopen	1	closes	skips only a failed open; fclose after the read loop
serialize.h	packSignatures	fopen	2	closes	both skip only a failed open; fclose after each read loop
serialize.h	packSource	fopen	1	closes	skips only a failed open; fclose after the read loop
serialize.h	renderWholeFiles	fopen	1	closes	returns only on a failed open; fclose before the empty-body return
skillsinstall.h	runShellCapture	popen	1	closes	no exit between popen and pclose; the read loop leaves by fread returning 0
skillsinstall.h	writeStoreFile	open	1	closes	the only early exit is the failed open; FdGuard closes it on every remaining path
verbs_change.h	readBriefFile	fopen	1	closes	continue-only loop; fclose before the return
verbs_change.h	readTraceText	fopen	1	closes	returns only on a failed open; fclose after the read loop
verbs_change.h	runChangeViews	fopen	1	closes	returns only on a failed open; fclose after the write
verbs_doctor.h	doctorSameFileBytes	fopen	2	closes	break-only loop; each stream is fclosed on every path
verbs_doctor.h	runDoctor	fopen	1	closes	if-scoped fputs then fclose
verbs_lint.h	lintSymbolLevelChecks	fopen	1	closes	if-scoped; fclose after the sized read
verbs_lint.h	parseProfTsv	fopen	1	closes	returns only on a failed open; fclose after the read loop
verbs_navigate.h	runSafeDelete	fopen	1	closes	if-scoped; fclose after the sized read
verbs_navigate.h	runSlice	fopen	1	closes	if-scoped; fclose after the read loop
verbs_quality.h	runQualityViews	fopen	1	closes	returns on a failed open; fclose before the other return
REGISTRY

# The allocations S1 reports inside a reader function whose size is NOT a decoded count, with why.
cat > "$TMP/s1_allow.tsv" <<'S1ALLOW'
ingest_cache.h	finishCacheBlob	entryCount	writer: entryCount counts the in-memory records being written, not a decoded field
ingest_cache.h	saveCache	slotCount	writer: slotCount sizes the table from the in-memory plan, not a decoded field
S1ALLOW
# The short-circuited closes S2 refuses, registered with why. Empty: the one row this held (saveCache) excused a live
# instance of B1's exact shape until #250 made its fclose unconditional, and a stale row now fails the gate.
cat > "$TMP/s2_shortcircuit_allow.tsv" <<'S2ALLOW'
S2ALLOW
# Thread bodies S3 reports as bare, with why each is accepted. Empty: the one row this held (search.h grepCollect,
# accepted because every throwing statement sat inside a catch(...) that recorded the degrade) excused nothing once
# lane/regex-long-lines moved the scan threads onto src/infra/stackthreads.h, and a stale row fails the gate.
cat > "$TMP/s3_allow.tsv" <<'S3ALLOW'
S3ALLOW

judge_static(){   # $1 = scan output dir, $2 = label; echoes one line per violation, returns 0
    python3 - "$1" "$TMP" "$2" <<'JUDGEPY'
import os, sys
out, tmp, label = sys.argv[1], sys.argv[2], sys.argv[3]
def rows(path):
    if not os.path.exists(path):
        return []
    return [l.rstrip("\n").split("\t") for l in open(path) if l.strip()]
allow1  = {(r[0], r[1], r[2]) for r in rows(tmp + "/s1_allow.tsv")}
allowSc = {(r[0], r[1]) for r in rows(tmp + "/s2_shortcircuit_allow.tsv")}
allow3  = {(r[0], r[1]) for r in rows(tmp + "/s3_allow.tsv")}
used1, usedSc, used3 = set(), set(), set()
registry = {(r[0], r[1], r[2]): int(r[3]) for r in rows(tmp + "/registry.tsv")}
for f, fn, ident, ln in rows(out + "/s1.tsv"):
    if label == "src" and (f, fn, ident) in allow1:
        used1.add((f, fn, ident))
    else:
        print("S1\t%s:%s (%s) sizes an allocation by `%s` with no bound on it earlier in the function" % (f, ln, fn, ident))
for f, fn, ln in rows(out + "/s2_shortcircuit.tsv"):
    if label == "src" and (f, fn) in allowSc:
        usedSc.add((f, fn))
    else:
        print("S2\t%s:%s (%s) closes a handle inside && / || / ?: — a short-circuit skips the close; own it (rw::OwnedFile)" % (f, ln, fn))
seen = {}
for f, fn, kind, n in rows(out + "/s2_sites.tsv"):
    seen[(f, fn, kind)] = int(n)
if label == "src":
    for key, n in sorted(seen.items()):
        if registry.get(key) != n:
            print("S2\t%s %s: %d raw %s call(s), registry says %s — wrap it in rw::OwnedFile (rw::openOwnedFile) or register it with the reason every path closes it" % (key[0], key[1], n, key[2], registry.get(key, 0)))
    for key, n in sorted(registry.items()):
        if key not in seen:
            print("S2\tregistry row %s %s %s matches no site any more — delete the row" % key)
else:
    for key, n in sorted(seen.items()):
        print("S2\t%s %s: %d raw %s call(s) outside the registry" % (key[0], key[1], n, key[2]))
for f, fn, ln, verdict in rows(out + "/s3.tsv"):
    if verdict != "bare":
        continue
    if label == "src" and (f, fn) in allow3:
        used3.add((f, fn))
    else:
        print("S3\t%s:%s (%s) hands a thread a body that is neither noexcept nor one try block" % (f, ln, fn))
# An allow row that excuses nothing any more is a stale permission: it would silently excuse the next site of that
# name. Each one fails until it is deleted.
if label == "src":
    for rule, allowed, used in (("S1", allow1, used1), ("S2", allowSc, usedSc), ("S3", allow3, used3)):
        for row in sorted(allowed - used):
            print("%s\tallow row %s excuses nothing any more — delete the row" % (rule, " ".join(row)))
JUDGEPY
}

# The probe tree: one violation and one compliant twin per rule.
PROBE="$TMP/probe"; mkdir -p "$PROBE"
cat > "$PROBE/probe_reader.h" <<'PROBEH'
#include <cstdio>
#include <string>
#include <thread>
#include <vector>
inline bool qsnapGet( const char*& p, const char* end, unsigned& out );
inline bool probeUnbounded( const char* p, const char* end, std::vector<unsigned long>& v )
{
    unsigned n = 0;
    if( !qsnapGet( p, end, n ) ) { return false; }
    v.reserve( n );
    return true;
}
inline bool probeBounded( const char* p, const char* end, std::vector<unsigned long>& v )
{
    unsigned m = 0;
    if( !qsnapGet( p, end, m ) || !qsnapCountFits( p, end, m, 8 ) ) { return false; }
    v.reserve( m );
    return true;
}
inline bool probeShortCircuit( const char* path )
{
    std::FILE* fp = std::fopen( path, "rb" );
    const bool ok = ( fp != nullptr ) && ( std::fclose( fp ) == 0 );
    return ok;
}
struct OwnedFd { explicit OwnedFd( int ) noexcept {} };
inline void probeOwnedDescriptor( const char* path )
{
    const OwnedFd fd( ::open( path, 0 ) );   // handed straight to an owner: S2 must not count it
}
namespace os { std::FILE* fopen( const char* path, const char* mode ); }   // stands in for rw::os::fopen
inline void probeOsSpelling( const char* path )
{
    std::FILE* fp = os::fopen( path, "rb" );   // os::-spelled site, unregistered: S2 must still catch it
    (void)fp;
}
inline void probeThreads()
{
    std::vector<std::thread> pool;
    pool.emplace_back( [ & ]() { probeShortCircuit( "x" ); } );
    pool.emplace_back( [ & ]() noexcept { probeShortCircuit( "y" ); } );
    for( std::thread& t : pool ) { t.join(); }
}
PROBEH
if ! python3 "$TMP/scan.py" "$BIN" "$PROBE" "$TMP/probe_out" >"$TMP/probe_scan.txt" 2>&1; then
    no "static rules: the probe scan did not complete:"; sed 's/^/          /' "$TMP/probe_scan.txt" | tail -25
else
    judge_static "$TMP/probe_out" probe >"$TMP/probe_verdict.txt"
    grep -q 'S1	probe_reader.h:[0-9]* (probeUnbounded)' "$TMP/probe_verdict.txt" && ! grep -q 'probeBounded' "$TMP/probe_verdict.txt" \
        && ok "S1 probe: the unbounded reserve fires and its bounded twin does not" \
        || { no "S1 probe: expected probeUnbounded only"; cat "$TMP/probe_verdict.txt"; }
    grep -q 'S2	probe_reader.h:[0-9]* (probeShortCircuit) closes a handle inside' "$TMP/probe_verdict.txt" \
        && ok "S2 probe: the short-circuited fclose fires" || { no "S2 probe: the short-circuited fclose did not fire"; cat "$TMP/probe_verdict.txt"; }
    grep -q 'S2	probe_reader.h probeShortCircuit: 1 raw fopen' "$TMP/probe_verdict.txt" \
        && ok "S2 probe: an unregistered raw fopen fires" || { no "S2 probe: the unregistered raw fopen did not fire"; cat "$TMP/probe_verdict.txt"; }
    grep -q 'probeOwnedDescriptor' "$TMP/probe_verdict.txt" \
        && { no "S2 probe: an open handed straight to OwnedFd was counted as raw"; cat "$TMP/probe_verdict.txt"; } \
        || ok "S2 probe: an open handed straight to an owner type (OwnedFd) is not counted"
    grep -q 'S2	probe_reader.h probeOsSpelling: 1 raw fopen' "$TMP/probe_verdict.txt" \
        && ok "S2 probe: an os::-spelled unregistered site still fires (the seam's own spelling is not a free pass)" \
        || { no "S2 probe: an os::-spelled unregistered site did not fire"; cat "$TMP/probe_verdict.txt"; }
    [ "$( grep -c '^S3' "$TMP/probe_verdict.txt" )" -eq 1 ] \
        && ok "S3 probe: the bare thread body fires and its noexcept twin does not" \
        || { no "S3 probe: expected exactly one bare thread body"; cat "$TMP/probe_verdict.txt"; }
fi

if ! python3 "$TMP/scan.py" "$BIN" "$SRC" "$TMP/src_out" >"$TMP/src_scan.txt" 2>&1; then
    no "static rules: the source scan did not complete:"; sed 's/^/          /' "$TMP/src_scan.txt" | tail -25
else
    SUMMARY="$( grep '^SCANOK' "$TMP/src_scan.txt" )"
    READERS="$( printf '%s' "$SUMMARY" | sed -E 's/.*readers=([0-9]+).*/\1/' )"
    OPENERS="$( printf '%s' "$SUMMARY" | sed -E 's/.*openers=([0-9]+).*/\1/' )"
    BODIES="$( printf '%s' "$SUMMARY" | sed -E 's/.*threadbodies=([0-9]+).*/\1/' )"
    if [ "${READERS:-0}" -ge 5 ] && [ "${OPENERS:-0}" -ge 20 ] && [ "${BODIES:-0}" -ge 5 ]; then
        ok "static rules reached the source ($SUMMARY)"
    else
        no "static rules found almost nothing to judge ($SUMMARY) — a broken query reads as a clean tree"
    fi
    judge_static "$TMP/src_out" src >"$TMP/src_verdict.txt"
    for rule in S1 S2 S3; do
        if grep -q "^$rule" "$TMP/src_verdict.txt"; then
            no "$rule: $( grep -c "^$rule" "$TMP/src_verdict.txt" ) violation(s):"
            grep "^$rule" "$TMP/src_verdict.txt" | cut -f2 | sed 's/^/          /'
        else
            ok "$rule: no violation in $SRC"
        fi
    done
fi

# ═══════════════════════════════════════════════════════════════════════════════════════════════════
echo
echo "=== B1: a short read closes its stream (interposed short-read shim) ==="
# ═══════════════════════════════════════════════════════════════════════════════════════════════════
# The shim shortens every fread on a stream opened on a path containing RWSHIM_MATCH by one byte and counts how
# many of those streams the program closed; the counts land in RWSHIM_LOG at exit. A plain binary only: the
# sanitizer runtime must come first in the preload order on Linux, and nothing here needs it.
SHIM_SRC="$TMP/shortread.c"
cat > "$SHIM_SRC" <<'SHIMC'
#define _GNU_SOURCE
#include <fcntl.h>
#include <pthread.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>
#ifndef __APPLE__
#include <dlfcn.h>
#endif
#define MAXS 8192
static FILE* marked[MAXS];
static unsigned long opened, closed, shorted;
static pthread_mutex_t mu = PTHREAD_MUTEX_INITIALIZER;
static int logFd = -1;
#ifdef __APPLE__
static FILE* real_fopen( const char* p, const char* m ) { return fopen( p, m ); }
static size_t real_fread( void* b, size_t s, size_t n, FILE* f ) { return fread( b, s, n, f ); }
static int real_fclose( FILE* f ) { return fclose( f ); }
#else
static FILE* real_fopen( const char* p, const char* m ) { FILE* (*fn)( const char*, const char* ) = dlsym( RTLD_NEXT, "fopen" ); return fn( p, m ); }
static size_t real_fread( void* b, size_t s, size_t n, FILE* f ) { size_t (*fn)( void*, size_t, size_t, FILE* ) = dlsym( RTLD_NEXT, "fread" ); return fn( b, s, n, f ); }
static int real_fclose( FILE* f ) { int (*fn)( FILE* ) = dlsym( RTLD_NEXT, "fclose" ); return fn( f ); }
#endif
static int isMarked( FILE* f ) { int hit = 0; pthread_mutex_lock( &mu ); for( int i = 0; i < MAXS; ++i ) { if( marked[i] == f ) { hit = 1; break; } } pthread_mutex_unlock( &mu ); return hit; }
FILE* rw_fopen( const char* p, const char* m )
{
    FILE* f = real_fopen( p, m );
    const char* match = getenv( "RWSHIM_MATCH" );
    if( f && match && *match && strstr( p, match ) && m && m[0] == 'r' )
    {
        pthread_mutex_lock( &mu );
        for( int i = 0; i < MAXS; ++i ) { if( marked[i] == NULL ) { marked[i] = f; ++opened; break; } }
        pthread_mutex_unlock( &mu );
    }
    return f;
}
size_t rw_fread( void* b, size_t s, size_t n, FILE* f )
{
    if( n > 1 && isMarked( f ) ) { pthread_mutex_lock( &mu ); ++shorted; pthread_mutex_unlock( &mu ); return real_fread( b, s, n - 1, f ); }
    return real_fread( b, s, n, f );
}
int rw_fclose( FILE* f )
{
    pthread_mutex_lock( &mu );
    for( int i = 0; i < MAXS; ++i ) { if( marked[i] == f ) { marked[i] = NULL; ++closed; break; } }
    pthread_mutex_unlock( &mu );
    return real_fclose( f );
}
__attribute__((constructor)) static void openLog( void ) { const char* log = getenv( "RWSHIM_LOG" ); if( log ) { logFd = open( log, O_WRONLY | O_CREAT | O_TRUNC, 0644 ); } }
__attribute__((destructor)) static void report( void ) { if( logFd >= 0 ) { dprintf( logFd, "opened=%lu shorted=%lu closed=%lu\n", opened, shorted, closed ); close( logFd ); } }
#ifdef __APPLE__
#define INTERPOSE( r, o ) __attribute__((used)) static struct { const void* rep; const void* orig; } interpose_##o __attribute__((section( "__DATA,__interpose" ))) = { (const void*)&r, (const void*)&o };
INTERPOSE( rw_fopen, fopen )
INTERPOSE( rw_fread, fread )
INTERPOSE( rw_fclose, fclose )
#else
FILE* fopen( const char* p, const char* m ) { return rw_fopen( p, m ); }
FILE* fopen64( const char* p, const char* m ) { return rw_fopen( p, m ); }
size_t fread( void* b, size_t s, size_t n, FILE* f ) { return rw_fread( b, s, n, f ); }
size_t __fread_chk( void* b, size_t bl, size_t s, size_t n, FILE* f ) { (void)bl; return rw_fread( b, s, n, f ); }
int fclose( FILE* f ) { return rw_fclose( f ); }
#endif
SHIMC
CC_BIN="$( command -v cc || command -v clang || command -v gcc || true )"
if is_sanitized "$BIN" || LC_ALL=C grep -q -a '__tsan_init' "$BIN" 2>/dev/null; then
    skip "B1: $BIN is a sanitizer build — the preload shim needs a plain binary"
elif [ -z "$CC_BIN" ]; then
    skip "B1: no C compiler to build the short-read shim"
else
    if [ "$( uname -s )" = "Darwin" ]; then
        "$CC_BIN" -O1 -dynamiclib -o "$TMP/shortread.so" "$SHIM_SRC" 2>"$TMP/shim_cc.txt"; PRELOAD_VAR=DYLD_INSERT_LIBRARIES
    else
        "$CC_BIN" -O1 -shared -fPIC -o "$TMP/shortread.so" "$SHIM_SRC" -ldl -lpthread 2>"$TMP/shim_cc.txt"; PRELOAD_VAR=LD_PRELOAD
    fi
    if [ ! -f "$TMP/shortread.so" ]; then
        skip "B1: the short-read shim did not compile: $( head -2 "$TMP/shim_cc.txt" )"
    else
        FD="$TMP/fdtree"; mkdir -p "$FD"
        for i in $( seq 1 300 ); do printf 'int shortread_f%d( int x ) { return x + %d; }\n' "$i" "$i" > "$FD/a_shortread_$i.c"; done
        for i in $( seq 1 20 );  do printf 'int zkeep_%d( int x ) { return x; }\n' "$i" > "$FD/z_keep_$i.c"; done
        # 1: the counts, which do not depend on any limit — every stream the shim shortened must have been closed.
        env "$PRELOAD_VAR=$TMP/shortread.so" RWSHIM_MATCH=shortread_ RWSHIM_LOG="$TMP/shim1.txt" \
            "$BIN" "$FD" --no-cache --grep=zkeep_ >"$TMP/b1_out.txt" 2>"$TMP/b1_err.txt"; rc=$?
        COUNTS="$( cat "$TMP/shim1.txt" 2>/dev/null )"
        OPENED="$( printf '%s' "$COUNTS" | sed -nE 's/.*opened=([0-9]+).*/\1/p' )"
        SHORTED="$( printf '%s' "$COUNTS" | sed -nE 's/.*shorted=([0-9]+).*/\1/p' )"
        CLOSED="$( printf '%s' "$COUNTS" | sed -nE 's/.*closed=([0-9]+).*/\1/p' )"
        if [ -z "$COUNTS" ] || [ "${SHORTED:-0}" -eq 0 ]; then
            skip "B1: the shim did not intercept this binary's reads (log: '${COUNTS:-absent}') — nothing was shortened, so nothing is measured"
        elif [ "$rc" -ne 0 ]; then
            no "B1: exit $rc under the short-read shim"
        elif [ "$CLOSED" -eq "$OPENED" ]; then
            ok "B1: every stream that read short was closed (opened=$OPENED shorted=$SHORTED closed=$CLOSED)"
        else
            no "B1: $(( OPENED - CLOSED )) of $OPENED short-read streams were never closed (shorted=$SHORTED) — a descriptor leaks per short read"
        fi
        # 2: the consequence under a descriptor limit — the ordinary files must still be answered.
        if [ -n "$COUNTS" ] && [ "${SHORTED:-0}" -gt 0 ]; then
            ( ulimit -n 200 2>/dev/null; exec env "$PRELOAD_VAR=$TMP/shortread.so" RWSHIM_MATCH=shortread_ RWSHIM_LOG="$TMP/shim2.txt" \
                "$BIN" "$FD" --no-cache --grep=zkeep_ ) >"$TMP/b1_lim.txt" 2>/dev/null
            KEPT="$( grep -o '<f p="[^"]*z_keep_[0-9]*\.c"' "$TMP/b1_lim.txt" | sort -u | grep -c . )"
            [ "$KEPT" -eq 20 ] && ok "B1: under ulimit -n 200 all 20 ordinary files are still answered" \
                               || no "B1: under ulimit -n 200 only $KEPT of 20 ordinary files were answered — leaked descriptors starved the reads"
        fi
    fi
fi

# ═══════════════════════════════════════════════════════════════════════════════════════════════════
echo
echo "=== B2: a fixed-name file that is not a regular file (FIFO, directory, device link) ==="
# ═══════════════════════════════════════════════════════════════════════════════════════════════════
B2="$TMP/b2repo"; mkdir -p "$B2/src"
printf 'int helper( int x ) { int s = 0; for( int i = 0; i < x; ++i ) { s += i; } return s; }\n' > "$B2/src/lib.cpp"
git -C "$B2" init -q; git -C "$B2" config user.email x@y; git -C "$B2" config user.name x
git -C "$B2" add -A; git -C "$B2" commit -qm init
B2XDG="$TMP/b2xdg"; mkdir -p "$B2XDG"
b2run(){ bounded_run env -u TMPDIR XDG_CACHE_HOME="$B2XDG" "$1" "$B2" --quality-delta; }
normalize_at(){ sed -E 's/ at="[0-9a-f]+(\+dirty)?"/ at="AT"/'; }
b2run "$BIN" 2>/dev/null | normalize_at >"$TMP/b2_truth.txt"
if [ ! -s "$TMP/b2_truth.txt" ]; then
    no "B2: the clean --quality-delta produced nothing — cannot judge the shapes"
else
for name in .ripwire_config .ripwire_quality_acks; do
    for shape in fifo directory devzero urandom; do
        case "$shape" in
            fifo)      mkfifo "$B2/$name" ;;
            directory) mkdir "$B2/$name"; printf 'x\n' > "$B2/$name/inside" ;;
            devzero)   ln -s /dev/zero "$B2/$name" ;;
            urandom)   ln -s /dev/urandom "$B2/$name" ;;
        esac
        for bin in "${RUN_BINS[@]}"; do
            tag="$shape $name ($( bin_tag "$bin" ))"
            b2run "$bin" >"$TMP/b2_out.txt" 2>"$TMP/b2_err.txt"; rc=$?
            if is_hang "$rc"; then
                no "B2 [$tag]: --quality-delta HUNG (killed after 30 s)"
            elif [ "$rc" -ne 0 ]; then
                no "B2 [$tag]: exit $rc — $( grep -m1 -iE 'terminat|abort|error|sanitizer' "$TMP/b2_err.txt" | cut -c1-160 )"
            elif ! normalize_at <"$TMP/b2_out.txt" | cmp -s - "$TMP/b2_truth.txt"; then
                no "B2 [$tag]: the answer changed — a file that is not regular must read as absent"
            elif ! grep -q "at '$B2/$name': it is not a regular file" "$TMP/b2_err.txt"; then
                no "B2 [$tag]: exit 0, but nothing on stderr says the file was ignored"
            elif [ "$( grep -c "at '$B2/$name': it is not a regular file" "$TMP/b2_err.txt" )" -ne 1 ]; then
                no "B2 [$tag]: the refusal was printed $( grep -c "at '$B2/$name': it is not a regular file" "$TMP/b2_err.txt" ) times in one run — once per path is the contract"
            else
                ok "B2 [$tag]: refused before reading, disclosed, answer unchanged"
            fi
        done
        rm -rf "$B2/$name"
    done
done
fi

# ═══════════════════════════════════════════════════════════════════════════════════════════════════
echo
echo "=== B3: a file timestamp past 2262 ==="
# ═══════════════════════════════════════════════════════════════════════════════════════════════════
B3="$TMP/b3tree"; mkdir -p "$B3"
printf 'int far( int x ) { return x; }\n' > "$B3/far.c"
STORED="$( python3 -c 'import os,sys; p=sys.argv[1]; os.utime(p,(10**10,10**10)); print(int(os.stat(p).st_mtime))' "$B3/far.c" 2>/dev/null )"
if [ "${STORED:-0}" -lt 9300000000 ]; then
    note "B3: this filesystem does not store a timestamp past 2262 (read back ${STORED:-nothing}) — the input cannot be built here"
else
    for bin in "${RUN_BINS[@]}"; do
        tag="$( bin_tag "$bin" )"
        bounded_run "$bin" "$B3" --cache="$TMP/b3.cache" >"$TMP/b3_out.txt" 2>"$TMP/b3_err.txt"; rc=$?
        if [ "$rc" -ne 0 ] || grep -q 'runtime error' "$TMP/b3_err.txt"; then
            no "B3 [$tag]: exit $rc on a file dated $STORED — $( grep -m1 'runtime error' "$TMP/b3_err.txt" | cut -c1-160 )"
        elif ! grep -q 'n="far"' "$TMP/b3_out.txt"; then
            no "B3 [$tag]: exit 0 but the far-dated file is missing from the map"
        else
            ok "B3 [$tag]: a file dated $STORED indexes cleanly"
        fi
    done
    is_sanitized "$BIN" || [ -n "$ASAN_BIN" ] \
        || note "B3: no sanitizer binary (RIPWIRE_ASAN_BIN) — the overflow this arm exists for is only observable in that build"
fi

echo
[ "$fail" -eq 0 ] && { echo "crashsweepcheck: ALL PASS"; exit 0; } || { echo "crashsweepcheck: SOME CHECKS FAILED"; exit 1; }
