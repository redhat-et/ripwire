#pragma once

// os_win32_logic.h — the PURE logic behind the Windows bodies in os_win32.cpp, kept out of that file so it compiles
// and runs on every platform.
//
// WHY A SEPARATE HEADER. os_win32.cpp is compiled only for Windows, and nobody who reviews this code has a Windows
// machine. Everything in it that is not a Win32 call — a table, a string transform, a classification — lives here
// instead: no <windows.h>, no preprocessor platform test, no system call. test/verify_os_win32_logic.cpp exercises
// every function on the Linux and macOS legs, so the Windows-only logic is type-checked and tested where it is
// reviewed, and cannot rot unseen. Uncalled inline code emits nothing, so a POSIX build pays nothing for it.
//
// WHAT IS HERE
//   1. errnoFromWin32 — one Win32/Winsock error → errno table, so every Windows body sets the errno its POSIX
//      twin's call site already tests (ELOOP, EWOULDBLOCK, EINTR, …).
//   2. UTF-8 ↔ UTF-16, strict, and WidePath — the UTF-16 spelling of a program path on a stack buffer (heap only
//      past MAX_PATH), accepting Git Bash's "/c/..." drive spelling at the same pass.
//   3. The program path spelling — '/' separators, an upper-case drive letter, no "\\?\" prefix — from a native
//      path (realpath/getcwd/exepath results), and the in-place intake rewrite for path-valued arguments.
//   4. Command-line quoting for CreateProcessW, adapted from libuv (notice at that section).
//   5. Reparse-tag and file-attribute classification — which reparse points are links (symlink, junction) and
//      the st_mode a stat reports.
//   6. Time, wait-status and socket-timeout conversions, and the socket-descriptor range.
//   7. The shell choice: which bash may run a command (never a WSL launcher, never a relative PATH entry).
//   8. The PATH remedy --doctor prints when no copy of this program is on PATH, in PowerShell's spelling.
//
// Nothing here reads errno, the environment or the file system; every input is a parameter. Every function is noexcept
// (owner directive 2026-09-16: RAII and return values, no exception handling): the ones that build a std::string can
// only fail by exhausting memory, which the house treats as the operator-new seam, not as a recoverable error.

#include <algorithm>
#include <array>
#include <cerrno>
#include <cstddef>
#include <cstdint>
#include <initializer_list>
#include <memory>
#include <new>
#include <string>
#include <string_view>

