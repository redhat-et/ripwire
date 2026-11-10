#pragma once

// pathguard.h — THE ONE RULE for "this sidecar name is a symlink, so do not write OR read through it", and
// the two atomic opens that ENFORCE it rather than merely describing it (round 3 added the read; see below).
//
// WHY IT IS ITS OWN HEADER. The rule was born at the MCP edit seam (mcpedit.h, A4-F14) because that is
// where following a link loses an agent's edit. It was never given to the SIDECAR writers, and that gap was
// a reported vulnerability (CWE-59, link following): `.ripwire_quality_baseline` (quality::writeBaseline),
// `.ripwire_notes` (notes::writeNotes) and `.ripwire_arch_baseline` (archWriteBaseline) each opened a FIXED
// name with a truncating open — ofstream( path, trunc ) twice, fopen( path, "w" ) once — and a truncating
// open resolves its final path component through the filesystem's symlink layer. A repository carrying a
// symlink at one of those names turned the tool's own write into an arbitrary-file truncate anywhere the
// invoking user could write. Reproduced on the shipped binary: a victim file holding `important user data`
// came back holding baseline content, and the sidecar was still a symlink afterwards.
//
// The fix for a rule that exists in one place and is missing in three is not a fourth copy of it, so the
// PREDICATE moved here — where a sidecar writer can reach it without including a JSON-RPC server, and where
// a fifth writer joins the rule instead of re-deriving it.
//
// ── ROUND 2: THE FIRST FIX WAS CHECK-THEN-OPEN, AND THAT IS A SECOND DEFECT (CWE-367, TOCTOU) ─────────
//
// The first fix put an lstat/S_ISLNK REFUSAL immediately in front of each writer's unchanged truncating
// open. It closed the reported attack and was honest about its own limit, and an external reviewer then
// flagged the limit as its own finding, correctly. The guard was ADVISORY: lstat(2) answered a question
// about the destination at one instant, open(2) re-resolved the same path at a later one, and anything that
// replaced the entry in between made the write follow a link after all. A guard the code then relies on for
// safety is not a guard; it is a description that happened to be true when it was read.
//
// The stated reason for stopping there was that std::ofstream cannot express O_NOFOLLOW portably. True of
// ofstream, and not true of the problem: the writers do not need ofstream, they need a descriptor. So the
// check and the create are now ONE syscall, and it is the only one a writer makes:
//
//     ::open( path, O_WRONLY | O_CREAT | O_NOFOLLOW | O_NONBLOCK, 0666 )   (round 4: O_NONBLOCK, then fstat, then ftruncate
//                                                                          in place of the O_TRUNC it once carried)
//
// O_NOFOLLOW makes the KERNEL refuse a final component that is a symlink, at the instant of resolution.
// There is no window because there is no second resolution — whatever the entry is when the kernel looks
// is what the kernel acts on. POSIX, and present on both targets (macOS, Linux). MSVC is explicitly not a
// target for this project, so there is no portability scaffolding here and none is wanted.
//
// WHERE lstat SURVIVES, AND WHY THAT IS NOT A RELAPSE. isSymlink stays, for two callers that are not the
// sidecar guard:
//
//   - mcpedit, whose tmp+rename publish genuinely wants to KNOW (it refuses into a JSON-RPC error object
//     and never opens the destination at all, so there is nothing for an atomic open to be atomic with);
//   - openNoFollowTruncate itself, AFTER a failed open, to decide which sentence ELOOP has earned. ELOOP
//     is also what a symlink LOOP in an earlier directory component returns, and printing "that path is a
//     symlink" at a path whose last component is a directory would be a false security claim rather than
//     a diagnosis. That lstat is racy too, and it does not matter in the slightest: it cannot decide
//     whether to write. The worst a lost race can do there is pick the less specific of two refusals.
//
// The distinction is the whole point of the round: a check that GATES an open is a vulnerability; a check
// that WORDS an error is a message.
//
// WHY THE PREDICATE IS SHARED BUT THE REFUSAL TEXT IS NOT ONE SENTENCE. The two seams fail in OPPOSITE
// directions, and a single message would have to be wrong about one of them:
//
//   - mcpedit's atomicWrite is tmp+rename. A rename REPLACES the link entry with a regular file and leaves
//     the real target untouched — the edit silently goes nowhere. Data-losing, not a write primitive.
//   - the three sidecar writers truncate in place. The link is FOLLOWED and its target destroyed, while the
//     link entry survives — an arbitrary write.
//
// So `isSymlink` is one spelling (lstat, never stat: inspect the LINK, not what it points at) and each
// caller says what would actually have happened to the user's file. Claiming the wrong mechanism in a
// security refusal is the kind of dishonesty in output the project's non-negotiables rule out; a shared
// sentence that fits neither seam would be exactly that. The same rule is why an open that failed for some
// OTHER reason — a directory at the name, a read-only tree, a full disk — reports its own errno instead of
// being folded into the symlink sentence, which would turn every failure into a security event.
//
// DELIVERY differs too, and deliberately: an MCP verb refuses into its JSON-RPC error object, a CLI sidecar
// writer refuses onto stderr. openNoFollowTruncate below is the stderr half, used by the three sidecar
// writers; mcpedit takes the predicate alone and keeps its own error payload.
//
// THE MODE, 0666, IS NOT A CHOICE — it is what std::ofstream( path, trunc ) and std::fopen( path, "w" )
// both request, and the process umask narrows it exactly as before (0644 under the usual 022). Naming a
// mode by hand is the one thing moving from a stream to a descriptor forces, so it is measured rather than
// asserted: test/sidecarsymlinkcheck.sh's (g) arms create each sidecar under `umask 000` and require 0666,
// which is the only umask under which a wrong 0644 is visible at all.
//
// ── ROUND 3: THE READERS OF THE SAME NAMES REFUSE A LINK TOO — A DECISION, NOT A DEFAULT ─────────────
//
// Rounds 1-2 guarded the writes and left every reader of these three names following a link:
// notes::readNotes, quality::readBaseline / readBaselineHeadSha / readBaselineAbsorbed, archReadBaseline,
// and a bare stream the arch verb opened only to learn whether the sidecar existed. So a link at one of the
// names still decided which file those readers opened, inside the tree or out of it, and its lines were read
// as sidecar records.
//
// No privilege is crossed; the user could read those files anyway. The boundary is the one the crawl already
// holds (ingest.h, withinCanonicalRoot): repository content does not choose which of the user's files the
// tool reads. Three answers were on the table, and the choice is pinned by the round-3 arms of
// test/sidecarsymlinkcheck.sh rather than left to whoever next edits a reader:
//
//   (a) Leave the readers following. REJECTED: a link would keep deciding what is read at three fixed names,
//       right beside a crawl that no longer lets one.
//   (c) Refuse only a link that leaves the crawl root, which is the crawl's own rule. REJECTED, three ways:
//       - It does not keep the setup that argues for it. A sidecar symlinked into a SHARED config directory
//         points outside the tree, and (c) refuses that as well. What (c) keeps beyond (b) is a link to
//         another file INSIDE the tree — which the writers already refuse, so it is readable and never
//         again updatable.
//       - It cannot be one syscall. "Where does the link lead" is realpath() followed by an open: the
//         check-then-open shape round 2 removed from the writers, or a descriptor-then-verify dance to close
//         that same race a second time.
//       - It has no single anchor. The arch baseline resolves against the process CWD (archBaselinePath),
//         not the crawl root, so "leaves the root" is not even defined for one of the three.
//   (b) Refuse a link on READ exactly as on write: O_NOFOLLOW at the open. CHOSEN. One sentence covers every
//       site — a sidecar is a regular file at its fixed name, read or written — and the kernel enforces it
//       in the very syscall that would otherwise have followed the link.
//
// The crawl follows an in-tree link and these readers do not, and that is not an inconsistency. A source
// tree's links are the user's content; a sidecar is this tool's own state file, which it never creates as
// a link and, since round 1, will not write through one. git draws the same line: since 2.32 it opens the
// in-tree .gitattributes, .gitignore and .mailmap with O_NOFOLLOW.
//
// MIGRATION. A repository that symlinks one of these sidecars on purpose now gets a stderr refusal on every
// read and no sidecar in force: no notes surface, quality-delta reports baseline="git-HEAD (symlinked
// sidecar refused)" and compares against HEAD, and the arch verb reports every violation as new. Replace
// the link with a regular copy of its target — copy the target to a temporary name beside the link, then
// mv that over the link — and if it must track a shared original, copy it in as a CI step instead.
//
// NOT COVERED, and why:
//   - `.ripwire_quality_acks` (readAckRecords). Its writer publishes by tmp+rename, which REPLACES a link
//     instead of following it, so what a refused read should make that writer do belongs to the lane that
//     guards the writer. The reader moves with it.
//   - `.ripwire_config` (readRegisterMacrosConfig). User-authored, never written by the tool, and the one
//     of these names where a link into a shared directory is the ordinary setup. Whether it takes this rule
//     is its own decision.
//   - An in-document disclosure where the document has no channel for one. The refusal reaches stderr from
//     every surface, and the document only where a marker already tells "no sidecar" from "a sidecar not
//     used" (quality-delta, CLI and MCP). A refused note is simply absent from --for, --expand and the MCP
//     verbs, and an MCP client never sees the server's stderr.
//   - Directory components. O_NOFOLLOW constrains the final component only, exactly as for the writes.
//
// Each sidecar keeps ONE read seam (readNotesSidecar / readBaselineSidecar / readArchBaselineSidecar) that
// calls openNoFollowRead below and carries its own DISCLOSE, for the same once-per-site reason the
// write seams keep theirs.
//
// ── ROUND 4: A NON-REGULAR FILE AT THE NAME, AND A READ THAT HOLDS ONE LINE ─────────────────────────────
//
// Two review findings on round 3, both confirmed before anything changed.
//
// A FIFO planted AT a sidecar name, with no link involved, blocked BOTH opens: a read open waits for a writer
// and a write open waits for a reader. It predates round 3 (the streams these descriptors replaced blocked the
// same way) and a git checkout cannot contain a FIFO, but a blocked open is still wrong, and fixing the reader
// alone would have been half a fix.
// So both opens carry O_NONBLOCK, which lets the open RETURN whatever sits at the name, and both then ask
// fstat whether it is a regular file before a byte moves. A writer refuses anything else, loudly, with nothing
// written. A reader treats it as a sidecar that is there but unreadable, which is what the stream it replaced
// reported for a directory at the name. O_NONBLOCK changes nothing about a regular file's reads or writes.
//
// The round-3 read also held the WHOLE file in memory before parsing began, where the std::ifstream it
// replaced held one line. The remedy is streaming, not a size cap: the crawl's --max-file-size is a ceiling
// for SOURCE files, and applying it here would refuse a legitimately large quality baseline, which is a wrong
// answer rather than a guard. The read now hands its caller one line at a time through POSIX getline over the
// descriptor's stream, which costs what the std::ifstream readers cost. Two other shapes were ruled out first:
// a call per byte (rw::readByteSafeLine's fgetc loop) measured ~15× slower on 64 MB of sidecar lines, and a
// custom std::streambuf under std::getline would narrow a high byte through libc++'s no-get-area fallback,
// which aborts the sanitizer build (src/infra/stdinline.h records that trap).
//
// It carries no index/graph dependency on purpose — the emitter and the degrade macro are the whole of it — so
// it stays includable from any layer, which is the property that let the rule be missing in the first place.
// It is NOT under src/infra/: that layer is vendored into a sibling repo and may not name this project
// (test/infraportcheck.sh rule (C)), and every sentence below has to.
//
// Gated by test/sidecarsymlinkcheck.sh, whose three symlink arms were observed RED before this header
// existed, whose (e)/(f) mechanism arms were observed RED before the open below replaced the check, whose
// round-3 read arms were observed RED against the round-2 binary before the read below existed, and whose
// round-4 arms were observed RED against the round-3 binary and source.

