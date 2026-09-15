#include "platform_compat.h"

#if defined(_WIN32) || defined(_MSC_VER)

#include <cerrno>
#include <cstring>
#include <string>
#include <mutex>
#include <vector>

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

/// Resolves a Windows path through a handle so junctions and symbolic links are followed safely.
char* rw_realpath( const char* path, char* resolved_path ) noexcept
{
    if( path == nullptr || resolved_path == nullptr )
    {
        errno = EINVAL;
        return nullptr;
    }
    const std::string nativePath = rw_windows_path_from_msys( path );
    const std::wstring widePath = rw_utf8_to_wide( nativePath );
    if( widePath.empty() )
    {
        errno = EINVAL;
        return nullptr;
    }
    const HANDLE handle = ::CreateFileW( widePath.c_str(), FILE_READ_ATTRIBUTES,
                                         FILE_SHARE_READ | FILE_SHARE_WRITE | FILE_SHARE_DELETE, nullptr, OPEN_EXISTING,
                                         FILE_FLAG_BACKUP_SEMANTICS, nullptr );
    if( handle == INVALID_HANDLE_VALUE )
    {
        return nullptr;
    }
    std::wstring finalPath( PATH_MAX, L'\0' );
    DWORD length = ::GetFinalPathNameByHandleW( handle, finalPath.data(), static_cast<DWORD>( finalPath.size() ), FILE_NAME_NORMALIZED );
    if( length >= finalPath.size() )
    {
        finalPath.resize( static_cast<std::size_t>( length ) + 1 );
        length = ::GetFinalPathNameByHandleW( handle, finalPath.data(), static_cast<DWORD>( finalPath.size() ), FILE_NAME_NORMALIZED );
    }
    ::CloseHandle( handle );
    if( length == 0 || length >= finalPath.size() )
    {
        return nullptr;
    }
    finalPath.resize( length );
    if( finalPath.rfind( L"\\\\?\\UNC\\", 0 ) == 0 )
    {
        finalPath.erase( 0, 8 );
        finalPath.insert( 0, L"\\\\" );
    }
    else if( finalPath.rfind( L"\\\\?\\", 0 ) == 0 )
    {
        finalPath.erase( 0, 4 );
    }
    const std::string utf8Path = rw_wide_to_utf8( finalPath );
    if( utf8Path.empty() || utf8Path.size() + 1 > PATH_MAX )
    {
        errno = ENAMETOOLONG;
        return nullptr;
    }
    std::memcpy( resolved_path, utf8Path.c_str(), utf8Path.size() + 1 );
    return resolved_path;
}