namespace rw::oswin
{

// ═════════════════════════════════════════════════════════════════════════════════════════════════════════════
// 1. Win32 / Winsock error codes → errno
// ═════════════════════════════════════════════════════════════════════════════════════════════════════════════
//
// Rows are adapted from libuv's uv_translate_sys_error (src/win/error.c at libuv e15526ade343bdfc7cdaaeb0a51b9bba656533ce;
// MIT, "Copyright Joyent, Inc. and other Node contributors", notice in THIRD_PARTY.md), retargeted from UV_E* to
// <cerrno> names and modified where a POSIX call site needs a different answer than libuv's event loop does:
//   ACCESS_DENIED → EACCES (libuv EPERM: open()/rename() callers expect EACCES)   LOCK_VIOLATION → EWOULDBLOCK (flock LOCK_NB)
//   DIRECTORY → ENOTDIR (libuv ENOENT)   STOPPED_ON_SYMLINK → ELOOP (added)        BROKEN_PIPE / NO_DATA → EPIPE (libuv EOF/EAGAIN)
//   WSAEINTR → EINTR (libuv ECANCELED)   NO_UNICODE_TRANSLATION → EILSEQ          BAD_EXE_FORMAT → ENOEXEC
//   NOT_A_REPARSE_POINT → EINVAL, DELETE_PENDING → EACCES, BUSY → EBUSY, TIMEOUT → ETIMEDOUT, NOT_READY → EIO,
//   BAD_NETPATH / BAD_NET_NAME → ENOENT (added)
//   WSAESOCKTNOSUPPORT → EPROTONOSUPPORT and WSAEPFNOSUPPORT → EAFNOSUPPORT (the UCRT has no ESOCKTNOSUPPORT)
// An unmapped code is EIO: an honest "the operation failed", never a guess at a cause.
//
// The numeric codes are Win32 ABI constants (winerror.h / winsock2.h); they are spelled as numbers because this
// header must not see <windows.h>. The name is on every row.
struct ErrnoRow
{
    std::uint32_t code;
    int           errnoValue;
};

inline constexpr ErrnoRow kWin32ErrnoTable[] = {
    { 1,     EISDIR },          // ERROR_INVALID_FUNCTION (ReadFile on a directory handle)
    { 2,     ENOENT },          // ERROR_FILE_NOT_FOUND
    { 3,     ENOENT },          // ERROR_PATH_NOT_FOUND
    { 4,     EMFILE },          // ERROR_TOO_MANY_OPEN_FILES
    { 5,     EACCES },          // ERROR_ACCESS_DENIED
    { 6,     EBADF },           // ERROR_INVALID_HANDLE
    { 8,     ENOMEM },          // ERROR_NOT_ENOUGH_MEMORY
    { 13,    EINVAL },          // ERROR_INVALID_DATA
    { 14,    ENOMEM },          // ERROR_OUTOFMEMORY
    { 15,    ENOENT },          // ERROR_INVALID_DRIVE
    { 17,    EXDEV },           // ERROR_NOT_SAME_DEVICE
    { 19,    EROFS },           // ERROR_WRITE_PROTECT
    { 21,    EIO },             // ERROR_NOT_READY
    { 23,    EIO },             // ERROR_CRC
    { 31,    EIO },             // ERROR_GEN_FAILURE
    { 32,    EBUSY },           // ERROR_SHARING_VIOLATION
    { 33,    EWOULDBLOCK },     // ERROR_LOCK_VIOLATION
    { 39,    ENOSPC },          // ERROR_HANDLE_DISK_FULL
    { 50,    ENOTSUP },         // ERROR_NOT_SUPPORTED
    { 53,    ENOENT },          // ERROR_BAD_NETPATH
    { 64,    ECONNRESET },      // ERROR_NETNAME_DELETED
    { 67,    ENOENT },          // ERROR_BAD_NET_NAME
    { 80,    EEXIST },          // ERROR_FILE_EXISTS
    { 82,    ENOSPC },          // ERROR_CANNOT_MAKE
    { 87,    EINVAL },          // ERROR_INVALID_PARAMETER
    { 109,   EPIPE },           // ERROR_BROKEN_PIPE
    { 110,   EIO },             // ERROR_OPEN_FAILED
    { 111,   ENAMETOOLONG },    // ERROR_BUFFER_OVERFLOW
    { 112,   ENOSPC },          // ERROR_DISK_FULL
    { 121,   ETIMEDOUT },       // ERROR_SEM_TIMEOUT
    { 122,   EINVAL },          // ERROR_INSUFFICIENT_BUFFER
    { 123,   ENOENT },          // ERROR_INVALID_NAME
    { 126,   ENOENT },          // ERROR_MOD_NOT_FOUND
    { 131,   EINVAL },          // ERROR_NEGATIVE_SEEK
    { 145,   ENOTEMPTY },       // ERROR_DIR_NOT_EMPTY
    { 156,   EIO },             // ERROR_SIGNAL_REFUSED
    { 161,   ENOENT },          // ERROR_BAD_PATHNAME
    { 170,   EBUSY },           // ERROR_BUSY
    { 183,   EEXIST },          // ERROR_ALREADY_EXISTS
    { 193,   ENOEXEC },         // ERROR_BAD_EXE_FORMAT
    { 203,   ENOENT },          // ERROR_ENVVAR_NOT_FOUND
    { 205,   EIO },             // ERROR_NO_SIGNAL_SENT
    { 206,   ENAMETOOLONG },    // ERROR_FILENAME_EXCED_RANGE
    { 208,   E2BIG },           // ERROR_META_EXPANSION_TOO_LONG
    { 230,   EPIPE },           // ERROR_BAD_PIPE
    { 231,   EBUSY },           // ERROR_PIPE_BUSY
    { 232,   EPIPE },           // ERROR_NO_DATA (the read end is closed)
    { 233,   EPIPE },           // ERROR_PIPE_NOT_CONNECTED
    { 267,   ENOTDIR },         // ERROR_DIRECTORY
    { 277,   ENOSPC },          // ERROR_EA_TABLE_FULL
    { 303,   EACCES },          // ERROR_DELETE_PENDING
    { 681,   ELOOP },           // ERROR_STOPPED_ON_SYMLINK
    { 740,   EACCES },          // ERROR_ELEVATION_REQUIRED
    { 995,   ECANCELED },       // ERROR_OPERATION_ABORTED
    { 997,   EWOULDBLOCK },     // ERROR_IO_PENDING — defence: LockFileEx( LOCKFILE_FAIL_IMMEDIATELY ) reports contention
                                // as 33/ERROR_LOCK_VIOLATION on the synchronous handles this codebase uses (measured;
                                // #44's rw_flock passed mcpeditracecheck's race trials on that code), never 997. If an
                                // overlapped handle ever reaches this path, 997 must still read as contention — an
                                // unmapped EIO would make the edit-lock retry loop give up and proceed lock-free.
    { 998,   EFAULT },          // ERROR_NOACCESS
    { 1004,  EBADF },           // ERROR_INVALID_FLAGS
    { 1100,  ENOSPC },          // ERROR_END_OF_MEDIA
    { 1101,  EIO },             // ERROR_FILEMARK_DETECTED
    { 1102,  EIO },             // ERROR_BEGINNING_OF_MEDIA
    { 1103,  EIO },             // ERROR_SETMARK_DETECTED
    { 1104,  EIO },             // ERROR_NO_DATA_DETECTED
    { 1106,  EIO },             // ERROR_INVALID_BLOCK_LENGTH
    { 1111,  EIO },             // ERROR_BUS_RESET
    { 1113,  EILSEQ },          // ERROR_NO_UNICODE_TRANSLATION
    { 1117,  EIO },             // ERROR_IO_DEVICE
    { 1129,  EIO },             // ERROR_EOM_OVERFLOW
    { 1165,  EIO },             // ERROR_DEVICE_REQUIRES_CLEANING
    { 1166,  EIO },             // ERROR_DEVICE_DOOR_OPEN
    { 1225,  ECONNREFUSED },    // ERROR_CONNECTION_REFUSED
    { 1227,  EADDRINUSE },      // ERROR_ADDRESS_ALREADY_ASSOCIATED
    { 1231,  ENETUNREACH },     // ERROR_NETWORK_UNREACHABLE
    { 1232,  EHOSTUNREACH },    // ERROR_HOST_UNREACHABLE
    { 1236,  ECONNABORTED },    // ERROR_CONNECTION_ABORTED
    { 1314,  EPERM },           // ERROR_PRIVILEGE_NOT_HELD
    { 1393,  EIO },             // ERROR_DISK_CORRUPT
    { 1460,  ETIMEDOUT },       // ERROR_TIMEOUT
    { 1464,  EINVAL },          // ERROR_SYMLINK_NOT_SUPPORTED
    { 1920,  EACCES },          // ERROR_CANT_ACCESS_FILE
    { 1921,  ELOOP },           // ERROR_CANT_RESOLVE_FILENAME
    { 2250,  ENOTCONN },        // ERROR_NOT_CONNECTED
    { 4390,  EINVAL },          // ERROR_NOT_A_REPARSE_POINT
    { 4392,  ENOENT },          // ERROR_INVALID_REPARSE_DATA
    { 10004, EINTR },           // WSAEINTR
    { 10009, EBADF },           // WSAEBADF
    { 10013, EACCES },          // WSAEACCES
    { 10014, EFAULT },          // WSAEFAULT
    { 10022, EINVAL },          // WSAEINVAL
    { 10024, EMFILE },          // WSAEMFILE
    { 10035, EWOULDBLOCK },     // WSAEWOULDBLOCK
    { 10036, EINPROGRESS },     // WSAEINPROGRESS
    { 10037, EALREADY },        // WSAEALREADY
    { 10038, ENOTSOCK },        // WSAENOTSOCK
    { 10040, EMSGSIZE },        // WSAEMSGSIZE
    { 10043, EPROTONOSUPPORT }, // WSAEPROTONOSUPPORT
    { 10044, EPROTONOSUPPORT }, // WSAESOCKTNOSUPPORT
    { 10046, EAFNOSUPPORT },    // WSAEPFNOSUPPORT
    { 10047, EAFNOSUPPORT },    // WSAEAFNOSUPPORT
    { 10048, EADDRINUSE },      // WSAEADDRINUSE
    { 10049, EADDRNOTAVAIL },   // WSAEADDRNOTAVAIL
    { 10050, ENETDOWN },        // WSAENETDOWN
    { 10051, ENETUNREACH },     // WSAENETUNREACH
    { 10053, ECONNABORTED },    // WSAECONNABORTED
    { 10054, ECONNRESET },      // WSAECONNRESET
    { 10055, ENOBUFS },         // WSAENOBUFS
    { 10056, EISCONN },         // WSAEISCONN
    { 10057, ENOTCONN },        // WSAENOTCONN
    { 10058, EPIPE },           // WSAESHUTDOWN
    { 10060, ETIMEDOUT },       // WSAETIMEDOUT
    { 10061, ECONNREFUSED },    // WSAECONNREFUSED
    { 10065, EHOSTUNREACH },    // WSAEHOSTUNREACH
    { 10093, ENETDOWN },        // WSANOTINITIALISED
    { 11001, ENOENT },          // WSAHOST_NOT_FOUND
    { 11004, ENOENT },          // WSANO_DATA
};

// errno for a Win32 or Winsock error code; EIO for a code the table does not name. A binary search over the sorted
// table — the static_asserts below keep it sorted and without duplicates.
constexpr int errnoFromWin32( std::uint32_t code ) noexcept
{
    std::size_t low = 0, high = std::size( kWin32ErrnoTable );
    while( low < high )
    {
        const std::size_t mid = low + ( high - low ) / 2;
        if( kWin32ErrnoTable[ mid ].code < code )
        {
            low = mid + 1;
        }
        else
        {
            high = mid;
        }
    }
    return low < std::size( kWin32ErrnoTable ) && kWin32ErrnoTable[ low ].code == code ? kWin32ErrnoTable[ low ].errnoValue : EIO;
}

constexpr bool isWin32ErrnoTableSorted() noexcept
{
    const auto isOutOfOrder = []( const ErrnoRow& a, const ErrnoRow& b ) { return a.code >= b.code; };
    return std::ranges::adjacent_find( kWin32ErrnoTable, isOutOfOrder ) == std::ranges::end( kWin32ErrnoTable );
}
static_assert( isWin32ErrnoTableSorted(), "kWin32ErrnoTable must be strictly ascending by code — errnoFromWin32 binary-searches it" );

// COMPLETENESS, compile-time: every errno a call site under src/ compares against (ELOOP after a no-follow open,
// EWOULDBLOCK after flock LOCK_NB, EINTR around accept/poll) and every errno a body sets on the paths those
// call sites read must be PRODUCIBLE from some Win32 code — a value no row yields would make that branch dead on
// Windows without a word. Extend this list when a call site starts testing a new errno.
constexpr bool win32TableProduces( int errnoValue ) noexcept
{
    return std::ranges::any_of( kWin32ErrnoTable, [ errnoValue ]( const ErrnoRow& row ) { return row.errnoValue == errnoValue; } );
}
inline constexpr int kErrnoValuesCallSitesTest[] = { ELOOP, EWOULDBLOCK, EINTR, ENOENT, EACCES, EEXIST, EINVAL, ENOTDIR, EISDIR,
                                                    EPIPE, EBUSY, ENOSPC, ENAMETOOLONG, EILSEQ, EADDRINUSE, ECONNRESET, ETIMEDOUT };
constexpr bool win32TableIsComplete() noexcept
{
    return std::ranges::all_of( kErrnoValuesCallSitesTest, []( int value ) { return win32TableProduces( value ); } );
}
static_assert( win32TableIsComplete(), "an errno that a call site tests is produced by no Win32 code in kWin32ErrnoTable" );
static_assert( errnoFromWin32( 5 ) == EACCES && errnoFromWin32( 33 ) == EWOULDBLOCK && errnoFromWin32( 1921 ) == ELOOP
               && errnoFromWin32( 10004 ) == EINTR && errnoFromWin32( 0xDEADBEEF ) == EIO );

// ═════════════════════════════════════════════════════════════════════════════════════════════════════════════
// 2. UTF-8 ↔ UTF-16 (strict) and WidePath
// ═════════════════════════════════════════════════════════════════════════════════════════════════════════════
//
// Strict both ways: an overlong form, a surrogate code point encoded in UTF-8, a value past U+10FFFF, a truncated
// sequence, or a lone UTF-16 surrogate is an error (EILSEQ), never a replacement character and never a fallback to
// the ANSI code page. A path that cannot be spelled exactly is refused, because a lossy spelling names a different
// file. (libuv's WTF-8 decoder, the alternative D0 looked at, accepts the overlong "E0 80 AF" as '/'.)

// Decode one scalar value at text[ at ]; advances `at`. False on any malformed or non-shortest form.
constexpr bool decodeUtf8( std::string_view text, std::size_t& at, char32_t& scalar ) noexcept
{
    const auto byteAt = [ & ]( std::size_t i ) -> unsigned { return static_cast<unsigned char>( text[ i ] ); };
    const unsigned lead = byteAt( at );
    if( lead < 0x80 )
    {
        scalar = lead;
        at += 1;
        return true;
    }
    std::size_t length = 0;
    char32_t    value  = 0;
    char32_t    floor  = 0;
    if( lead >= 0xC2 && lead <= 0xDF )
    {
        length = 2; value = lead & 0x1F; floor = 0x80;
    }
    else if( lead >= 0xE0 && lead <= 0xEF )
    {
        length = 3; value = lead & 0x0F; floor = 0x800;
    }
    else if( lead >= 0xF0 && lead <= 0xF4 )
    {
        length = 4; value = lead & 0x07; floor = 0x10000;
    }
    else
    {
        return false;                                   // a continuation byte, C0/C1 (always overlong), or F5..FF
    }
    if( text.size() - at < length )
    {
        return false;
    }
    for( std::size_t i = 1; i < length; ++i )
    {
        const unsigned next = byteAt( at + i );
        if( ( next & 0xC0 ) != 0x80 )
        {
            return false;
        }
        value = ( value << 6 ) | ( next & 0x3F );
    }
    if( value < floor || value > 0x10FFFF || ( value >= 0xD800 && value <= 0xDFFF ) )
    {
        return false;
    }
    scalar = value;
    at += length;
    return true;
}

// UTF-16 code units `utf8` needs, or -1 when it is not valid UTF-8.
constexpr std::ptrdiff_t utf16LengthOf( std::string_view utf8 ) noexcept
{
    std::ptrdiff_t units = 0;
    for( std::size_t at = 0; at < utf8.size(); )
    {
        char32_t scalar = 0;
        if( !decodeUtf8( utf8, at, scalar ) )
        {
            return -1;
        }
        units += scalar >= 0x10000 ? 2 : 1;
    }
    return units;
}

// Write the UTF-16 of an already-validated `utf8` into out (utf16LengthOf( utf8 ) units, no terminator added).
constexpr void encodeUtf16( std::string_view utf8, char16_t* out ) noexcept
{
    for( std::size_t at = 0; at < utf8.size(); )
    {
        char32_t scalar = 0;
        (void)decodeUtf8( utf8, at, scalar );
        if( scalar >= 0x10000 )
        {
            scalar -= 0x10000;
            *out++ = static_cast<char16_t>( 0xD800 + ( scalar >> 10 ) );
            *out++ = static_cast<char16_t>( 0xDC00 + ( scalar & 0x3FF ) );
        }
        else
        {
            *out++ = static_cast<char16_t>( scalar );
        }
    }
}

// UTF-8 bytes `utf16` needs, or -1 when it holds a lone surrogate.
constexpr std::ptrdiff_t utf8LengthOf( std::u16string_view utf16 ) noexcept
{
    std::ptrdiff_t bytes = 0;
    for( std::size_t i = 0; i < utf16.size(); ++i )
    {
        const char32_t unit = utf16[ i ];
        if( unit >= 0xD800 && unit <= 0xDBFF )
        {
            if( i + 1 >= utf16.size() || utf16[ i + 1 ] < 0xDC00 || utf16[ i + 1 ] > 0xDFFF )
            {
                return -1;
            }
            bytes += 4;
            ++i;
        }
        else if( unit >= 0xDC00 && unit <= 0xDFFF )
        {
            return -1;
        }
        else
        {
            bytes += unit < 0x80 ? 1 : unit < 0x800 ? 2 : 3;
        }
    }
    return bytes;
}

// Write the UTF-8 of an already-validated `utf16` into out (utf8LengthOf( utf16 ) bytes, no terminator added).
constexpr void encodeUtf8( std::u16string_view utf16, char* out ) noexcept
{
    for( std::size_t i = 0; i < utf16.size(); ++i )
    {
        char32_t scalar = utf16[ i ];
        if( scalar >= 0xD800 && scalar <= 0xDBFF )
        {
            scalar = 0x10000 + ( ( scalar - 0xD800 ) << 10 ) + ( char32_t( utf16[ i + 1 ] ) - 0xDC00 );
            ++i;
        }
        if( scalar < 0x80 )
        {
            *out++ = static_cast<char>( scalar );
        }
        else if( scalar < 0x800 )
        {
            *out++ = static_cast<char>( 0xC0 | ( scalar >> 6 ) );
            *out++ = static_cast<char>( 0x80 | ( scalar & 0x3F ) );
        }
        else if( scalar < 0x10000 )
        {
            *out++ = static_cast<char>( 0xE0 | ( scalar >> 12 ) );
            *out++ = static_cast<char>( 0x80 | ( ( scalar >> 6 ) & 0x3F ) );
            *out++ = static_cast<char>( 0x80 | ( scalar & 0x3F ) );
        }
        else
        {
            *out++ = static_cast<char>( 0xF0 | ( scalar >> 18 ) );
            *out++ = static_cast<char>( 0x80 | ( ( scalar >> 12 ) & 0x3F ) );
            *out++ = static_cast<char>( 0x80 | ( ( scalar >> 6 ) & 0x3F ) );
            *out++ = static_cast<char>( 0x80 | ( scalar & 0x3F ) );
        }
    }
}

constexpr char asciiUpper( char c ) noexcept
{
    return c >= 'a' && c <= 'z' ? static_cast<char>( c - ( 'a' - 'A' ) ) : c;
}

// A Windows DRIVE letter, which is what all eight call sites below actually ask — "C:", "/c/", the
// extended-length prefix, the MSYS rewrite, path_is_root. Spelled through asciiUpper because that IS the
// rule: a drive letter is case-insensitive, `C:` and `c:` name the same volume, and every caller here
// then compares or rewrites the spelling rather than the case. It replaces an `isAsciiLetter` whose name
// promised more than any caller wanted and whose body repeated a range pair this file already folds.
constexpr bool isDriveLetter( char c ) noexcept
{
    const char upper = asciiUpper( c );
    return upper >= 'A' && upper <= 'Z';
}

// Git Bash's drive spelling: "/c" or "/c/..." (one ASCII letter). Length-preserving: the rewrite is "C:" + rest.
constexpr bool isMsysDrivePrefix( std::string_view path ) noexcept
{
    return path.size() >= 2 && path[ 0 ] == '/' && isDriveLetter( path[ 1 ] ) && ( path.size() == 2 || path[ 2 ] == '/' || path[ 2 ] == '\\' );
}

// WidePath: the NUL-terminated UTF-16 spelling a -W Win32 call takes, for one UTF-8 program path. The storage is on
// the stack up to MAX_PATH (260) units — nearly every path — and one heap block past it. Separators become '\', and
// Git Bash's "/c/..." becomes "C:\...". No other rewriting: the path names exactly what the caller asked for.
// ok() is false with error() == EILSEQ for invalid UTF-8, ENOMEM when the heap block cannot be had, and EINVAL for a
// null pointer; a failed WidePath's c_str() is an empty string, which every -W API refuses.
class WidePath
{
public:
    static constexpr std::size_t kStackUnits = 261;   // MAX_PATH + the terminator

