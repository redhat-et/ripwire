#pragma once

#if defined(_WIN32) || defined(_MSC_VER)

  #ifndef _CRT_SECURE_NO_WARNINGS
    #define _CRT_SECURE_NO_WARNINGS
  #endif
  #ifndef _CRT_NONSTDC_NO_DEPRECATE
    #define _CRT_NONSTDC_NO_DEPRECATE
  #endif

  #ifndef WIN32_LEAN_AND_MEAN
    #define WIN32_LEAN_AND_MEAN
  #endif
  #ifndef NOMINMAX
    #define NOMINMAX
  #endif

  #include <winsock2.h>
  #include <ws2tcpip.h>
  #include <windows.h>
  #ifdef near
    #undef near
  #endif
  #ifdef far
    #undef far
  #endif

  #include <io.h>
  #include <direct.h>
  #include <process.h>
  #include <basetsd.h>
  #include <fcntl.h>
  #include <sys/stat.h>
  #include <stdio.h>
  #include <cstdio>
  #include <stdlib.h>

  #ifndef PATH_MAX
    #define PATH_MAX 4096
  #endif

  #ifndef O_CLOEXEC
    #ifdef _O_NOINHERIT
      #define O_CLOEXEC _O_NOINHERIT
    #else
      #define O_CLOEXEC 0
    #endif
  #endif

  // The upstream code uses POSIX descriptor calls for bounded regular-file reads. Keep the calls available
  // on MSVC through the CRT, but do not invent an O_NOFOLLOW value: pathguard.h has the real Win32
  // FILE_FLAG_OPEN_REPARSE_POINT implementation for the security-sensitive opens.
  #ifndef O_NONBLOCK
    #define O_NONBLOCK 0
  #endif
  #ifndef F_GETFL
    #define F_GETFL 3
  #endif
  #ifndef F_SETFL
    #define F_SETFL 4
  #endif
  #ifndef open
    #define open _open
  #endif
  #ifndef fdopen
    #define fdopen _fdopen
  #endif
  #ifndef S_ISREG
    #define S_ISREG(m) (((m) & S_IFMT) == S_IFREG)
  #endif
  #ifndef S_ISDIR
    #define S_ISDIR(m) (((m) & S_IFMT) == S_IFDIR)
  #endif
  #ifndef S_ISLNK
    #define S_ISLNK(m) 0
  #endif

  #ifndef LOCK_SH
    #define LOCK_SH 1
    #define LOCK_EX 2
    #define LOCK_NB 4
    #define LOCK_UN 8
  #endif

