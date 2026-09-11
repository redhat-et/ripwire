#include "platform_compat.h"

#if defined(_WIN32) || defined(_MSC_VER)

#include <cerrno>
#include <cstring>
#include <string>
#include <mutex>
#include <unordered_map>

#ifdef fclose
  #undef fclose
#endif
#ifdef fflush
  #undef fflush
#endif
#ifdef open_memstream
  #undef open_memstream
#endif
#ifdef close
  #undef close
#endif

namespace rw::compat
{

/// Maps POSIX advisory locking flags to Win32 byte-range locks and reports failures through errno.
int rw_flock( int fd, int operation ) noexcept
{
    HANDLE hFile = reinterpret_cast<HANDLE>( _get_osfhandle( fd ) );
    if( hFile == INVALID_HANDLE_VALUE )
    {
        errno = EBADF;
        return -1;
    }

    if( operation & LOCK_UN )
    {
        OVERLAPPED ov{};
        const BOOL ok = UnlockFileEx( hFile, 0, MAXDWORD, MAXDWORD, &ov );
        if( !ok )
        {
            errno = EINVAL;
            return -1;
        }
        return 0;
    }

    DWORD flags = 0;
    if( operation & LOCK_NB )
    {
        flags |= LOCKFILE_FAIL_IMMEDIATELY;
    }
    if( operation & LOCK_EX )
    {
        flags |= LOCKFILE_EXCLUSIVE_LOCK;
    }

    OVERLAPPED ov{};
    const BOOL ok = LockFileEx( hFile, flags, 0, MAXDWORD, MAXDWORD, &ov );
    if( !ok )
    {
        const DWORD err = GetLastError();
        if( err == ERROR_LOCK_VIOLATION )
        {
            errno = EWOULDBLOCK;
        }
        else
        {
            errno = EACCES;
        }
        return -1;
    }
    return 0;
}

/// Reads a byte range at an explicit offset without changing the descriptor's shared file position.
ssize_t rw_pread( int fd, void* buf, std::size_t count, std::uint64_t offset ) noexcept
{
    HANDLE hFile = reinterpret_cast<HANDLE>( _get_osfhandle( fd ) );
    if( hFile == INVALID_HANDLE_VALUE )
    {
        errno = EBADF;
        return -1;
    }

    OVERLAPPED ov{};
    ov.Offset     = static_cast<DWORD>( offset & 0xFFFFFFFFull );
    ov.OffsetHigh = static_cast<DWORD>( ( offset >> 32 ) & 0xFFFFFFFFull );

    DWORD bytesRead = 0;
    const BOOL ok = ReadFile( hFile, buf, static_cast<DWORD>( count ), &bytesRead, &ov );
    if( !ok )
    {
        const DWORD err = GetLastError();
        if( err == ERROR_HANDLE_EOF )
        {
            return 0;
        }
        errno = EIO;
        return -1;
    }
    return static_cast<ssize_t>( bytesRead );
}

/// Resolves a Windows path through the CRT equivalent of POSIX realpath.
char* rw_realpath( const char* path, char* resolved_path ) noexcept
{
    if( path == nullptr )
    {
        errno = EINVAL;
        return nullptr;
    }
    return _fullpath( resolved_path, path, PATH_MAX );
}

/// Runs a shell command with binary pipes and translates POSIX null-device redirection to Windows NUL.
std::FILE* rw_popen( const char* command, const char* mode )
{
    if( command == nullptr || mode == nullptr )
    {
        return nullptr;
    }

    std::string cmd = command;
    // Replace POSIX /dev/null redirection with Windows NUL
    const std::string devNull = "/dev/null";
    std::size_t pos = 0;
    while( ( pos = cmd.find( devNull, pos ) ) != std::string::npos )
    {
        cmd.replace( pos, devNull.length(), "NUL" );
        pos += 3;
    }

    // Windows popen in text mode ("r") translates CRLF -> LF and truncates at ^Z (0x1A),
    // corrupting binary streams and git cat-file batches. Force binary mode to match POSIX.
    std::string winMode = mode;
    if( winMode == "r" )
    {
        winMode = "rb";
    }
    else if( winMode == "w" )
    {
        winMode = "wb";
    }

    return _popen( cmd.c_str(), winMode.c_str() );
}

/// Returns an 8.3 path suitable for cmd.exe redirection, or the normalized input when conversion fails.
std::string rw_short_path( const std::string& path )
{
    if( path.empty() )
    {
        return path;
    }
    std::string winPath = path;
    for( char& c : winPath )
    {
        if( c == '/' )
        {
            c = '\\';
        }
    }
    char buf[MAX_PATH];
    const DWORD len = GetShortPathNameA( winPath.c_str(), buf, MAX_PATH );
    if( len > 0 && len < MAX_PATH )
    {
        return std::string( buf, len );
    }
    return winPath;
}

/// Closes a command pipe opened by rw_popen and returns the child-process status.
int rw_pclose( std::FILE* stream )
{
    if( stream == nullptr )
    {
        return -1;
    }
    return _pclose( stream );
}

/// Returns the absolute path of the running executable when Windows can provide it.
std::string rw_self_exe_path()
{
    char buf[MAX_PATH];
    const DWORD len = GetModuleFileNameA( nullptr, buf, MAX_PATH );
    if( len > 0 && len < MAX_PATH )
    {
        return std::string( buf, len );
    }
    return {};
}

struct pollfd;
/// Polls inherited Windows pipe handles until input, hangup, an invalid descriptor, or the deadline is seen.
int rw_poll( struct pollfd* fds, unsigned long nfds, int timeout )
{
    if( fds == nullptr || nfds == 0 )
    {
        if( timeout > 0 )
        {
            Sleep( static_cast<DWORD>( timeout ) );
        }
        return 0;
    }

    struct WinPollFd
    {
        int   fd;
        short events;
        short revents;
    };
    auto* pfds = reinterpret_cast<WinPollFd*>( fds );

    const DWORD start = GetTickCount();
    for( ;; )
    {
        int ready = 0;
        for( unsigned long i = 0; i < nfds; ++i )
        {
            pfds[i].revents = 0;
            HANDLE h = reinterpret_cast<HANDLE>( _get_osfhandle( pfds[i].fd ) );
            if( h == INVALID_HANDLE_VALUE )
            {
                pfds[i].revents = 0x0020; // POLLNVAL
                ready++;
                continue;
            }
            DWORD bytesAvail = 0;
            if( PeekNamedPipe( h, nullptr, 0, nullptr, &bytesAvail, nullptr ) )
            {
                if( bytesAvail > 0 )
                {
                    pfds[i].revents |= 0x0001; // POLLIN
                    ready++;
                }
            }
            else
            {
                const DWORD err = GetLastError();
                if( err == ERROR_BROKEN_PIPE || err == ERROR_HANDLE_EOF )
                {
                    pfds[i].revents |= 0x0010; // POLLHUP
                    ready++;
                }
            }
        }
        if( ready > 0 )
        {
            return ready;
        }
        if( timeout >= 0 )
        {
            const DWORD elapsed = GetTickCount() - start;
            if( elapsed >= static_cast<DWORD>( timeout ) )
            {
                return 0;
            }
        }
        Sleep( 5 );
    }
}

struct MemStreamInfo
{
    char**       bufloc;
    std::size_t* sizeloc;
};

static std::mutex                                     s_memstream_mutex;
static std::unordered_map<std::FILE*, MemStreamInfo> s_memstreams;

/// Creates a temporary-file-backed stream with the open_memstream ownership contract.
std::FILE* rw_open_memstream( char** bufloc, std::size_t* sizeloc )
{
    if( bufloc == nullptr || sizeloc == nullptr )
    {
        errno = EINVAL;
        return nullptr;
    }

    char tempPath[MAX_PATH];
    if( GetTempPathA( MAX_PATH, tempPath ) == 0 )
    {
        return nullptr;
    }

    char tempFileName[MAX_PATH];
    if( GetTempFileNameA( tempPath, "rwm", 0, tempFileName ) == 0 )
    {
        return nullptr;
    }

    HANDLE hFile = CreateFileA(
        tempFileName,
        GENERIC_READ | GENERIC_WRITE,
        FILE_SHARE_READ | FILE_SHARE_WRITE | FILE_SHARE_DELETE,
        nullptr,
        CREATE_ALWAYS,
        FILE_ATTRIBUTE_TEMPORARY | FILE_FLAG_DELETE_ON_CLOSE,
        nullptr
    );
    if( hFile == INVALID_HANDLE_VALUE )
    {
        return nullptr;
    }

    int fd = _open_osfhandle( reinterpret_cast<intptr_t>( hFile ), _O_RDWR | _O_BINARY );
    if( fd == -1 )
    {
        CloseHandle( hFile );
        return nullptr;
    }

    std::FILE* fp = _fdopen( fd, "w+b" );
    if( !fp )
    {
        _close( fd );
        return nullptr;
    }

    *bufloc = static_cast<char*>( std::malloc( 1 ) );
    if( *bufloc )
    {
        ( *bufloc )[0] = '\0';
    }
    *sizeloc = 0;

    std::lock_guard<std::mutex> lock( s_memstream_mutex );
    s_memstreams[fp] = MemStreamInfo{ bufloc, sizeloc };
    return fp;
}

/// Flushes a compatibility memory stream and refreshes its caller-owned buffer and byte count.
int rw_fflush( std::FILE* stream )
{
    if( stream == nullptr )
    {
        return 0;
    }

    std::lock_guard<std::mutex> lock( s_memstream_mutex );
    auto it = s_memstreams.find( stream );
    if( it != s_memstreams.end() )
    {
        auto& info = it->second;
        const int flushRes = ::fflush( stream );
        if( flushRes != 0 )
        {
            return flushRes;
        }
        long currentPos = std::ftell( stream );
        std::fseek( stream, 0, SEEK_END );
        long len = std::ftell( stream );
        if( len < 0 )
        {
            len = 0;
        }
        std::fseek( stream, 0, SEEK_SET );

        char* newBuf = static_cast<char*>( std::realloc( *info.bufloc, len + 1 ) );
        if( newBuf )
        {
            size_t readBytes = 0;
            if( len > 0 )
            {
                readBytes = std::fread( newBuf, 1, len, stream );
            }
            newBuf[readBytes] = '\0';
            *info.bufloc      = newBuf;
            *info.sizeloc     = readBytes;
        }
        std::fseek( stream, currentPos, SEEK_SET );
        return 0;
    }
    return ::fflush( stream );
}

/// Flushes and closes a compatibility memory stream, publishing its final buffer before release.
int rw_fclose( std::FILE* stream )
{
    if( stream == nullptr )
    {
        return 0;
    }

    MemStreamInfo info{};
    bool          isMem = false;
    {
        std::lock_guard<std::mutex> lock( s_memstream_mutex );
        auto it = s_memstreams.find( stream );
        if( it != s_memstreams.end() )
        {
            info  = it->second;
            isMem = true;
            s_memstreams.erase( it );
        }
    }

    if( isMem )
    {
        const int flushRes = ::fflush( stream );
        if( flushRes != 0 )
        {
            ::fclose( stream );
            return flushRes;
        }
        std::fseek( stream, 0, SEEK_END );
        long len = std::ftell( stream );
        if( len < 0 )
        {
            len = 0;
        }
        std::fseek( stream, 0, SEEK_SET );

        char* newBuf = static_cast<char*>( std::realloc( *info.bufloc, len + 1 ) );
        if( newBuf )
        {
            size_t readBytes = 0;
            if( len > 0 )
            {
                readBytes = std::fread( newBuf, 1, len, stream );
            }
            newBuf[readBytes] = '\0';
            *info.bufloc      = newBuf;
            *info.sizeloc     = readBytes;
        }
        return ::fclose( stream );
    }

    return ::fclose( stream );
}

/// Closes a CRT file descriptor without confusing it with a Winsock SOCKET.
int rw_close( int fd )
{
    if( fd < 0 )
    {
        return -1;
    }
    return _close( fd );
}

struct WinsockAutoInit
{
    /// Initializes Winsock for the process before any socket compatibility wrapper is used.
    WinsockAutoInit()
    {
        WSADATA d;
        WSAStartup( MAKEWORD( 2, 2 ), &d );
    }
    /// Balances the process-wide Winsock initialization at normal process teardown.
    ~WinsockAutoInit()
    {
        WSACleanup();
    }
};
static WinsockAutoInit s_winsockAutoInit;

} // namespace rw::compat

#endif
