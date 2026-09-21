// os_win32.cpp — the Windows bodies of the functions os.h declares. Compiled only for Windows; the one translation
// unit that includes <windows.h>.
//
// WHAT EACH BODY KEEPS. A call site is POSIX code, so each body keeps the POSIX contract that call site reads: the
// return value, errno (from os_win32_logic.h's one Win32→errno table), and the stat fields. Where Windows semantics
// differ in a way a caller can see, the difference is named at that body. Paths arrive in the program's spelling
// (UTF-8, '/') and are converted at the call through NativePath — a stack buffer, heap only past MAX_PATH — and
// paths handed back (realpath, getcwd, exepath, which) leave in that spelling again.
//
// WHAT IS NOT HERE. Every piece of logic that needs no Win32 call — the errno table, UTF-8/UTF-16, quoting, reparse
// classification, time and wait-status conversion — is in os_win32_logic.h, compiled and tested on every platform.
//
// INCLUDE ORDER. <winsock2.h> and <windows.h> come first, so os.h's #ifndef-guarded POSIX constants find the SDK's own
// definitions here, and its htons macro is never defined in this file.

#define WIN32_LEAN_AND_MEAN
#define NOMINMAX
#include <winsock2.h>
#include <ws2tcpip.h>
#include <windows.h>
#include <aclapi.h>
#include <sddl.h>
#include <shellapi.h>   // CommandLineToArgvW
#undef near             // <windows.h> still defines these 16-bit keywords, and the program uses `near` as a name
#undef far

#include "Diagnostics.h"       // EXPECTS — the thread calls' preconditions
#include "os.h"
#include "os_win32_logic.h"    // the pure logic, compiled and tested on every platform

#include <array>
#include <atomic>
#include <cerrno>
#include <charconv>
#include <climits>
#include <cstddef>
#include <cstdint>
#include <cstdlib>
#include <cstring>
#include <ctime>
#include <cwchar>
#include <initializer_list>
#include <memory>
#include <mutex>
#include <new>
#include <string>
#include <string_view>
#include <utility>
#include <vector>

#include <direct.h>
#include <io.h>
#include <process.h>

namespace rw::os
{

namespace
{

// ── errno ───────────────────────────────────────────────────────────────────────────────────────────────────────
int fail( int errnoValue )
{
    errno = errnoValue;
    return -1;
}

int failWin32( DWORD code )
{
    errno = oswin::errnoFromWin32( code );
    return -1;
}

int failLastError()
{
    return failWin32( ::GetLastError() );
}

// ── RAII: every handle this file opens has exactly one owner, so no early return needs a close ──────────────────────
// Owner directive 2026-09-16: RAII over exception handling. A Unique<Traits> closes what it holds in its destructor;
// release() hands ownership on (to _open_osfhandle, to a child table); nothing here throws. Traits name the value
// type, its "holds nothing" value, the validity test and the close call.
template<class Traits>
class Unique
{
public:
    using Value = typename Traits::Value;

    Unique() noexcept = default;
    explicit Unique( Value value ) noexcept : value_( value ) {}
    Unique( const Unique& ) = delete;
    Unique& operator=( const Unique& ) = delete;
    Unique( Unique&& other ) noexcept : value_( std::exchange( other.value_, Traits::empty() ) ) {}
    Unique& operator=( Unique&& other ) noexcept
    {
        if( this != &other )
        {
            reset( std::exchange( other.value_, Traits::empty() ) );
        }
        return *this;
    }
    ~Unique() { reset(); }

    [[nodiscard]] Value get() const noexcept { return value_; }
    [[nodiscard]] bool  valid() const noexcept { return Traits::isValid( value_ ); }
    [[nodiscard]] Value release() noexcept { return std::exchange( value_, Traits::empty() ); }
    void reset( Value value = Traits::empty() ) noexcept
    {
        if( Traits::isValid( value_ ) )
        {
            Traits::close( value_ );
        }
        value_ = value;
    }

private:
    Value value_ = Traits::empty();
};

// A kernel HANDLE. Win32 reports failure as INVALID_HANDLE_VALUE (CreateFile) or nullptr (CreateJobObject, OpenProcess);
// both hold nothing. GetCurrentProcess()'s pseudo-handle is never wrapped.
struct HandleTraits
{
    using Value = HANDLE;
    static Value empty() noexcept { return nullptr; }
    static bool  isValid( Value value ) noexcept { return value != nullptr && value != INVALID_HANDLE_VALUE; }
    static void  close( Value value ) noexcept { ::CloseHandle( value ); }
};
using UniqueHandle = Unique<HandleTraits>;

// Memory Win32 allocated with LocalAlloc for the caller: security descriptors, CommandLineToArgvW's array.
struct LocalTraits
{
    using Value = HLOCAL;
    static Value empty() noexcept { return nullptr; }
    static bool  isValid( Value value ) noexcept { return value != nullptr; }
    static void  close( Value value ) noexcept { ::LocalFree( value ); }
};
using UniqueLocal = Unique<LocalTraits>;

// A CRT descriptor, owned until _fdopen or a caller takes it.
struct CrtFdTraits
{
    using Value = int;
    static Value empty() noexcept { return -1; }
    static bool  isValid( Value value ) noexcept { return value >= 0; }
    static void  close( Value value ) noexcept { ::_close( value ); }
};
using UniqueFd = Unique<CrtFdTraits>;

struct SocketTraits
{
    using Value = SOCKET;
    static Value empty() noexcept { return INVALID_SOCKET; }
    static bool  isValid( Value value ) noexcept { return value != INVALID_SOCKET; }
    static void  close( Value value ) noexcept { ::closesocket( value ); }
};
using UniqueSocket = Unique<SocketTraits>;

struct EnvironmentBlockTraits
{
    using Value = LPWCH;
    static Value empty() noexcept { return nullptr; }
    static bool  isValid( Value value ) noexcept { return value != nullptr; }
    static void  close( Value value ) noexcept { ::FreeEnvironmentStringsW( value ); }
};
using UniqueEnvironmentBlock = Unique<EnvironmentBlockTraits>;

// A file this code created and must not leave behind unless it succeeds: deleted on destruction until kept.
class TemporaryFile
{
public:
    explicit TemporaryFile( std::wstring path ) noexcept : path_( std::move( path ) ) {}
    TemporaryFile() noexcept = default;
    TemporaryFile( const TemporaryFile& ) = delete;
    TemporaryFile& operator=( const TemporaryFile& ) = delete;
    TemporaryFile( TemporaryFile&& other ) noexcept : path_( std::exchange( other.path_, std::wstring() ) ) {}
    TemporaryFile& operator=( TemporaryFile&& other ) noexcept
    {
        if( this != &other )
        {
            remove();
            path_ = std::exchange( other.path_, std::wstring() );
        }
        return *this;
    }
    ~TemporaryFile() { remove(); }
    [[nodiscard]] const std::wstring& path() const noexcept { return path_; }
    [[nodiscard]] std::wstring        keep() noexcept { return std::exchange( path_, std::wstring() ); }

private:
    void remove() noexcept
    {
        if( !path_.empty() )
        {
            ::DeleteFileW( path_.c_str() );
        }
    }

    std::wstring path_;
};

// The UCRT's per-stream lock, held for a scope.
class StreamLock
{
public:
    explicit StreamLock( std::FILE* stream ) noexcept : stream_( stream ) { ::_lock_file( stream_ ); }
    StreamLock( const StreamLock& ) = delete;
    StreamLock& operator=( const StreamLock& ) = delete;
    ~StreamLock() { ::_unlock_file( stream_ ); }

private:
    std::FILE* stream_;
};

// Every handle this file opens shares read, write and delete — POSIX never refuses a rename or unlink because another
// descriptor has the file open.
constexpr DWORD kShareAll = FILE_SHARE_READ | FILE_SHARE_WRITE | FILE_SHARE_DELETE;

// ── UTF-8 / UTF-16 at the boundary ──────────────────────────────────────────────────────────────────────────────
std::u16string_view viewOf( const wchar_t* text )
{
    return text == nullptr ? std::u16string_view() : std::u16string_view( reinterpret_cast<const char16_t*>( text ), std::wcslen( text ) );
}

// UTF-8 of a UTF-16 string, or false (a lone surrogate); `out` is untouched on false.
bool utf8Of( std::u16string_view wide, std::string& out )
{
    const std::ptrdiff_t bytes = oswin::utf8LengthOf( wide );
    if( bytes < 0 )
    {
        return false;
    }
    out.assign( static_cast<std::size_t>( bytes ), '\0' );
    oswin::encodeUtf8( wide, out.data() );
    return true;
}

std::u16string utf16Of( std::string_view utf8, bool& ok )
{
    const std::ptrdiff_t units = oswin::utf16LengthOf( utf8 );
    ok = units >= 0;
    std::u16string out( static_cast<std::size_t>( ok ? units : 0 ), u'\0' );
    if( ok )
    {
        oswin::encodeUtf16( utf8, out.data() );
    }
    return out;
}

// An environment variable in UTF-8, read from the wide environment (the narrow one is in the ANSI code page).
std::string environmentUtf8( const wchar_t* name )
{
    std::string value;
    const wchar_t* const wide = ::_wgetenv( name );
    if( wide != nullptr )
    {
        (void)utf8Of( viewOf( wide ), value );
    }
    return value;
}

// A native path returned by Windows, written to `out` in the program's spelling: 0, or -1 with errno.
int programPathInto( std::u16string_view native, char* out, std::size_t outCount )
{
    int error = 0;
    if( oswin::programPathFromNative( native, out, outCount, &error ) < 0 )
    {
        return fail( error );
    }
    return 0;
}

// The user's temporary directory as Windows reports it (absolute, ending in '\'), read once and sized to fit — a TMP
// longer than MAX_PATH is legal, and runtracecheck's LONG_TMP arm sets one. Empty when Windows cannot say.
const std::u16string& nativeTempDirectory()
{
    static const std::u16string directory = []
    {
        std::u16string buffer( MAX_PATH + 2, u'\0' );
        DWORD          length = ::GetTempPathW( static_cast<DWORD>( buffer.size() ), reinterpret_cast<LPWSTR>( buffer.data() ) );
        if( length > buffer.size() )
        {
            buffer.assign( length, u'\0' );
            length = ::GetTempPathW( static_cast<DWORD>( buffer.size() ), reinterpret_cast<LPWSTR>( buffer.data() ) );
        }
        buffer.resize( length < buffer.size() ? length : 0 );
        return buffer;
    }();
    return directory;
}

// The same directory in the program's spelling — Git for Windows' "/tmp".
const std::string& userTempDirectory()
{
    static const std::string directory = []
    {
        char out[ PATH_MAX ];
        return programPathInto( nativeTempDirectory(), out, sizeof( out ) ) == 0 ? std::string( out ) : std::string();
    }();
    return directory;
}

// A new, empty, uniquely named file in the user's temporary directory, created with CREATE_NEW (never an existing
// file, never a planted link) and returned OPEN, with its extended-length name so a temporary directory past MAX_PATH
// works whatever LongPathsEnabled says. `flags` adds FILE_FLAG_* / FILE_ATTRIBUTE_* bits. Replaces GetTempFileNameW,
// which is MAX_PATH-bound and creates the file for a second open to race. From lennix1337's win32-port-snapshot
// (windowsCreateUniqueTempFile). Invalid handle with errno set on failure.
struct CreatedTemporary
{
    UniqueHandle   handle;
    std::u16string name;   // extended-length native name
};

CreatedTemporary createTemporary( const char* prefix, DWORD flags )
{
    static std::atomic<std::uint32_t> counter{ 0 };
    CreatedTemporary created;
    std::u16string   directory = oswin::extendedLengthPath( nativeTempDirectory() );
    if( directory.empty() )
    {
        (void)fail( ENOENT );
        return created;
    }
    if( directory.back() != u'\\' )
    {
        directory.push_back( u'\\' );
    }
    for( int attempt = 0; attempt < 64; ++attempt )
    {
        char        name[ 64 ];
        char*       end = name;
        const char* p   = prefix;
        while( *p != '\0' && end < name + 16 )
        {
            *end++ = *p++;
        }
        end    = std::to_chars( end, name + sizeof( name ) - 8, static_cast<unsigned long>( ::GetCurrentProcessId() ) ).ptr;
        *end++ = '-';
        end    = std::to_chars( end, name + sizeof( name ) - 5, counter.fetch_add( 1, std::memory_order_relaxed ) ).ptr;
        created.name = directory;
        for( const char* c = name; c < end; ++c )
        {
            created.name.push_back( static_cast<char16_t>( *c ) );   // ASCII
        }
        created.name.append( u".tmp" );
        created.handle.reset( ::CreateFileW( reinterpret_cast<LPCWSTR>( created.name.c_str() ), GENERIC_READ | GENERIC_WRITE, kShareAll, nullptr, CREATE_NEW,
                                             FILE_ATTRIBUTE_TEMPORARY | flags, nullptr ) );
        if( created.handle.valid() )
        {
            return created;
        }
        if( ::GetLastError() != ERROR_FILE_EXISTS && ::GetLastError() != ERROR_ALREADY_EXISTS )
        {
            break;
        }
    }
    (void)failLastError();
    created.name.clear();
    return created;
}

// A program path as the -W calls take it: Git for Windows' "/tmp" rebased onto the user's temp directory, a POSIX
// fail-closed "/dev/null/..." made unopenable (os_win32_logic.h says why) — only a path starting "/tmp" or "/dev" pays
// for either — then WidePath's UTF-16: '\' separators, "/c/..." as "C:\...", on a stack buffer below MAX_PATH. Past
// oswin::kExtendedLengthThresholdUnits, c_str() answers with the "\\?\" extended-length spelling instead (MED-1):
// without it, a path deeper than that on a default-policy (LongPathsEnabled=0) machine fails CreateFileW with
// ERROR_PATH_NOT_FOUND — ENOENT for a file that exists — and the crawl/sidecar silently skips it.
class NativePath
{
public:
    // ENSURES: c_str() always names the same file `path` did — extended_ only ever substitutes an equivalent "\\?\"
    // spelling for wide_'s; it never changes which file is opened.
    explicit NativePath( const char* path )
        : rebased_( rebase( path ) )
        , wide_( rebased_.empty() ? path : rebased_.c_str() )
        , extended_( wide_.ok() ? oswin::extendedLengthPathIfLong( std::u16string_view( wide_.c_str(), wide_.size() ) ) : std::u16string() )
    {
    }

    [[nodiscard]] bool    ok() const { return wide_.ok(); }
    [[nodiscard]] int     error() const { return wide_.error(); }
    // extended_ is empty (so wide_'s own spelling is used, byte-for-byte as before this fix) for every path short of
    // the threshold, already "\\?\"-prefixed, or not prefixable (relative/drive-relative/"."/".." — those still need
    // the machine's LongPathsEnabled policy, which this cannot substitute for).
    [[nodiscard]] LPCWSTR c_str() const
    {
        return reinterpret_cast<LPCWSTR>( extended_.empty() ? wide_.c_str() : extended_.c_str() );
    }

private:
    // The dispatch itself (which rebase, if any, applies to `path`) is pure logic, moved to os_win32_logic.h
    // (oswin::rebasedProgramPath) so it compiles and is tested on every platform; this keeps only the one thing
    // that IS a Windows fact — userTempDirectory() reads GetTempPathW().
    static std::string rebase( const char* path )
    {
        return path == nullptr ? std::string() : oswin::rebasedProgramPath( path, userTempDirectory() );
    }