namespace
{

std::string windowsBashPath()
{
    auto usable = []( const std::string& path )
    {
        if( path.empty() || GetFileAttributesA( path.c_str() ) == INVALID_FILE_ATTRIBUTES )
        {
            return false;
        }
        std::string lower = path;
        for( char& c : lower )
        {
            if( c >= 'A' && c <= 'Z' )
            {
                c = static_cast<char>( c - 'A' + 'a' );
            }
        }
        return lower.find( "\\windows\\system32\\bash.exe" ) == std::string::npos;
    };

    const char* envBash = std::getenv( "RW_BASH" );
    const char* programFiles = std::getenv( "ProgramFiles" );
    const char* programW6432  = std::getenv( "ProgramW6432" );
    const std::string pf      = programFiles != nullptr ? programFiles : "C:\\Program Files";
    const std::string pf6432  = programW6432 != nullptr ? programW6432 : pf;
    const std::string configuredBash = envBash != nullptr ? rw_windows_path_from_msys( envBash ) : std::string();
    const std::string choices[] = {
        configuredBash,
        pf + "\\Git\\usr\\bin\\bash.exe",
        pf6432 + "\\Git\\usr\\bin\\bash.exe",
        pf + "\\Git\\bin\\bash.exe",
        pf6432 + "\\Git\\bin\\bash.exe",
    };
    for( const std::string& choice : choices )
    {
        if( usable( choice ) )
        {
            return choice;
        }
    }
    return {};
}

std::vector<wchar_t> windowsGitEnvironment( const std::string& bash )
{
    std::vector<std::wstring> entries;
    LPWCH                       raw = ::GetEnvironmentStringsW();
    if( raw == nullptr )
    {
        return {};
    }
    for( const wchar_t* p = raw; *p != L'\0'; p += std::wcslen( p ) + 1 )
    {
        entries.emplace_back( p );
    }
    ::FreeEnvironmentStringsW( raw );

    std::wstring bashWide = rw_utf8_to_wide( bash );
    for( wchar_t& c : bashWide )
    {
        if( c == L'/' )
        {
            c = L'\\';
        }
    }
    const std::size_t slash = bashWide.find_last_of( L"\\/" );
    if( slash == std::wstring::npos )
    {
        return {};
    }
    const std::wstring gitBin = bashWide.substr( 0, slash );
    std::wstring       gitRoot = gitBin;
    if( gitBin.size() >= 8 && gitBin.compare( gitBin.size() - 8, 8, L"\\usr\\bin" ) == 0 )
    {
        gitRoot.resize( gitBin.size() - 8 );
    }
    else if( gitBin.size() >= 4 && gitBin.compare( gitBin.size() - 4, 4, L"\\bin" ) == 0 )
    {
        gitRoot.resize( gitBin.size() - 4 );
    }
    const std::wstring prefix = gitRoot + L"\\usr\\bin;" + gitRoot + L"\\bin;" + gitRoot + L"\\cmd;";

    bool pathFound = false;
    for( std::wstring& entry : entries )
    {
        if( entry.size() >= 5 && ( entry[ 0 ] == L'P' || entry[ 0 ] == L'p' ) && ( entry[ 1 ] == L'A' || entry[ 1 ] == L'a' )
            && ( entry[ 2 ] == L'T' || entry[ 2 ] == L't' ) && ( entry[ 3 ] == L'H' || entry[ 3 ] == L'h' )
            && entry[ 4 ] == L'=' )
        {
            entry     = L"PATH=" + entry.substr( 5 ) + L";" + prefix;
            pathFound = true;
        }
    }
    if( !pathFound )
    {
        entries.push_back( L"PATH=" + prefix );
    }

    std::size_t chars = 1;
    for( const std::wstring& entry : entries )
    {
        chars += entry.size() + 1;
    }
    std::vector<wchar_t> block;
    block.reserve( chars );
    for( const std::wstring& entry : entries )
    {
        block.insert( block.end(), entry.begin(), entry.end() );
        block.push_back( L'\0' );
    }
    block.push_back( L'\0' );
    return block;
}

std::string windowsToMsysPath( std::string path )
{
    if( path.rfind( "\\\\?\\", 0 ) == 0 )
    {
        path.erase( 0, 4 );
    }
    if( path.size() >= 2 && path[1] == ':' )
    {
        const char drive = static_cast<char>( path[0] >= 'A' && path[0] <= 'Z' ? path[0] - 'A' + 'a' : path[0] );
        std::string out = "/";
        out += drive;
        for( std::size_t i = 2; i < path.size(); ++i )
        {
            out += path[i] == '\\' ? '/' : path[i];
        }
        return out;
    }
    for( char& c : path )
    {
        if( c == '\\' )
        {
            c = '/';
        }
    }
    return path;
}

std::string windowsPathFromMsys( std::string_view path )
{
    if( path == "/tmp" || ( path.size() > 5 && path.substr( 0, 5 ) == "/tmp/" ) )
    {
        std::wstring tempPath( 32768, L'\0' );
        bool haveTempRoot = false;
        DWORD length = ::GetEnvironmentVariableW( L"RW_MSYS_TMP", tempPath.data(), static_cast<DWORD>( tempPath.size() ) );
        if( length > 0 && length < tempPath.size() )
        {
            tempPath.resize( length );
            haveTempRoot = true;
        }
        if( !haveTempRoot )
        {
            std::wstring localAppData( 32768, L'\0' );
            const DWORD localLength = ::GetEnvironmentVariableW( L"LOCALAPPDATA", localAppData.data(), static_cast<DWORD>( localAppData.size() ) );
            if( localLength > 0 && localLength < localAppData.size() )
            {
                localAppData.resize( localLength );
                tempPath = std::move( localAppData ) + L"\\Temp";
                haveTempRoot = true;
            }
        }
        if( !haveTempRoot )
        {
            length = ::GetTempPathW( static_cast<DWORD>( tempPath.size() ), tempPath.data() );
            if( length > 0 && length < tempPath.size() )
            {
                tempPath.resize( length );
                haveTempRoot = true;
            }
        }
        if( haveTempRoot )
        {
            std::string native = rw_wide_to_utf8( tempPath );
            while( !native.empty() && ( native.back() == '/' || native.back() == '\\' ) )
            {
                native.pop_back();
            }
            native.append( path.substr( 4 ) );
            return native;
        }
    }
    if( path.size() >= 3 && path[0] == '/' &&
        ( ( path[1] >= 'a' && path[1] <= 'z' ) || ( path[1] >= 'A' && path[1] <= 'Z' ) ) && path[2] == '/' )
    {
        std::string native;
        native.reserve( path.size() + 1 );
        native += path[1];
        native += ':';
        native.append( path.substr( 2 ) );
        return native;
    }
    return std::string( path );
}

std::string windowsShortPath( const std::string& path )
{
    const std::wstring widePath = rw_utf8_to_wide( path );
    if( widePath.empty() )
    {
        return path;
    }
    std::wstring buffer( 32768, L'\0' );
    const DWORD length = ::GetShortPathNameW( widePath.c_str(), buffer.data(), static_cast<DWORD>( buffer.size() ) );
    if( length > 0 && length < buffer.size() )
    {
        buffer.resize( length );
        const std::string utf8 = rw_wide_to_utf8( buffer );
        return utf8.empty() ? path : utf8;
    }
    return path;
}

bool writeCommandScript( const std::string& path, const std::string& command )
{
    const std::wstring widePath = rw_utf8_to_wide( path );
    if( widePath.empty() )
    {
        return false;
    }
    HANDLE hFile = CreateFileW( widePath.c_str(), GENERIC_WRITE, 0, nullptr, CREATE_ALWAYS, FILE_ATTRIBUTE_TEMPORARY, nullptr );
    if( hFile == INVALID_HANDLE_VALUE )
    {
        return false;
    }
    const std::string script = R"(trap 'rm -f -- "$0"' EXIT
)" + command + std::string( 1, char( 10 ) );
    DWORD written = 0;
    const BOOL ok = WriteFile( hFile, script.data(), static_cast<DWORD>( script.size() ), &written, nullptr );
    CloseHandle( hFile );
    return ok && written == script.size();
}

} // namespace