#include "infra/emit.h"   // rw::emitTo — the refusal goes to stderr through THE emitter, not fprintf

#include "infra/os.h"     // os::open + O_NOFOLLOW + O_NONBLOCK — the whole mechanism, in one syscall; os::lstat + S_ISLNK (mcpedit, and
                          // the post-ELOOP wording); os::fstat + S_ISREG (round 4); os::write / os::read / os::close / os::getpid —
                          // the descriptor the writers hold instead of a stream, and the entropy-fallback mixer (round 5)
#include <cerrno>
#include <cstddef>
#include <cstdint>        // std::uint64_t — the entropy-fallback mixer (round 5)
#include <cstdio>         // std::FILE / os::fdopen / os::getline / std::fclose — the read half's line stream
#include <cstdlib>        // std::free — POSIX getline's buffer
#include <cstring>        // std::strerror — an honest reason for a failure that is not a link
#include <chrono>         // std::chrono::steady_clock — the entropy-fallback mixer (round 5)
#include <random>         // std::random_device — the entropy fallback when /dev/urandom is unavailable (round 5)
#include <optional>       // readRegularFileNoFollow's absent-or-bytes answer
#include <string>
#include <string_view>

namespace rw::pathguard
{

// Is the LAST path component itself a symlink? lstat, not stat: stat() answers for the target and would
// report `false` for precisely the case this exists to catch. A path that does not exist, or that cannot be
// lstat'd at all, is NOT a symlink — an absent destination is the normal first-run case for every sidecar,
// and refusing it would break the tool for everyone to defend against nobody.
//
// THIS IS NOT A WRITE GUARD and must never be used as one again: between its answer and any subsequent open
// the entry can change, which is the CWE-367 finding this header's round 2 closes. It answers a question
// (mcpedit, which never opens the destination) and it words an error (openNoFollowTruncate, after the fact).
inline bool isSymlink( const std::string& path ) noexcept
{
    os::stat_t linkSt{};
    return os::lstat( path.c_str(), &linkSt ) == 0 && S_ISLNK( linkSt.st_mode );
}

// What the atomic open produced: a descriptor, or the errno that explains why there is none. Both are
// returned rather than left in `errno`, because the refusal is emitted before the caller looks and an
// emitter is entitled to clobber errno on its way to stderr.
//
// `err == ELOOP` is the link case, and it is the one the caller re-words into its own site-specific
// DISCLOSE — see the three sidecar writers, which each keep the alert text they have always had.
struct OpenedFile
{
    int fd  = -1;
    int err = 0;
};

// Create-or-truncate `path` for writing WITHOUT following a symlink at the final component, and tell the
// user on stderr if that is refused. Returns a descriptor >= 0, or fd == -1 with the errno that failed.
//
// `what` names the sidecar in the user's words ("the quality baseline sidecar"), not the code's.
//
// LOUDLY, NOT SILENTLY. A skipped write that says nothing leaves the user believing a sidecar exists that
// does not — a committed baseline that is actually absent reads as "no debt", which is a worse answer than
// an error. So this always emits on failure, and every caller turns it into a non-zero exit.
//
// O_NOFOLLOW constrains the FINAL component only; an intermediate symlinked directory is still traversed.
// That is the same reach the lstat check had, so nothing regressed with the change — and widening it would
// mean refusing every repository that lives under a symlinked path, which is most of them.
//
// NOT A REGULAR FILE (round 4). O_NONBLOCK lets the open return for a FIFO instead of waiting for a reader:
// with nobody reading, it fails at once with ENXIO and takes the plain-errno branch below. The fstat then
// refuses whatever DID open but is not a regular file, before any byte is written. That refusal reports EINVAL,
// because no syscall failed: the name holds something a sidecar cannot be.
//
// TRUNCATION COMES LAST. The open does not carry O_TRUNC: with it, an existing regular sidecar was emptied before
// fstat had looked at anything, so a failure there returned an error over a file already destroyed. The descriptor
// is truncated with ftruncate only once fstat has confirmed a regular file, so every refusal and every failure
// before that point leaves the old sidecar exactly as it was.
inline OpenedFile openNoFollowTruncate( std::string_view what, const std::string& path )
{
    const int fd = os::open( path.c_str(), O_WRONLY | O_CREAT | O_NOFOLLOW | O_NONBLOCK, 0666 );
    if( fd >= 0 )
    {
        os::stat_t openedSt{};
        if( os::fstat( fd, &openedSt ) != 0 )
        {
            const int statErr = errno;
            os::close( fd );
            rw::emitTo( stderr, "ripwire: could not inspect {} at '{}': {}. Nothing was written.\n", what, path, std::strerror( statErr ) );
            return { -1, statErr };
        }
        if( !S_ISREG( openedSt.st_mode ) )
        {
            os::close( fd );
            rw::emitTo( stderr,
                        "ripwire: refusing to write {} at '{}': that path is not a regular file (a FIFO, for example), so there is no\n"
                        "  sidecar there to write. Nothing was written. Remove it and re-run.\n",
                        what, path );
            return { -1, EINVAL };
        }
        if( os::ftruncate( fd, 0 ) != 0 )
        {
            const int truncErr = errno;
            os::close( fd );
            rw::emitTo( stderr, "ripwire: could not truncate {} at '{}' for writing: {}. Nothing was written.\n", what, path, std::strerror( truncErr ) );
            return { -1, truncErr };
        }
        return { fd, 0 };
    }
    const int err = errno;

    if( err == ELOOP && isSymlink( path ) )
    {
        rw::emitTo( stderr,
                    "ripwire: refusing to write {} at '{}': that path is a symlink, and writing through it would follow the link and\n"
                    "  overwrite whatever it points at — outside this tree, if that is where it leads — while leaving the link itself in place.\n"
                    "  Nothing was written. Remove the symlink (or replace it with a real file) and re-run.\n",
                    what, path );
    }
    else if( err == ELOOP )
    {
        // ELOOP without a link at the final component: a symlink loop somewhere earlier in the path. Still a
        // refusal, still nothing written — but saying "that path is a symlink" here would be a claim about a
        // component that is not one.
        rw::emitTo( stderr,
                    "ripwire: refusing to write {} at '{}': the path could not be resolved without following a symlink loop\n"
                    "  in one of its directory components (ELOOP). Nothing was written.\n",
                    what, path );
    }
    else
    {
        // Not a link question at all — a directory at the name, a read-only tree, a full disk. Reported as
        // what it is; folding it into the symlink sentence would turn every failed write into a security
        // event and teach the user to ignore the one that is.
        rw::emitTo( stderr,
                    "ripwire: could not open {} at '{}' for writing: {}. Nothing was written.\n",
                    what, path, std::strerror( err ) );
    }
    return { -1, err };
}

// Write every byte of `bytes` to `fd` WITHOUT closing it — a short write is retried (a signal can truncate
// one), EINTR is retried, anything else is a failure. Shared by writeAllAndClose and the round-5 temp holder.
inline bool writeAll( int fd, std::string_view bytes ) noexcept
{
    std::size_t off = 0;
    while( off < bytes.size() )
    {
        const os::ssize_t n = os::write( fd, bytes.data() + off, bytes.size() - off );
        if( n > 0 )
        {
            off += static_cast<std::size_t>( n );
            continue;
        }
        if( n < 0 && errno == EINTR )
        {
            continue;
        }
        return false;
    }
    return true;
}

// Write every byte of `bytes` to `fd`, then close it — the descriptor is consumed either way. Returns false
// if any byte did not land or the close failed, which the callers turn into their "could not write" answer.
// writeBaseline used to `return true` regardless of whether the bytes reached the disk and now returns this;
// writeNotes already answered for its stream (`return bool( f )`) and keeps that contract through the
// descriptor. Either way a full disk stops being reported as a written sidecar.
inline bool writeAllAndClose( int fd, std::string_view bytes ) noexcept
{
    bool wrote = writeAll( fd, bytes );
    if( os::close( fd ) != 0 )
    {
        wrote = false;
    }
    return wrote;
}

// ── ROUND 5: THE TEMP FILE OF A tmp+rename PUBLISH IS CREATED EXCLUSIVELY, WITHOUT FOLLOWING A LINK ──────
//
// Rounds 1-4 guarded the FINAL sidecar names (openNoFollowTruncate / openNoFollowRead). The three atomic
// "publish" writers — mcpedit::atomicWrite, quality::atomicWriteFile and ingest::saveCache — reach their
// final name only through a rename() of a TEMP file they open beside it. That temp is now created the same
// way the sidecar names are: as a fresh file, refusing an existing entry at the name.
//
// The rule is the CREATE, not a check in front of it (round 2's CWE-367 lesson): O_CREAT|O_EXCL means the
// kernel creates the file or fails — a symlink OR any existing file at the name yields EEXIST and is never
// opened, never followed, never truncated; O_NOFOLLOW is kept as belt-and-braces for the same intent;
// O_CLOEXEC keeps the descriptor out of any child git/tar. The name carries a CSPRNG-drawn suffix, so an
// existing entry at a candidate name does not block the write either — a fresh draw picks another and the
// loop retries a few times on EEXIST. The mode argument is each writer's HISTORICAL create mode (0644 for the
// mcpedit temp, which then fchmods to the edited file's own bits; 0666 for the two tool-state writers, whose
// ofstream / fopen requested exactly that), so the kernel applies the umask precisely as before and every
// file keeps today's permissions.
//
// D1 FOLLOW-UP: when lane/os-header lands, randomTempSuffix()'s entropy read and openExclNoFollow's ::open
// move behind the rw::os seam (arc4random_buf / getrandom, os::open) — this local helper is the pre-D1 form
// and is the one place that moves. Gated by test/tempfilesymlinkcheck.sh (red on main, green after).

// A short, unpredictable hex suffix for a temp name. CSPRNG-quality via /dev/urandom; if that cannot be read
// the O_EXCL|O_NOFOLLOW create still holds, so the fallback only needs to avoid a needless EEXIST retry —
// it mixes std::random_device with the pid and a monotone clock.
inline std::string randomTempSuffix()
{
    unsigned char raw[ 12 ] = { 0 };
    bool          haveEntropy = false;
    const int     rfd = os::open( "/dev/urandom", O_RDONLY | O_CLOEXEC );
    if( rfd >= 0 )
    {
        std::size_t got = 0;
        while( got < sizeof( raw ) )
        {
            const os::ssize_t n = os::read( rfd, raw + got, sizeof( raw ) - got );
            if( n > 0 )
            {
                got += static_cast<std::size_t>( n );
                continue;
            }
            if( n < 0 && errno == EINTR )
            {
                continue;
            }
            break;
        }
        os::close( rfd );
        haveEntropy = ( got == sizeof( raw ) );
    }
    if( !haveEntropy )
    {
        std::random_device rd;
        std::uint64_t      mix = ( static_cast<std::uint64_t>( rd() ) << 32 ) ^ static_cast<std::uint64_t>( rd() )
                               ^ ( static_cast<std::uint64_t>( os::getpid() ) << 17 )
                               ^ static_cast<std::uint64_t>( std::chrono::steady_clock::now().time_since_epoch().count() );
        for( unsigned char& b : raw )
        {
            mix = mix * 6364136223846793005ULL + 1442695040888963407ULL;
            b   = static_cast<unsigned char>( mix >> 56 );
        }
    }
    static constexpr char kHex[] = "0123456789abcdef";
    std::string           out;
    out.reserve( sizeof( raw ) * 2 );
    for( unsigned char b : raw )
    {
        out.push_back( kHex[ b >> 4 ] );
        out.push_back( kHex[ b & 0x0f ] );
    }
    return out;
}

// Create EXACTLY `path` for writing, failing (never following a link, never truncating) if anything already
// sits at the name. O_EXCL makes the create atomic — a symlink at the name yields EEXIST, not a followed
// open — and O_NOFOLLOW is the redundant guard for the same intent. Returns the descriptor, or -1 with errno.
inline int openExclNoFollow( const char* path, os::mode_t mode ) noexcept
{
    return os::open( path, O_WRONLY | O_CREAT | O_EXCL | O_NOFOLLOW | O_CLOEXEC, mode );
}

// An RAII holder for the temp side of a tmp+rename publish. It owns the exclusively-created descriptor and
// the temp name, and its destructor UNLINKS the temp unless commit() has renamed it into place — so every
// early return, and every failed write, cleans up on its own with no manual unlink at the call site. This is
// the one place the create/cleanup discipline lives; the three publish writers hold one and never re-derive
// it. Move-only; a moved-from holder owns nothing and does nothing.
//
// The write can go three ways, all supported: write() through the fd (atomicWriteFile); the caller's own
// loop on fd() with an fchmod/fsync in between (mcpedit::atomicWrite); or releaseFd() into a FILE* the caller
// then fcloses (ingest::saveCache). commit() closes any descriptor the holder still owns and renames.
class ExclTempFile
{
public:
    ExclTempFile() = default;
    ExclTempFile( int fd, std::string path ) noexcept : fd_( fd ), path_( std::move( path ) ) {}