    explicit WidePath( const char* utf8Path ) noexcept
    {
        if( utf8Path == nullptr )
        {
            error_ = EINVAL;
            return;
        }
        std::string_view text( utf8Path );
        const bool msysDrive = isMsysDrivePrefix( text );
        const std::ptrdiff_t units = utf16LengthOf( text );
        if( units < 0 )
        {
            error_ = EILSEQ;
            return;
        }
        const std::size_t needed = static_cast<std::size_t>( units ) + 1;
        if( needed > kStackUnits )
        {
            heap_.reset( new( std::nothrow ) char16_t[ needed ] );
            if( !heap_ )
            {
                error_ = ENOMEM;
                return;
            }
            data_ = heap_.get();
        }
        encodeUtf16( text, data_ );
        data_[ units ] = u'\0';
        for( std::ptrdiff_t i = 0; i < units; ++i )
        {
            if( data_[ i ] == u'/' )
            {
                data_[ i ] = u'\\';
            }
        }
        if( msysDrive )
        {
            data_[ 0 ] = static_cast<char16_t>( asciiUpper( text[ 1 ] ) );
            data_[ 1 ] = u':';
            if( units == 2 )
            {
                // "/c" alone names the drive root: "C:" would be the drive's CURRENT directory, so spell "C:\". Three units
                // and the terminator always fit the stack buffer, which is where a 2-unit path is.
                data_[ 2 ] = u'\\';
                data_[ 3 ] = u'\0';
                length_ = 3;
                return;
            }
        }
        length_ = static_cast<std::size_t>( units );
    }