std::string rw_windows_path_from_msys( std::string_view path )
{
    return windowsPathFromMsys( path );
}

struct ChildPipeRecord
{
    std::FILE*  stream;
    HANDLE      process;
    std::wstring script;
};

static std::mutex                   s_child_pipe_mutex;
static std::vector<ChildPipeRecord> s_child_pipes;

/// Runs POSIX-shaped commands through Git Bash so quoting, pipes, redirects and Git's path grammar agree with Linux.
std::FILE* rw_popen( const char* command, const char* mode )
{
    if( command == nullptr || mode == nullptr )
    {
        return nullptr;
    }
    const std::string bash = windowsBashPath();
    if( bash.empty() )
    {
        errno = ENOENT;
        return nullptr;
    }

    std::wstring tempDir( 32768, L'\0' );
    const DWORD tempLength = ::GetTempPathW( static_cast<DWORD>( tempDir.size() ), tempDir.data() );
    if( tempLength == 0 || tempLength >= tempDir.size() )
    {
        return nullptr;
    }
    tempDir.resize( tempLength );
    std::wstring scriptWide( 32768, L'\0' );
    if( ::GetTempFileNameW( tempDir.c_str(), L"rwc", 0, scriptWide.data() ) == 0 )
    {
        return nullptr;
    }
    scriptWide.resize( std::wcslen( scriptWide.c_str() ) );
    const std::string script = rw_wide_to_utf8( scriptWide );
    if( script.empty() )
    {
        ::DeleteFileW( scriptWide.c_str() );
        errno = EILSEQ;
        return nullptr;
    }
    if( !writeCommandScript( script, command ) )
    {
        ::DeleteFileW( scriptWide.c_str() );
        return nullptr;
    }

    std::string winMode = mode;
    if( winMode == "r" )
    {
        winMode = "rb";
    }
    else if( winMode == "w" )
    {
        winMode = "wb";
    }

    // rw_system and popenTrimmed only need a read pipe. Keep the legacy write mode for callers that use it.
    if( mode[ 0 ] != 'r' )
    {
        const std::string launch = windowsShortPath( bash ) + " " + windowsToMsysPath( windowsShortPath( script ) );
        std::FILE*       pipe = _popen( launch.c_str(), winMode.c_str() );
        if( pipe == nullptr )
        {
            ::DeleteFileW( scriptWide.c_str() );
        }
        return pipe;
    }

    SECURITY_ATTRIBUTES security{ sizeof( SECURITY_ATTRIBUTES ), nullptr, TRUE };
    HANDLE               readHandle = nullptr;
    HANDLE               writeHandle = nullptr;
    if( !::CreatePipe( &readHandle, &writeHandle, &security, 0 ) )
    {
        ::DeleteFileW( scriptWide.c_str() );
        return nullptr;
    }
    if( !::SetHandleInformation( readHandle, HANDLE_FLAG_INHERIT, 0 ) )
    {
        ::CloseHandle( readHandle );
        ::CloseHandle( writeHandle );
        ::DeleteFileW( scriptWide.c_str() );
        return nullptr;
    }

    HANDLE childStdin = ::CreateFileW( L"NUL", GENERIC_READ, FILE_SHARE_READ | FILE_SHARE_WRITE, &security, OPEN_EXISTING,
                                       FILE_ATTRIBUTE_NORMAL, nullptr );
    if( childStdin == INVALID_HANDLE_VALUE )
    {
        ::CloseHandle( readHandle );
        ::CloseHandle( writeHandle );
        ::DeleteFileW( scriptWide.c_str() );
        return nullptr;
    }

    HANDLE childStderr = nullptr;
    const HANDLE parentStderr = ::GetStdHandle( STD_ERROR_HANDLE );
    if( parentStderr != nullptr && parentStderr != INVALID_HANDLE_VALUE )
    {
        ::DuplicateHandle( ::GetCurrentProcess(), parentStderr, ::GetCurrentProcess(), &childStderr, 0, TRUE,
                           DUPLICATE_SAME_ACCESS );
    }
    if( childStderr == nullptr )
    {
        childStderr = ::CreateFileW( L"NUL", GENERIC_WRITE, FILE_SHARE_READ | FILE_SHARE_WRITE, &security, OPEN_EXISTING,
                                     FILE_ATTRIBUTE_NORMAL, nullptr );
    }
    if( childStderr == INVALID_HANDLE_VALUE || childStderr == nullptr )
    {
        ::CloseHandle( childStdin );
        ::CloseHandle( readHandle );
        ::CloseHandle( writeHandle );
        ::DeleteFileW( scriptWide.c_str() );
        return nullptr;
    }

    STARTUPINFOEXW startup{};
    startup.StartupInfo.cb = sizeof( STARTUPINFOEXW );
    startup.StartupInfo.dwFlags = STARTF_USESTDHANDLES;
    startup.StartupInfo.hStdInput = childStdin;
    startup.StartupInfo.hStdOutput = writeHandle;
    startup.StartupInfo.hStdError = childStderr;

    SIZE_T attributeBytes = 0;
    ::InitializeProcThreadAttributeList( nullptr, 1, 0, &attributeBytes );
    auto* attributes = static_cast<LPPROC_THREAD_ATTRIBUTE_LIST>( ::HeapAlloc( ::GetProcessHeap(), 0, attributeBytes ) );
    if( attributes == nullptr || !::InitializeProcThreadAttributeList( attributes, 1, 0, &attributeBytes ) )
    {
        if( attributes != nullptr )
        {
            ::HeapFree( ::GetProcessHeap(), 0, attributes );
        }
        ::CloseHandle( childStderr );
        ::CloseHandle( childStdin );
        ::CloseHandle( readHandle );
        ::CloseHandle( writeHandle );
        ::DeleteFileW( scriptWide.c_str() );
        return nullptr;
    }

    HANDLE inheritedHandles[] = { childStdin, writeHandle, childStderr };
    const BOOL handlesUpdated = ::UpdateProcThreadAttribute( attributes, 0, PROC_THREAD_ATTRIBUTE_HANDLE_LIST,
                                                              inheritedHandles, sizeof( inheritedHandles ), nullptr, nullptr );
    startup.lpAttributeList = attributes;

    const std::wstring bashWide = rw_utf8_to_wide( windowsShortPath( bash ) );
    const std::wstring scriptArgument = rw_utf8_to_wide( windowsToMsysPath( windowsShortPath( script ) ) );
    std::wstring       launch = L"\"" + bashWide + L"\" \"" + scriptArgument + L"\"";
    std::vector<wchar_t> commandLine( launch.begin(), launch.end() );
    commandLine.push_back( L'\0' );
    std::vector<wchar_t> childEnvironment = windowsGitEnvironment( bash );
    PROCESS_INFORMATION processInfo{};
    const BOOL processCreated = handlesUpdated && !bashWide.empty() && !scriptArgument.empty()
                              && ::CreateProcessW( bashWide.c_str(), commandLine.data(), nullptr, nullptr, TRUE,
                                                   EXTENDED_STARTUPINFO_PRESENT | CREATE_UNICODE_ENVIRONMENT,
                                                   childEnvironment.empty() ? nullptr : childEnvironment.data(), nullptr,
                                                   &startup.StartupInfo, &processInfo );
    ::DeleteProcThreadAttributeList( attributes );
    ::HeapFree( ::GetProcessHeap(), 0, attributes );
    ::CloseHandle( childStdin );
    ::CloseHandle( writeHandle );
    ::CloseHandle( childStderr );

    if( !processCreated )
    {
        ::CloseHandle( readHandle );
        ::DeleteFileW( scriptWide.c_str() );
        return nullptr;
    }
    ::CloseHandle( processInfo.hThread );

    const int fd = ::_open_osfhandle( reinterpret_cast<intptr_t>( readHandle ), _O_RDONLY | _O_BINARY );
    if( fd < 0 )
    {
        ::TerminateProcess( processInfo.hProcess, ERROR_OPERATION_ABORTED );
        ::WaitForSingleObject( processInfo.hProcess, INFINITE );
        ::CloseHandle( processInfo.hProcess );
        ::CloseHandle( readHandle );
        ::DeleteFileW( scriptWide.c_str() );
        return nullptr;
    }
    std::FILE* pipe = ::_fdopen( fd, "rb" );
    if( pipe == nullptr )
    {
        ::_close( fd );
        ::TerminateProcess( processInfo.hProcess, ERROR_OPERATION_ABORTED );
        ::WaitForSingleObject( processInfo.hProcess, INFINITE );
        ::CloseHandle( processInfo.hProcess );
        ::DeleteFileW( scriptWide.c_str() );
        return nullptr;
    }

    {
        std::lock_guard<std::mutex> lock( s_child_pipe_mutex );
        s_child_pipes.push_back( ChildPipeRecord{ pipe, processInfo.hProcess, scriptWide } );
    }
    return pipe;
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
    ChildPipeRecord record{};
    bool             childPipe = false;
    {
        std::lock_guard<std::mutex> lock( s_child_pipe_mutex );
        for( auto it = s_child_pipes.begin(); it != s_child_pipes.end(); ++it )
        {
            if( it->stream == stream )
            {
                record = *it;
                s_child_pipes.erase( it );
                childPipe = true;
                break;
            }
        }
    }
    if( !childPipe )
    {
        return _pclose( stream );
    }

    std::fclose( stream );
    const DWORD waitResult = ::WaitForSingleObject( record.process, INFINITE );
    DWORD       exitCode = 1;
    if( waitResult == WAIT_OBJECT_0 )
    {
        ::GetExitCodeProcess( record.process, &exitCode );
    }
    ::CloseHandle( record.process );
    ::DeleteFileW( record.script.c_str() );
    return waitResult == WAIT_OBJECT_0 ? static_cast<int>( exitCode ) : -1;
}