#ifdef __cplusplus

  #include <cstddef>
  #include <cstdint>
  #include <cerrno>
  #include <string>
  #include <string_view>
  #include <thread>

  namespace rw::compat
  {
  /// Returns the processors this process can actually run on, not just the machine total.
  /// Windows' std::thread::hardware_concurrency() reports the system count even after a caller
  /// narrows the process affinity mask; using it for worker pools silently oversubscribes constrained
  /// jobs and makes Windows measurements incomparable with a cgroup-limited POSIX process.
  inline unsigned rw_effective_hardware_concurrency() noexcept
  {
#if defined( _WIN32 )
      DWORD_PTR processMask = 0;
      DWORD_PTR systemMask  = 0;
      if( ::GetProcessAffinityMask( ::GetCurrentProcess(), &processMask, &systemMask ) && processMask != 0 )
      {
          unsigned count = 0;
          for( DWORD_PTR mask = processMask; mask != 0; mask >>= 1 )
          {
              count += static_cast<unsigned>( mask & 1u );
          }
          if( count != 0 )
          {
              return count;
          }
      }
#endif
      const unsigned hardware = std::thread::hardware_concurrency();
      return hardware == 0 ? 1u : hardware;
  }

  std::string rw_windows_path_from_msys( std::string_view path );

  // Git Bash can pass a drive-rooted option value as /c/... even when the caller
  // launches the native executable. The parser keeps string_views into argv, so
  // normalize only the equal-length drive prefix in place; longer /tmp mappings
  // are handled by the caller's native temporary directory.
  inline void rw_normalize_msys_drive_paths_in_place( char* text ) noexcept
  {
#if defined( _WIN32 )
      if( text == nullptr )
      {
          return;
      }
      for( char* p = text; *p != 0; ++p )
      {
          const bool boundary = ( p == text || p[ -1 ] == ',' || p[ -1 ] == ':' );
          const char drive = p[ 1 ];
          const bool driveLetter = ( drive >= 'a' && drive <= 'z' ) || ( drive >= 'A' && drive <= 'Z' );
          if( boundary && p[ 0 ] == '/' && driveLetter && ( p[ 2 ] == '/' || p[ 2 ] == 0 ) )
          {
              p[ 0 ] = drive >= 'a' && drive <= 'z' ? static_cast<char>( drive - ( 'a' - 'A' ) ) : drive;
              p[ 1 ] = ':';
          }
      }
#else
      (void)text;
#endif
  }

  /// Converts the application's UTF-8 paths to the native Windows wide spelling.
  /// Invalid UTF-8 falls back to the active code page to preserve the CRT's historical behavior.
  inline std::wstring rw_utf8_to_wide( std::string_view text )
  {
      if( text.empty() )
      {
          return {};
      }
      const int utf8Length = ::MultiByteToWideChar( CP_UTF8, MB_ERR_INVALID_CHARS, text.data(), static_cast<int>( text.size() ), nullptr, 0 );
      const UINT codePage = utf8Length > 0 ? CP_UTF8 : CP_ACP;
      const DWORD flags = utf8Length > 0 ? MB_ERR_INVALID_CHARS : 0;
      const int length = ::MultiByteToWideChar( codePage, flags, text.data(), static_cast<int>( text.size() ), nullptr, 0 );
      if( length <= 0 )
      {
          return {};
      }
      std::wstring result( static_cast<std::size_t>( length ), L'\0' );
      if( ::MultiByteToWideChar( codePage, flags, text.data(), static_cast<int>( text.size() ), result.data(), length ) != length )
      {
          return {};
      }
      return result;
  }

  inline std::string rw_wide_to_utf8( std::wstring_view text )
  {
      if( text.empty() )
      {
          return {};
      }
      const int length = ::WideCharToMultiByte( CP_UTF8, WC_ERR_INVALID_CHARS, text.data(), static_cast<int>( text.size() ), nullptr, 0, nullptr, nullptr );
      if( length <= 0 )
      {
          return {};
      }
      std::string result( static_cast<std::size_t>( length ), '\0' );
      if( ::WideCharToMultiByte( CP_UTF8, WC_ERR_INVALID_CHARS, text.data(), static_cast<int>( text.size() ), result.data(), length, nullptr, nullptr ) != length )
      {
          return {};
      }
      return result;
  }

  /// Opens a UTF-8 path using the native wide CRT on Windows, after accepting Git Bash's /drive and /tmp spellings.
  inline std::FILE* rw_fopen_utf8( std::string_view path, std::string_view mode )
  {
      const std::wstring widePath = rw_utf8_to_wide( rw_windows_path_from_msys( path ) );
      const std::wstring wideMode = rw_utf8_to_wide( mode );
      return widePath.empty() || wideMode.empty() ? nullptr : ::_wfopen( widePath.c_str(), wideMode.c_str() );
  }

  struct RwFileTimes
  {
      long long mtimeNs;
      long long sizeBytes;
      long long changeTimeNs;
  };

  /// Reads the Windows file size, write time and change time through one native handle.
  inline RwFileTimes rw_file_times_of( const std::string& path ) noexcept
  {
      const std::wstring widePath = rw_utf8_to_wide( rw_windows_path_from_msys( path ) );
      if( widePath.empty() )
      {
          return { -1, -1, -1 };
      }
      const HANDLE handle = ::CreateFileW( widePath.c_str(), FILE_READ_ATTRIBUTES,
                                           FILE_SHARE_READ | FILE_SHARE_WRITE | FILE_SHARE_DELETE, nullptr, OPEN_EXISTING,
                                           FILE_FLAG_BACKUP_SEMANTICS, nullptr );
      if( handle == INVALID_HANDLE_VALUE )
      {
          return { -1, -1, -1 };
      }
      FILE_BASIC_INFO basic{};
      FILE_STANDARD_INFO standard{};
      const bool ok = ::GetFileInformationByHandleEx( handle, FileBasicInfo, &basic, sizeof( basic ) ) != 0
                   && ::GetFileInformationByHandleEx( handle, FileStandardInfo, &standard, sizeof( standard ) ) != 0;
      ::CloseHandle( handle );
      if( !ok )
      {
          return { -1, -1, -1 };
      }
      constexpr long long kWindowsToUnixEpoch100ns = 116444736000000000LL;
      const auto toUnixNs = []( LARGE_INTEGER value ) noexcept -> long long
      {
          if( value.QuadPart < kWindowsToUnixEpoch100ns )
          {
              return -1;
          }
          return ( value.QuadPart - kWindowsToUnixEpoch100ns ) * 100LL;
      };
      return { toUnixNs( basic.LastWriteTime ), standard.EndOfFile.QuadPart, toUnixNs( basic.ChangeTime ) };
  }

  /// Keeps XML/stdout byte streams from receiving CRT newline translation on Windows.
  inline void rw_set_stdout_binary() noexcept
  {
      (void)::_setmode( ::_fileno( stdout ), _O_BINARY );
      (void)::_setmode( ::_fileno( stderr ), _O_BINARY );
  }
  }

  /// MSVC's _fstat64 uses its private _stat64 layout, while the portable sources expose struct stat.
  /// Copy the fields consumed by the descriptor callers instead of aliasing incompatible objects.
  inline int rw_fstat( int fd, struct stat* out ) noexcept
  {
      struct _stat64 native{};
      if( ::_fstat64( fd, &native ) != 0 )
      {
          return -1;
      }
      out->st_mode = native.st_mode;
      out->st_size = native.st_size;
      return 0;
  }
  #ifndef fstat
    #define fstat rw_fstat
  #endif

  /// Regular Windows files never expose POSIX descriptor status flags; the SCIP reader only uses these
  /// operations to clear O_NONBLOCK after its non-blocking probe, so both operations are safe no-ops.
  inline int rw_fcntl( int, int command, int /*flags*/ = 0 ) noexcept
  {
      if( command == F_GETFL || command == F_SETFL )
      {
          return 0;
      }
      errno = EINVAL;
      return -1;
  }
  #ifndef fcntl
    #define fcntl rw_fcntl
  #endif

  using ssize_t = SSIZE_T;

  namespace rw::compat
  {
      int rw_flock( int fd, int operation ) noexcept;
      ssize_t rw_pread( int fd, void* buf, std::size_t count, std::uint64_t offset ) noexcept;
      char* rw_realpath( const char* path, char* resolved_path ) noexcept;
      std::FILE* rw_popen( const char* command, const char* mode );
      int rw_pclose( std::FILE* stream );
      int rw_system( const char* command ) noexcept;
      std::string rw_self_exe_path();
      std::FILE* rw_open_memstream( char** bufloc, std::size_t* sizeloc );
      int rw_fclose( std::FILE* stream );
      int rw_fflush( std::FILE* stream );
      int rw_close( int fd );
      std::string rw_short_path( const std::string& path );

      /// Publishes a replacement file with bounded retries for transient Windows sharing violations.
      inline int rw_rename( const char* oldname, const char* newname )
      {
          const std::wstring wideOldName = rw_utf8_to_wide( rw_windows_path_from_msys( oldname ? oldname : "" ) );
          const std::wstring wideNewName = rw_utf8_to_wide( rw_windows_path_from_msys( newname ? newname : "" ) );
          if( wideOldName.empty() || wideNewName.empty() )
          {
              errno = EINVAL;
              return -1;
          }
          for( int attempt = 0; attempt < 8; ++attempt )
          {
              if( MoveFileExW( wideOldName.c_str(), wideNewName.c_str(), MOVEFILE_REPLACE_EXISTING | MOVEFILE_COPY_ALLOWED ) )
              {
                  return 0;
              }
              const DWORD err = GetLastError();
              if( err != ERROR_ACCESS_DENIED && err != ERROR_SHARING_VIOLATION )
              {
                  break;
              }
              Sleep( 5 );
          }
          return -1;
      }

      inline int rw_remove_utf8( std::string_view path )
      {
          const std::wstring widePath = rw_utf8_to_wide( rw_windows_path_from_msys( path ) );
          return widePath.empty() ? -1 : ::_wremove( widePath.c_str() );
      }
  }

  namespace std
  {
      using rw::compat::rw_fclose;
      using rw::compat::rw_fflush;
      using rw::compat::rw_rename;
  }

  using rw::compat::rw_fclose;
  using rw::compat::rw_fflush;
  using rw::compat::rw_close;
  using rw::compat::rw_rename;
  using rw::compat::rw_short_path;

  #ifndef rename
    #define rename rw_rename
  #endif

  // Transparent polyfills for POSIX symbols called as ::popen, ::pread, etc.
  #ifndef popen
    #define popen rw::compat::rw_popen
  #endif
  #ifndef pclose
    #define pclose rw::compat::rw_pclose
  #endif
  #ifndef pread
    #define pread rw::compat::rw_pread
  #endif
  #ifndef realpath
    #define realpath rw::compat::rw_realpath
  #endif
  #ifndef flock
    #define flock rw::compat::rw_flock
  #endif
  #ifndef open_memstream
    #define open_memstream rw::compat::rw_open_memstream
  #endif
  #ifndef fclose
    #define fclose rw_fclose
  #endif
  #ifndef fflush
    #define fflush rw_fflush
  #endif
  /// Closes a CRT descriptor while preserving the separate SOCKET close path.
  inline int close( int fd )
  {
      return rw::compat::rw_close( fd );
  }

  #include <ctime>
  /// Fills a caller-provided tm with local time using the thread-safe MSVC API.
  inline struct tm* rw_localtime_r( const time_t* timer, struct tm* buf ) noexcept
  {
      return localtime_s( buf, timer ) == 0 ? buf : nullptr;
  }
  /// Fills a caller-provided tm with UTC time using the thread-safe MSVC API.
  inline struct tm* rw_gmtime_r( const time_t* timer, struct tm* buf ) noexcept
  {
      return gmtime_s( buf, timer ) == 0 ? buf : nullptr;
  }
  #ifndef localtime_r
    #define localtime_r rw_localtime_r
  #endif
  #ifndef gmtime_r
    #define gmtime_r rw_gmtime_r
  #endif

  /// Adapts POSIX directory creation to the CRT while intentionally ignoring POSIX mode bits.
  inline int mkdir( const char* path, int /*mode*/ )
  {
      return _mkdir( path );
  }

  /// Provides the lstat shape used by the POSIX code through the CRT stat result.
  inline int lstat( const char* path, struct stat* buf )
  {
      return ::stat( path, buf );
  }

  /// Supplies the stable non-root identity used by cache-path code on Windows.
  inline unsigned int getuid() noexcept
  {
      return 1000;
  }

  /// Sleeps for the requested POSIX timespec duration and preserves the zero-success convention.
  inline int nanosleep( const struct timespec* req, struct timespec* /*rem*/ ) noexcept
  {
      if( req )
      {
          DWORD ms = static_cast<DWORD>( req->tv_sec * 1000 + ( req->tv_nsec + 999999 ) / 1000000 );
          Sleep( ms );
      }
      return 0;
  }

  /// Keeps the POSIX permission call harmless where Windows descriptors use a different model.
  inline int fchmod( int /*fd*/, int /*mode*/ ) noexcept
  {
      return 0;
  }

  /// Flushes a Windows CRT descriptor to the underlying file through _commit.
  inline int fsync( int fd ) noexcept
  {
      return _commit( fd );
  }

  using socket_t = SOCKET;
  #define RW_INVALID_SOCKET INVALID_SOCKET

  /// Closes a Winsock handle through closesocket rather than the CRT close function.
  inline int rw_closesocket( SOCKET s ) noexcept
  {
      return ::closesocket( s );
  }

  namespace rw::compat
  {
      /// Converts POSIX timeval receive timeouts to the millisecond form expected by Winsock.
      inline int rw_setsockopt( SOCKET s, int level, int optname, const void* optval, int optlen )
      {
          if( level == SOL_SOCKET && optname == SO_RCVTIMEO && optlen == sizeof( timeval ) )
          {
              const auto* tv = static_cast<const timeval*>( optval );
              DWORD ms = static_cast<DWORD>( tv->tv_sec * 1000 + tv->tv_usec / 1000 );
              return ::setsockopt( s, level, optname, reinterpret_cast<const char*>( &ms ), sizeof( ms ) );
          }
          return ::setsockopt( s, level, optname, static_cast<const char*>( optval ), optlen );
      }
  }

  using rw::compat::rw_setsockopt;

  #ifndef setsockopt
    #define setsockopt rw_setsockopt
  #endif

  #include <format>
  namespace std
  {
  #if defined(_MSC_VER) && ( !defined(__cpp_lib_format) || __cpp_lib_format < 202207L )
      template <class... _Args>
      using format_string = _Fmt_string<_Args...>;
  #endif
  }