    ExclTempFile( const ExclTempFile& )            = delete;
    ExclTempFile& operator=( const ExclTempFile& ) = delete;
    ExclTempFile& operator=( ExclTempFile&& )      = delete;
    ExclTempFile( ExclTempFile&& other ) noexcept
        : fd_( other.fd_ ), path_( std::move( other.path_ ) ), committed_( other.committed_ )
    {
        other.fd_        = -1;
        other.committed_ = true;   // a moved-from holder owns nothing and must not unlink
        other.path_.clear();
    }
    ~ExclTempFile()
    {
        if( fd_ >= 0 )
        {
            os::close( fd_ );
        }
        if( !committed_ && !path_.empty() )
        {
            os::unlink( path_.c_str() );   // an uncommitted temp never survives the writer's scope
        }
    }

    bool               ok() const noexcept   { return !path_.empty(); }
    int                fd() const noexcept   { return fd_; }
    const std::string& path() const noexcept { return path_; }

    // Hand the descriptor to a FILE* owner (saveCache's fdopen). The holder keeps the PATH — still unlinked
    // on destruction unless committed — but no longer closes the fd; the new owner does.
    int releaseFd() noexcept
    {
        const int f = fd_;
        fd_ = -1;
        return f;
    }

    // Write every byte through the fd and leave it open for a following fchmod / fsync / commit.
    bool write( std::string_view bytes ) noexcept
    {
        return fd_ >= 0 && writeAll( fd_, bytes );
    }