    WidePath( const WidePath& ) = delete;
    WidePath& operator=( const WidePath& ) = delete;

    [[nodiscard]] bool            ok() const noexcept { return error_ == 0; }
    [[nodiscard]] int             error() const noexcept { return error_; }
    [[nodiscard]] const char16_t* c_str() const noexcept { return ok() ? data_ : u""; }
    [[nodiscard]] std::size_t     size() const noexcept { return ok() ? length_ : 0; }
    [[nodiscard]] bool            onHeap() const noexcept { return static_cast<bool>( heap_ ); }

private:
    char16_t                    stack_[ kStackUnits ] = {};
    std::unique_ptr<char16_t[]> heap_;
    char16_t*                   data_   = stack_;
    std::size_t                 length_ = 0;
    int                         error_  = 0;
};

// ═════════════════════════════════════════════════════════════════════════════════════════════════════════════
// 3. The program's path spelling
// ═════════════════════════════════════════════════════════════════════════════════════════════════════════════
//
// Inside the program a path is UTF-8 with '/' separators on every platform. On Windows that means an upper-case
// drive letter ("C:/repo"), a UNC share as "//server/share", and no "\\?\" extended-length prefix (which Windows
// adds to GetFinalPathNameByHandleW's answer and which no caller wants in XML, a cache key or an MCP handle).

// UTF-8 program path of a native UTF-16 path, written to out (NUL-terminated). The bytes written, excluding the NUL;
// or -1 with *error = EILSEQ (a lone surrogate) or ENAMETOOLONG (does not fit in outCount bytes).
constexpr std::ptrdiff_t programPathFromNative( std::u16string_view native, char* out, std::size_t outCount, int* error ) noexcept
{
    bool isUnc = false;
    if( native.substr( 0, 8 ) == u"\\\\?\\UNC\\" )
    {
        native.remove_prefix( 8 );
        isUnc = true;
    }
    else if( native.substr( 0, 4 ) == u"\\\\?\\" || native.substr( 0, 4 ) == u"\\??\\" )
    {
        native.remove_prefix( 4 );
    }
    const std::ptrdiff_t bytes = utf8LengthOf( native );
    if( bytes < 0 )
    {
        *error = EILSEQ;
        return -1;
    }
    const std::size_t prefix = isUnc ? 2 : 0;
    if( static_cast<std::size_t>( bytes ) + prefix + 1 > outCount )
    {
        *error = ENAMETOOLONG;
        return -1;
    }
    if( isUnc )
    {
        out[ 0 ] = '/';
        out[ 1 ] = '/';
    }
    encodeUtf8( native, out + prefix );
    const std::size_t total = static_cast<std::size_t>( bytes ) + prefix;
    out[ total ] = '\0';
    for( std::size_t i = 0; i < total; ++i )
    {
        if( out[ i ] == '\\' )
        {
            out[ i ] = '/';
        }
    }
    if( !isUnc && total >= 2 && isDriveLetter( out[ 0 ] ) && out[ 1 ] == ':' )
    {
        out[ 0 ] = asciiUpper( out[ 0 ] );
    }
    return static_cast<std::ptrdiff_t>( total );
}

// The intake rewrite for ONE path-valued argument (a positional root, a --cache= value, an MCP `path`), in place and
// length-preserving: every '\' becomes '/', Git Bash's "/c/..." drive spelling becomes "C:/...", and a drive letter is
// upper-cased ("c:/repo" → "C:/repo", the spelling realpath returns). The drive rewrite
// is tried at the start of the text and after each ',' (list-valued flags such as --affected=F1,F2) — never after a
// ':', because "C:/a/b" would then read its "/a/" as a second drive. Only ever called for arguments the parser knows
// are paths: a --grep pattern containing "/x/" must not be touched.
constexpr void normalizePathArgInPlace( char* text ) noexcept
{
    if( text == nullptr )
    {
        return;
    }
    for( char* p = text; *p != '\0'; ++p )
    {
        if( *p == '\\' )
        {
            *p = '/';
        }
    }
    for( char* p = text; *p != '\0'; ++p )
    {
        const bool atBoundary = p == text || p[ -1 ] == ',';
        if( atBoundary && p[ 0 ] == '/' && isDriveLetter( p[ 1 ] ) && ( p[ 2 ] == '/' || p[ 2 ] == '\0' || p[ 2 ] == ',' ) )
        {
            p[ 0 ] = asciiUpper( p[ 1 ] );
            p[ 1 ] = ':';
        }
        else if( atBoundary && isDriveLetter( p[ 0 ] ) && p[ 1 ] == ':' )
        {
            p[ 0 ] = asciiUpper( p[ 0 ] );   // "c:/repo" and "C:/repo" are one directory; the program spells the drive upper-case
        }
    }
}

// POSIX code fails a path CLOSED by putting it under "/dev/null" — a device, so nothing below it can ever exist
// (quality.h's cache ladder does this for an unsafe cache directory). On Windows that spelling would name "\\dev\\null\\..."
// on the current drive, which any user may create. A path at or under "/dev/null/" is therefore rewritten to one that
// contains '|', a character no Win32 file name may hold, so every open, stat and mkdir of it fails. "/dev/null" itself
// is the NUL device. Any other path returns empty.
inline std::string rebaseDevNull( std::string_view path ) noexcept
{
    if( path == "/dev/null" )
    {
        return "NUL";
    }
    if( path.substr( 0, 10 ) != "/dev/null/" )
    {
        return {};
    }
    return "|unusable|" + std::string( path.substr( 9 ) );
}

// Git for Windows' "/tmp" is the user's temporary directory. A program path at or under "/tmp" — the POSIX cache
// ladder's last rung, or a Git Bash spelling that reached the program unconverted — is rebased onto nativeTmp (read
// once by the caller; either separator, a trailing one allowed) and returned in the program's spelling. Any other
// path returns empty, and the caller uses it unchanged.
inline std::string rebaseMsysTmp( std::string_view path, std::string_view nativeTmp ) noexcept
{
    if( path.substr( 0, 4 ) != "/tmp" || ( path.size() > 4 && path[ 4 ] != '/' ) || nativeTmp.empty() )
    {
        return {};
    }
    while( nativeTmp.size() > 1 && ( nativeTmp.back() == '/' || nativeTmp.back() == '\\' ) )
    {
        nativeTmp.remove_suffix( 1 );
    }
    std::string out;
    out.reserve( nativeTmp.size() + path.size() - 4 );
    out.append( nativeTmp );
    out.append( path.substr( 4 ) );
    for( char& c : out )
    {
        if( c == '\\' )
        {
            c = '/';
        }
    }
    if( out.size() >= 2 && isDriveLetter( out[ 0 ] ) && out[ 1 ] == ':' )
    {
        out[ 0 ] = asciiUpper( out[ 0 ] );
    }
    return out;
}

// The dispatch every os_win32.cpp syscall body makes before it touches Win32: which rebase (if any) applies to
// `path`. Extracted from NativePath::rebase() (os_win32.cpp) so a caller OUTSIDE the os:: layer — one that hands a
// path to something Win32-shaped that is not os:: itself, such as std::filesystem or a popen'd shell command — can
// ask the same question without a Win32 call, and so this routing is exercised by test/verify_os_win32_logic.cpp
// instead of only by whichever Windows CI leg happens to touch it. Pure prefix routing: "" (not "/tmp" or
// "/dev/null") is returned unchanged by both branches above, and reaches here as-is; NativePath treats an empty
// result as "no rebase, use `path` verbatim" and os::rebased_path does the same.
//
// #326: this is the seam --doctor's cache-dir check was missing — its writability probe called bare std::fopen and
// its blob scan called std::filesystem::directory_iterator directly on cacheDirLadder()'s un-rebased "/tmp/<cache-dir>-
// <uid>" spelling, neither of which passes through NativePath, so on Windows both silently measured a directory
// (the CURRENT DRIVE's "\tmp\<cache-dir>-<uid>") that the cache never actually uses (rw::os::mkdir DID rebase, via this
// same routing, so the real cache directory the tool writes to was elsewhere and always healthy). The cache-eviction
// sweep (quality.h evictOldCacheFamily) and the shard layout (resolveCacheBlobPath) read that same spelling the same
// way, so cacheDirLadder() now resolves it ONCE through rw::os::rebased_path, at the source, for every consumer. That
// is only safe because this dispatch is idempotent: an answer it already gave starts with a drive letter (or the
// "|unusable|" sentinel), never '/', so a second pass — every os:: call NativePath makes on the resolved path — is a
// no-op. test/verify_os_win32_logic.cpp pins that property.
inline std::string rebasedProgramPath( std::string_view path, std::string_view nativeTmp ) noexcept
{
    if( path.empty() || path.front() != '/' )
    {
        return {};
    }
    if( path.substr( 0, 4 ) == "/tmp" )
    {
        return rebaseMsysTmp( path, nativeTmp );   // may itself answer {} — see that function's own boundary checks
    }
    if( path.substr( 0, 9 ) == "/dev/null" )
    {
        return rebaseDevNull( path );              // may itself answer {} — see that function's own boundary checks
    }
    return {};
}

// The extended-length spelling of an ABSOLUTE native path, for the -W calls that must work past MAX_PATH whatever the
// machine's LongPathsEnabled setting: "C:\\x" → "\\\\?\\C:\\x", "\\\\server\\share" → "\\\\?\\UNC\\server\\share", '/' → '\\'. A path that already
// carries the prefix is returned as it is; a relative or drive-relative path is returned empty — "\\\\?\\" turns off
// every normalisation, so it may only ever be put in front of a path that is already absolute and clean (the temp
// directory Windows reports). Idea from lennix1337's win32-port-snapshot (windowsExtendedPath), which did not check that.
inline std::u16string extendedLengthPath( std::u16string_view native ) noexcept
{
    const auto isSep = []( char16_t c ) noexcept { return c == u'\\' || c == u'/'; };
    std::u16string out;
    if( native.substr( 0, 4 ) == u"\\\\?\\" )
    {
        out.assign( native );
        return out;
    }
    const bool drive = native.size() >= 3 && native[ 0 ] < 0x80 && isDriveLetter( static_cast<char>( native[ 0 ] ) ) && native[ 1 ] == u':' && isSep( native[ 2 ] );
    const bool unc   = native.size() >= 3 && isSep( native[ 0 ] ) && isSep( native[ 1 ] ) && !isSep( native[ 2 ] ) && native[ 2 ] != u'?' && native[ 2 ] != u'.';
    if( !drive && !unc )
    {
        return out;
    }
    for( std::size_t start = 0; start <= native.size(); )
    {
        std::size_t end = start;
        while( end < native.size() && !isSep( native[ end ] ) )
        {
            ++end;
        }
        const std::u16string_view component = native.substr( start, end - start );
        if( component == u"." || component == u".." )
        {
            return out;   // a "." or ".." component: not clean, so not prefixable
        }
        start = end + 1;
    }
    out.reserve( native.size() + 6 );
    out.append( unc ? u"\\\\?\\UNC" : u"\\\\?\\" );
    for( std::size_t i = unc ? 1 : 0; i < native.size(); ++i )
    {
        out.push_back( isSep( native[ i ] ) ? u'\\' : native[ i ] );
    }
    return out;
}

// The threshold, in UTF-16 units, past which NativePath asks extendedLengthPath for the "\\?\" spelling: MAX_PATH
// (260) minus 12 — headroom CreateFileW and friends need before the hard limit (an internal 8.3-alias work item, the
// classic reason "just under MAX_PATH" still fails). Below it every path — short, already-prefixed, relative, UNC —
// is left exactly as WidePath produced it, which is also what a POSIX default-policy Windows (LongPathsEnabled=0)
// needs: past the threshold CreateFileW would otherwise fail with ERROR_PATH_NOT_FOUND → ENOENT for a file that
// exists, and the crawl or sidecar would silently skip it.
inline constexpr std::size_t kExtendedLengthThresholdUnits = 248;

// NativePath's actual decision: `native` (already WidePath's backslash spelling) gets the "\\?\" prefix only once it
// reaches `thresholdUnits`; below it, or when extendedLengthPath cannot prefix it (relative, drive-relative, or a
// "."/".." component — it still needs the machine's LongPathsEnabled policy, which this does not substitute for),
// the empty return means "unchanged": NativePath's caller keeps using the WidePath spelling it already had. Reuses
// extendedLengthPath rather than re-implementing its grammar; this is only the length gate in front of it.
inline std::u16string extendedLengthPathIfLong( std::u16string_view native, std::size_t thresholdUnits = kExtendedLengthThresholdUnits ) noexcept
{
    if( native.size() < thresholdUnits )
    {
        return {};
    }
    return extendedLengthPath( native );
}

// getline's buffer-growth arithmetic, pulled out so the NULL-line case is correct and testable without a stream.
// POSIX: "if *lineptr is NULL... the initial value of *n [capacity] is ignored" — a caller may leave garbage in
// *capacity when *line is NULL (the one caller here always passes 0, so this was latent), and doubling that garbage
// instead of starting from 0 would pick an arbitrary first allocation instead of the documented 128-byte floor.
constexpr std::size_t nextGetlineCapacity( bool lineIsNull, std::size_t capacity ) noexcept
{
    const std::size_t have = lineIsNull ? 0 : capacity;
    return have < 128 ? 128 : have * 2;
}

// A child's environment entry "NAME=value" that names a temporary directory (TMP, TEMP or TMPDIR, any case) whose
// value is at least `limit` UTF-16 units long. Git for Windows' shell and tools fail to create files under a temporary
// directory near MAX_PATH, so the process-spawning bodies give such a child a short temporary directory instead —
// in the child's environment block only, never this process's. From lennix1337's win32-port-snapshot
// (rw_windows_temporary_environment_is_long; runtracecheck's LONG_TMP arm), minus its process-wide environment rewrite.
inline constexpr std::size_t kLongTemporaryUnits = 240;

constexpr bool isLongTemporaryEntry( std::u16string_view entry, std::size_t limit = kLongTemporaryUnits ) noexcept
{
    const std::size_t equals = entry.find( u'=' );
    if( equals == std::u16string_view::npos || entry.size() - equals - 1 < limit )
    {
        return false;
    }
    const std::u16string_view name = entry.substr( 0, equals );
    const auto matches = [ & ]( std::u16string_view wanted ) noexcept
    {
        if( name.size() != wanted.size() )
        {
            return false;
        }
        for( std::size_t i = 0; i < name.size(); ++i )
        {
            const char16_t c = name[ i ] >= u'a' && name[ i ] <= u'z' ? static_cast<char16_t>( name[ i ] - 32 ) : name[ i ];
            if( c != wanted[ i ] )
            {
                return false;
            }
        }
        return true;
    };
    return matches( u"TMP" ) || matches( u"TEMP" ) || matches( u"TMPDIR" );
}

// ═════════════════════════════════════════════════════════════════════════════════════════════════════════════
// 4. Command-line quoting for CreateProcessW
// ═════════════════════════════════════════════════════════════════════════════════════════════════════════════
//
// Adapted from libuv's quote_cmd_arg (src/win/process.c at libuv e15526ade343bdfc7cdaaeb0a51b9bba656533ce).
//   Copyright Joyent, Inc. and other Node contributors. All rights reserved.
//   Permission is hereby granted, free of charge, to any person obtaining a copy of this software and associated
//   documentation files (the "Software"), to deal in the Software without restriction, including without limitation
//   the rights to use, copy, modify, merge, publish, distribute, sublicense, and/or sell copies of the Software, and
//   to permit persons to whom the Software is furnished to do so, subject to the following conditions: The above
//   copyright notice and this permission notice shall be included in all copies or substantial portions of the
//   Software. THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR IMPLIED, INCLUDING BUT NOT
//   LIMITED TO THE WARRANTIES OF MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT
//   SHALL THE AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER LIABILITY, WHETHER IN AN ACTION
//   OF CONTRACT, TORT OR OTHERWISE, ARISING FROM, OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER
//   DEALINGS IN THE SOFTWARE.
// MODIFIED: operates on UTF-8 bytes (a '"' or '\' byte never occurs inside a multi-byte UTF-8 sequence, so quoting
// before the UTF-16 conversion is exact) instead of UTF-16; builds forward instead of writing reversed and calling
// _wcsrev; and ALWAYS quotes. libuv leaves an argument with no space, tab or quote bare, but the program started here
// is bash from Git for Windows, whose MSYS runtime GLOBS a bare argument ("*.cpp" would arrive expanded) — a quoted
// argument is not globbed. The rules are the MSVCRT ones CommandLineToArgvW and the MSYS runtime both implement:
// backslashes are literal unless they precede a '"'; 2n backslashes + '"' → n backslashes and a closing quote,
// 2n+1 backslashes + '"' → n backslashes and a literal '"'.
inline void appendQuotedArg( std::string& commandLine, std::string_view arg ) noexcept
{
    commandLine.push_back( '"' );
    std::size_t backslashes = 0;
    for( const char c : arg )
    {
        if( c == '\\' )
        {
            ++backslashes;
            continue;
        }
        if( c == '"' )
        {
            commandLine.append( backslashes * 2 + 1, '\\' );   // each pending '\' doubled, plus one escaping the quote
        }
        else
        {
            commandLine.append( backslashes, '\\' );           // backslashes not before a quote are literal
        }
        backslashes = 0;
        commandLine.push_back( c );
    }
    commandLine.append( backslashes * 2, '\\' );               // before the closing quote: doubled
    commandLine.push_back( '"' );
}

// The full command line for argv (each argument quoted, single spaces between). An argument that contains a NUL
// cannot be passed and makes the result empty.
inline std::string buildCommandLine( std::initializer_list<std::string_view> argv ) noexcept
{
    std::string commandLine;
    for( const std::string_view arg : argv )
    {
        if( arg.find( '\0' ) != std::string_view::npos )
        {
            return {};
        }
        if( !commandLine.empty() )
        {
            commandLine.push_back( ' ' );
        }
        appendQuotedArg( commandLine, arg );
    }
    return commandLine;
}

// ═════════════════════════════════════════════════════════════════════════════════════════════════════════════
// 5. Reparse points and file attributes → st_mode
// ═════════════════════════════════════════════════════════════════════════════════════════════════════════════
//
// OWNER DECISION (2026-09-16): a reparse point is a LINK — refused by O_NOFOLLOW and S_IFLNK in lstat — only when its
// tag is IO_REPARSE_TAG_SYMLINK or IO_REPARSE_TAG_MOUNT_POINT (a junction, or a volume mount point). Every other tag
// (OneDrive / cloud-files placeholders, deduplication, app-execution aliases, WSL's own symlink tag) is an ordinary
// file or directory, as CPython's os.lstat reads them. Only the FINAL component is judged (POSIX O_NOFOLLOW parity).
inline constexpr std::uint32_t kReparseTagMountPoint = 0xA0000003;   // IO_REPARSE_TAG_MOUNT_POINT (junction)
inline constexpr std::uint32_t kReparseTagSymlink    = 0xA000000C;   // IO_REPARSE_TAG_SYMLINK

inline constexpr std::uint32_t kFileAttributeReadonly     = 0x00000001;
inline constexpr std::uint32_t kFileAttributeDirectory    = 0x00000010;
inline constexpr std::uint32_t kFileAttributeReparsePoint = 0x00000400;

inline constexpr std::uint32_t kFileTypeDisk = 1;   // GetFileType: FILE_TYPE_DISK
inline constexpr std::uint32_t kFileTypeChar = 2;   // FILE_TYPE_CHAR (console, NUL)
inline constexpr std::uint32_t kFileTypePipe = 3;   // FILE_TYPE_PIPE

// POSIX st_mode type bits — the same numbers on Linux, macOS and the UCRT, spelled here so this header needs no
// <sys/stat.h>.
inline constexpr unsigned kModeFifo      = 0x1000;
inline constexpr unsigned kModeCharacter = 0x2000;
inline constexpr unsigned kModeDirectory = 0x4000;
inline constexpr unsigned kModeRegular   = 0x8000;
inline constexpr unsigned kModeLink      = 0xA000;

constexpr bool isLinkReparseTag( std::uint32_t tag ) noexcept
{
    return tag == kReparseTagSymlink || tag == kReparseTagMountPoint;
}

// What a no-follow open finds at the final component, from the handle opened WITH FILE_FLAG_OPEN_REPARSE_POINT.
enum class FinalComponent : std::uint8_t
{
    Plain,          // not a reparse point: use this handle
    Link,           // symlink or junction: refuse with ELOOP
    OtherReparse,   // any other tag: reopen WITHOUT the flag, so the file's own content is read — and require the
                    // reopened handle to be the SAME file (volume serial + file id), so a link swapped in between
                    // the two opens is refused, not followed
};

constexpr FinalComponent classifyFinalComponent( std::uint32_t attributes, std::uint32_t reparseTag ) noexcept
{
    if( ( attributes & kFileAttributeReparsePoint ) == 0 )
    {
        return FinalComponent::Plain;
    }
    return isLinkReparseTag( reparseTag ) ? FinalComponent::Link : FinalComponent::OtherReparse;
}

// The type bits of st_mode. `followed` is true for stat/fstat (the handle was opened through any link, so a link
// tag here means the target is itself a reparse point that did not resolve — reported as what its attributes say).
constexpr unsigned modeTypeBits( std::uint32_t fileType, std::uint32_t attributes, std::uint32_t reparseTag, bool followed ) noexcept
{
    if( fileType == kFileTypeChar )
    {
        return kModeCharacter;
    }
    if( fileType == kFileTypePipe )
    {
        return kModeFifo;
    }
    if( !followed && ( attributes & kFileAttributeReparsePoint ) != 0 && isLinkReparseTag( reparseTag ) )
    {
        return kModeLink;
    }
    return ( attributes & kFileAttributeDirectory ) != 0 ? kModeDirectory : kModeRegular;
}

// The permission bits stat reports when it has not read an ACL: 0777 less the write bits for a read-only file. The
// owner-only answer (0700) comes from lstat's ACL read, where the cache-directory check needs it.
constexpr unsigned modePermissionBits( std::uint32_t attributes ) noexcept
{
    return ( attributes & kFileAttributeReadonly ) != 0 && ( attributes & kFileAttributeDirectory ) == 0 ? 0555u : 0777u;
}

// ═════════════════════════════════════════════════════════════════════════════════════════════════════════════
// 6. Time, wait status, socket timeouts, socket descriptors
// ═════════════════════════════════════════════════════════════════════════════════════════════════════════════

// A FILETIME / LARGE_INTEGER time (100 ns ticks since 1601-01-01 UTC) as whole Unix seconds and nanoseconds, the
// nanoseconds always in [0, 1e9) — floor division, so a pre-1970 time does not come out with a negative tv_nsec.
struct UnixTime
{
    std::int64_t seconds;
    long         nanoseconds;
};
inline constexpr std::int64_t kFiletimeTicksAtUnixEpoch = 116444736000000000LL;

constexpr UnixTime unixTimeFromFiletime( std::int64_t ticks ) noexcept
{
    const std::int64_t sinceEpoch = ticks - kFiletimeTicksAtUnixEpoch;
    std::int64_t       seconds    = sinceEpoch / 10000000;
    std::int64_t       remainder  = sinceEpoch % 10000000;
    if( remainder < 0 )
    {
        remainder += 10000000;
        seconds -= 1;
    }
    return { seconds, static_cast<long>( remainder * 100 ) };
}

// POSIX signal NUMBERS as a wait status reports them. Spelled as numbers, not <csignal> macros: the UCRT's SIGABRT is
// 22, and a run-trace report must name the same signal on every platform.
inline constexpr int kSignalInt  = 2;
inline constexpr int kSignalIll  = 4;
inline constexpr int kSignalTrap = 5;
inline constexpr int kSignalAbrt = 6;
inline constexpr int kSignalFpe  = 8;
inline constexpr int kSignalKill = 9;
inline constexpr int kSignalSegv = 11;

// The signal a POSIX shell would have reported for a process that died with this NTSTATUS exit code, or 0 when the
// code is an ordinary exit status. Only codes whose POSIX meaning is unambiguous are mapped.
constexpr int signalFromExitCode( std::uint32_t exitCode ) noexcept
{
    switch( exitCode )
    {
        case 0xC0000005u: return kSignalSegv;   // STATUS_ACCESS_VIOLATION
        case 0xC00000FDu: return kSignalSegv;   // STATUS_STACK_OVERFLOW
        case 0xC000001Du: return kSignalIll;    // STATUS_ILLEGAL_INSTRUCTION
        case 0xC0000096u: return kSignalIll;    // STATUS_PRIVILEGED_INSTRUCTION
        case 0xC000008Eu: return kSignalFpe;    // STATUS_FLOAT_DIVIDE_BY_ZERO
        case 0xC0000090u: return kSignalFpe;    // STATUS_FLOAT_INVALID_OPERATION
        case 0xC0000091u: return kSignalFpe;    // STATUS_FLOAT_OVERFLOW
        case 0xC0000094u: return kSignalFpe;    // STATUS_INTEGER_DIVIDE_BY_ZERO
        case 0xC0000095u: return kSignalFpe;    // STATUS_INTEGER_OVERFLOW
        case 0x80000003u: return kSignalTrap;   // STATUS_BREAKPOINT
        case 0xC0000409u: return kSignalAbrt;   // STATUS_STACK_BUFFER_OVERRUN (__fastfail)
        case 0xC000013Au: return kSignalInt;    // STATUS_CONTROL_C_EXIT
        default:          return 0;
    }
}

// The wait status POSIX's W* macros decode: an exit is ( code & 0xff ) << 8, a signal death is the signal number.
constexpr int waitStatusFromExit( std::uint32_t exitCode ) noexcept
{
    const int signal = signalFromExitCode( exitCode );
    return signal != 0 ? signal : static_cast<int>( ( exitCode & 0xff ) << 8 );
}

constexpr int waitStatusFromSignal( int signal ) noexcept
{
    return signal & 0x7f;
}

// The decoders os.h's Windows branch defines WIFEXITED / WEXITSTATUS / WIFSIGNALED / WTERMSIG with — the glibc/BSD
// layout, so the same status reads the same through either set.
constexpr bool waitIfExited( int status ) noexcept   { return ( status & 0x7f ) == 0; }
constexpr int  waitExitStatus( int status ) noexcept { return ( status >> 8 ) & 0xff; }
constexpr bool waitIfSignaled( int status ) noexcept { return ( status & 0x7f ) != 0 && ( status & 0x7f ) != 0x7f; }
constexpr int  waitTermSig( int status ) noexcept    { return status & 0x7f; }

// SO_RCVTIMEO: POSIX takes a timeval, Winsock a DWORD of milliseconds where 0 means NEVER time out. Round up, so a
// sub-millisecond timeout stays a timeout instead of becoming an infinite wait, and saturate at the DWORD maximum.
constexpr std::uint32_t millisecondsFromTimeval( std::int64_t seconds, std::int64_t microseconds ) noexcept
{
    if( seconds < 0 || microseconds < 0 || ( seconds == 0 && microseconds == 0 ) )
    {
        return 0;
    }
    const std::uint64_t total = static_cast<std::uint64_t>( seconds ) * 1000u + ( static_cast<std::uint64_t>( microseconds ) + 999u ) / 1000u;
    return total > 0xFFFFFFFEu ? 0xFFFFFFFEu : static_cast<std::uint32_t>( total );
}

// A Winsock SOCKET is a kernel handle, not a CRT descriptor, and POSIX call sites keep sockets in an int. socket()
// hands out descriptors from this range — past the UCRT's 8,192-descriptor ceiling, so no CRT descriptor is ever
// mistaken for one — and the socket calls and close() map them back through a fixed table.
inline constexpr int kSocketFdBase  = 0x40000000;
inline constexpr int kSocketFdCount = 1024;

constexpr bool isSocketFd( int fd ) noexcept
{
    return fd >= kSocketFdBase && fd < kSocketFdBase + kSocketFdCount;
}

// The directory watcher (os::dirwatch_open) is an I/O completion port, not a CRT descriptor either; its descriptors come
// from a second range so close() can tell the three kinds apart without a lookup.
inline constexpr int kDirwatchFdBase  = 0x50000000;
inline constexpr int kDirwatchFdCount = 64;

constexpr bool isDirwatchFd( int fd ) noexcept
{
    return fd >= kDirwatchFdBase && fd < kDirwatchFdBase + kDirwatchFdCount;
}
static_assert( kSocketFdBase + kSocketFdCount <= kDirwatchFdBase, "the socket and watcher descriptor ranges must not overlap" );

// ═════════════════════════════════════════════════════════════════════════════════════════════════════════════
// 7. Which bash may run a command
// ═════════════════════════════════════════════════════════════════════════════════════════════════════════════
//
// CodeRabbit 3946215444 on PR #44: SearchPath looks in the application directory and the CURRENT directory before
// PATH, so a checkout carrying its own sh.exe ran it. The shell is therefore resolved from absolute locations only:
// an explicit override, Git for Windows' install directories, then absolute PATH entries — never a relative entry,
// never the current directory, and never %SystemRoot%\System32\bash.exe or a WindowsApps alias, which start WSL (a
// different machine, with different paths) rather than a POSIX shell for this one.

constexpr bool equalsAsciiCaseless( std::string_view a, std::string_view b ) noexcept
{
    if( a.size() != b.size() )
    {
        return false;
    }
    for( std::size_t i = 0; i < a.size(); ++i )
    {
        char x = a[ i ], y = b[ i ];
        x = x >= 'A' && x <= 'Z' ? static_cast<char>( x + 32 ) : x == '\\' ? '/' : x;
        y = y >= 'A' && y <= 'Z' ? static_cast<char>( y + 32 ) : y == '\\' ? '/' : y;
        if( x != y )
        {
            return false;
        }
    }
    return true;
}

constexpr bool endsWithAsciiCaseless( std::string_view text, std::string_view suffix ) noexcept
{
    return text.size() >= suffix.size() && equalsAsciiCaseless( text.substr( text.size() - suffix.size() ), suffix );
}

// An absolute Windows path in either separator: "C:/..." / "C:\...", or a UNC "//server/..." / "\\server\...".
constexpr bool isAbsoluteNativePath( std::string_view path ) noexcept
{
    const auto isSep = []( char c ) { return c == '/' || c == '\\'; };
    return ( path.size() >= 3 && isDriveLetter( path[ 0 ] ) && path[ 1 ] == ':' && isSep( path[ 2 ] ) )
        || ( path.size() >= 3 && isSep( path[ 0 ] ) && isSep( path[ 1 ] ) && !isSep( path[ 2 ] ) );
}

// True for a bash that would start WSL instead of running the command here.
constexpr bool isWslLauncher( std::string_view candidate ) noexcept
{
    return endsWithAsciiCaseless( candidate, "/System32/bash.exe" ) || endsWithAsciiCaseless( candidate, "/Sysnative/bash.exe" )
        || endsWithAsciiCaseless( candidate, "/WindowsApps/bash.exe" );
}

// May this path be used as the command shell? Absolute, a bash.exe, and not a WSL launcher.
constexpr bool isAcceptableShell( std::string_view candidate ) noexcept
{
    return isAbsoluteNativePath( candidate ) && endsWithAsciiCaseless( candidate, "bash.exe" ) && !isWslLauncher( candidate );
}

// Does the last component of `path` carry an extension ("tool.exe" yes; "tool", ".profile", "dir.d/tool" no)?
constexpr bool hasExtension( std::string_view path ) noexcept
{
    const std::size_t slash = path.find_last_of( "/\\" );
    const std::string_view name = slash == std::string_view::npos ? path : path.substr( slash + 1 );
    const std::size_t dot = name.rfind( '.' );
    return dot != std::string_view::npos && dot > 0 && dot + 1 < name.size();
}

// The next entry of a ';'-separated PATH list starting at `at` (advanced past it); empty entries are returned as
// empty views for the caller to skip.
constexpr std::string_view nextPathListEntry( std::string_view list, std::size_t& at ) noexcept
{
    const std::size_t end   = list.find( ';', at );
    const std::size_t stop  = end == std::string_view::npos ? list.size() : end;
    std::string_view  entry = list.substr( at, stop - at );
    at = end == std::string_view::npos ? list.size() + 1 : end + 1;
    if( entry.size() >= 2 && entry.front() == '"' && entry.back() == '"' )
    {
        entry = entry.substr( 1, entry.size() - 2 );   // PATH entries may be quoted when they contain ';'
    }
    return entry;
}

// Is the extension of `path` one of the ';'-separated, case-insensitive entries of `pathext` (".COM;.EXE;...")? The
// list is read with nextPathListEntry, the same reader PATH itself goes through.
constexpr bool extensionInList( std::string_view path, std::string_view pathext ) noexcept
{
    if( !hasExtension( path ) )
    {
        return false;
    }
    const std::string_view extension = path.substr( path.rfind( '.' ) );
    for( std::size_t at = 0; at <= pathext.size(); )
    {
        const std::string_view entry = nextPathListEntry( pathext, at );
        if( !entry.empty() && equalsAsciiCaseless( entry, extension ) )
        {
            return true;
        }
    }
    return false;
}

// ── 8. The PATH remedy, in PowerShell's spelling ──────────────────────────────────────────────────────────────────
// powerShellSingleQuote: `s` as ONE PowerShell single-quoted string literal, in which nothing expands (no `$`, no
// backtick escape, no `$(...)`). PowerShell's grammar is not POSIX's: an embedded quote is escaped by doubling it
// (`''`, not `'\''`), and its tokenizer accepts FIVE characters as a single quote — the ASCII `'` and the typographic
// U+2018..U+201B (‘ ’ ‚ ‛; UTF-8 E2 80 98..9B), any of which closes the literal. A directory named with a
// typographic apostrophe ("O’Brien") would otherwise end the literal early and let the rest of the name run as
// code. So each of the five is doubled, itself twice, which the tokenizer reads back as that one character. `s` is
// UTF-8; any other byte is copied through unchanged.
inline std::string powerShellSingleQuote( std::string_view s ) noexcept
{
    std::string out = "'";
    for( std::size_t i = 0; i < s.size(); ++i )
    {
        const bool typographic = i + 2 < s.size() && static_cast<unsigned char>( s[i] ) == 0xE2
                              && static_cast<unsigned char>( s[i + 1] ) == 0x80 && static_cast<unsigned char>( s[i + 2] ) >= 0x98
                              && static_cast<unsigned char>( s[i + 2] ) <= 0x9B;
        if( typographic )
        {
            out.append( s.substr( i, 3 ) ).append( s.substr( i, 3 ) );
            i += 2;
        }
        else if( s[i] == '\'' )
        {
            out += "''";
        }
        else
        {
            out += s[i];
        }
    }
    out += '\'';
    return out;
}

// --doctor's binary-path row says how to put this binary's directory on PATH when no copy of this program resolves from it. The POSIX
// remedy is a shell `export PATH=` line; both Windows testers on #334 read that line in PowerShell, where it does
// nothing. Here it is PowerShell's own assignment, with the directory in native '\' separators (a program path is '/'-
// separated), for this window, and the pointer to the user Path that new windows read (README's Windows install sets it).
// The directory (plus the trailing ';') is one PowerShell single-quoted literal (powerShellSingleQuote, above);
// `$env:Path` is appended outside the quotes so it still expands to the existing Path.
inline std::string powerShellPathPrependHint( std::string_view programDir ) noexcept
{
    std::string dir( programDir );
    std::replace( dir.begin(), dir.end(), '/', '\\' );
    return "$env:Path = " + powerShellSingleQuote( dir + ";" ) + " + $env:Path"
           " in PowerShell (this window; add the directory to your user Path for new ones)";
}

}   // namespace rw::oswin