#else

  typedef SSIZE_T ssize_t;

#endif // __cplusplus

#else

  #include <unistd.h>
  #include <sys/file.h>
  #include <sys/stat.h>
  #include <climits>
  #include <cstdint>
  #include <cstdio>
  #include <cstdlib>
  #include <string>
  #include <string_view>
  #include <thread>

  #ifdef __cplusplus
  namespace rw::compat
  {
      /// Keeps POSIX worker sizing aligned with the standard library's effective CPU view.
      inline unsigned rw_effective_hardware_concurrency() noexcept
      {
          const unsigned hardware = std::thread::hardware_concurrency();
          return hardware == 0 ? 1u : hardware;
      }

      /// Keeps the POSIX build on the same compatibility API by forwarding flock unchanged.
      inline int rw_flock( int fd, int operation ) noexcept
      {
          return ::flock( fd, operation );
      }

      /// Keeps the POSIX build on the same compatibility API by forwarding pread unchanged.
      inline ssize_t rw_pread( int fd, void* buf, std::size_t count, std::uint64_t offset ) noexcept
      {
          return ::pread( fd, buf, count, static_cast<off_t>( offset ) );
      }

      /// Keeps the POSIX build on the same compatibility API by forwarding realpath unchanged.
      inline char* rw_realpath( const char* path, char* resolved_path ) noexcept
      {
          return ::realpath( path, resolved_path );
      }

      /// Keeps the POSIX build on the same compatibility API by forwarding popen unchanged.
      inline std::FILE* rw_popen( const char* command, const char* mode )
      {
          return ::popen( command, mode );
      }

      /// Keeps path-based file opens on the shared compatibility API; POSIX paths are already UTF-8 byte paths.
      inline std::FILE* rw_fopen_utf8( std::string_view path, std::string_view mode )
      {
          return std::fopen( std::string( path ).c_str(), std::string( mode ).c_str() );
      }

      /// Removes a UTF-8 path through the same compatibility API on both platforms.
      inline int rw_remove_utf8( std::string_view path )
      {
          return std::remove( std::string( path ).c_str() );
      }

      /// Renames a path through the same compatibility API on both platforms.
      inline int rw_rename( const char* oldname, const char* newname )
      {
          return std::rename( oldname, newname );
      }

      /// Keeps the POSIX build on the same compatibility API by forwarding pclose unchanged.
      inline int rw_pclose( std::FILE* stream )
      {
          return ::pclose( stream );
      }

      /// Returns no executable override on POSIX, where the native path helper is unnecessary.
      inline std::string rw_self_exe_path()
      {
          return {};
      }

      /// POSIX stdout already writes bytes without newline translation.
      inline void rw_set_stdout_binary() noexcept
      {
      }
  }

  using socket_t = int;
  #define RW_INVALID_SOCKET ( -1 )
  /// Closes the POSIX socket descriptor through close.
  inline int rw_closesocket( int s ) noexcept
  {
      return ::close( s );
  }
  #endif

#endif