    // Publish over `finalPath`: close any descriptor we still hold, then rename the temp over the target.
    // On success the temp is consumed and the destructor leaves it alone; on failure nothing is published
    // and the destructor still removes the temp.
    bool commit( const std::string& finalPath ) noexcept
    {
        if( fd_ >= 0 )
        {
            const bool closed = os::close( fd_ ) == 0;
            fd_ = -1;
            if( !closed )
            {
                return false;
            }
        }
        if( path_.empty() || os::rename( path_.c_str(), finalPath.c_str() ) != 0 )
        {
            return false;
        }
        committed_ = true;
        return true;
    }

private:
    int         fd_        = -1;
    std::string path_;
    bool        committed_ = false;
};

// Open a fresh, unpredictably-named temp file `prefix<random>suffix` beside a target, created exclusively and
// without following a link, wrapped in the RAII holder above. `prefix` is typically "<target>." and `suffix`
// typically ".tmp"; keeping them separate lets a caller preserve its historical temp-name SHAPE (so a `*.tmp`
// residue glob still matches). Retries a few times on EEXIST — an existing entry at a candidate name that a
// fresh CSPRNG draw steps past — and stops at once on any other errno. `!ok()` means the caller refuses and discloses
// through its own path.
inline ExclTempFile createExclTempFile( const std::string& prefix, std::string_view suffix, os::mode_t mode )
{
    for( int attempt = 0; attempt < 8; ++attempt )
    {
        std::string cand = prefix + randomTempSuffix() + std::string( suffix );
        const int   fd   = openExclNoFollow( cand.c_str(), mode );
        if( fd >= 0 )
        {
            return ExclTempFile( fd, std::move( cand ) );
        }
        if( errno != EEXIST )
        {
            break;
        }
    }
    return ExclTempFile();
}

// A descriptor that closes itself: the RAII owner for a one-shot read. Move-only.
class OwnedFd
{
public:
    explicit OwnedFd( int fd ) noexcept : fd_( fd ) {}
    OwnedFd( const OwnedFd& )            = delete;
    OwnedFd& operator=( const OwnedFd& ) = delete;
    OwnedFd& operator=( OwnedFd&& )      = delete;
    OwnedFd( OwnedFd&& other ) noexcept : fd_( other.fd_ ) { other.fd_ = -1; }
    ~OwnedFd()
    {
        if( fd_ >= 0 )
        {
            os::close( fd_ );
        }
    }
    int  get() const noexcept   { return fd_; }
    bool valid() const noexcept { return fd_ >= 0; }

