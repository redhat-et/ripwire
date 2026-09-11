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
  #include <string>

  using ssize_t = SSIZE_T;

  namespace rw::compat
  {
      int rw_flock( int fd, int operation ) noexcept;
      ssize_t rw_pread( int fd, void* buf, std::size_t count, std::uint64_t offset ) noexcept;
      char* rw_realpath( const char* path, char* resolved_path ) noexcept;
      std::FILE* rw_popen( const char* command, const char* mode );
      int rw_pclose( std::FILE* stream );
      std::string rw_self_exe_path();
      std::FILE* rw_open_memstream( char** bufloc, std::size_t* sizeloc );
      int rw_fclose( std::FILE* stream );
      int rw_fflush( std::FILE* stream );
      int rw_close( int fd );
      std::string rw_short_path( const std::string& path );
      /// Publishes a replacement file with bounded retries for transient Windows sharing violations.
      inline int rw_rename( const char* oldname, const char* newname ) noexcept
      {
          for( int attempt = 0; attempt < 8; ++attempt )
          {
              if( MoveFileExA( oldname, newname, MOVEFILE_REPLACE_EXISTING | MOVEFILE_COPY_ALLOWED ) )
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

  #ifdef __cplusplus
  namespace rw::compat
  {
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