    std::string     rebased_;
    oswin::WidePath wide_;
    std::u16string  extended_;
};

// The kernel handle behind a CRT descriptor; INVALID_HANDLE_VALUE for anything else (a socket or watcher descriptor from
// this file's own ranges, or a negative one). init_process installs a quiet invalid-parameter handler, so a stale CRT
// descriptor is EBADF here, as on POSIX, instead of the UCRT's default of ending the process.
HANDLE handleOf( int fd )
{
    if( fd < 0 || oswin::isSocketFd( fd ) || oswin::isDirwatchFd( fd ) )
    {
        return INVALID_HANDLE_VALUE;
    }
    return reinterpret_cast<HANDLE>( ::_get_osfhandle( fd ) );
}

int closeDirwatch( int fd );   // below, with the watcher

// ── the socket table ───────────────────────────────────────────────────────────────────────────────────────────
// A SOCKET is a kernel handle, not a CRT descriptor, and a POSIX call site keeps a socket in an int and closes it with
// close(). socket() and accept() therefore hand out descriptors from a range the CRT never uses (os_win32_logic.h),
// each naming a slot of this table, and the socket calls and close() look the SOCKET up — no narrowing of a SOCKET to
// an int (CodeRabbit 3946215403). Winsock starts on the first socket(), not in a static constructor of every process.
struct SocketTable
{
    std::mutex                                 mutex;
    std::array<SOCKET, oswin::kSocketFdCount> slots;
    SocketTable() { slots.fill( INVALID_SOCKET ); }
};

SocketTable& socketTable()
{
    static SocketTable table;
    return table;
}

// Winsock's lifetime: started by the first socket call, cleaned up at process exit by this object's destructor.
class WinsockSession
{
public:
    WinsockSession() noexcept
    {
        WSADATA data {};
        started_ = ::WSAStartup( MAKEWORD( 2, 2 ), &data ) == 0;
    }
    WinsockSession( const WinsockSession& ) = delete;
    WinsockSession& operator=( const WinsockSession& ) = delete;
    ~WinsockSession()
    {
        if( started_ )
        {
            ::WSACleanup();
        }
    }
    [[nodiscard]] bool started() const noexcept { return started_; }

private:
    bool started_ = false;
};

bool winsockStarted()
{
    static const WinsockSession session;
    return session.started();
}

int failWsa()
{
    return failWin32( static_cast<DWORD>( ::WSAGetLastError() ) );
}

int adoptSocket( UniqueSocket s )
{
    SocketTable&                      table = socketTable();
    const std::lock_guard<std::mutex> lock( table.mutex );
    for( int slot = 0; slot < oswin::kSocketFdCount; ++slot )
    {
        if( table.slots[ static_cast<std::size_t>( slot ) ] == INVALID_SOCKET )
        {
            table.slots[ static_cast<std::size_t>( slot ) ] = s.release();
            return oswin::kSocketFdBase + slot;
        }
    }
    return fail( EMFILE );   // `s` closes the socket that found no slot
}

SOCKET socketOf( int fd )
{
    if( !oswin::isSocketFd( fd ) )
    {
        return INVALID_SOCKET;
    }
    SocketTable&                      table = socketTable();
    const std::lock_guard<std::mutex> lock( table.mutex );
    return table.slots[ static_cast<std::size_t>( fd - oswin::kSocketFdBase ) ];
}

int closeSocket( int fd )
{
    SOCKET s = INVALID_SOCKET;
    {
        SocketTable&                      table = socketTable();
        const std::lock_guard<std::mutex> lock( table.mutex );
        std::swap( s, table.slots[ static_cast<std::size_t>( fd - oswin::kSocketFdBase ) ] );
    }
    if( s == INVALID_SOCKET )
    {
        return fail( EBADF );
    }
    return ::closesocket( s ) == 0 ? 0 : failWsa();
}

// ── stat ────────────────────────────────────────────────────────────────────────────────────────────────────────
// What a stat reports, gathered from one handle or one by-name query.
struct Facts
{
    DWORD         fileType    = FILE_TYPE_DISK;
    DWORD         attributes  = 0;
    DWORD         reparseTag  = 0;
    DWORD         links       = 1;
    std::uint64_t volume      = 0;
    std::uint64_t fileId      = 0;
    std::int64_t  size        = 0;
    std::int64_t  writeTicks  = 0;
    std::int64_t  changeTicks = 0;
};

// stat and fstat never read the owner (it costs a security-descriptor query per call); their st_uid is this value,
// which no getuid() returns, so an ownership test over stat fails closed. lstat reads the owner.
constexpr uid_t kOwnerNotRead = static_cast<uid_t>( -2 );

// Three queries at most: GetFileType, then for a disk file BY_HANDLE_FILE_INFORMATION (volume serial, 64-bit file
// index, size, links, attributes) and FILE_BASIC_INFO (the change time POSIX calls ctime), plus the reparse tag only
// when the attributes say there is one.
bool factsFromHandle( HANDLE handle, Facts& facts )
{
    ::SetLastError( NO_ERROR );
    facts.fileType = ::GetFileType( handle );
    if( facts.fileType == FILE_TYPE_UNKNOWN && ::GetLastError() != NO_ERROR )
    {
        return false;
    }
    if( facts.fileType != FILE_TYPE_DISK )
    {
        return true;   // a pipe or a character device: its type is the whole answer
    }
    BY_HANDLE_FILE_INFORMATION information {};
    FILE_BASIC_INFO            basic {};
    if( !::GetFileInformationByHandle( handle, &information ) || !::GetFileInformationByHandleEx( handle, FileBasicInfo, &basic, sizeof( basic ) ) )
    {
        return false;
    }
    facts.attributes  = information.dwFileAttributes;
    facts.links       = information.nNumberOfLinks;
    facts.volume      = information.dwVolumeSerialNumber;
    facts.fileId      = ( std::uint64_t( information.nFileIndexHigh ) << 32 ) | information.nFileIndexLow;
    facts.size        = static_cast<std::int64_t>( ( std::uint64_t( information.nFileSizeHigh ) << 32 ) | information.nFileSizeLow );
    facts.writeTicks  = basic.LastWriteTime.QuadPart;
    facts.changeTicks = basic.ChangeTime.QuadPart;
    if( ( facts.attributes & FILE_ATTRIBUTE_REPARSE_POINT ) != 0 )
    {
        FILE_ATTRIBUTE_TAG_INFO tag {};
        if( ::GetFileInformationByHandleEx( handle, FileAttributeTagInfo, &tag, sizeof( tag ) ) )
        {
            facts.reparseTag = tag.ReparseTag;
        }
    }
    return true;
}

void fillStat( const Facts& facts, bool followed, stat_t* st )
{
    *st          = stat_t{};
    st->st_mode  = oswin::modeTypeBits( facts.fileType, facts.attributes, facts.reparseTag, followed ) | oswin::modePermissionBits( facts.attributes );
    st->st_dev   = facts.volume;
    st->st_ino   = facts.fileId;
    st->st_nlink = facts.links;
    st->st_uid   = kOwnerNotRead;
    st->st_size  = S_ISDIR( st->st_mode ) ? 0 : facts.size;
    if( facts.fileType == FILE_TYPE_DISK )
    {
        const oswin::UnixTime written = oswin::unixTimeFromFiletime( facts.writeTicks );
        const oswin::UnixTime changed = oswin::unixTimeFromFiletime( facts.changeTicks );
        st->st_mtime = static_cast<std::time_t>( written.seconds );
        st->st_ctime = static_cast<std::time_t>( changed.seconds );
        st->st_mtim  = ::timespec{ static_cast<std::time_t>( written.seconds ), written.nanoseconds };
        st->st_ctim  = ::timespec{ static_cast<std::time_t>( changed.seconds ), changed.nanoseconds };
    }
}

// The by-name stat, where the system has it (GetFileInformationByName, FileStatBasicByNameInfo: Windows 11 24H2 /
// Server 2025): one call and no handle, which is what the crawl's warm-run stat of every file wants. Adapted from
// libuv's fs__stat_path (src/win/fs.c at e15526ade343bdfc7cdaaeb0a51b9bba656533ce; MIT, notice in THIRD_PARTY.md):
// the structure layout is declared here under this file's own name so an older SDK builds, the function is looked up
// at run time, and — as libuv does — a reparse point always takes the handle path, which follows or classifies it.
struct StatBasicByName
{
    LARGE_INTEGER fileId;
    LARGE_INTEGER creationTime;
    LARGE_INTEGER lastAccessTime;
    LARGE_INTEGER lastWriteTime;
    LARGE_INTEGER changeTime;
    LARGE_INTEGER allocationSize;
    LARGE_INTEGER endOfFile;
    ULONG         fileAttributes;
    ULONG         reparseTag;
    ULONG         numberOfLinks;
    ULONG         deviceType;
    ULONG         deviceCharacteristics;
    ULONG         reserved;
    LARGE_INTEGER volumeSerialNumber;
    BYTE          fileId128[ 16 ];
};
using GetFileInformationByNameFn = BOOL( WINAPI* )( LPCWSTR, int, void*, ULONG );
constexpr int   kFileStatBasicByNameInfo = 3;
constexpr ULONG kFileDeviceNull          = 0x15;

GetFileInformationByNameFn getFileInformationByName()
{
    static const GetFileInformationByNameFn function = []() -> GetFileInformationByNameFn
    {
        for( const wchar_t* module : { L"kernelbase.dll", L"api-ms-win-core-file-l2-1-4.dll" } )
        {
            if( const HMODULE handle = ::GetModuleHandleW( module ) )
            {
                if( const FARPROC address = ::GetProcAddress( handle, "GetFileInformationByName" ) )
                {
                    return reinterpret_cast<GetFileInformationByNameFn>( reinterpret_cast<void*>( address ) );
                }
            }
        }
        return nullptr;
    }();
    return function;
}

enum class ByName : std::uint8_t
{
    Answered,
    Failed,     // errno set: the path does not exist, no retry would help
    UseHandle,
};

ByName statByName( LPCWSTR path, bool noFollow, stat_t* st )
{
    const GetFileInformationByNameFn byName = getFileInformationByName();
    if( byName == nullptr )
    {
        return ByName::UseHandle;
    }
    StatBasicByName information {};
    if( !byName( path, kFileStatBasicByNameInfo, &information, sizeof( information ) ) )
    {
        const DWORD error = ::GetLastError();
        if( error == ERROR_FILE_NOT_FOUND || error == ERROR_PATH_NOT_FOUND || error == ERROR_NOT_READY || error == ERROR_BAD_NET_NAME )
        {
            (void)failWin32( error );
            return ByName::Failed;
        }
        return ByName::UseHandle;
    }
    if( ( information.fileAttributes & FILE_ATTRIBUTE_REPARSE_POINT ) != 0 )
    {
        return ByName::UseHandle;
    }
    Facts facts;
    facts.fileType    = information.deviceType == kFileDeviceNull ? FILE_TYPE_CHAR : FILE_TYPE_DISK;
    facts.attributes  = information.fileAttributes;
    facts.links       = information.numberOfLinks;
    facts.volume      = static_cast<std::uint64_t>( information.volumeSerialNumber.QuadPart );
    facts.fileId      = static_cast<std::uint64_t>( information.fileId.QuadPart );
    facts.size        = information.endOfFile.QuadPart;
    facts.writeTicks  = information.lastWriteTime.QuadPart;
    facts.changeTicks = information.changeTime.QuadPart;
    fillStat( facts, !noFollow, st );
    return ByName::Answered;
}

int statByHandle( LPCWSTR path, bool noFollow, stat_t* st )
{
    const UniqueHandle handle( ::CreateFileW( path, FILE_READ_ATTRIBUTES, kShareAll, nullptr, OPEN_EXISTING,
                                              FILE_FLAG_BACKUP_SEMANTICS | ( noFollow ? FILE_FLAG_OPEN_REPARSE_POINT : 0 ), nullptr ) );
    if( !handle.valid() )
    {
        return failLastError();
    }
    Facts facts;
    if( !factsFromHandle( handle.get(), facts ) )
    {
        return failLastError();
    }
    fillStat( facts, !noFollow, st );
    return 0;
}

int statPath( const char* path, bool noFollow, stat_t* st )
{
    const NativePath native( path );
    if( !native.ok() )
    {
        return fail( native.error() );
    }
    switch( statByName( native.c_str(), noFollow, st ) )
    {
        case ByName::Answered:  return 0;
        case ByName::Failed:    return -1;
        case ByName::UseHandle: break;
    }
    return statByHandle( native.c_str(), noFollow, st );
}

// ── identity: the process's user, its uid, and who owns a file ─────────────────────────────────────────────────────
// lstat's st_uid is getuid() exactly when the file's owner is this user — or BUILTIN\Administrators while this token
// holds that group, the owner Windows gives an object an elevated administrator creates — and kOwnerSomeoneElse
// otherwise. getuid() is the relative identifier of the user's SID (1001 for a first local account), stable across runs.
constexpr uid_t kOwnerSomeoneElse = static_cast<uid_t>( -3 );

struct TokenIdentity
{
    std::vector<BYTE> userSid;
    uid_t             uid               = 1000;
    bool              hasAdministrators = false;
};

const TokenIdentity& tokenIdentity()
{
    static const TokenIdentity identity = []
    {
        TokenIdentity out;
        HANDLE        rawToken = nullptr;
        if( ::OpenProcessToken( ::GetCurrentProcess(), TOKEN_QUERY, &rawToken ) )
        {
            const UniqueHandle token( rawToken );
            DWORD              bytes = 0;
            (void)::GetTokenInformation( token.get(), TokenUser, nullptr, 0, &bytes );
            std::vector<BYTE> buffer( bytes );
            if( bytes != 0 && ::GetTokenInformation( token.get(), TokenUser, buffer.data(), bytes, &bytes ) )
            {
                const PSID sid = reinterpret_cast<TOKEN_USER*>( buffer.data() )->User.Sid;
                out.userSid.assign( static_cast<BYTE*>( sid ), static_cast<BYTE*>( sid ) + ::GetLengthSid( sid ) );
                const UCHAR subAuthorityCount = *::GetSidSubAuthorityCount( sid );
                if( subAuthorityCount > 0 )
                {
                    out.uid = static_cast<uid_t>( *::GetSidSubAuthority( sid, subAuthorityCount - 1U ) );
                }
            }
        }
        BYTE  administrators[ SECURITY_MAX_SID_SIZE ];
        DWORD administratorsBytes = sizeof( administrators );
        BOOL  member              = FALSE;
        if( ::CreateWellKnownSid( WinBuiltinAdministratorsSid, nullptr, administrators, &administratorsBytes )
            && ::CheckTokenMembership( nullptr, administrators, &member ) )
        {
            out.hasAdministrators = member != FALSE;
        }
        if( out.uid == kOwnerNotRead || out.uid == kOwnerSomeoneElse )
        {
            out.uid = 1000;   // never one of the two sentinels an ownership test compares against
        }
        return out;
    }();
    return identity;
}

bool isThisUser( PSID sid )
{
    const TokenIdentity& identity = tokenIdentity();
    return !identity.userSid.empty() && ::EqualSid( sid, static_cast<PSID>( const_cast<BYTE*>( identity.userSid.data() ) ) );
}

bool ownedByThisUser( PSID owner )
{
    return owner != nullptr && ( isThisUser( owner ) || ( tokenIdentity().hasAdministrators && ::IsWellKnownSid( owner, WinBuiltinAdministratorsSid ) ) );
}

// An ACL entry POSIX mode 0700 allows: this user, the owner (OWNER RIGHTS, CREATOR OWNER), Administrators or SYSTEM —
// the principals that can reach a POSIX user's 0700 directory too (root).
bool isOwnerClassSid( PSID sid )
{
    return isThisUser( sid ) || ::IsWellKnownSid( sid, WinCreatorOwnerRightsSid ) || ::IsWellKnownSid( sid, WinCreatorOwnerSid )
        || ::IsWellKnownSid( sid, WinBuiltinAdministratorsSid ) || ::IsWellKnownSid( sid, WinLocalSystemSid );
}

// Owner and permission bits from the handle's security descriptor: st_uid as above; mode 0700 when the DACL is
// PROTECTED (inherits nothing) and every allow entry names an owner-class principal, else the attribute-derived bits
// stat reports. A descriptor that cannot be read leaves st as it was (st_uid = kOwnerNotRead: fails closed).
void readOwnerAndMode( HANDLE handle, stat_t* st )
{
    PSID                 owner      = nullptr;
    PACL                 dacl       = nullptr;
    PSECURITY_DESCRIPTOR rawDescriptor = nullptr;
    if( ::GetSecurityInfo( handle, SE_FILE_OBJECT, OWNER_SECURITY_INFORMATION | DACL_SECURITY_INFORMATION, &owner, nullptr, &dacl, nullptr, &rawDescriptor ) != ERROR_SUCCESS )
    {
        return;
    }
    const UniqueLocal          descriptorOwner( rawDescriptor );
    const PSECURITY_DESCRIPTOR descriptor = rawDescriptor;
    st->st_uid = ownedByThisUser( owner ) ? tokenIdentity().uid : kOwnerSomeoneElse;
    WORD  control  = 0;
    DWORD revision = 0;
    bool  ownerOnly = dacl != nullptr && ::GetSecurityDescriptorControl( descriptor, &control, &revision ) && ( control & SE_DACL_PROTECTED ) != 0;
    for( DWORD aceIndex = 0; ownerOnly && aceIndex < dacl->AceCount; ++aceIndex )
    {
        LPVOID ace = nullptr;
        if( !::GetAce( dacl, aceIndex, &ace ) )
        {
            ownerOnly = false;
            break;
        }
        const BYTE aceType = static_cast<ACE_HEADER*>( ace )->AceType;
        if( aceType == ACCESS_DENIED_ACE_TYPE )
        {
            continue;
        }
        ownerOnly = aceType == ACCESS_ALLOWED_ACE_TYPE && isOwnerClassSid( reinterpret_cast<PSID>( &static_cast<ACCESS_ALLOWED_ACE*>( ace )->SidStart ) );
    }
    if( ownerOnly )
    {
        st->st_mode = ( st->st_mode & ~static_cast<mode_t>( 0777 ) ) | 0700;
    }
}

// The file identity a no-follow reopen must match.
bool sameFile( HANDLE a, HANDLE b )
{
    BY_HANDLE_FILE_INFORMATION x {}, y {};
    return ::GetFileInformationByHandle( a, &x ) && ::GetFileInformationByHandle( b, &y ) && x.dwVolumeSerialNumber == y.dwVolumeSerialNumber
        && x.nFileIndexHigh == y.nFileIndexHigh && x.nFileIndexLow == y.nFileIndexLow;
}

}   // namespace

// ── descriptors and files ──────────────────────────────────────────────────────────────────────────────────
//
// open: CreateFileW, then _open_osfhandle, so the result is a CRT descriptor read/write/close/fstat accept. The flag
// mapping follows libuv's fs__open (src/win/fs.c at e15526ad; MIT). Every handle shares read, write AND delete, so a
// file one descriptor holds open can still be renamed over or unlinked, as on POSIX; no handle is inheritable.
//   O_NOFOLLOW — the final component is opened with FILE_FLAG_OPEN_REPARSE_POINT and classified by its reparse tag
//     (os_win32_logic.h): a symlink or junction is ELOOP; any other reparse point (a OneDrive placeholder) is reopened
//     normally and must be the SAME file (volume serial and file index), or it is ELOOP too — a link swapped in between
//     the two opens is refused, never followed. Intermediate components are traversed, as POSIX O_NOFOLLOW does.
//     O_TRUNC with O_NOFOLLOW truncates only after that check, so a link is never truncated through.
//   O_NONBLOCK — nothing to do at open: CreateFileW does not block on a pipe or device the way a POSIX FIFO open does,
//     and every caller that passes it refuses a non-regular file by fstat before reading.
//   O_CLOEXEC — every handle here is non-inheritable already.
//   O_DIRECTORY — the path must name a directory (ENOTDIR otherwise). A directory descriptor is the one handle here that
//     does NOT share delete: while it is open the directory cannot be renamed or removed, so openat's name, joined onto
//     the directory's final path, still names an entry of THAT directory (POSIX anchors openat at the descriptor; this is
//     the Windows way to hold the same anchor without NtCreateFile's RootDirectory).
namespace
{
int openWide( LPCWSTR path, int flags, mode_t mode )
{
    DWORD access = 0;
    switch( flags & ( O_RDONLY | O_WRONLY | O_RDWR ) )
    {
        case O_RDONLY: access = FILE_GENERIC_READ; break;
        case O_WRONLY: access = FILE_GENERIC_WRITE; break;
        case O_RDWR:   access = FILE_GENERIC_READ | FILE_GENERIC_WRITE; break;
        default:       return fail( EINVAL );
    }
    if( ( flags & O_APPEND ) != 0 )
    {
        access &= ~FILE_WRITE_DATA;
        access |= FILE_APPEND_DATA;
    }
    const bool noFollow = ( flags & O_NOFOLLOW ) != 0;
    const bool truncate = ( flags & O_TRUNC ) != 0;
    const bool truncateAfterCheck = truncate && noFollow;
    DWORD disposition = OPEN_EXISTING;
    if( ( flags & O_CREAT ) != 0 )
    {
        disposition = ( flags & O_EXCL ) != 0 ? CREATE_NEW : ( truncate && !noFollow ) ? CREATE_ALWAYS : OPEN_ALWAYS;
    }
    else if( truncate && !noFollow )
    {
        disposition = TRUNCATE_EXISTING;
    }
    DWORD attributes = FILE_ATTRIBUTE_NORMAL;
    if( ( flags & O_CREAT ) != 0 && ( mode & 0200 ) == 0 )
    {
        attributes = FILE_ATTRIBUTE_READONLY;   // POSIX: a file created without the owner write bit
    }
    const bool  directory = ( flags & O_DIRECTORY ) != 0;
    const DWORD share     = directory ? ( FILE_SHARE_READ | FILE_SHARE_WRITE ) : kShareAll;
    const DWORD fileFlags = FILE_FLAG_BACKUP_SEMANTICS | ( noFollow ? FILE_FLAG_OPEN_REPARSE_POINT : 0 );
    UniqueHandle handle( ::CreateFileW( path, access, share, nullptr, disposition, attributes | fileFlags, nullptr ) );
    if( !handle.valid() )
    {
        return failLastError();
    }
    if( noFollow )
    {
        FILE_ATTRIBUTE_TAG_INFO tag {};
        if( !::GetFileInformationByHandleEx( handle.get(), FileAttributeTagInfo, &tag, sizeof( tag ) ) )
        {
            return failLastError();
        }
        switch( oswin::classifyFinalComponent( tag.FileAttributes, tag.ReparseTag ) )
        {
            case oswin::FinalComponent::Plain:
                break;
            case oswin::FinalComponent::Link:
                return fail( ELOOP );
            case oswin::FinalComponent::OtherReparse:
            {
                UniqueHandle content( ::CreateFileW( path, access, share, nullptr, OPEN_EXISTING, FILE_FLAG_BACKUP_SEMANTICS, nullptr ) );
                if( !content.valid() || !sameFile( handle.get(), content.get() ) )
                {
                    return fail( ELOOP );
                }
                handle = std::move( content );
                break;
            }
        }
        if( truncateAfterCheck )
        {
            FILE_END_OF_FILE_INFO end {};
            if( !::SetFileInformationByHandle( handle.get(), FileEndOfFileInfo, &end, sizeof( end ) ) )
            {
                return failLastError();
            }
        }
    }
    if( directory )
    {
        FILE_BASIC_INFO basic {};
        if( !::GetFileInformationByHandleEx( handle.get(), FileBasicInfo, &basic, sizeof( basic ) ) )
        {
            return failLastError();
        }
        if( ( basic.FileAttributes & FILE_ATTRIBUTE_DIRECTORY ) == 0 )
        {
            return fail( ENOTDIR );
        }
    }
    int crtFlags = _O_BINARY;
    if( ( flags & ( O_RDONLY | O_WRONLY | O_RDWR ) ) == O_RDONLY )
    {
        crtFlags |= _O_RDONLY;
    }
    if( ( flags & O_APPEND ) != 0 )
    {
        crtFlags |= _O_APPEND;
    }
    const int fd = ::_open_osfhandle( reinterpret_cast<intptr_t>( handle.get() ), crtFlags );
    if( fd < 0 )
    {
        return -1;   // errno set by the CRT; `handle` still owns the handle and closes it
    }
    (void)handle.release();   // the descriptor owns it now
    return fd;
}

int openImpl( const char* path, int flags, mode_t mode )
{
    const NativePath native( path );
    if( !native.ok() )
    {
        return fail( native.error() );
    }
    return openWide( native.c_str(), flags, mode );
}
}   // namespace

int open( const char* path, int flags )                  { return openImpl( path, flags, 0666 ); }
int open( const char* path, int flags, mode_t mode )     { return openImpl( path, flags, mode ); }

// openat: ONE entry name relative to an O_DIRECTORY descriptor (the only shape its caller, pathguard.h's no-follow
// descriptor chain, passes). The name is joined onto the directory's final path — which cannot change while that
// descriptor is open (see O_DIRECTORY above) — and opened with open()'s own flag handling, so O_NOFOLLOW still judges
// the entry itself. A name that is empty, "." or "..", or that holds a separator or a ':' (a drive or an alternate data
// stream) is not one entry of that directory and is refused.
//
// RESIDUAL (owner call, kept for this release): the join is handle-anchored, not NtCreateFile( RootDirectory=handle,
// FILE_OPEN_REPARSE_POINT ) — the real openat. GetFinalPathNameByHandleW is re-read on every call, so a link swapped
// in ABOVE the directory between calls is bypassed (stronger than the POSIX chain), and O_NOFOLLOW still judges the
// final entry itself once openWide reopens it. What handle-anchoring does NOT close: `joined` is a fresh STRING —
// directory's final path + '\' + name — and openWide's CreateFileW walks that whole string again from the root, not
// from the directory handle. In the narrow window between GetFinalPathNameByHandleW returning it and CreateFileW
// resolving it, an ancestor ABOVE the directory (not the directory itself, which cannot be renamed while its
// descriptor is open) could be replaced by a link/junction, and the walk would follow it — a race true handle-relative
// NtCreateFile( RootDirectory=... ) closes because it never re-parses a path string. Do NtCreateFile only if a
// contributor actually hits this or the no-drive-letter case (LOW-6); it needs the whole openWide flag mapping
// reimplemented on the NT API and cannot be reviewed without a Windows machine.
int openat( int dirFd, const char* path, int flags )
{
    const HANDLE directory = handleOf( dirFd );
    if( directory == INVALID_HANDLE_VALUE )
    {
        return fail( EBADF );
    }
    const std::string_view name = path != nullptr ? std::string_view( path ) : std::string_view();
    if( name.empty() || name == "." || name == ".." || name.find_first_of( "/\\:" ) != std::string_view::npos )
    {
        return fail( ENOENT );
    }
    bool                 ok       = false;
    const std::u16string wideName = utf16Of( name, ok );
    if( !ok )
    {
        return fail( EILSEQ );
    }
    std::vector<wchar_t> joined( MAX_PATH );
    for( ;; )
    {
        const DWORD units = ::GetFinalPathNameByHandleW( directory, joined.data(), static_cast<DWORD>( joined.size() ), FILE_NAME_NORMALIZED | VOLUME_NAME_DOS );
        if( units == 0 )
        {
            return failLastError();
        }
        if( units < joined.size() )
        {
            joined.resize( units );   // "\\?\C:\dir" — the extended-length form, so no MAX_PATH limit applies below
            break;
        }
        joined.resize( static_cast<std::size_t>( units ) + 1 );
    }
    joined.push_back( L'\\' );
    joined.insert( joined.end(), wideName.begin(), wideName.end() );
    joined.push_back( L'\0' );
    return openWide( joined.data(), flags, 0666 );
}

int close( int fd )
{
    if( oswin::isSocketFd( fd ) )
    {
        return closeSocket( fd );
    }
    if( oswin::isDirwatchFd( fd ) )
    {
        return closeDirwatch( fd );
    }
    return ::_close( fd );
}

ssize_t read( int fd, void* buf, std::size_t count )
{
    return ::_read( fd, buf, static_cast<unsigned>( count > INT_MAX ? INT_MAX : count ) );
}

ssize_t write( int fd, const void* buf, std::size_t count )
{
    return ::_write( fd, buf, static_cast<unsigned>( count > INT_MAX ? INT_MAX : count ) );
}

// pread: ReadFile at an explicit OVERLAPPED offset. Unlike POSIX, on a synchronous handle this also moves the
// descriptor's file position (the only caller reads a cache blob by offset and never by position).
ssize_t pread( int fd, void* buf, std::size_t count, off_t offset )
{
    const HANDLE handle = handleOf( fd );
    if( handle == INVALID_HANDLE_VALUE )
    {
        return fail( EBADF );
    }
    OVERLAPPED position {};
    position.Offset     = static_cast<DWORD>( static_cast<std::uint64_t>( offset ) & 0xFFFFFFFFu );
    position.OffsetHigh = static_cast<DWORD>( static_cast<std::uint64_t>( offset ) >> 32 );
    DWORD bytesRead = 0;
    if( !::ReadFile( handle, buf, static_cast<DWORD>( count > INT_MAX ? INT_MAX : count ), &bytesRead, &position ) )
    {
        const DWORD error = ::GetLastError();
        return error == ERROR_HANDLE_EOF ? 0 : failWin32( error );
    }
    return static_cast<ssize_t>( bytesRead );
}

int fstat( int fd, stat_t* st )
{
    const HANDLE handle = handleOf( fd );
    if( handle == INVALID_HANDLE_VALUE )
    {
        return fail( EBADF );
    }
    Facts facts;
    if( !factsFromHandle( handle, facts ) )
    {
        return failLastError();
    }
    fillStat( facts, true, st );
    return 0;
}

int stat( const char* path, stat_t* st )  { return statPath( path, false, st ); }
// lstat: the entry itself (a symlink or junction reports S_IFLNK), plus its owner and ACL-derived mode (see
// readOwnerAndMode) — the one stat that pays for a security-descriptor read, because the cache-directory check
// (`S_ISDIR && st_uid == getuid() && ( st_mode & 0777 ) == 0700`) is the caller that needs them.
int lstat( const char* path, stat_t* st )
{
    const NativePath native( path );
    if( !native.ok() )
    {
        return fail( native.error() );
    }
    constexpr DWORD kNoFollow       = FILE_FLAG_BACKUP_SEMANTICS | FILE_FLAG_OPEN_REPARSE_POINT;
    bool            canReadSecurity = true;
    UniqueHandle    handle( ::CreateFileW( native.c_str(), FILE_READ_ATTRIBUTES | READ_CONTROL, kShareAll, nullptr, OPEN_EXISTING, kNoFollow, nullptr ) );
    if( !handle.valid() && ::GetLastError() == ERROR_ACCESS_DENIED )
    {
        canReadSecurity = false;
        handle.reset( ::CreateFileW( native.c_str(), FILE_READ_ATTRIBUTES, kShareAll, nullptr, OPEN_EXISTING, kNoFollow, nullptr ) );
    }
    if( !handle.valid() )
    {
        return failLastError();
    }
    Facts facts;
    if( !factsFromHandle( handle.get(), facts ) )
    {
        return failLastError();
    }
    fillStat( facts, false, st );
    if( canReadSecurity && facts.fileType == FILE_TYPE_DISK )
    {
        readOwnerAndMode( handle.get(), st );
    }
    return 0;
}

// fcntl: a CRT descriptor has no status flags to read or set; F_GETFL answers 0 and F_SETFL accepts and ignores (the
// only caller clears O_NONBLOCK, which a Windows handle never had).
int fcntl( int fd, int cmd )           { return fcntl( fd, cmd, 0 ); }
int fcntl( int fd, int cmd, int )
{
    if( handleOf( fd ) == INVALID_HANDLE_VALUE )
    {
        return fail( EBADF );
    }
    return cmd == F_GETFL || cmd == F_SETFL ? 0 : fail( EINVAL );
}

int dup( int fd )           { return ::_dup( fd ); }
int dup2( int fd, int fd2 ) { return ::_dup2( fd, fd2 ); }

int ftruncate( int fd, off_t length )
{
    const errno_t error = ::_chsize_s( fd, length );
    return error == 0 ? 0 : fail( error );
}

int fsync( int fd ) { return ::_commit( fd ); }

// fchmod: NTFS has no POSIX mode bits. The owner write bit maps to the read-only attribute; everything else is ignored.
int fchmod( int fd, mode_t mode )
{
    const HANDLE handle = handleOf( fd );
    FILE_BASIC_INFO basic {};
    if( handle == INVALID_HANDLE_VALUE || !::GetFileInformationByHandleEx( handle, FileBasicInfo, &basic, sizeof( basic ) ) )
    {
        return handle == INVALID_HANDLE_VALUE ? fail( EBADF ) : failLastError();
    }
    const DWORD wanted = ( mode & 0200 ) != 0 ? ( basic.FileAttributes & ~FILE_ATTRIBUTE_READONLY ) : ( basic.FileAttributes | FILE_ATTRIBUTE_READONLY );
    if( wanted == basic.FileAttributes )
    {
        return 0;
    }
    basic.FileAttributes = wanted == 0 ? FILE_ATTRIBUTE_NORMAL : wanted;
    basic.CreationTime.QuadPart = basic.LastAccessTime.QuadPart = basic.LastWriteTime.QuadPart = basic.ChangeTime.QuadPart = 0;   // 0 = unchanged
    return ::SetFileInformationByHandle( handle, FileBasicInfo, &basic, sizeof( basic ) ) ? 0 : failLastError();
}

// flock: LockFileEx over the whole range — PR #44's rw_flock (proven by mcpeditracecheck's race trials on lennix1337's
// machine), with its errors through the errno table: a held lock is EWOULDBLOCK under LOCK_NB, and unlocking an
// unlocked descriptor succeeds, as POSIX's does. The lock is mandatory for the locked range on Windows, which is
// harmless for what callers lock: dedicated .lock files nobody reads.
int flock( int fd, int operation )
{
    const HANDLE handle = handleOf( fd );
    if( handle == INVALID_HANDLE_VALUE )
    {
        return fail( EBADF );
    }
    OVERLAPPED wholeFile {};
    if( ( operation & LOCK_UN ) != 0 )
    {
        if( ::UnlockFileEx( handle, 0, MAXDWORD, MAXDWORD, &wholeFile ) )
        {
            return 0;
        }
        const DWORD error = ::GetLastError();
        return error == ERROR_NOT_LOCKED ? 0 : failWin32( error );
    }
    const DWORD flags = ( ( operation & LOCK_EX ) != 0 ? LOCKFILE_EXCLUSIVE_LOCK : 0 ) | ( ( operation & LOCK_NB ) != 0 ? LOCKFILE_FAIL_IMMEDIATELY : 0 );
    return ::LockFileEx( handle, flags, 0, MAXDWORD, MAXDWORD, &wholeFile ) ? 0 : failLastError();
}

// pipe: the CRT's anonymous pipe, both ends non-inheritable (spawn_sh hands the write end to its child explicitly).
int pipe( int fds[ 2 ] ) { return ::_pipe( fds, 65536, _O_BINARY | _O_NOINHERIT ); }

// poll: pipes only — the one caller waits on a spawn_sh pipe. POLLIN when bytes are waiting, POLLHUP once every writer
// has closed (the read that follows returns 0, POSIX's EOF), POLLNVAL for a descriptor with no handle. There is no
// readiness wait for an anonymous pipe on Windows, so the wait is a PeekNamedPipe loop at 1 ms. nullptr/0 fds sleeps.
int poll( pollfd* fds, nfds_t count, int timeoutMs )
{
    const ULONGLONG start = ::GetTickCount64();
    for( ;; )
    {
        int ready = 0;
        for( nfds_t i = 0; fds != nullptr && i < count; ++i )
        {
            fds[ i ].revents   = 0;
            const HANDLE handle = handleOf( fds[ i ].fd );
            DWORD        waiting = 0;
            if( handle == INVALID_HANDLE_VALUE )
            {
                fds[ i ].revents = 0x0020;   // POLLNVAL
            }
            else if( ::PeekNamedPipe( handle, nullptr, 0, nullptr, &waiting, nullptr ) )
            {
                fds[ i ].revents = waiting > 0 ? static_cast<short>( fds[ i ].events & POLLIN ) : 0;
            }
            else
            {
                fds[ i ].revents = 0x0010;   // POLLHUP: ERROR_BROKEN_PIPE, or any error a read would report
            }
            ready += fds[ i ].revents != 0 ? 1 : 0;
        }
        const ULONGLONG elapsed = ::GetTickCount64() - start;
        if( ready > 0 || ( timeoutMs >= 0 && elapsed >= static_cast<ULONGLONG>( timeoutMs ) ) )
        {
            return ready;
        }
        ::Sleep( fds == nullptr || count == 0 ? static_cast<DWORD>( timeoutMs < 0 ? INFINITE : static_cast<ULONGLONG>( timeoutMs ) - elapsed ) : 1 );
    }
}

// ── streams over descriptors and memory ────────────────────────────────────────────────────────────────────
std::FILE* fdopen( int fd, const char* mode ) { return ::_fdopen( fd, mode ); }
int        fileno( std::FILE* stream )        { return ::_fileno( stream ); }

// getline: POSIX's contract (the line including its '\n', NUL-terminated, the buffer grown with realloc; -1 at EOF
// before any byte), read under one stream lock with _getc_nolock — never a locked fgetc per byte. LOW-4: while
// *line is NULL, POSIX ignores whatever *capacity holds (a caller need not zero it first) — nextGetlineCapacity
// applies that rule instead of doubling unread caller garbage.
ssize_t getline( char** line, std::size_t* capacity, std::FILE* stream )
{
    if( line == nullptr || capacity == nullptr || stream == nullptr )
    {
        return fail( EINVAL );
    }
    const StreamLock lock( stream );
    std::size_t      used   = 0;
    ssize_t     result = -1;
    for( ;; )
    {
        const int c = ::_getc_nolock( stream );
        if( c == EOF )
        {
            result = used == 0 ? -1 : static_cast<ssize_t>( used );
            break;
        }
        if( *line == nullptr || used + 2 > *capacity )
        {
            const std::size_t grown = oswin::nextGetlineCapacity( *line == nullptr, *capacity );
            char* const       next  = static_cast<char*>( std::realloc( *line, grown ) );
            if( next == nullptr )
            {
                errno = ENOMEM;
                break;
            }
            *line     = next;
            *capacity = grown;
        }
        ( *line )[ used++ ] = static_cast<char>( c );
        ( *line )[ used ]   = '\0';
        if( c == '\n' )
        {
            result = static_cast<ssize_t>( used );
            break;
        }
    }
    return result;
}

// open_memstream: the UCRT has no memory stream, so the stream is a delete-on-close temporary file (kept in the
// system cache by FILE_ATTRIBUTE_TEMPORARY) and *buffer / *size are published when the caller calls os::fflush or
// os::fclose on it — exactly the two moments POSIX publishes them. The registry below is consulted ONLY by those two
// calls, never by std::fflush / std::fclose, so no other stream pays for it. Carried from PR #44's rw_open_memstream
// (proven by the MCP verb gates on lennix1337's machine), changed to wide temp paths and a registry keyed by stream.
namespace
{
struct MemoryStream
{
    std::FILE*   stream;
    char**       buffer;
    std::size_t* size;
};

std::mutex& memoryStreamMutex()
{
    static std::mutex mutex;
    return mutex;
}

std::vector<MemoryStream>& memoryStreams()
{
    static std::vector<MemoryStream> streams;
    return streams;
}

// Copy the stream's whole content into a fresh *buffer (NUL-terminated) and *size, leaving the position where it was.
int publishMemoryStream( const MemoryStream& record )
{
    const std::int64_t position = ::_ftelli64( record.stream );
    if( ::_fseeki64( record.stream, 0, SEEK_END ) != 0 )
    {
        return EOF;
    }
    const std::int64_t length = ::_ftelli64( record.stream );
    if( length < 0 || ::_fseeki64( record.stream, 0, SEEK_SET ) != 0 )
    {
        return EOF;
    }
    char* const published = static_cast<char*>( std::realloc( *record.buffer, static_cast<std::size_t>( length ) + 1 ) );
    if( published == nullptr )
    {
        errno = ENOMEM;
        return EOF;
    }
    const std::size_t got = length > 0 ? std::fread( published, 1, static_cast<std::size_t>( length ), record.stream ) : 0;
    published[ got ] = '\0';
    *record.buffer   = published;
    *record.size     = got;
    return position >= 0 && ::_fseeki64( record.stream, position, SEEK_SET ) == 0 ? 0 : EOF;
}
}   // namespace

std::FILE* open_memstream( char** buffer, std::size_t* size )
{
    if( buffer == nullptr || size == nullptr )
    {
        errno = EINVAL;
        return nullptr;
    }
    CreatedTemporary temporary = createTemporary( "rwm", FILE_FLAG_DELETE_ON_CLOSE );   // gone when the stream closes
    if( !temporary.handle.valid() )
    {
        return nullptr;
    }
    UniqueFd fd( ::_open_osfhandle( reinterpret_cast<intptr_t>( temporary.handle.get() ), _O_RDWR | _O_BINARY ) );
    if( !fd.valid() )
    {
        return nullptr;
    }
    (void)temporary.handle.release();   // the descriptor owns it
    std::FILE* const stream = ::_fdopen( fd.get(), "w+b" );
    if( stream == nullptr )
    {
        return nullptr;
    }
    (void)fd.release();       // the stream owns it
    *buffer = static_cast<char*>( std::malloc( 1 ) );
    if( *buffer == nullptr )
    {
        std::fclose( stream );
        errno = ENOMEM;
        return nullptr;
    }
    ( *buffer )[ 0 ] = '\0';
    *size            = 0;
    const std::lock_guard<std::mutex> lock( memoryStreamMutex() );
    memoryStreams().push_back( MemoryStream{ stream, buffer, size } );
    return stream;
}

int fflush( std::FILE* stream )
{
    const int flushed = std::fflush( stream );
    if( flushed != 0 || stream == nullptr )
    {
        return flushed;
    }
    const std::lock_guard<std::mutex> lock( memoryStreamMutex() );
    for( const MemoryStream& record : memoryStreams() )
    {
        if( record.stream == stream )
        {
            return publishMemoryStream( record );
        }
    }
    return 0;
}

int fclose( std::FILE* stream )
{
    int published = 0;
    {
        const std::lock_guard<std::mutex> lock( memoryStreamMutex() );
        std::vector<MemoryStream>&        streams = memoryStreams();
        for( auto it = streams.begin(); it != streams.end(); ++it )
        {
            if( it->stream == stream )
            {
                published = std::fflush( stream ) == 0 ? publishMemoryStream( *it ) : EOF;
                streams.erase( it );
                break;
            }
        }
    }
    const int closed = std::fclose( stream );
    return published != 0 ? published : closed;
}

// ── paths ──────────────────────────────────────────────────────────────────────────────────────────────────
// unlink: DeleteFileW. POSIX removes a file whatever its mode bits, so a read-only file loses the attribute and the
// delete is retried once. With every handle opened FILE_SHARE_DELETE, a file another descriptor holds open is
// unlinked too (POSIX delete semantics are the NTFS default since Windows 10 1903).
int unlink( const char* path )
{
    const NativePath native( path );
    if( !native.ok() )
    {
        return fail( native.error() );
    }
    if( ::DeleteFileW( native.c_str() ) )
    {
        return 0;
    }
    const DWORD error      = ::GetLastError();
    const DWORD attributes = ::GetFileAttributesW( native.c_str() );
    if( error == ERROR_ACCESS_DENIED && attributes != INVALID_FILE_ATTRIBUTES && ( attributes & FILE_ATTRIBUTE_READONLY ) != 0
        && ( attributes & FILE_ATTRIBUTE_DIRECTORY ) == 0 && ::SetFileAttributesW( native.c_str(), attributes & ~FILE_ATTRIBUTE_READONLY ) )
    {
        if( ::DeleteFileW( native.c_str() ) )
        {
            return 0;
        }
        (void)::SetFileAttributesW( native.c_str(), attributes );
    }
    return failWin32( error );
}

// remove: POSIX's — unlink for a file, rmdir for a directory.
int remove( const char* path )
{
    const NativePath native( path );
    if( !native.ok() )
    {
        return fail( native.error() );
    }
    const DWORD attributes = ::GetFileAttributesW( native.c_str() );
    if( attributes != INVALID_FILE_ATTRIBUTES && ( attributes & FILE_ATTRIBUTE_DIRECTORY ) != 0 && ( attributes & FILE_ATTRIBUTE_REPARSE_POINT ) == 0 )
    {
        return ::RemoveDirectoryW( native.c_str() ) ? 0 : failLastError();
    }
    return os::unlink( path );
}

// rename: POSIX replaces the destination atomically even while another descriptor holds it open. FileRenameInfoEx
// with REPLACE_IF_EXISTS | POSIX_SEMANTICS (Windows 10 1809+, NTFS) does exactly that, through a handle on the
// source opened without following it (renaming a link renames the link, as POSIX does). Where the file system refuses
// the flags (FAT, an SMB share) MoveFileExW( REPLACE_EXISTING | WRITE_THROUGH ) follows, with a short bounded retry
// on a sharing violation — PR #44's rw_rename retry, without its COPY_ALLOWED (a cross-volume copy is not atomic,
// and POSIX says EXDEV) and with errno set on the final failure.
namespace
{
struct RenameInfo   // FILE_RENAME_INFO's layout, with the Flags member of the union
{
    DWORD   flags;
    HANDLE  rootDirectory;
    DWORD   fileNameLength;
    wchar_t fileName[ 1 ];
};
constexpr int   kFileRenameInfoEx        = 22;           // FILE_INFO_BY_HANDLE_CLASS::FileRenameInfoEx
constexpr DWORD kRenameReplaceIfExists   = 0x00000001;   // FILE_RENAME_FLAG_REPLACE_IF_EXISTS
constexpr DWORD kRenamePosixSemantics    = 0x00000002;   // FILE_RENAME_FLAG_POSIX_SEMANTICS

DWORD renameWithPosixSemantics( LPCWSTR from, LPCWSTR to )
{
    const UniqueHandle source( ::CreateFileW( from, DELETE | SYNCHRONIZE, kShareAll, nullptr, OPEN_EXISTING,
                                              FILE_FLAG_BACKUP_SEMANTICS | FILE_FLAG_OPEN_REPARSE_POINT, nullptr ) );
    if( !source.valid() )
    {
        return ::GetLastError();
    }
    const std::size_t units = std::wcslen( to );
    const std::size_t bytes = offsetof( RenameInfo, fileName ) + ( units + 1 ) * sizeof( wchar_t );
    std::unique_ptr<std::uint8_t[]> storage( new( std::nothrow ) std::uint8_t[ bytes ]() );
    if( !storage )
    {
        return ERROR_NOT_ENOUGH_MEMORY;
    }
    auto* const information         = reinterpret_cast<RenameInfo*>( storage.get() );
    information->flags              = kRenameReplaceIfExists | kRenamePosixSemantics;
    information->rootDirectory      = nullptr;
    information->fileNameLength     = static_cast<DWORD>( units * sizeof( wchar_t ) );
    std::memcpy( information->fileName, to, ( units + 1 ) * sizeof( wchar_t ) );
    return ::SetFileInformationByHandle( source.get(), static_cast<FILE_INFO_BY_HANDLE_CLASS>( kFileRenameInfoEx ), information, static_cast<DWORD>( bytes ) )
               ? NO_ERROR
               : ::GetLastError();
}
}   // namespace

int rename( const char* from, const char* to )
{
    const NativePath nativeFrom( from );
    const NativePath nativeTo( to );
    if( !nativeFrom.ok() || !nativeTo.ok() )
    {
        return fail( !nativeFrom.ok() ? nativeFrom.error() : nativeTo.error() );
    }
    DWORD error = renameWithPosixSemantics( nativeFrom.c_str(), nativeTo.c_str() );
    if( error == NO_ERROR )
    {
        return 0;
    }
    if( error != ERROR_INVALID_PARAMETER && error != ERROR_NOT_SUPPORTED && error != ERROR_INVALID_FUNCTION )
    {
        return failWin32( error );
    }
    for( int attempt = 0; attempt < 8; ++attempt )
    {
        if( ::MoveFileExW( nativeFrom.c_str(), nativeTo.c_str(), MOVEFILE_REPLACE_EXISTING | MOVEFILE_WRITE_THROUGH ) )
        {
            return 0;
        }
        error = ::GetLastError();
        if( error != ERROR_SHARING_VIOLATION && error != ERROR_ACCESS_DENIED )
        {
            break;
        }
        ::Sleep( 5 );
    }
    return failWin32( error );
}

// mkdir / chmod with mode 0700: NTFS has no mode bits, so "owner only" is an ACL — PROTECTED (nothing inherited from a
// shared parent such as %TEMP%) and granting only the owner and Administrators: PR #44's cacheDirLadder descriptor,
// proven by cacheisolationcheck's ACL probe (CodeRabbit 3946215433). mkdir sets it at creation, never after, and fails
// closed if the descriptor cannot be built (CodeRabbit 3946351163). Any other mode creates with the inherited ACL.
constexpr const wchar_t* kOwnerOnlyDescriptor = L"D:P(A;OICI;GA;;;OW)(A;OICI;GA;;;BA)";

// The owner-only security descriptor, built for one call: empty (errno set) when Windows cannot build it.
UniqueLocal ownerOnlyDescriptor()
{
    PSECURITY_DESCRIPTOR descriptor = nullptr;
    if( !::ConvertStringSecurityDescriptorToSecurityDescriptorW( kOwnerOnlyDescriptor, SDDL_REVISION_1, &descriptor, nullptr ) )
    {
        (void)failLastError();
        return UniqueLocal();
    }
    return UniqueLocal( descriptor );
}

// Not yet implemented (skillsinstall.h's own header already documents this: "Windows: symlink-only
// for now... deferred until src/infra/os.h's POSIX seam lands" — CreateSymbolicLinkW needs privilege
// or developer-mode detection this port has not built yet). Declared, not silently unavailable: the
// ENOSYS/-1 shape matches os.h's own exepath() fallback for the same reason.
int symlink( const char*, const char* )
{
    return fail( ENOSYS );
}

int mkdir( const char* path, mode_t mode )
{
    const NativePath native( path );
    if( !native.ok() )
    {
        return fail( native.error() );
    }
    if( ( mode & 077 ) != 0 )
    {
        return ::CreateDirectoryW( native.c_str(), nullptr ) ? 0 : failLastError();
    }
    const UniqueLocal descriptor = ownerOnlyDescriptor();
    if( !descriptor.valid() )
    {
        return -1;
    }
    SECURITY_ATTRIBUTES security { sizeof( SECURITY_ATTRIBUTES ), descriptor.get(), FALSE };
    return ::CreateDirectoryW( native.c_str(), &security ) ? 0 : failLastError();
}

// chmod: 0700 writes the owner-only ACL above through a handle on the entry ITSELF, after checking that entry is not a
// link. CodeRabbit 3946215433's open residual on #44: SetNamedSecurityInfoW on a path follows a junction, so a
// junction planted where the cache directory should be redirected the ACL write onto its target. Here a symlink or
// junction is refused with ELOOP and nothing is written — stricter than POSIX chmod, which follows links; the cache
// ladder then fails closed. Other modes map the owner write bit to the read-only attribute of a file.
int chmod( const char* path, mode_t mode )
{
    const NativePath native( path );
    if( !native.ok() )
    {
        return fail( native.error() );
    }
    const bool   ownerOnly = ( mode & 077 ) == 0;
    const DWORD  access    = FILE_READ_ATTRIBUTES | FILE_WRITE_ATTRIBUTES | ( ownerOnly ? READ_CONTROL | WRITE_DAC : 0 );
    const UniqueHandle handle( ::CreateFileW( native.c_str(), access, kShareAll, nullptr, OPEN_EXISTING, FILE_FLAG_BACKUP_SEMANTICS | FILE_FLAG_OPEN_REPARSE_POINT, nullptr ) );
    if( !handle.valid() )
    {
        return failLastError();
    }
    FILE_ATTRIBUTE_TAG_INFO tag {};
    if( !::GetFileInformationByHandleEx( handle.get(), FileAttributeTagInfo, &tag, sizeof( tag ) ) )
    {
        return failLastError();
    }
    if( oswin::classifyFinalComponent( tag.FileAttributes, tag.ReparseTag ) == oswin::FinalComponent::Link )
    {
        return fail( ELOOP );
    }
    if( ownerOnly )
    {
        const UniqueLocal descriptor = ownerOnlyDescriptor();
        BOOL              present    = FALSE;
        BOOL              defaulted  = FALSE;
        PACL              dacl       = nullptr;
        if( !descriptor.valid() )
        {
            return -1;
        }
        if( !::GetSecurityDescriptorDacl( descriptor.get(), &present, &dacl, &defaulted ) || !present || dacl == nullptr )
        {
            return failLastError();
        }
        const DWORD error = ::SetSecurityInfo( handle.get(), SE_FILE_OBJECT, DACL_SECURITY_INFORMATION | PROTECTED_DACL_SECURITY_INFORMATION, nullptr, nullptr, dacl, nullptr );
        if( error != ERROR_SUCCESS )
        {
            return failWin32( error );
        }
    }
    if( ( tag.FileAttributes & FILE_ATTRIBUTE_DIRECTORY ) == 0 )
    {
        const DWORD wanted = ( mode & 0200 ) != 0 ? ( tag.FileAttributes & ~FILE_ATTRIBUTE_READONLY ) : ( tag.FileAttributes | FILE_ATTRIBUTE_READONLY );
        FILE_BASIC_INFO basic {};
        basic.FileAttributes = wanted == 0 ? FILE_ATTRIBUTE_NORMAL : wanted;   // zero times = unchanged; through the checked handle, not the path
        if( wanted != tag.FileAttributes && !::SetFileInformationByHandle( handle.get(), FileBasicInfo, &basic, sizeof( basic ) ) )
        {
            return failLastError();
        }
    }
    return 0;
}

// access: F_OK/R_OK — the path exists; W_OK — and is not a read-only file; X_OK — a directory (search), or a file
// whose extension PATHEXT lists. The UCRT's _access is never called: it rejects X_OK with the invalid-parameter
// handler, which ends the process.
int access( const char* path, int mode )
{
    const NativePath native( path );
    if( !native.ok() )
    {
        return fail( native.error() );
    }
    const DWORD attributes = ::GetFileAttributesW( native.c_str() );
    if( attributes == INVALID_FILE_ATTRIBUTES )
    {
        return failLastError();
    }
    const bool isDirectory = ( attributes & FILE_ATTRIBUTE_DIRECTORY ) != 0;
    if( ( mode & W_OK ) != 0 && !isDirectory && ( attributes & FILE_ATTRIBUTE_READONLY ) != 0 )
    {
        return fail( EACCES );
    }
    if( ( mode & X_OK ) != 0 && !isDirectory )
    {
        std::string pathext = environmentUtf8( L"PATHEXT" );
        if( pathext.empty() )
        {
            pathext = ".COM;.EXE;.BAT;.CMD";
        }
        if( !oswin::extensionInList( path, pathext ) )
        {
            return fail( EACCES );
        }
    }
    return 0;
}

// realpath: the path of the file itself, links resolved (GetFinalPathNameByHandleW on a handle opened through them),
// in the program's spelling — "C:/…" with an upper-case drive, "//server/share/…" for a UNC path. resolved == nullptr
// allocates with malloc, as POSIX.1-2008 specifies.
char* realpath( const char* path, char* resolved )
{
    const NativePath native( path );
    if( !native.ok() )
    {
        errno = native.error();
        return nullptr;
    }
    const UniqueHandle handle( ::CreateFileW( native.c_str(), FILE_READ_ATTRIBUTES, kShareAll, nullptr, OPEN_EXISTING, FILE_FLAG_BACKUP_SEMANTICS, nullptr ) );
    if( !handle.valid() )
    {
        (void)failLastError();
        return nullptr;
    }
    wchar_t                    stackBuffer[ MAX_PATH + 1 ];
    std::unique_ptr<wchar_t[]> heapBuffer;
    wchar_t*                   buffer = stackBuffer;
    DWORD length = ::GetFinalPathNameByHandleW( handle.get(), buffer, MAX_PATH + 1, FILE_NAME_NORMALIZED | VOLUME_NAME_DOS );
    if( length > MAX_PATH )
    {
        heapBuffer.reset( new( std::nothrow ) wchar_t[ length ] );
        buffer = heapBuffer.get();
        length = buffer == nullptr ? 0 : ::GetFinalPathNameByHandleW( handle.get(), buffer, length, FILE_NAME_NORMALIZED | VOLUME_NAME_DOS );
    }
    const DWORD error = ::GetLastError();
    if( length == 0 || buffer == nullptr )
    {
        (void)failWin32( buffer == nullptr ? ERROR_NOT_ENOUGH_MEMORY : error );
        return nullptr;
    }
    char* const out = resolved != nullptr ? resolved : static_cast<char*>( std::malloc( PATH_MAX ) );
    if( out == nullptr )
    {
        errno = ENOMEM;
        return nullptr;
    }
    if( programPathInto( std::u16string_view( reinterpret_cast<const char16_t*>( buffer ), length ), out, PATH_MAX ) != 0 )
    {
        if( resolved == nullptr )
        {
            std::free( out );
        }
        return nullptr;
    }
    return out;
}

// The public counterpart of NativePath's private rebase(): same routing (oswin::rebasedProgramPath over
// userTempDirectory()), but for a caller OUTSIDE this file that must hand a path to something which performs no
// rebase of its own — #326's fix, so --doctor's cache-dir writability probe and blob scan measure the same
// directory os::mkdir/os::open/os::stat already write into, instead of the un-rebased "/tmp/<cache-dir>-<uid>"
// spelling read literally off the current drive.
std::string rebased_path( const char* path )
{
    if( path == nullptr )
    {
        return {};
    }
    const std::string rebased = oswin::rebasedProgramPath( path, userTempDirectory() );
    return rebased.empty() ? std::string( path ) : rebased;
}

char* getcwd( char* buf, std::size_t size )
{
    if( buf == nullptr || size == 0 )
    {
        errno = EINVAL;
        return nullptr;
    }
    wchar_t                    stackBuffer[ MAX_PATH + 1 ];
    std::unique_ptr<wchar_t[]> heapBuffer;
    wchar_t*                   buffer = stackBuffer;
    DWORD length = ::GetCurrentDirectoryW( MAX_PATH + 1, buffer );
    if( length > MAX_PATH )
    {
        heapBuffer.reset( new( std::nothrow ) wchar_t[ length ] );
        buffer = heapBuffer.get();
        length = buffer == nullptr ? 0 : ::GetCurrentDirectoryW( length, buffer );
    }
    if( length == 0 )
    {
        (void)failLastError();
        return nullptr;
    }
    const int written = programPathInto( std::u16string_view( reinterpret_cast<const char16_t*>( buffer ), length ), buf, size );
    if( written != 0 )
    {
        if( errno == ENAMETOOLONG )
        {
            errno = ERANGE;   // POSIX getcwd's "buffer too small"
        }
        return nullptr;
    }
    return buf;
}

int setenv( const char* name, const char* value, int overwrite )
{
    if( name == nullptr || value == nullptr || *name == '\0' || std::strchr( name, '=' ) != nullptr )
    {
        return fail( EINVAL );
    }
    bool                 nameOk = false, valueOk = false;
    const std::u16string wideName  = utf16Of( name, nameOk );
    const std::u16string wideValue = utf16Of( value, valueOk );
    if( !nameOk || !valueOk )
    {
        return fail( EILSEQ );
    }
    if( overwrite == 0 && ::_wgetenv( reinterpret_cast<const wchar_t*>( wideName.c_str() ) ) != nullptr )
    {
        return 0;
    }
    const errno_t error = ::_wputenv_s( reinterpret_cast<const wchar_t*>( wideName.c_str() ), reinterpret_cast<const wchar_t*>( wideValue.c_str() ) );
    return error == 0 ? 0 : fail( error );
}

// which: the program a shell would start for `command`. PATH is ';'-separated; an entry that is empty or relative (the
// current directory) is never searched — a checkout carrying its own copy of this program or of git.exe must not answer; a name
// without an extension is tried with each PATHEXT extension, one with an extension as given (if PATHEXT lists it).
// The answer is in the program's spelling.
std::string which( std::string_view command )
{
    if( command.empty() || command.find( '\0' ) != std::string_view::npos )
    {
        return {};
    }
    std::string pathext = environmentUtf8( L"PATHEXT" );
    if( pathext.empty() )
    {
        pathext = ".COM;.EXE;.BAT;.CMD";
    }
    const auto isFile = []( const std::string& candidate )
    {
        const NativePath native( candidate.c_str() );
        const DWORD      attributes = native.ok() ? ::GetFileAttributesW( native.c_str() ) : INVALID_FILE_ATTRIBUTES;
        return attributes != INVALID_FILE_ATTRIBUTES && ( attributes & FILE_ATTRIBUTE_DIRECTORY ) == 0;
    };
    const auto resolve = [ & ]( std::string base ) -> std::string
    {
        oswin::normalizePathArgInPlace( base.data() );
        if( oswin::hasExtension( base ) )
        {
            return oswin::extensionInList( base, pathext ) && isFile( base ) ? base : std::string();
        }
        std::size_t at = 0;
        while( at <= pathext.size() )
        {
            const std::string_view extension = oswin::nextPathListEntry( pathext, at );
            if( !extension.empty() && isFile( base + std::string( extension ) ) )
            {
                return base + std::string( extension );
            }
        }
        return {};
    };
    if( command.find_first_of( "/\\:" ) != std::string_view::npos )
    {
        return resolve( std::string( command ) );
    }
    const std::string path = environmentUtf8( L"PATH" );
    std::size_t       at   = 0;
    while( at <= path.size() )
    {
        std::string_view directory = oswin::nextPathListEntry( path, at );
        if( directory.empty() || !oswin::isAbsoluteNativePath( directory ) )
        {
            continue;
        }
        while( directory.size() > 3 && ( directory.back() == '/' || directory.back() == '\\' ) )
        {
            directory.remove_suffix( 1 );
        }
        std::string found = resolve( std::string( directory ) + "/" + std::string( command ) );
        if( !found.empty() )
        {
            return found;
        }
    }
    return {};
}

// ── process start and path intake ──────────────────────────────────────────────────────────────────────────
void normalize_path_arg( char* text )
{
    oswin::normalizePathArgInPlace( text );
}

void init_process( int& argc, char**& argv )
{
    static_assert( sizeof( wchar_t ) == sizeof( char16_t ), "the Windows ABI's wchar_t is UTF-16" );

    // A bad descriptor or argument makes a UCRT call return its error (EBADF, EINVAL) — POSIX's behaviour — instead of
    // running the default invalid-parameter handler, which ends the process. PR #44 relied on the default.
    (void)::_set_thread_local_invalid_parameter_handler( nullptr );
    (void)::_set_invalid_parameter_handler( []( const wchar_t*, const wchar_t*, const wchar_t*, unsigned int, std::uintptr_t ) noexcept {} );

    // stdout carries XML/JSON bytes and stdin carries MCP requests: no CRLF translation in either direction.
    (void)::_setmode( ::_fileno( stdin ), _O_BINARY );
    (void)::_setmode( ::_fileno( stdout ), _O_BINARY );
    (void)::_setmode( ::_fileno( stderr ), _O_BINARY );

    // argv as UTF-8, from the UTF-16 command line: the CRT's narrow argv is in the ANSI code page, which is UTF-8 only
    // when the manifest's activeCodePage took effect. An argument that is not valid UTF-16 leaves the CRT's argv in
    // place — every argument, so the indices stay aligned.
    int                 wideCount = 0;
    LPWSTR* const       wideArgv  = ::CommandLineToArgvW( ::GetCommandLineW(), &wideCount );
    const UniqueLocal   wideArgvOwner( static_cast<HLOCAL>( wideArgv ) );
    if( wideArgv != nullptr )
    {
        static std::vector<std::string> storage;
        static std::vector<char*>       pointers;
        storage.resize( static_cast<std::size_t>( wideCount ) );
        bool allValid = wideCount > 0;
        for( int i = 0; i < wideCount && allValid; ++i )
        {
            allValid = utf8Of( viewOf( wideArgv[ i ] ), storage[ static_cast<std::size_t>( i ) ] );
        }
        if( allValid )
        {
            pointers.clear();
            for( std::string& arg : storage )
            {
                pointers.push_back( arg.data() );
            }
            pointers.push_back( nullptr );
            argc = wideCount;
            argv = pointers.data();
        }
    }

    // the path-valued environment the program reads, in its own spelling. A variable whose spelling is already right is
    // not rewritten, so a child process inherits exactly what this one was given unless the spelling had to change.
    static constexpr const wchar_t* kPathVariables[] = { L"HOME", L"TMPDIR", L"XDG_CACHE_HOME", L"CODEX_HOME", L"CLAUDE_CONFIG_DIR" };
    for( const wchar_t* const name : kPathVariables )
    {
        std::string value = environmentUtf8( name );
        if( value.empty() )
        {
            continue;
        }
        const std::string before = value;
        oswin::normalizePathArgInPlace( value.data() );
        bool                 ok = false;
        const std::u16string programSpelling = utf16Of( value, ok );
        if( value != before && ok )
        {
            (void)::_wputenv_s( name, reinterpret_cast<const wchar_t*>( programSpelling.c_str() ) );
        }
    }
}

// exepath: GetModuleFileNameW, grown past MAX_PATH when the answer did not fit, in the program's spelling.
int exepath( char* buf, std::size_t bufCount )
{
    wchar_t                    stackBuffer[ MAX_PATH + 1 ];
    std::unique_ptr<wchar_t[]> heapBuffer;
    wchar_t*                   buffer   = stackBuffer;
    DWORD                      capacity = MAX_PATH + 1;
    DWORD                      length   = ::GetModuleFileNameW( nullptr, buffer, capacity );
    while( length == capacity && capacity < 32768 )
    {
        capacity *= 4;
        heapBuffer.reset( new( std::nothrow ) wchar_t[ capacity ] );
        buffer = heapBuffer.get();
        length = buffer == nullptr ? 0 : ::GetModuleFileNameW( nullptr, buffer, capacity );
    }
    if( length == 0 || length == capacity )
    {
        return -1;
    }
    return programPathInto( std::u16string_view( reinterpret_cast<const char16_t*>( buffer ), length ), buf, bufCount );
}

// ── time ───────────────────────────────────────────────────────────────────────────────────────────────────
// nanosleep: Sleep in whole milliseconds, rounded up so a nonzero request never becomes a zero sleep; never interrupted.
int nanosleep( const ::timespec* request, ::timespec* remaining )
{
    if( request == nullptr || request->tv_sec < 0 || request->tv_nsec < 0 || request->tv_nsec >= 1000000000L )
    {
        return fail( EINVAL );
    }
    const std::uint64_t milliseconds = static_cast<std::uint64_t>( request->tv_sec ) * 1000u + ( static_cast<std::uint64_t>( request->tv_nsec ) + 999999u ) / 1000000u;
    ::Sleep( milliseconds > 0xFFFFFFFEu ? 0xFFFFFFFEu : static_cast<DWORD>( milliseconds ) );
    if( remaining != nullptr )
    {
        *remaining = ::timespec{};
    }
    return 0;
}

std::tm* localtime_r( const std::time_t* time, std::tm* result ) { return ::localtime_s( result, time ) == 0 ? result : nullptr; }

// ── processes ──────────────────────────────────────────────────────────────────────────────────────────────
pid_t getpid() { return static_cast<pid_t>( ::GetCurrentProcessId() ); }
uid_t getuid() { return tokenIdentity().uid; }

namespace
{
// The POSIX shell every command runs under: bash from Git for Windows, resolved ONCE per process. Candidates, in
// order: RW_BASH (an explicit override, PR #44's name), Git for Windows' install directories, then the absolute PATH
// entries. Each must pass oswin::isAcceptableShell — absolute, a bash.exe, not a WSL launcher — so the current
// directory, a relative PATH entry, the application directory and System32\bash.exe are never used. That closes
// CodeRabbit 3946215444's regression on #44, where SearchPathA( "sh.exe" ) searched the application directory and
// the current directory first and ran a checkout's planted sh.exe. When no shell qualifies there is no fallback to
// cmd.exe (a different language: the command would run with different quoting); the spawn fails with ENOENT.
const std::string& trustedBash()
{
    static const std::string bash = []
    {
        const auto isFile = []( const std::string& candidate )
        {
            const NativePath native( candidate.c_str() );
            const DWORD      attributes = native.ok() ? ::GetFileAttributesW( native.c_str() ) : INVALID_FILE_ATTRIBUTES;
            return attributes != INVALID_FILE_ATTRIBUTES && ( attributes & FILE_ATTRIBUTE_DIRECTORY ) == 0;
        };
        const auto usable = [ & ]( std::string candidate )
        {
            oswin::normalizePathArgInPlace( candidate.data() );
            return oswin::isAcceptableShell( candidate ) && isFile( candidate ) ? candidate : std::string();
        };
        if( std::string chosen = usable( environmentUtf8( L"RW_BASH" ) ); !chosen.empty() )
        {
            return chosen;
        }
        for( const wchar_t* const root : { L"ProgramW6432", L"ProgramFiles", L"ProgramFiles(x86)", L"LOCALAPPDATA" } )
        {
            const std::string base = environmentUtf8( root );
            if( base.empty() )
            {
                continue;
            }
            const std::string git = base + ( std::wstring_view( root ) == L"LOCALAPPDATA" ? "/Programs/Git" : "/Git" );
            for( const char* const tail : { "/bin/bash.exe", "/usr/bin/bash.exe" } )
            {
                if( std::string chosen = usable( git + tail ); !chosen.empty() )
                {
                    return chosen;
                }
            }
        }
        const std::string path = environmentUtf8( L"PATH" );
        std::size_t       at   = 0;
        while( at <= path.size() )
        {
            const std::string_view directory = oswin::nextPathListEntry( path, at );
            if( !directory.empty() )
            {
                if( std::string chosen = usable( std::string( directory ) + "/bash.exe" ); !chosen.empty() )
                {
                    return chosen;
                }
            }
        }
        return std::string();
    }();
    return bash;
}

// The environment block a child gets: this process's own, with Git for Windows' usr/bin, bin and cmd directories
// appended to PATH so the tools a shell command names (tail, tar, sed, git) resolve — PR #44's windowsGitEnvironment.
// Rebuilt for each spawn, because setenv (githarden's GIT_CONFIG_* pins) changes the environment between spawns.
std::vector<wchar_t> childEnvironment( const std::string& bash )
{
    std::string gitRoot = bash.substr( 0, bash.find_last_of( '/' ) );
    for( const std::string_view tail : { std::string_view( "/usr/bin" ), std::string_view( "/bin" ) } )
    {
        if( gitRoot.size() > tail.size() && gitRoot.compare( gitRoot.size() - tail.size(), tail.size(), tail ) == 0 )
        {
            gitRoot.resize( gitRoot.size() - tail.size() );
            break;
        }
    }
    bool                         ok = false;
    const std::u16string         extra = utf16Of( ";" + gitRoot + "/usr/bin;" + gitRoot + "/bin;" + gitRoot + "/cmd", ok );
    const UniqueEnvironmentBlock environment( ::GetEnvironmentStringsW() );
    std::vector<wchar_t>         block;
    if( !environment.valid() || !ok )
    {
        return block;   // empty: CreateProcessW then gives the child this process's environment unchanged
    }
    // A temporary directory near MAX_PATH breaks Git for Windows' tools; such a TMP/TEMP/TMPDIR is replaced, in the
    // child's block only, by %LOCALAPPDATA%\Temp when that is shorter (lennix1337's win32-port-snapshot).
    bool                 shortOk = false;
    const std::string    localAppData = environmentUtf8( L"LOCALAPPDATA" );
    const std::u16string shortTemp    = localAppData.empty() ? std::u16string() : utf16Of( localAppData + "\\Temp", shortOk );
    bool pathSeen = false;
    for( const wchar_t* entry = environment.get(); *entry != L'\0'; entry += std::wcslen( entry ) + 1 )
    {
        const std::size_t         length = std::wcslen( entry );
        const std::u16string_view view( reinterpret_cast<const char16_t*>( entry ), length );
        if( shortOk && oswin::isLongTemporaryEntry( view ) && shortTemp.size() < oswin::kLongTemporaryUnits )
        {
            const std::size_t equals = view.find( u'=' );
            block.insert( block.end(), entry, entry + equals + 1 );
            block.insert( block.end(), shortTemp.begin(), shortTemp.end() );
            block.push_back( L'\0' );
            continue;
        }
        block.insert( block.end(), entry, entry + length );
        if( length >= 5 && ::_wcsnicmp( entry, L"PATH=", 5 ) == 0 )
        {
            block.insert( block.end(), extra.begin(), extra.end() );
            pathSeen = true;
        }
        block.push_back( L'\0' );
    }
    if( !pathSeen )
    {
        const std::wstring_view name = L"PATH=";
        block.insert( block.end(), name.begin(), name.end() );
        block.insert( block.end(), extra.begin() + 1, extra.end() );
        block.push_back( L'\0' );
    }
    block.push_back( L'\0' );
    return block;
}

// A PROC_THREAD_ATTRIBUTE_LIST owned for one CreateProcessW call.
class ProcThreadAttributes
{
public:
    explicit ProcThreadAttributes( DWORD attributeCount ) noexcept
    {
        SIZE_T bytes = 0;
        (void)::InitializeProcThreadAttributeList( nullptr, attributeCount, 0, &bytes );
        storage_.reset( new( std::nothrow ) BYTE[ bytes ] );
        initialized_ = storage_ && ::InitializeProcThreadAttributeList( get(), attributeCount, 0, &bytes ) != FALSE;
    }
    ProcThreadAttributes( const ProcThreadAttributes& ) = delete;
    ProcThreadAttributes& operator=( const ProcThreadAttributes& ) = delete;
    ~ProcThreadAttributes()
    {
        if( initialized_ )
        {
            ::DeleteProcThreadAttributeList( get() );
        }
    }
    [[nodiscard]] bool                         valid() const noexcept { return initialized_; }
    [[nodiscard]] LPPROC_THREAD_ATTRIBUTE_LIST get() const noexcept { return reinterpret_cast<LPPROC_THREAD_ATTRIBUTE_LIST>( storage_.get() ); }

private:
    std::unique_ptr<BYTE[]> storage_;
    bool                    initialized_ = false;
};

// A started shell: its process, the job holding its tree, and its id.
struct StartedChild
{
    UniqueHandle process;
    UniqueHandle job;
    DWORD        pid = 0;
};

// Start bash with argv = { bash, arguments... } (quoted for CreateProcessW by os_win32_logic.h), stdin/stdout/stderr
// the given inheritable handles and nothing else inherited (PROC_THREAD_ATTRIBUTE_HANDLE_LIST, PR #44's rw_popen
// pattern), suspended until it is inside a KILL_ON_JOB_CLOSE job — so nothing it starts escapes a kill (PR #44's
// order, proven by runtracecheck on lennix1337's machine). False with the Win32 error in GetLastError().
bool startBash( std::initializer_list<std::string_view> arguments, HANDLE input, HANDLE output, HANDLE error, StartedChild& started )
{
    const std::string& bash = trustedBash();
    if( bash.empty() )
    {
        ::SetLastError( ERROR_FILE_NOT_FOUND );
        return false;
    }
    std::string commandLine;
    oswin::appendQuotedArg( commandLine, bash );
    for( const std::string_view argument : arguments )
    {
        if( argument.find( '\0' ) != std::string_view::npos )
        {
            ::SetLastError( ERROR_INVALID_PARAMETER );
            return false;
        }
        commandLine.push_back( ' ' );
        oswin::appendQuotedArg( commandLine, argument );
    }
    bool             converted   = false;
    std::u16string   wideCommand = utf16Of( commandLine, converted );
    const NativePath program( bash.c_str() );
    if( !converted || !program.ok() )
    {
        ::SetLastError( ERROR_NO_UNICODE_TRANSLATION );
        return false;
    }
    std::vector<wchar_t> environment = childEnvironment( bash );

    const ProcThreadAttributes attributes( 1 );
    HANDLE                     inherited[ 3 ] = { input, output, error };
    const DWORD                inheritedCount = output == error ? 2 : 3;
    if( !attributes.valid()
        || !::UpdateProcThreadAttribute( attributes.get(), 0, PROC_THREAD_ATTRIBUTE_HANDLE_LIST, inherited, inheritedCount * sizeof( HANDLE ), nullptr, nullptr ) )
    {
        return false;
    }
    STARTUPINFOEXW startup {};
    startup.StartupInfo.cb         = sizeof( startup );
    startup.StartupInfo.dwFlags    = STARTF_USESTDHANDLES;
    startup.StartupInfo.hStdInput  = input;
    startup.StartupInfo.hStdOutput = output;
    startup.StartupInfo.hStdError  = error;
    startup.lpAttributeList        = attributes.get();

    // The job first: without it a timeout could end the shell but not what the shell started, so a job that cannot be
    // created or configured refuses the spawn (fail closed) rather than starting a tree nothing can stop.
    started.job.reset( ::CreateJobObjectW( nullptr, nullptr ) );
    JOBOBJECT_EXTENDED_LIMIT_INFORMATION limits {};
    limits.BasicLimitInformation.LimitFlags = JOB_OBJECT_LIMIT_KILL_ON_JOB_CLOSE;
    if( !started.job.valid() || !::SetInformationJobObject( started.job.get(), JobObjectExtendedLimitInformation, &limits, sizeof( limits ) ) )
    {
        return false;
    }
    PROCESS_INFORMATION information {};
    if( !::CreateProcessW( program.c_str(), reinterpret_cast<LPWSTR>( wideCommand.data() ), nullptr, nullptr, TRUE,
                           CREATE_SUSPENDED | CREATE_NO_WINDOW | EXTENDED_STARTUPINFO_PRESENT | CREATE_UNICODE_ENVIRONMENT,
                           environment.empty() ? nullptr : environment.data(), nullptr, &startup.StartupInfo, &information ) )
    {
        return false;
    }
    started.process.reset( information.hProcess );
    const UniqueHandle thread( information.hThread );
    started.pid = information.dwProcessId;
    // Inside the job before it runs a single instruction. If that fails (a job the caller's own job forbids nesting
    // into), the suspended shell is ended and the spawn fails, for the same reason as above.
    if( !::AssignProcessToJobObject( started.job.get(), started.process.get() ) )
    {
        const DWORD assignError = ::GetLastError();
        ::TerminateProcess( started.process.get(), 1 );
        ::SetLastError( assignError );
        return false;
    }
    if( ::ResumeThread( thread.get() ) == static_cast<DWORD>( -1 ) )
    {
        const DWORD resumeError = ::GetLastError();
        ::TerminateJobObject( started.job.get(), 1 );
        ::SetLastError( resumeError );
        return false;
    }
    return true;
}

// An inheritable duplicate of a handle, for a child's standard stream.
UniqueHandle inheritableCopy( HANDLE handle )
{
    HANDLE copy = nullptr;
    return UniqueHandle( ::DuplicateHandle( ::GetCurrentProcess(), handle, ::GetCurrentProcess(), &copy, 0, TRUE, DUPLICATE_SAME_ACCESS ) ? copy : nullptr );
}

UniqueHandle inheritableNul( DWORD access )
{
    SECURITY_ATTRIBUTES inherit { sizeof( SECURITY_ATTRIBUTES ), nullptr, TRUE };
    return UniqueHandle( ::CreateFileW( L"NUL", access, FILE_SHARE_READ | FILE_SHARE_WRITE, &inherit, OPEN_EXISTING, FILE_ATTRIBUTE_NORMAL, nullptr ) );
}

// One spawn_sh child: the signal kill() delivered is recorded so waitpid reports WIFSIGNALED, as POSIX does for a
// SIGKILLed group.
struct Child
{
    pid_t        pid       = 0;
    UniqueHandle process;
    UniqueHandle job;
    int          signalled = 0;
};

std::mutex& childMutex()
{
    static std::mutex mutex;
    return mutex;
}

std::vector<Child>& children()
{
    static std::vector<Child> table;
    return table;
}
}   // namespace

// spawn_sh: POSIX's fork/exec of `/bin/sh -c command` in its own process group becomes bash -c command inside a job
// object — the job IS the process group: kill( -pid, SIGKILL ) terminates it. stdin is NUL, stdout and stderr both
// go to pipeFds[1], nothing else is inherited. The pid is the Windows process id. Where POSIX reports an unstartable
// shell as the child's exit status 127, this returns -1 with errno (ENOENT when no trusted bash exists) — the caller
// treats both as a failed spawn.
pid_t spawn_sh( const std::string& command, const int pipeFds[ 2 ] )
{
    const HANDLE output = handleOf( pipeFds[ 1 ] );
    if( output == INVALID_HANDLE_VALUE )
    {
        return fail( EBADF );
    }
    const UniqueHandle input       = inheritableNul( GENERIC_READ );
    const UniqueHandle childOutput = inheritableCopy( output );
    if( !input.valid() || !childOutput.valid() )
    {
        return failLastError();
    }
    StartedChild started;
    if( !startBash( { "-c", command }, input.get(), childOutput.get(), childOutput.get(), started ) )
    {
        return failLastError();
    }
    const pid_t pid = static_cast<pid_t>( started.pid );
    const std::lock_guard<std::mutex> lock( childMutex() );
    children().push_back( Child{ pid, std::move( started.process ), std::move( started.job ), 0 } );
    return pid;
}

// kill: a negative pid is the process group — TerminateJobObject ends the whole tree; a positive pid ends that
// process. Only children spawn_sh started are known (ESRCH otherwise). Signal 0 asks whether the child still runs. The
// signal is recorded so waitpid reports the death as that signal.
int kill( pid_t pid, int sig )
{
    const std::lock_guard<std::mutex> lock( childMutex() );
    for( Child& child : children() )
    {
        if( child.pid != ( pid < 0 ? -pid : pid ) )
        {
            continue;
        }
        if( sig == 0 )
        {
            return ::WaitForSingleObject( child.process.get(), 0 ) == WAIT_TIMEOUT ? 0 : fail( ESRCH );
        }
        const UINT exitCode = 128u + static_cast<UINT>( sig );
        const BOOL ended    = pid < 0 ? ::TerminateJobObject( child.job.get(), exitCode ) : ::TerminateProcess( child.process.get(), exitCode );
        if( ended || ::WaitForSingleObject( child.process.get(), 0 ) == WAIT_OBJECT_0 )
        {
            if( child.signalled == 0 )
            {
                child.signalled = sig;
            }
            return 0;
        }
        return failLastError();
    }
    return fail( ESRCH );
}

// waitpid: WNOHANG polls; 0 blocks. The status decodes through os.h's W* macros: an exit code, the recorded kill()
// signal, or the signal a crash's NTSTATUS corresponds to. Reaping closes the job, which (KILL_ON_JOB_CLOSE) ends any
// descendant the shell left running — where POSIX would leave an orphan to init. One thread reaps a given child.
pid_t waitpid( pid_t pid, int* status, int options )
{
    std::unique_lock<std::mutex> lock( childMutex() );
    auto& table = children();
    auto  found = [ & ] { auto it = table.begin(); while( it != table.end() && it->pid != pid ) { ++it; } return it; };
    auto  it    = found();
    if( it == table.end() )
    {
        return fail( ECHILD );
    }
    const HANDLE process = it->process.get();
    lock.unlock();
    const DWORD waited = ::WaitForSingleObject( process, ( options & WNOHANG ) != 0 ? 0 : INFINITE );
    if( waited == WAIT_TIMEOUT )
    {
        return 0;
    }
    if( waited != WAIT_OBJECT_0 )
    {
        return failLastError();
    }
    lock.lock();
    it = found();
    if( it == table.end() )
    {
        return fail( ECHILD );
    }
    DWORD exitCode = 0;
    (void)::GetExitCodeProcess( it->process.get(), &exitCode );
    if( status != nullptr )
    {
        *status = it->signalled != 0 ? oswin::waitStatusFromSignal( it->signalled ) : oswin::waitStatusFromExit( exitCode );
    }
    table.erase( it );   // closes the process and the job
    return pid;
}

// popen: PR #44's Git Bash bridge (proven by the git-backed gates on lennix1337's machine): the command text is written
// to a temporary script and bash runs the script, so no byte of the command passes through a Windows command line
// (and cmd.exe never sees a '%' in a git --format; CodeRabbit 3946215374 / 3946215385). The shell is the trusted bash
// above, resolved once; stdin is NUL, stderr is this process's stderr, stdout is the returned stream. Read mode only
// (no caller writes); "w" is EINVAL.
namespace
{
struct PipeChild
{
    std::FILE*    stream = nullptr;
    UniqueHandle  process;
    UniqueHandle  job;      // closed only after the shell is reaped: KILL_ON_JOB_CLOSE ends what the command left running
    TemporaryFile script;   // the script's own trap removes it; this is the backstop
};

std::vector<PipeChild>& pipeChildren()
{
    static std::vector<PipeChild> table;
    return table;
}

bool writeScript( HANDLE file, const std::string& command )
{
    const std::string script  = "trap 'rm -f -- \"$0\"' EXIT\n" + command + "\n";
    DWORD             written = 0;
    return ::WriteFile( file, script.data(), static_cast<DWORD>( script.size() ), &written, nullptr ) && written == script.size();
}
}   // namespace

std::FILE* popen( const char* command, const char* mode )
{
    if( command == nullptr || mode == nullptr || mode[ 0 ] != 'r' )
    {
        errno = EINVAL;
        return nullptr;
    }
    // The script is written through the handle CREATE_NEW returned — no second open of a name another process could
    // have replaced in between — and closed before bash opens it.
    std::string   scriptPath( PATH_MAX, '\0' );
    TemporaryFile script;
    {
        CreatedTemporary created = createTemporary( "rwc", 0 );
        if( !created.handle.valid() )
        {
            return nullptr;
        }
        script = TemporaryFile( std::wstring( reinterpret_cast<const wchar_t*>( created.name.c_str() ) ) );
        if( !writeScript( created.handle.get(), command ) )
        {
            (void)failLastError();
            return nullptr;
        }
        if( programPathInto( created.name, scriptPath.data(), scriptPath.size() ) != 0 )
        {
            return nullptr;
        }
        scriptPath.resize( std::strlen( scriptPath.c_str() ) );
    }
    SECURITY_ATTRIBUTES pipeSecurity { sizeof( SECURITY_ATTRIBUTES ), nullptr, TRUE };
    HANDLE              rawRead = nullptr, rawWrite = nullptr;
    if( !::CreatePipe( &rawRead, &rawWrite, &pipeSecurity, 0 ) )
    {
        (void)failLastError();
        return nullptr;
    }
    UniqueHandle       readEnd( rawRead );
    const UniqueHandle writeEnd( rawWrite );
    (void)::SetHandleInformation( readEnd.get(), HANDLE_FLAG_INHERIT, 0 );
    const UniqueHandle input       = inheritableNul( GENERIC_READ );
    const HANDLE       parentError = ::GetStdHandle( STD_ERROR_HANDLE );
    UniqueHandle       error       = parentError != nullptr && parentError != INVALID_HANDLE_VALUE ? inheritableCopy( parentError ) : UniqueHandle();
    if( !error.valid() )
    {
        error = inheritableNul( GENERIC_WRITE );
    }
    StartedChild started;
    if( !input.valid() || !error.valid() || !startBash( { std::string_view( scriptPath ) }, input.get(), writeEnd.get(), error.get(), started ) )
    {
        (void)failLastError();
        return nullptr;
    }
    UniqueFd fd( ::_open_osfhandle( reinterpret_cast<intptr_t>( readEnd.get() ), _O_RDONLY | _O_BINARY ) );
    if( !fd.valid() )
    {
        ::TerminateJobObject( started.job.get(), 1 );
        return nullptr;
    }
    (void)readEnd.release();   // the descriptor owns it
    std::FILE* const stream = ::_fdopen( fd.get(), "rb" );
    if( stream == nullptr )
    {
        ::TerminateJobObject( started.job.get(), 1 );
        return nullptr;
    }
    (void)fd.release();        // the stream owns it
    const std::lock_guard<std::mutex> lock( childMutex() );
    pipeChildren().push_back( PipeChild{ stream, std::move( started.process ), std::move( started.job ), TemporaryFile( script.keep() ) } );
    return stream;
}

// pclose: close the stream, wait for the shell, and return its wait status (WEXITSTATUS is the exit code) — callers
// test `== 0`, which holds exactly when the command exited 0.
int pclose( std::FILE* stream )
{
    PipeChild child;
    {
        const std::lock_guard<std::mutex> lock( childMutex() );
        auto& table = pipeChildren();
        auto  it    = table.begin();
        while( it != table.end() && it->stream != stream )
        {
            ++it;
        }
        if( it == table.end() )
        {
            return fail( ECHILD );
        }
        child = std::move( *it );
        table.erase( it );
    }
    std::fclose( stream );
    if( ::WaitForSingleObject( child.process.get(), INFINITE ) != WAIT_OBJECT_0 )
    {
        return failLastError();
    }
    DWORD exitCode = 1;
    (void)::GetExitCodeProcess( child.process.get(), &exitCode );
    return oswin::waitStatusFromExit( exitCode );   // `child` closes the process, the job and the script as it leaves
}

// system: popen, drain, pclose. POSIX system lets the command's output through to this process's stdout; every caller
// redirects it to /dev/null inside the command, so draining it here loses nothing.
int system( const char* command )
{
    std::FILE* const stream = os::popen( command, "r" );
    if( stream == nullptr )
    {
        return -1;
    }
    char buffer[ 4096 ];
    while( std::fread( buffer, 1, sizeof( buffer ), stream ) > 0 )
    {
    }
    return os::pclose( stream );
}

// ── threads ────────────────────────────────────────────────────────────────────────────────────────────────
pthread_t     pthread_self() { return ::GetCurrentThread(); }   // the pseudo-handle: never closed, never joined
std::uint64_t gettid()       { return ::GetCurrentThreadId(); }

// pthread_main_np: the thread that first asks is taken as the initial one — the same latch POSIX platforms without the
// call use. Its only caller asks from main's thread before any worker starts.
int pthread_main_np()
{
    static const DWORD firstCaller = ::GetCurrentThreadId();
    return ::GetCurrentThreadId() == firstCaller ? 1 : 0;
}

int pthread_getname_np( pthread_t, char* name, std::size_t nameCount )
{
    if( nameCount > 0 )
    {
        name[ 0 ] = '\0';
    }
    return 0;
}

// pthread_attr_* / pthread_create / pthread_join: the one attribute a caller sets is the stack size (stackthreads.h),
// which _beginthreadex takes as a RESERVATION, as a POSIX stack is: pages commit only as deep as the thread recurses.
// The result is the thread's own HANDLE (not the pseudo-handle pthread_self answers), owned by the pthread_t until
// pthread_join waits on it and closes it. A thread's return value is not carried across (_beginthreadex's is 32-bit);
// join reports nullptr, which is what the one caller asks for.
int pthread_attr_init( pthread_attr_t* attr )
{
    EXPECTS( attr != nullptr, "pthread_attr_init: the caller owns the attribute object" );
    *attr = pthread_attr_t {};
    return 0;
}
int pthread_attr_setstacksize( pthread_attr_t* attr, std::size_t stackBytes )
{
    EXPECTS( attr != nullptr, "pthread_attr_setstacksize: the caller owns the attribute object" );
    if( stackBytes > UINT_MAX )
    {
        return EINVAL;   // _beginthreadex's size is an unsigned; POSIX: a size the implementation cannot honour is EINVAL
    }
    attr->stackBytes = stackBytes;
    return 0;
}
int pthread_attr_destroy( pthread_attr_t* ) { return 0; }

namespace
{
struct ThreadStart
{
    void* ( *start )( void* );
    void* arg;
};
unsigned __stdcall threadTrampoline( void* raw )
{
    const std::unique_ptr<ThreadStart> launch( static_cast<ThreadStart*>( raw ) );
    (void)launch->start( launch->arg );
    return 0;
}
}   // namespace

int pthread_create( pthread_t* thread, const pthread_attr_t* attr, void* ( *start )( void* ), void* arg )
{
    EXPECTS( thread != nullptr && start != nullptr, "pthread_create: an out-handle and an entry point" );
    std::unique_ptr<ThreadStart> launch( new( std::nothrow ) ThreadStart { start, arg } );
    if( !launch )
    {
        return EAGAIN;
    }
    const unsigned stackBytes = attr != nullptr ? static_cast<unsigned>( attr->stackBytes ) : 0u;
    const std::uintptr_t handle = ::_beginthreadex( nullptr, stackBytes, &threadTrampoline, launch.get(),
                                                    stackBytes != 0 ? STACK_SIZE_PARAM_IS_A_RESERVATION : 0u, nullptr );
    if( handle == 0 )
    {
        return errno != 0 ? errno : EAGAIN;   // POSIX returns the error number; it does not set errno
    }
    (void)launch.release();   // the thread owns it now
    *thread = reinterpret_cast<pthread_t>( handle );
    return 0;
}

int pthread_join( pthread_t thread, void** valueOut )
{
    const UniqueHandle handle( static_cast<HANDLE>( thread ) );
    if( !handle.valid() )
    {
        return ESRCH;
    }
    if( ::WaitForSingleObject( handle.get(), INFINITE ) != WAIT_OBJECT_0 )
    {
        return EINVAL;
    }
    if( valueOut != nullptr )
    {
        *valueOut = nullptr;
    }
    return 0;
}

// ── directory watching ─────────────────────────────────────────────────────────────────────────────────────
// kqueue's EVFILT_VNODE on a directory descriptor, done with ReadDirectoryChangesW: dirwatch_open is an I/O completion
// port behind a descriptor from its own range; dirwatch_add reopens the directory for overlapped listing and starts a
// NON-recursive watch for entries created, deleted or renamed (FILE_NAME | DIR_NAME — what NOTE_WRITE reports on a
// directory; a file's content edits are the caller's per-file stat sweep, exactly as on kqueue); dirwatch_poll drains
// completions within the timeout and re-arms each one. Any completion counts as an event — an overflow, or a watched
// directory deleted, included — and a failed re-arm is -1, which the caller treats as "assume changed". The caller's
// own contract is unchanged: all-or-nothing arming, a sweep whenever the watcher is unhealthy.
// The capability is from lennix1337's win32-port-snapshot (RwFsWatcher: one recursive watch and a skipped per-file
// sweep); here it is the kevent-shaped os:: API the macOS watcher already uses, so mcpindex.h asks nothing about the
// platform and keeps its per-file sweep.
namespace
{
struct DirectoryWatch
{
    UniqueHandle directory;
    OVERLAPPED   overlapped {};
    DWORD        buffer[ 256 ];   // FILE_NOTIFY_INFORMATION records are DWORD-aligned; their content is never read
};

struct Watcher
{
    UniqueHandle                                 port;
    std::vector<std::unique_ptr<DirectoryWatch>> watches;   // stable addresses: the OVERLAPPED is the kernel's to write