    // Give up ownership without closing: the caller now owns the descriptor (a lock that must live until exit).
    [[nodiscard]] int release() noexcept
    {
        const int fd = fd_;
        fd_          = -1;
        return fd;
    }

    // Close what is held and take ownership of `fd` — how a descriptor chain steps one component down.
    void reset( int fd ) noexcept
    {
        if( fd_ >= 0 )
        {
            os::close( fd_ );
        }
        fd_ = fd;
    }

private:
    int fd_ = -1;
};

// Read everything `fd` yields into `out`, retrying EINTR. False, with `out` empty, on a read error.
inline bool readAllFromFd( int fd, std::string& out )
{
    char buf[ 8192 ];
    for( ;; )
    {
        const os::ssize_t n = os::read( fd, buf, sizeof( buf ) );
        if( n > 0 )
        {
            out.append( buf, static_cast<std::size_t>( n ) );
            continue;
        }
        if( n == 0 )
        {
            return true;
        }
        if( errno == EINTR )
        {
            continue;
        }
        out.clear();
        return false;
    }
}

// The whole of `path` when it is a regular file, read through ONE non-blocking, no-follow descriptor; nullopt when it
// is absent, a symlink at the final component, anything that is not a regular file (a FIFO never blocks the open:
// O_NONBLOCK, then fstat), or unreadable. For small metadata a caller only inspects — never a file whose absence
// or refusal it has to word to the user.
inline std::optional<std::string> readRegularFileNoFollow( const std::string& path )
{
    const OwnedFd fd( os::open( path.c_str(), O_RDONLY | O_NOFOLLOW | O_NONBLOCK | O_CLOEXEC ) );
    os::stat_t    openedSt{};
    if( !fd.valid() || os::fstat( fd.get(), &openedSt ) != 0 || !S_ISREG( openedSt.st_mode ) )
    {
        return std::nullopt;
    }
    std::string bytes;
    if( !readAllFromFd( fd.get(), bytes ) )
    {
        return std::nullopt;
    }
    return bytes;
}

// The part of `path` below `dir`, or false when `path` is not strictly beneath it — including a sibling whose name
// merely starts with dir's ("/x/plans-other/…" is not beneath "/x/plans").
inline bool relativeBeneath( const std::string& dir, const std::string& path, std::string_view& rel ) noexcept
{
    if( dir.empty() || path.size() <= dir.size() || path.compare( 0, dir.size(), dir ) != 0 )
    {
        return false;
    }
    std::size_t relStart = dir.size();
    if( dir.back() != '/' )
    {
        if( path[ relStart ] != '/' )
        {
            return false;
        }
        ++relStart;
    }
    rel = std::string_view( path ).substr( relStart );
    return !rel.empty();
}

// Read the whole of `path` into `out`, where the caller has already confined `path` beneath `dir` (both
// canonical, as realpath spells them). The read goes through a descriptor chain ANCHORED at `dir`: `dir` is
// opened once, and every component of `path` below it is opened with openat( ..., O_NOFOLLOW ) relative to the
// previous descriptor — O_DIRECTORY for the intermediates — so no component beneath the confined directory is
// resolved through a symbolic link at read time, and the bytes read belong to a file that really is beneath
// `dir` when it is opened. A component that is now a link, missing, empty, "." or ".." refuses the read, as does
// a `path` that does not start with `dir`. The final component must be a regular file (O_NONBLOCK, then fstat —
// a FIFO never blocks). Returns false, with `out` empty, on any refusal or read failure; the caller words its
// own refusal. POSIX openat throughout, behind rw::os with the rest.
inline bool readWholeBeneathNoFollow( const std::string& dir, const std::string& path, std::string& out )
{
    out.clear();
    std::string_view rel;
    if( !relativeBeneath( dir, path, rel ) )
    {
        return false;
    }

    OwnedFd cur( os::open( dir.c_str(), O_RDONLY | O_DIRECTORY | O_CLOEXEC ) );
    if( !cur.valid() )
    {
        return false;
    }
    for( ;; )
    {
        const std::size_t slash = rel.find( '/' );
        const std::string component( rel.substr( 0, slash ) );
        if( component.empty() || component == "." || component == ".." )
        {
            return false;
        }
        if( slash == std::string_view::npos )
        {
            const OwnedFd file( os::openat( cur.get(), component.c_str(), O_RDONLY | O_NOFOLLOW | O_NONBLOCK | O_CLOEXEC ) );
            os::stat_t    openedSt{};
            if( !file.valid() || os::fstat( file.get(), &openedSt ) != 0 || !S_ISREG( openedSt.st_mode ) )
            {
                return false;
            }
            return readAllFromFd( file.get(), out );
        }
        const int next = os::openat( cur.get(), component.c_str(), O_RDONLY | O_DIRECTORY | O_NOFOLLOW | O_CLOEXEC );
        if( next < 0 )
        {
            return false;
        }
        cur.reset( next );
        rel.remove_prefix( slash + 1 );
    }
}

// ── the read half (round 3) ───────────────────────────────────────────────────────────────────────────

// What the no-follow open produced, and the handle the caller reads through. `opened` is the OPEN, not the
// content: something that is not a symlink sits at the name and it opened, so a caller that tells "a sidecar is
// there" from "no sidecar" (readBaseline's `present`, the arch verb's baseline-in-force) reads that. readLine then
// yields the sidecar one line at a time, and yields nothing at all when what opened is not a regular file —
// which is how a directory or a FIFO at the name reads: present, and unreadable.
//
// It OWNS the stream, so it moves and never copies, and the stream closes with the handle. The shape follows
// ingest_cache.h's ReadFd, which this header cannot include without taking on the cache layer.
struct NoFollowRead
{
    std::FILE*  file    = nullptr;   // the sidecar, open for reading — null unless it opened as a regular file
    bool        opened  = false;     // the open succeeded: something that is not a symlink sits at the name
    bool        refused = false;     // the open failed with ELOOP — nothing was followed, and stderr says why
    int         err     = 0;         // errno of the open or fdopen that failed; 0 when neither did
    char*       lineBuf = nullptr;   // POSIX getline's buffer: grown by getline, reused for every line, freed here
    std::size_t lineCap = 0;         // its capacity, as getline tracks it