/// Executes a POSIX-shaped command through the same bridge as rw_popen and drains its output before closing it.
int rw_system( const char* command ) noexcept
{
    std::FILE* pipe = rw_popen( command, "r" );
    if( pipe == nullptr )
    {
        return -1;
    }
    char buffer[4096];
    while( std::fread( buffer, 1, sizeof( buffer ), pipe ) > 0 )
    {
    }
    return rw_pclose( pipe );
}

/// Returns the absolute UTF-8 path of the running executable when Windows can provide it.
std::string rw_self_exe_path()
{
    std::wstring buffer( 32768, wchar_t( 0 ) );
    const DWORD len = GetModuleFileNameW( nullptr, buffer.data(), static_cast<DWORD>( buffer.size() ) );
    if( len == 0 || len >= buffer.size() )
    {
        return {};
    }
    return rw_wide_to_utf8( std::wstring_view( buffer.data(), len ) );
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

struct MemStreamRecord
{
    std::FILE*    stream;
    MemStreamInfo info;
};

static std::mutex                   s_memstream_mutex;
static std::vector<MemStreamRecord> s_memstreams;

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
    s_memstreams.push_back( MemStreamRecord{ fp, MemStreamInfo{ bufloc, sizeloc } } );
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
    MemStreamInfo*             info = nullptr;
    for( auto& record : s_memstreams )
    {
        if( record.stream == stream )
        {
            info = &record.info;
            break;
        }
    }
    if( info != nullptr )
    {
        auto& streamInfo = *info;
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

        char* newBuf = static_cast<char*>( std::realloc( *streamInfo.bufloc, len + 1 ) );
        if( newBuf )
        {
            size_t readBytes = 0;
            if( len > 0 )
            {
                readBytes = std::fread( newBuf, 1, len, stream );
            }
            newBuf[readBytes]     = '\0';
            *streamInfo.bufloc    = newBuf;
            *streamInfo.sizeloc   = readBytes;
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
        for( auto it = s_memstreams.begin(); it != s_memstreams.end(); ++it )
        {
            if( it->stream == stream )
            {
                info  = it->info;
                isMem = true;
                s_memstreams.erase( it );
                break;
            }
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