    ~Watcher()
    {
        for( const std::unique_ptr<DirectoryWatch>& watch : watches )
        {
            if( ::CancelIoEx( watch->directory.get(), &watch->overlapped ) || ::GetLastError() != ERROR_NOT_FOUND )
            {
                DWORD ignored = 0;
                (void)::GetOverlappedResult( watch->directory.get(), &watch->overlapped, &ignored, TRUE );   // wait until the kernel lets go of it
            }
        }
    }
};

struct WatcherTable
{
    std::mutex                                                  mutex;
    std::array<std::unique_ptr<Watcher>, oswin::kDirwatchFdCount> slots;
};

WatcherTable& watcherTable()
{
    static WatcherTable table;
    return table;
}

bool armWatch( DirectoryWatch& watch )
{
    watch.overlapped = OVERLAPPED {};
    return ::ReadDirectoryChangesW( watch.directory.get(), watch.buffer, sizeof( watch.buffer ), FALSE,
                                    FILE_NOTIFY_CHANGE_FILE_NAME | FILE_NOTIFY_CHANGE_DIR_NAME, nullptr, &watch.overlapped, nullptr ) != FALSE;
}

int closeDirwatch( int fd )
{
    std::unique_ptr<Watcher> watcher;
    {
        WatcherTable&                     table = watcherTable();
        const std::lock_guard<std::mutex> lock( table.mutex );
        watcher = std::move( table.slots[ static_cast<std::size_t>( fd - oswin::kDirwatchFdBase ) ] );
    }
    return watcher ? 0 : fail( EBADF );   // ~Watcher cancels, waits, and closes every handle
}
}   // namespace

int dirwatch_open()
{
    auto watcher = std::make_unique<Watcher>();
    watcher->port.reset( ::CreateIoCompletionPort( INVALID_HANDLE_VALUE, nullptr, 0, 1 ) );
    if( !watcher->port.valid() )
    {
        return failLastError();
    }
    WatcherTable&                     table = watcherTable();
    const std::lock_guard<std::mutex> lock( table.mutex );
    for( std::size_t slot = 0; slot < table.slots.size(); ++slot )
    {
        if( !table.slots[ slot ] )
        {
            table.slots[ slot ] = std::move( watcher );
            return oswin::kDirwatchFdBase + static_cast<int>( slot );
        }
    }
    return fail( EMFILE );
}

int dirwatch_add( int watchFd, int dirFd, dirwatch_event* change )
{
    const HANDLE original = handleOf( dirFd );
    if( !oswin::isDirwatchFd( watchFd ) || original == INVALID_HANDLE_VALUE )
    {
        return fail( EBADF );
    }
    auto watch = std::make_unique<DirectoryWatch>();
    watch->directory.reset( ::ReOpenFile( original, FILE_LIST_DIRECTORY, kShareAll, FILE_FLAG_BACKUP_SEMANTICS | FILE_FLAG_OVERLAPPED ) );
    if( !watch->directory.valid() )
    {
        return failLastError();
    }
    WatcherTable&                     table = watcherTable();
    const std::lock_guard<std::mutex> lock( table.mutex );
    Watcher* const watcher = table.slots[ static_cast<std::size_t>( watchFd - oswin::kDirwatchFdBase ) ].get();
    if( watcher == nullptr )
    {
        return fail( EBADF );
    }
    if( ::CreateIoCompletionPort( watch->directory.get(), watcher->port.get(), static_cast<ULONG_PTR>( dirFd ), 0 ) == nullptr || !armWatch( *watch ) )
    {
        return failLastError();
    }
    if( change != nullptr )
    {
        change->ident = dirFd;
    }
    watcher->watches.push_back( std::move( watch ) );
    return 0;
}

int dirwatch_poll( int watchFd, dirwatch_event* events, int eventCount, const ::timespec* timeout )
{
    if( !oswin::isDirwatchFd( watchFd ) || events == nullptr || eventCount <= 0 )
    {
        return fail( EINVAL );
    }
    WatcherTable&                     table = watcherTable();
    const std::lock_guard<std::mutex> lock( table.mutex );
    Watcher* const watcher = table.slots[ static_cast<std::size_t>( watchFd - oswin::kDirwatchFdBase ) ].get();
    if( watcher == nullptr )
    {
        return fail( EBADF );
    }
    const DWORD milliseconds = timeout == nullptr ? INFINITE
                                                  : static_cast<DWORD>( timeout->tv_sec * 1000 + ( timeout->tv_nsec + 999999 ) / 1000000 );
    OVERLAPPED_ENTRY entries[ os::kDirwatchBatch ];
    ULONG            removed = 0;
    const ULONG      wanted  = static_cast<ULONG>( eventCount < os::kDirwatchBatch ? eventCount : os::kDirwatchBatch );
    if( !::GetQueuedCompletionStatusEx( watcher->port.get(), entries, wanted, &removed, milliseconds, FALSE ) )
    {
        return ::GetLastError() == WAIT_TIMEOUT ? 0 : failLastError();
    }
    for( ULONG i = 0; i < removed; ++i )
    {
        events[ i ].ident = static_cast<int>( entries[ i ].lpCompletionKey );
        for( const std::unique_ptr<DirectoryWatch>& watch : watcher->watches )
        {
            if( &watch->overlapped == entries[ i ].lpOverlapped && !armWatch( *watch ) )
            {
                return failLastError();   // this directory is no longer watched: the caller must assume change from now on
            }
        }
    }
    return static_cast<int>( removed );
}

// ── sockets ────────────────────────────────────────────────────────────────────────────────────────────────
// The structures call sites fill are os.h's Winsock-layout copies; they must match the SDK's exactly.
static_assert( sizeof( os::sockaddr ) == sizeof( ::sockaddr ) && sizeof( os::sockaddr_in ) == sizeof( ::sockaddr_in )
               && offsetof( os::sockaddr_in, sin_port ) == offsetof( ::sockaddr_in, sin_port )
               && offsetof( os::sockaddr_in, sin_addr ) == offsetof( ::sockaddr_in, sin_addr ) && sizeof( os::timeval ) == sizeof( ::timeval ) );

int socket( int domain, int type, int protocol )
{
    if( !winsockStarted() )
    {
        return fail( ENETDOWN );
    }
    UniqueSocket s( ::WSASocketW( domain, type, protocol, nullptr, 0, WSA_FLAG_OVERLAPPED | WSA_FLAG_NO_HANDLE_INHERIT ) );
    return s.valid() ? adoptSocket( std::move( s ) ) : failWsa();
}

// setsockopt: two options mean something different on Winsock, and the POSIX meaning is kept.
//   SO_REUSEADDR — POSIX lets a restarted listener rebind a port still in TIME_WAIT; Winsock lets a SECOND socket bind a
//     port this one is already listening on, so another local process could take --listen's port. The POSIX-safe
//     meaning on Windows is SO_EXCLUSIVEADDRUSE (and Windows never blocks a rebind on TIME_WAIT the way POSIX does).
//   SO_RCVTIMEO / SO_SNDTIMEO — POSIX takes a timeval, Winsock a DWORD of milliseconds in which 0 means forever; the
//     conversion rounds up, so the 10-second slow-loris guard stays 10 seconds and no nonzero timeout becomes infinite.
int setsockopt( int fd, int level, int name, const void* value, socklen_t length )
{
    const SOCKET s = socketOf( fd );
    if( s == INVALID_SOCKET )
    {
        return fail( EBADF );
    }
    if( level == SOL_SOCKET && name == SO_REUSEADDR && length == sizeof( int ) )
    {
        if( *static_cast<const int*>( value ) == 0 )
        {
            return 0;
        }
        const int exclusive = 1;
        return ::setsockopt( s, SOL_SOCKET, SO_EXCLUSIVEADDRUSE, reinterpret_cast<const char*>( &exclusive ), sizeof( exclusive ) ) == 0 ? 0 : failWsa();
    }
    if( level == SOL_SOCKET && ( name == SO_RCVTIMEO || name == SO_SNDTIMEO ) && length == sizeof( os::timeval ) )
    {
        const auto* const tv           = static_cast<const os::timeval*>( value );
        const DWORD       milliseconds = oswin::millisecondsFromTimeval( tv->tv_sec, tv->tv_usec );
        return ::setsockopt( s, level, name, reinterpret_cast<const char*>( &milliseconds ), sizeof( milliseconds ) ) == 0 ? 0 : failWsa();
    }
    return ::setsockopt( s, level, name, static_cast<const char*>( value ), length ) == 0 ? 0 : failWsa();
}

int bind( int fd, const sockaddr* address, socklen_t length )
{
    const SOCKET s = socketOf( fd );
    return s == INVALID_SOCKET ? fail( EBADF ) : ::bind( s, reinterpret_cast<const ::sockaddr*>( address ), length ) == 0 ? 0 : failWsa();
}

int listen( int fd, int backlog )
{
    const SOCKET s = socketOf( fd );
    return s == INVALID_SOCKET ? fail( EBADF ) : ::listen( s, backlog ) == 0 ? 0 : failWsa();
}

int accept( int fd, sockaddr* address, socklen_t* length )
{
    const SOCKET s = socketOf( fd );
    if( s == INVALID_SOCKET )
    {
        return fail( EBADF );
    }
    UniqueSocket client( ::accept( s, reinterpret_cast<::sockaddr*>( address ), length ) );
    if( !client.valid() )
    {
        return failWsa();   // WSAEINTR is EINTR, which the accept loop retries
    }
    (void)::SetHandleInformation( reinterpret_cast<HANDLE>( client.get() ), HANDLE_FLAG_INHERIT, 0 );
    return adoptSocket( std::move( client ) );
}

ssize_t recv( int fd, void* buf, std::size_t count, int flags )
{
    const SOCKET s = socketOf( fd );
    if( s == INVALID_SOCKET )
    {
        return fail( EBADF );
    }
    const int received = ::recv( s, static_cast<char*>( buf ), static_cast<int>( count > INT_MAX ? INT_MAX : count ), flags );
    return received == SOCKET_ERROR ? failWsa() : received;
}

ssize_t send( int fd, const void* buf, std::size_t count, int flags )
{
    const SOCKET s = socketOf( fd );
    if( s == INVALID_SOCKET )
    {
        return fail( EBADF );
    }
    const int sent = ::send( s, static_cast<const char*>( buf ), static_cast<int>( count > INT_MAX ? INT_MAX : count ), flags & ~MSG_NOSIGNAL );
    return sent == SOCKET_ERROR ? failWsa() : sent;
}

int inet_pton( int family, const char* text, void* address )
{
    if( !winsockStarted() )
    {
        return fail( ENETDOWN );
    }
    const INT converted = ::inet_pton( family, text, address );
    return converted < 0 ? failWsa() : converted;
}

// Winsock never raises SIGPIPE: nothing to switch off.
int setsockopt_nosigpipe( int, const void*, socklen_t ) { return 0; }

}   // namespace rw::os