    NoFollowRead() = default;
    NoFollowRead( const NoFollowRead& )            = delete;
    NoFollowRead& operator=( const NoFollowRead& ) = delete;
    NoFollowRead& operator=( NoFollowRead&& )      = delete;
    NoFollowRead( NoFollowRead&& other ) noexcept
        : file( other.file ), opened( other.opened ), refused( other.refused ), err( other.err ),
          lineBuf( other.lineBuf ), lineCap( other.lineCap )
    {
        other.file    = nullptr;
        other.lineBuf = nullptr;
        other.lineCap = 0;
    }
    ~NoFollowRead()
    {
        if( file != nullptr )
        {
            std::fclose( file );
        }
        std::free( lineBuf );
    }

    // One line into `line`, with std::getline's contract: the '\n' is consumed and not kept, a '\r' before it IS
    // kept, an embedded NUL is kept, and a last line with no '\n' is still delivered once. False only at the end of
    // the stream or on a read error — and always false when no regular file opened.
    //
    // WHY POSIX getline. It scans the stream's own buffer, so this costs what the std::ifstream readers cost; a
    // call per byte (fgetc) measured ~15× slower on 64 MB of sidecar lines. And it is the C API, so no byte goes
    // through libc++ std::getline's no-get-area fallback, which narrows a high byte and aborts the sanitizer build
    // (src/infra/stdinline.h records that trap).
    bool readLine( std::string& line )
    {
        if( file == nullptr )
        {
            return false;
        }
        const os::ssize_t got = os::getline( &lineBuf, &lineCap, file );
        if( got < 0 )
        {
            return false;
        }
        std::size_t length = static_cast<std::size_t>( got );
        if( length > 0 && lineBuf[length - 1] == '\n' )
        {
            --length;
        }
        line.assign( lineBuf, length );
        return true;
    }
};

// Open `path` for reading WITHOUT following a symlink at the final component — openNoFollowTruncate's read
// twin: the same O_NOFOLLOW, the same single syscall with no lstat in front of it to race, the same O_NONBLOCK
// and fstat check, and the same rule that a refusal is loud.
//
// ONLY THE REFUSAL IS LOUD. An absent file is every sidecar's first-run case and says nothing, and any other
// open failure stays exactly as silent as the stream this replaced — the callers already read those as "no
// sidecar", and making them loud is a behaviour change with questions of its own, not a rider on this one. A
// read refused over a link is different in kind: the file is RIGHT THERE, and a caller that went quiet about it
// would leave the user believing there is no sidecar at all. Something at the name that is not a regular file
// is quiet the way the stream was about a directory there: present, and it yields no lines.
//
// `what` names the sidecar in the user's words, as for the write.
inline NoFollowRead openNoFollowRead( std::string_view what, const std::string& path )
{
    NoFollowRead result;
    const int    fd = os::open( path.c_str(), O_RDONLY | O_NOFOLLOW | O_NONBLOCK );
    if( fd < 0 )
    {
        result.err = errno;
        if( result.err != ELOOP )
        {
            return result;
        }
        result.refused = true;
        if( isSymlink( path ) )
        {
            rw::emitTo( stderr,
                        "ripwire: refusing to read {} at '{}': that path is a symlink, and reading through it would open whatever it points at\n"
                        "  — outside this tree, if that is where it leads — and use its contents as {}. Nothing was read. A sidecar behind a\n"
                        "  symlink is refused on read exactly as on write: replace the link with a regular copy of its target (or remove it) and re-run.\n",
                        what, path, what );
        }
        else
        {
            // As for the write: ELOOP with no link at the final component is a loop in an earlier directory
            // component, and "that path is a symlink" would be a claim about a component that is not one.
            rw::emitTo( stderr,
                        "ripwire: refusing to read {} at '{}': the path could not be resolved without following a symlink loop\n"
                        "  in one of its directory components (ELOOP). Nothing was read.\n",
                        what, path );
        }
        return result;
    }

    result.opened = true;
    os::stat_t openedSt{};
    if( os::fstat( fd, &openedSt ) != 0 || !S_ISREG( openedSt.st_mode ) )
    {
        os::close( fd );   // a FIFO, a directory, a device: present, and no lines — never a read that could wait
        return result;
    }
    result.file = os::fdopen( fd, "r" );
    if( result.file == nullptr )
    {
        result.err = errno;
        os::close( fd );   // fdopen did not take the descriptor, so it is still this function's to close
    }
    return result;
}

} // namespace rw::pathguard
