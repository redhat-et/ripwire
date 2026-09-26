// verify_os_win32_logic.cpp — the Windows port's pure logic (src/infra/os_win32_logic.h), tested on the platforms its
// reviewers have. Every function in that header is exercised here against an ORACLE written independently of it: a
// reference UTF-8 encoder, a reference MSVCRT command-line parser, the traditional Unix wait-status and S_IF* encodings
// (and, on a host that has them, the host's own W* and S_IS* macros), and linear scans for the binary-searched table. A case that only restated the implementation would pass
// while proving nothing, so each oracle is a different algorithm from the code it checks.
#define DOCTEST_CONFIG_IMPLEMENT_WITH_MAIN
#include <doctest/doctest.h>

#include "infra/os_win32_logic.h"

// A POSIX host's own W* and S_IS* macros are a second oracle for the encodings. This target also builds on Windows,
// whose UCRT has neither header shape, so the host arm is feature-detected; the traditional-encoding oracle below
// runs everywhere. (This file is under test/, outside osswitchcheck's scope, and tests a header, not a platform.)
#if __has_include( <sys/wait.h> )
#include <sys/stat.h>
#include <sys/wait.h>
#define OSWIN_TEST_HOST_WAIT_MACROS 1
#else
#define OSWIN_TEST_HOST_WAIT_MACROS 0
#endif

#include <cerrno>
#include <cstdint>
#include <cstring>
#include <string>
#include <string_view>
#include <utility>
#include <vector>

using namespace rw::oswin;

namespace
{

// The traditional Unix encodings, written from the System V / 4.4BSD definitions every POSIX libc still uses:
// type bits in the high octal digits of st_mode, exit status in bits 8..15, terminating signal in bits 0..6.
namespace traditional
{
inline constexpr unsigned kIfmt = 0170000, kIfifo = 0010000, kIfchr = 0020000, kIfdir = 0040000, kIfreg = 0100000, kIflnk = 0120000;
constexpr bool isType( unsigned mode, unsigned type ) noexcept { return ( mode & kIfmt ) == type; }
constexpr bool exited( int status ) noexcept { return ( status & 0x7f ) == 0; }
constexpr int  exitStatus( int status ) noexcept { return ( status >> 8 ) & 0xff; }
constexpr bool signaled( int status ) noexcept { return ( status & 0x7f ) != 0 && ( status & 0x7f ) != 0x7f; }
constexpr int  termSig( int status ) noexcept { return status & 0x7f; }
}   // namespace traditional

// ── oracles ─────────────────────────────────────────────────────────────────────────────────────────────────
std::string referenceUtf8( char32_t scalar )
{
    std::string out;
    if( scalar < 0x80 ) { out.push_back( char( scalar ) ); }
    else if( scalar < 0x800 ) { out.push_back( char( 0xC0 | ( scalar >> 6 ) ) ); out.push_back( char( 0x80 | ( scalar & 0x3F ) ) ); }
    else if( scalar < 0x10000 )
    {
        out.push_back( char( 0xE0 | ( scalar >> 12 ) ) ); out.push_back( char( 0x80 | ( ( scalar >> 6 ) & 0x3F ) ) ); out.push_back( char( 0x80 | ( scalar & 0x3F ) ) );
    }
    else
    {
        out.push_back( char( 0xF0 | ( scalar >> 18 ) ) ); out.push_back( char( 0x80 | ( ( scalar >> 12 ) & 0x3F ) ) );
        out.push_back( char( 0x80 | ( ( scalar >> 6 ) & 0x3F ) ) ); out.push_back( char( 0x80 | ( scalar & 0x3F ) ) );
    }
    return out;
}

std::u16string toUtf16( std::string_view utf8, bool& ok )
{
    const std::ptrdiff_t units = utf16LengthOf( utf8 );
    ok = units >= 0;
    if( !ok ) { return {}; }
    std::u16string out( std::size_t( units ), u'\0' );
    encodeUtf16( utf8, out.data() );
    return out;
}

std::string toUtf8( std::u16string_view utf16, bool& ok )
{
    const std::ptrdiff_t bytes = utf8LengthOf( utf16 );
    ok = bytes >= 0;
    if( !ok ) { return {}; }
    std::string out( std::size_t( bytes ), '\0' );
    encodeUtf8( utf16, out.data() );
    return out;
}

// The MSVCRT (2008 and later) / CommandLineToArgvW argument rules, written the way Microsoft documents them — a
// state machine over characters, not the backslash-count arithmetic appendQuotedArg uses. Every argument here is
// parsed with the non-first-argument rules (the program name is quoted by the same function, and contains no '"').
std::vector<std::string> parseCommandLine( std::string_view line )
{
    std::vector<std::string> args;
    std::size_t i = 0;
    while( true )
    {
        while( i < line.size() && ( line[ i ] == ' ' || line[ i ] == '\t' ) ) { ++i; }
        if( i >= line.size() ) { break; }
        std::string arg;
        bool inQuotes = false;
        while( i < line.size() )
        {
            const char c = line[ i ];
            if( ( c == ' ' || c == '\t' ) && !inQuotes ) { break; }
            if( c == '\\' )
            {
                std::size_t run = 0;
                while( i < line.size() && line[ i ] == '\\' ) { ++run; ++i; }
                if( i < line.size() && line[ i ] == '"' )
                {
                    arg.append( run / 2, '\\' );
                    if( run % 2 == 1 ) { arg.push_back( '"' ); ++i; }
                }
                else
                {
                    arg.append( run, '\\' );
                }
                continue;
            }
            if( c == '"' )
            {
                if( inQuotes && i + 1 < line.size() && line[ i + 1 ] == '"' ) { arg.push_back( '"' ); i += 2; continue; }
                inQuotes = !inQuotes;
                ++i;
                continue;
            }
            arg.push_back( c );
            ++i;
        }
        args.push_back( std::move( arg ) );
    }
    return args;
}

std::string normalized( std::string text )
{
    normalizePathArgInPlace( text.data() );
    return text;
}

std::string fromNative( std::u16string_view native, std::size_t capacity, int& error, std::ptrdiff_t& written )
{
    std::vector<char> out( capacity + 1, '\x7f' );
    error   = 0;
    written = programPathFromNative( native, out.data(), capacity, &error );
    return written < 0 ? std::string() : std::string( out.data() );
}

}   // namespace

// ── 1. errno table ──────────────────────────────────────────────────────────────────────────────────────────
TEST_CASE( "win32 errno: the binary search agrees with a linear scan for every code 0..12000 and a few far ones" )
{
    const auto linear = []( std::uint32_t code )
    {
        for( const ErrnoRow& row : kWin32ErrnoTable ) { if( row.code == code ) { return row.errnoValue; } }
        return EIO;
    };
    for( std::uint32_t code = 0; code <= 12000; ++code )
    {
        REQUIRE( errnoFromWin32( code ) == linear( code ) );
    }
    for( const std::uint32_t code : { 0x7FFFFFFFu, 0x80000000u, 0xC0000005u, 0xFFFFFFFFu } )
    {
        CHECK( errnoFromWin32( code ) == EIO );
    }
    CHECK( isWin32ErrnoTableSorted() );
    CHECK( win32TableIsComplete() );
}

TEST_CASE( "win32 errno: the rows call sites depend on" )
{
    CHECK( errnoFromWin32( 2 ) == ENOENT );           // ERROR_FILE_NOT_FOUND
    CHECK( errnoFromWin32( 3 ) == ENOENT );           // ERROR_PATH_NOT_FOUND
    CHECK( errnoFromWin32( 5 ) == EACCES );           // ERROR_ACCESS_DENIED — deliberately not libuv's EPERM
    CHECK( errnoFromWin32( 32 ) == EBUSY );           // ERROR_SHARING_VIOLATION
    CHECK( errnoFromWin32( 33 ) == EWOULDBLOCK );     // ERROR_LOCK_VIOLATION — flock( LOCK_NB )'s retry predicate
    CHECK( errnoFromWin32( 80 ) == EEXIST );          // ERROR_FILE_EXISTS
    CHECK( errnoFromWin32( 183 ) == EEXIST );         // ERROR_ALREADY_EXISTS
    CHECK( errnoFromWin32( 267 ) == ENOTDIR );        // ERROR_DIRECTORY
    CHECK( errnoFromWin32( 681 ) == ELOOP );          // ERROR_STOPPED_ON_SYMLINK
    CHECK( errnoFromWin32( 1921 ) == ELOOP );         // ERROR_CANT_RESOLVE_FILENAME
    CHECK( errnoFromWin32( 1113 ) == EILSEQ );        // ERROR_NO_UNICODE_TRANSLATION
    CHECK( errnoFromWin32( 109 ) == EPIPE );          // ERROR_BROKEN_PIPE
    CHECK( errnoFromWin32( 10004 ) == EINTR );        // WSAEINTR — accept()'s retry predicate
    CHECK( errnoFromWin32( 10048 ) == EADDRINUSE );   // WSAEADDRINUSE — the --listen bind failure text
    CHECK( errnoFromWin32( 10054 ) == ECONNRESET );
    CHECK( errnoFromWin32( 10060 ) == ETIMEDOUT );    // WSAETIMEDOUT — an SO_RCVTIMEO expiry
    CHECK( errnoFromWin32( 997 ) == EWOULDBLOCK );    // ERROR_IO_PENDING (LOW-2) — defence alongside 33/ERROR_LOCK_VIOLATION,
                                                       // the code LockFileEx actually reports on these synchronous handles
}

// ── 2. UTF-8 / UTF-16 ───────────────────────────────────────────────────────────────────────────────────────
TEST_CASE( "utf: every scalar value round-trips UTF-8 -> UTF-16 -> UTF-8 byte-exactly" )
{
    std::size_t checked = 0;
    for( char32_t scalar = 0; scalar <= 0x10FFFF; ++scalar )
    {
        if( scalar >= 0xD800 && scalar <= 0xDFFF ) { continue; }
        const std::string utf8 = referenceUtf8( scalar );
        bool ok = false;
        const std::u16string utf16 = toUtf16( utf8, ok );
        REQUIRE( ok );
        REQUIRE( utf16.size() == ( scalar >= 0x10000 ? 2u : 1u ) );
        const std::string back = toUtf8( utf16, ok );
        REQUIRE( ok );
        REQUIRE( back == utf8 );
        ++checked;
    }
    CHECK( checked == 0x110000 - 0x800 );
}

TEST_CASE( "utf: malformed UTF-8 is refused, never replaced" )
{
    const std::vector<std::string> bad = {
        "\xC0\xAF",             // overlong '/'
        "\xC1\xBF",             // overlong
        "\xE0\x80\xAF",         // overlong '/' — the form libuv's WTF-8 decoder accepts
        "\xF0\x80\x80\xAF",     // overlong '/'
        "\xED\xA0\x80",         // U+D800, a surrogate
        "\xED\xBF\xBF",         // U+DFFF
        "\xF4\x90\x80\x80",     // U+110000
        "\xF5\x80\x80\x80",     // lead byte past F4
        "\x80",                 // stray continuation
        "\xC3",                 // truncated
        "\xE2\x82",             // truncated
        "ok\xFF",               // invalid byte after valid text
        "\xE2\x28\xA1",         // bad continuation
    };
    for( const std::string& text : bad )
    {
        CAPTURE( text );
        CHECK( utf16LengthOf( text ) == -1 );
    }
    CHECK( utf16LengthOf( "" ) == 0 );
    CHECK( utf16LengthOf( "caf\xC3\xA9" ) == 4 );
}

TEST_CASE( "utf: a lone UTF-16 surrogate is refused" )
{
    const char16_t high[] = { u'a', char16_t( 0xD83D ) };
    const char16_t low[]  = { char16_t( 0xDE00 ), u'a' };
    const char16_t swap[] = { char16_t( 0xDE00 ), char16_t( 0xD83D ) };
    const char16_t pair[] = { char16_t( 0xD83D ), char16_t( 0xDE00 ) };
    CHECK( utf8LengthOf( std::u16string_view( high, 2 ) ) == -1 );
    CHECK( utf8LengthOf( std::u16string_view( low, 2 ) ) == -1 );
    CHECK( utf8LengthOf( std::u16string_view( swap, 2 ) ) == -1 );
    CHECK( utf8LengthOf( std::u16string_view( pair, 2 ) ) == 4 );   // U+1F600
}

// ── WidePath ────────────────────────────────────────────────────────────────────────────────────────────────
TEST_CASE( "WidePath: separators, the Git Bash drive spelling, and nothing else rewritten" )
{
    CHECK( std::u16string_view( WidePath( "C:/repo/src/a.cpp" ).c_str() ) == u"C:\\repo\\src\\a.cpp" );
    CHECK( std::u16string_view( WidePath( "/c/repo" ).c_str() ) == u"C:\\repo" );
    CHECK( std::u16string_view( WidePath( "/d" ).c_str() ) == u"D:\\" );
    CHECK( std::u16string_view( WidePath( "/c/" ).c_str() ) == u"C:\\" );
    CHECK( std::u16string_view( WidePath( "/cd/x" ).c_str() ) == u"\\cd\\x" );         // two letters: not a drive
    CHECK( std::u16string_view( WidePath( "rel/c/x" ).c_str() ) == u"rel\\c\\x" );     // not at the start: not a drive
    CHECK( std::u16string_view( WidePath( "//server/share/x" ).c_str() ) == u"\\\\server\\share\\x" );
    CHECK( std::u16string_view( WidePath( "caf\xC3\xA9/\xF0\x9F\x98\x80" ).c_str() ) == u"caf\u00E9\\\U0001F600" );
    const WidePath empty( "" );
    CHECK( empty.ok() );
    CHECK( empty.size() == 0 );
}

TEST_CASE( "WidePath: the stack holds MAX_PATH units; one past it takes exactly one heap block" )
{
    const std::string fits( WidePath::kStackUnits - 1, 'a' );
    const std::string over( WidePath::kStackUnits, 'a' );
    const WidePath onStack( fits.c_str() );
    const WidePath onHeap( over.c_str() );
    CHECK( onStack.ok() );
    CHECK( !onStack.onHeap() );
    CHECK( onStack.size() == fits.size() );
    CHECK( onHeap.ok() );
    CHECK( onHeap.onHeap() );
    CHECK( onHeap.size() == over.size() );
    CHECK( std::u16string_view( onHeap.c_str() ) == std::u16string( over.size(), u'a' ) );
    // a 4-byte scalar is two units: 130 of them is 260 units + terminator — exactly the stack
    std::string emoji;
    for( int i = 0; i < 130; ++i ) { emoji += "\xF0\x9F\x98\x80"; }
    const WidePath pairs( emoji.c_str() );
    CHECK( pairs.ok() );
    CHECK( !pairs.onHeap() );
    CHECK( pairs.size() == 260 );
}

TEST_CASE( "WidePath: invalid input fails closed with an errno and an empty spelling" )
{
    const WidePath bad( "a\xE0\x80\xAF" "b" );
    CHECK( !bad.ok() );
    CHECK( bad.error() == EILSEQ );
    CHECK( std::u16string_view( bad.c_str() ).empty() );
    const WidePath null( nullptr );
    CHECK( !null.ok() );
    CHECK( null.error() == EINVAL );
}

// ── 3. program path spelling ────────────────────────────────────────────────────────────────────────────────
TEST_CASE( "programPathFromNative: prefixes stripped, '/' separators, upper-case drive, UNC kept as //" )
{
    int error = 0;
    std::ptrdiff_t written = 0;
    CHECK( fromNative( u"\\\\?\\C:\\repo\\src", 64, error, written ) == "C:/repo/src" );
    CHECK( written == 11 );
    CHECK( fromNative( u"c:\\Users\\x", 64, error, written ) == "C:/Users/x" );
    CHECK( fromNative( u"\\\\?\\UNC\\server\\share\\dir", 64, error, written ) == "//server/share/dir" );
    CHECK( fromNative( u"\\\\server\\share", 64, error, written ) == "//server/share" );
    CHECK( fromNative( u"\\??\\D:\\x", 64, error, written ) == "D:/x" );
    CHECK( fromNative( u"C:\\caf\u00E9", 64, error, written ) == "C:/caf\xC3\xA9" );
}

TEST_CASE( "programPathFromNative: the buffer bound is exact and a lone surrogate is EILSEQ" )
{
    int error = 0;
    std::ptrdiff_t written = 0;
    CHECK( fromNative( u"C:\\abc", 7, error, written ) == "C:/abc" );     // 6 bytes + NUL in exactly 7
    CHECK( written == 6 );
    CHECK( fromNative( u"C:\\abcd", 7, error, written ).empty() );    // 7 bytes + NUL do not fit in 7
    CHECK( written == -1 );
    CHECK( error == ENAMETOOLONG );
    const char16_t lone[] = { u'C', u':', u'\\', char16_t( 0xDC00 ) };
    std::vector<char> out( 32 );
    error = 0;
    CHECK( programPathFromNative( std::u16string_view( lone, 4 ), out.data(), out.size(), &error ) == -1 );
    CHECK( error == EILSEQ );
}

TEST_CASE( "normalizePathArgInPlace: separators and Git Bash drives, length-preserving, at list boundaries only" )
{
    CHECK( normalized( "C:\\repo\\src" ) == "C:/repo/src" );
    CHECK( normalized( "/c/repo" ) == "C:/repo" );
    CHECK( normalized( "/d" ) == "D:" );
    CHECK( normalized( "src/a.cpp,/c/x/b.cpp" ) == "src/a.cpp,C:/x/b.cpp" );
    CHECK( normalized( "/c,/d/y" ) == "C:,D:/y" );
    CHECK( normalized( "C:/a/b" ) == "C:/a/b" );         // PR #44's rewrite also fired after ':' and made this "C:A:b"
    CHECK( normalized( "/cd/x" ) == "/cd/x" );
    CHECK( normalized( "rel/c/x" ) == "rel/c/x" );
    CHECK( normalized( "c:\\Repo" ) == "C:/Repo" );          // the drive upper-cased, nothing else
    CHECK( normalized( "a,d:/x" ) == "a,D:/x" );
    CHECK( normalized( "" ).empty() );
    std::string text = "/e/\\x";
    const std::size_t before = text.size();
    normalizePathArgInPlace( text.data() );
    CHECK( text == "E://x" );
    CHECK( text.size() == before );
    normalizePathArgInPlace( nullptr );                   // no crash
}

TEST_CASE( "rebaseDevNull: a POSIX fail-closed path stays unopenable on Windows" )
{
    CHECK( rebaseDevNull( "/dev/null" ) == "NUL" );
    const std::string unusable = rebaseDevNull( "/dev/null/ripwire-cache-unavailable/blob" );
    CHECK( unusable.find( '|' ) != std::string::npos );          // '|' is refused in every Win32 file name
    CHECK( unusable.find( "ripwire-cache-unavailable/blob" ) != std::string::npos );
    CHECK( rebaseDevNull( "/dev/nullx" ).empty() );
    CHECK( rebaseDevNull( "/dev/null2/x" ).empty() );
    CHECK( rebaseDevNull( "C:/dev/null/x" ).empty() );
}

TEST_CASE( "rebaseMsysTmp: Git for Windows' /tmp is the user's temp directory; nothing else moves" )
{
    CHECK( rebaseMsysTmp( "/tmp/ripwire-1001", "C:\\Users\\x\\AppData\\Local\\Temp\\" ) == "C:/Users/x/AppData/Local/Temp/ripwire-1001" );
    CHECK( rebaseMsysTmp( "/tmp", "c:/t/" ) == "C:/t" );
    CHECK( rebaseMsysTmp( "/tmp/", "C:/t" ) == "C:/t/" );
    CHECK( rebaseMsysTmp( "/tmpfoo/x", "C:/t" ).empty() );      // a sibling whose name starts with tmp
    CHECK( rebaseMsysTmp( "/var/tmp/x", "C:/t" ).empty() );
    CHECK( rebaseMsysTmp( "C:/tmp/x", "C:/t" ).empty() );
    CHECK( rebaseMsysTmp( "/tmp/x", "" ).empty() );
}

// #326: the dispatch NativePath makes at every os_win32.cpp syscall — which of rebaseMsysTmp / rebaseDevNull (if
// either) applies to a program path — extracted to oswin::rebasedProgramPath so a caller outside os_win32.cpp
// (os::rebased_path, for a consumer like std::filesystem or a bare std::fopen that performs no rebase of its own)
// can ask the same question. ORACLE: reimplemented here independently (manual prefix dispatch, not a call into the
// function under test) against the exact bug this seam exists for — --doctor's cache-dir probe measuring
// "/tmp/ripwire-<uid>" via std::fopen/std::filesystem, which on Windows resolves against the CURRENT DRIVE rather
// than the real, os::mkdir-created cache directory os_win32.cpp's NativePath rebases every os:: call onto.
TEST_CASE( "rebasedProgramPath: routes exactly like NativePath's own dispatch, for a non-os:: caller" )
{
    const std::string nativeTmp = "C:\\Users\\x\\AppData\\Local\\Temp\\";
    const auto        oracle    = [ & ]( std::string_view path ) -> std::string
    {
        if( path.empty() || path.front() != '/' ) { return {}; }
        if( path.substr( 0, 4 ) == "/tmp" ) { return rebaseMsysTmp( path, nativeTmp ); }
        if( path.substr( 0, 9 ) == "/dev/null" ) { return rebaseDevNull( path ); }
        return {};
    };

    // the exact repro from the issue: cacheDirLadder()'s third-tier literal for uid 1001.
    const std::string doctorCacheDir = "/tmp/ripwire-1001";
    CHECK( rebasedProgramPath( doctorCacheDir, nativeTmp ) == oracle( doctorCacheDir ) );
    CHECK( rebasedProgramPath( doctorCacheDir, nativeTmp ) == "C:/Users/x/AppData/Local/Temp/ripwire-1001" );

    // the sentinel cacheDirLadder() returns when the ladder itself judged the directory unsafe/unusable — must
    // still fail closed (a '|' byte, never a real openable Windows path), same as calling rebaseDevNull directly.
    const std::string unusableCacheDir = "/dev/null/ripwire-cache-unavailable";
    CHECK( rebasedProgramPath( unusableCacheDir, nativeTmp ) == oracle( unusableCacheDir ) );
    CHECK( rebasedProgramPath( unusableCacheDir, nativeTmp ).find( '|' ) != std::string::npos );

    // an already-native or unrelated absolute path: no rebase applies, dispatch answers empty (the caller's
    // contract, matching NativePath, is "empty means use `path` itself unchanged").
    CHECK( rebasedProgramPath( "C:/Users/x/project", nativeTmp ) == oracle( "C:/Users/x/project" ) );
    CHECK( rebasedProgramPath( "C:/Users/x/project", nativeTmp ).empty() );
    CHECK( rebasedProgramPath( "/home/x/project", nativeTmp ) == oracle( "/home/x/project" ) );
    CHECK( rebasedProgramPath( "/home/x/project", nativeTmp ).empty() );

    // relative and empty input: never crashes, never fabricates an absolute answer.
    CHECK( rebasedProgramPath( "", nativeTmp ).empty() );
    CHECK( rebasedProgramPath( "tmp/x", nativeTmp ).empty() );

    // GetTempPathW itself failed (userTempDirectory() empty): degrades to "no rebase" rather than a garbage path —
    // the caller (os::rebased_path) then falls back to the ORIGINAL spelling, same failure shape as before #326,
    // not a crash or a fabricated location.
    CHECK( rebasedProgramPath( doctorCacheDir, "" ).empty() );
}

// #326 structural follow-up: cacheDirLadder() (src/quality.h) itself now calls os::rebased_path on its return
// value, so EVERY consumer in the tree (resolveCacheBlobPath, evictOldCacheFamily, slicediff.h/editpreview.h's
// temp roots, crossref.h, ingest_docpass.h, main.cpp's clone cache — see that function's own comment for the
// full list) is correct by construction, not just --doctor. This case exercises rebasedProgramPath against the
// EXACT three shapes cacheDirLadder's three tiers can hand it, so a change to either function is caught here
// regardless of which one actually changed. It is not a NEW dispatch rule — rebasedProgramPath's prefix-only
// routing already covers every one of these inputs generically (proved by the previous test case) — so, unlike
// that case, these assertions do not fail to compile on 8a2d9ce1: rebasedProgramPath itself is unchanged since
// that commit. What changed is an ADDITIONAL, new CALL SITE (cacheDirLadder(), in a different translation
// unit this seam cannot link against — it takes os::mkdir/os::getenv, which is exactly what os_win32_logic.h
// exists to stay free of). That change is proven instead by: (a) reading the diff — cacheDirLadder() at
// src/quality.h now ends every return path through os::rebased_path; (b) the extended Windows CI step, which
// is genuinely red on unfixed code and green after, on the one platform where the two spellings differ.
TEST_CASE( "rebasedProgramPath: the exact shapes quality.h::cacheDirLadder's three tiers produce" )
{
    const std::string nativeTmp = "C:\\Users\\x\\AppData\\Local\\Temp\\";

    // tier 3 (neither TMPDIR nor XDG_CACHE_HOME set): the hardcoded fallback literal — must rebase.
    CHECK( rebasedProgramPath( "/tmp/ripwire-1001", nativeTmp ) == "C:/Users/x/AppData/Local/Temp/ripwire-1001" );

    // tier 1 (TMPDIR set): os::init_process already normalises TMPDIR into the program's spelling at intake
    // (CONTRIBUTING.md §3, "Windows spells them once where they enter"), so the ordinary case is an
    // already-native path the ladder appends "/ripwire" to — no rebase applies, identity.
    CHECK( rebasedProgramPath( "C:/Users/x/AppData/Local/Temp/ripwire", nativeTmp ).empty() );

    // tier 1, the edge case: nothing stops a user (or Git Bash's own default environment) from setting
    // TMPDIR=/tmp verbatim. cacheDirLadder() rebases UNCONDITIONALLY on its return value, regardless of which
    // tier produced the string — so this tier-1 output is rebased exactly like tier 3's, uniformly, rather
    // than only the hardcoded fallback literal receiving special treatment.
    CHECK( rebasedProgramPath( "/tmp/ripwire", nativeTmp ) == "C:/Users/x/AppData/Local/Temp/ripwire" );

    // tier 2 (XDG_CACHE_HOME set): same as tier 1's ordinary case — an already-native path, identity.
    CHECK( rebasedProgramPath( "D:/CacheRoot/ripwire", nativeTmp ).empty() );

    // the ladder's own fail-closed sentinel, in full: rebases to the unusable '|' spelling, never silently
    // "worked" by accident the way a bare drive-relative "/dev/null/..." would on some machines.
    const std::string sentinel = rebasedProgramPath( "/dev/null/ripwire-cache-unavailable", nativeTmp );
    CHECK( sentinel.find( '|' ) != std::string::npos );
    CHECK( sentinel.find( "ripwire-cache-unavailable" ) != std::string::npos );
}

// #326's sibling (the cache-eviction sweep): cacheDirLadder() now resolves its own spelling ONCE through this
// dispatch, on every value it returns, so std::filesystem and os:: consumers read the same bytes. Every
// os:: call the ladder and its callers then make hands that ALREADY-RESOLVED answer back through NativePath — i.e.
// through this same dispatch a second time. The fix is only correct if that second pass is a no-op on every answer the
// first can give: a drive-lettered temp path, an already-native TMPDIR tier, and the fail-closed sentinel. The oracle
// is the contract itself ("empty means use `path` verbatim"), asserted on the dispatch's own outputs.
TEST_CASE( "rebasedProgramPath: idempotent — an os:: caller handed an already-resolved cacheDirLadder() answer sees no second rewrite" )
{
    const std::string nativeTmp = "D:\\Temp\\";

    // third tier, the one a plain cmd.exe/PowerShell user lands on (neither TMPDIR nor XDG_CACHE_HOME is set there):
    // resolved once to the real temp directory, and that answer routes to "no rebase" when it comes back around.
    const std::string once = rebasedProgramPath( "/tmp/ripwire-1001", nativeTmp );
    CHECK( once == "D:/Temp/ripwire-1001" );
    CHECK( rebasedProgramPath( once, nativeTmp ).empty() );
    CHECK( rebasedProgramPath( once + "/ripwire-deadbeef0000aaaa-lean.bin", nativeTmp ).empty() );   // a blob under it: same
    CHECK( rebasedProgramPath( once + "/locks", nativeTmp ).empty() );                                // the edit-lock subtree: same

    // the ladder promises NO trailing slash (every caller appends "/<name>"): the rebase keeps that promise even
    // when the native temp directory is spelled with one or several trailing separators, as GetTempPathW returns it.
    CHECK( once.back() != '/' );
    CHECK( rebasedProgramPath( "/tmp/ripwire-1001", "D:\\Temp\\\\" ) == "D:/Temp/ripwire-1001" );
    CHECK( rebasedProgramPath( "/tmp/ripwire-1001", "D:\\Temp" ) == "D:/Temp/ripwire-1001" );

    // first tier: a TMPDIR os::init_process already put in the program's spelling — no rewrite on either pass.
    CHECK( rebasedProgramPath( "D:/Temp/ripwire", nativeTmp ).empty() );

    // the fail-closed sentinel: rebasing it once yields the unopenable "|unusable|..." spelling; rebasing THAT
    // again must not turn it into anything openable (it still does not start with '/', so: no rewrite).
    const std::string sentinelOnce = rebasedProgramPath( "/dev/null/ripwire-cache-unavailable", nativeTmp );
    CHECK( sentinelOnce.rfind( "|unusable|", 0 ) == 0 );
    CHECK( rebasedProgramPath( sentinelOnce, nativeTmp ).empty() );
}

TEST_CASE( "extendedLengthPath: only an absolute, clean path gets the \\\\?\\ prefix" )
{
    CHECK( extendedLengthPath( u"C:\\Users\\x\\Temp\\" ) == u"\\\\?\\C:\\Users\\x\\Temp\\" );
    CHECK( extendedLengthPath( u"c:/a/b" ) == u"\\\\?\\c:\\a\\b" );
    CHECK( extendedLengthPath( u"\\\\server\\share\\dir" ) == u"\\\\?\\UNC\\server\\share\\dir" );
    CHECK( extendedLengthPath( u"\\\\?\\C:\\already" ) == u"\\\\?\\C:\\already" );
    CHECK( extendedLengthPath( u"relative\\x" ).empty() );
    CHECK( extendedLengthPath( u"C:relative" ).empty() );                    // drive-relative
    CHECK( extendedLengthPath( u"\\rooted-no-drive" ).empty() );
    CHECK( extendedLengthPath( u"C:\\a\\..\\b" ).empty() );              // ".." would not be folded under the prefix
    CHECK( extendedLengthPath( u"C:\\a\\.\\b" ).empty() );
    CHECK( extendedLengthPath( u"C:\\..hidden\\.x" ) == u"\\\\?\\C:\\..hidden\\.x" );   // names that only start with dots are fine
    CHECK( extendedLengthPath( u"\\\\.\\pipe\\x" ).empty() );         // a device path is not a UNC share
}

TEST_CASE( "extendedLengthPathIfLong: MED-1 — prefixes only once native reaches the threshold" )
{
    // Below kExtendedLengthThresholdUnits (248): untouched even though extendedLengthPath alone would prefix it.
    CHECK( extendedLengthPathIfLong( u"C:\\Users\\x\\Temp\\" ).empty() );

    // The boundary is size() >= threshold, not size() > threshold — checked with an explicit threshold so the case
    // does not depend on the default's exact value.
    CHECK( extendedLengthPathIfLong( u"C:\\ab", 5 ) == extendedLengthPath( u"C:\\ab" ) );   // size()==5==threshold: prefixed
    CHECK( extendedLengthPathIfLong( u"C:\\ab", 6 ).empty() );                               // size()==5<6: untouched

    // 259 / 260 / 261 UTF-16 units total (just under / at / just over the classic MAX_PATH=260 failure point): an
    // absolute drive path with one long clean component, every one past the default threshold (248) and prefixed
    // exactly as extendedLengthPath alone would prefix it.
    for( const std::size_t total : { 259, 260, 261 } )
    {
        std::u16string native = u"C:\\";
        native.append( total - native.size(), u'a' );
        REQUIRE( native.size() == total );
        const std::u16string got = extendedLengthPathIfLong( native );
        CHECK( got == extendedLengthPath( native ) );
        CHECK( got == u"\\\\?\\" + native );
        CHECK( got.size() == total + 4 );
    }

    // UNC, long: the \\?\UNC\ form, same as extendedLengthPath alone.
    {
        std::u16string unc = u"\\\\server\\share\\";
        unc.append( 248, u'b' );
        REQUIRE( unc.size() >= kExtendedLengthThresholdUnits );
        CHECK( extendedLengthPathIfLong( unc ) == extendedLengthPath( unc ) );
        CHECK( extendedLengthPathIfLong( unc ).starts_with( u"\\\\?\\UNC\\server\\share\\" ) );
    }

    // Already "\\?\"-prefixed, long: returned unchanged — extendedLengthPath's own idempotence, not a double prefix.
    {
        std::u16string already = u"\\\\?\\C:\\";
        already.append( 260, u'c' );
        CHECK( extendedLengthPathIfLong( already ) == already );
    }

    // Long but RELATIVE (not prefixable): extendedLengthPath refuses it, so "below the threshold" and "not
    // prefixable" collapse to the same empty return — NativePath keeps using its own unprefixed spelling either way,
    // needing the machine's LongPathsEnabled policy instead (this cannot substitute for it).
    {
        const std::u16string longRelative( 260, u'd' );
        CHECK( extendedLengthPathIfLong( longRelative ).empty() );
    }
}

TEST_CASE( "nextGetlineCapacity: POSIX ignores *capacity while *line is NULL (LOW-4)" )
{
    CHECK( nextGetlineCapacity( true, 0 ) == 128 );
    CHECK( nextGetlineCapacity( true, 999999 ) == 128 );   // *line == nullptr: garbage left in *capacity must not be doubled
    CHECK( nextGetlineCapacity( false, 0 ) == 128 );
    CHECK( nextGetlineCapacity( false, 64 ) == 128 );
    CHECK( nextGetlineCapacity( false, 128 ) == 256 );
    CHECK( nextGetlineCapacity( false, 200 ) == 400 );
}

TEST_CASE( "isLongTemporaryEntry: TMP/TEMP/TMPDIR, any case, at or past the limit" )
{
    const std::u16string longValue( 240, u'x' );
    const std::u16string shortValue( 239, u'x' );
    CHECK( isLongTemporaryEntry( u"TMP=" + longValue ) );
    CHECK( isLongTemporaryEntry( u"temp=" + longValue ) );
    CHECK( isLongTemporaryEntry( u"TmpDir=" + longValue ) );
    CHECK( !isLongTemporaryEntry( u"TMP=" + shortValue ) );
    CHECK( !isLongTemporaryEntry( u"TEMPORARY=" + longValue ) );
    CHECK( !isLongTemporaryEntry( u"PATH=" + longValue ) );
    CHECK( !isLongTemporaryEntry( u"=C:=" + longValue ) );
    CHECK( !isLongTemporaryEntry( u"TMP" ) );
    CHECK( isLongTemporaryEntry( u"TMP=abcd", 4 ) );
}

// ── 4. command-line quoting ─────────────────────────────────────────────────────────────────────────────────
TEST_CASE( "quoting: libuv's documented cases, always quoted" )
{
    const auto quoted = []( std::string_view arg ) { std::string out; appendQuotedArg( out, arg ); return out; };
    CHECK( quoted( "" ) == "\"\"" );
#if defined( OSWIN_LOGIC_MUTANT )
    CHECK( quoted( "hello" ) == "hello" );                     // MUTANT: libuv's bare form — must be caught
    CHECK( errnoFromWin32( 5 ) == EPERM );                     // MUTANT: libuv's EPERM for ACCESS_DENIED — must be caught
#else
    CHECK( quoted( "hello" ) == "\"hello\"" );
#endif
    CHECK( quoted( "hello\"world" ) == "\"hello\\\"world\"" );
    CHECK( quoted( "hello\"\"world" ) == "\"hello\\\"\\\"world\"" );
    CHECK( quoted( "hello\\world" ) == "\"hello\\world\"" );
    CHECK( quoted( "hello\\\\world" ) == "\"hello\\\\world\"" );
    CHECK( quoted( "hello\\\"world" ) == "\"hello\\\\\\\"world\"" );
    CHECK( quoted( "hello\\\\\"world" ) == "\"hello\\\\\\\\\\\"world\"" );
    CHECK( quoted( "hello world\\" ) == "\"hello world\\\\\"" );
    CHECK( quoted( "*.cpp" ) == "\"*.cpp\"" );            // quoted, so the MSYS runtime does not glob it
}

// A deterministic generator whose arithmetic never wraps: arm (B) of oswin32logiccheck runs this file under the G1
// `integer` sanitizer, which refuses std::mt19937's own tempering inside libc++ (a left shift that drops bits). The
// state stays below 2^31 and the multiplier below 2^31, so the product fits in 64 bits. Quality is not the point:
// only that the vectors vary and every run draws the same ones.
struct Lcg31
{
    std::uint64_t state;
    int below( int bound ) noexcept
    {
        state = ( state * 1103515245u + 12345u ) % 2147483648u;
        return static_cast<int>( state % static_cast<std::uint64_t>( bound ) );
    }
};

TEST_CASE( "quoting: 20,000 random argument vectors survive the MSVCRT parser unchanged" )
{
    Lcg31 rng{ 0x5eed };
    const std::string_view alphabet[] = { "a", "b", " ", "\t", "\"", "\\", "*", "?", "'", "$", "%", "^", "&", "|", "\xC3\xA9", "\xF0\x9F\x98\x80", "-c", "/" };
    for( int trial = 0; trial < 20000; ++trial )
    {
        std::vector<std::string> argv{ "C:/Program Files/Git/bin/bash.exe" };
        const int count = rng.below( 5 );
        for( int a = 0; a < count; ++a )
        {
            std::string arg;
            const int length = rng.below( 13 );
            for( int c = 0; c < length; ++c ) { arg += alphabet[ rng.below( int( std::size( alphabet ) ) ) ]; }
            argv.push_back( arg );
        }
        std::string line;
        for( const std::string& arg : argv )
        {
            if( !line.empty() ) { line.push_back( ' ' ); }
            appendQuotedArg( line, arg );
        }
        CAPTURE( line );
        REQUIRE( parseCommandLine( line ) == argv );
    }
}

TEST_CASE( "quoting: buildCommandLine joins with single spaces and refuses an embedded NUL" )
{
    CHECK( buildCommandLine( { "bash.exe", "-c", "echo \"hi\"" } ) == "\"bash.exe\" \"-c\" \"echo \\\"hi\\\"\"" );
    CHECK( buildCommandLine( { "a", std::string_view( "b\0c", 3 ) } ).empty() );
    CHECK( parseCommandLine( buildCommandLine( { "C:/x/bash.exe", "-c", "git log --format='%H' | tail -1" } ) )
           == std::vector<std::string>{ "C:/x/bash.exe", "-c", "git log --format='%H' | tail -1" } );
}

// ── 5. reparse points and modes ─────────────────────────────────────────────────────────────────────────────
TEST_CASE( "reparse: symlink and junction are links; cloud, dedup, app-exec-link and WSL tags are not" )
{
    CHECK( isLinkReparseTag( 0xA000000C ) );   // IO_REPARSE_TAG_SYMLINK
    CHECK( isLinkReparseTag( 0xA0000003 ) );   // IO_REPARSE_TAG_MOUNT_POINT
    for( const std::uint32_t tag : { 0x9000001Au, 0x9000101Au, 0x80000013u, 0x8000001Bu, 0xA000001Du, 0x80000017u, 0u } )
    {
        CAPTURE( tag );
        CHECK( !isLinkReparseTag( tag ) );
    }
    CHECK( classifyFinalComponent( kFileAttributeReparsePoint, kReparseTagSymlink ) == FinalComponent::Link );
    CHECK( classifyFinalComponent( kFileAttributeReparsePoint | kFileAttributeDirectory, kReparseTagMountPoint ) == FinalComponent::Link );
    CHECK( classifyFinalComponent( kFileAttributeReparsePoint, 0x9000001A ) == FinalComponent::OtherReparse );
    CHECK( classifyFinalComponent( 0, kReparseTagSymlink ) == FinalComponent::Plain );   // no reparse attribute: the tag is noise
    CHECK( classifyFinalComponent( kFileAttributeDirectory, 0 ) == FinalComponent::Plain );
}

TEST_CASE( "mode: type bits match the traditional S_IF* encoding, and the host's S_IS* macros where it has them" )
{
    CHECK( kModeFifo == traditional::kIfifo );
    CHECK( kModeCharacter == traditional::kIfchr );
    CHECK( kModeDirectory == traditional::kIfdir );
    CHECK( kModeRegular == traditional::kIfreg );
    CHECK( kModeLink == traditional::kIflnk );

    const unsigned symlink  = modeTypeBits( kFileTypeDisk, kFileAttributeReparsePoint, kReparseTagSymlink, false );
    const unsigned junction = modeTypeBits( kFileTypeDisk, kFileAttributeReparsePoint | kFileAttributeDirectory, kReparseTagMountPoint, true );
    const unsigned oneDrive = modeTypeBits( kFileTypeDisk, kFileAttributeReparsePoint, 0x9000001A, false );   // a OneDrive placeholder
    const unsigned dir      = modeTypeBits( kFileTypeDisk, kFileAttributeDirectory, 0, false );
    const unsigned regular  = modeTypeBits( kFileTypeDisk, 0, 0, false );
    const unsigned fifo     = modeTypeBits( kFileTypePipe, 0, 0, true );
    const unsigned chr      = modeTypeBits( kFileTypeChar, 0, 0, true );
    CHECK( traditional::isType( symlink, traditional::kIflnk ) );
    CHECK( traditional::isType( junction, traditional::kIfdir ) );
    CHECK( traditional::isType( oneDrive, traditional::kIfreg ) );
    CHECK( traditional::isType( dir, traditional::kIfdir ) );
    CHECK( traditional::isType( regular, traditional::kIfreg ) );
    CHECK( traditional::isType( fifo, traditional::kIfifo ) );
    CHECK( traditional::isType( chr, traditional::kIfchr ) );
#if OSWIN_TEST_HOST_WAIT_MACROS   // the macros do not exist to name on a host without them, so this cannot be an if
    CHECK( kModeLink == unsigned( S_IFLNK ) );
    CHECK( S_ISLNK( symlink ) );
    CHECK( S_ISDIR( junction ) );
    CHECK( S_ISREG( oneDrive ) );
    CHECK( S_ISDIR( dir ) );
    CHECK( S_ISREG( regular ) );
    CHECK( S_ISFIFO( fifo ) );
    CHECK( S_ISCHR( chr ) );
#endif
    CHECK( modePermissionBits( 0 ) == 0777 );
    CHECK( modePermissionBits( kFileAttributeReadonly ) == 0555 );
    CHECK( modePermissionBits( kFileAttributeReadonly | kFileAttributeDirectory ) == 0777 );   // read-only is not honoured on directories
}

// ── 6. time, wait status, timeouts, socket descriptors ──────────────────────────────────────────────────────
TEST_CASE( "time: FILETIME ticks to Unix seconds and nanoseconds, floor-divided" )
{
    const auto at = []( std::int64_t ticks ) { return unixTimeFromFiletime( ticks ); };
    CHECK( at( kFiletimeTicksAtUnixEpoch ).seconds == 0 );
    CHECK( at( kFiletimeTicksAtUnixEpoch ).nanoseconds == 0 );
    CHECK( at( kFiletimeTicksAtUnixEpoch + 1 ).nanoseconds == 100 );
    CHECK( at( kFiletimeTicksAtUnixEpoch - 1 ).seconds == -1 );
    CHECK( at( kFiletimeTicksAtUnixEpoch - 1 ).nanoseconds == 999999900 );
    // 2026-09-16T00:00:00Z = 1789516800 s
    const UnixTime day = at( kFiletimeTicksAtUnixEpoch + 1789516800LL * 10000000LL + 1234567 );
    CHECK( day.seconds == 1789516800 );
    CHECK( day.nanoseconds == 123456700 );
}

TEST_CASE( "wait status: the encoding decodes as a POSIX child's would — traditional encoding, and the host's W* macros" )
{
    // Checks one status through every decoder this host has: the traditional-encoding oracle, the header's own
    // decoders (what os.h's W* macros expand to on Windows), and the host's W* macros where they exist.
    const auto exitedWith = []( int status, int code )
    {
        CHECK( traditional::exited( status ) );
        CHECK( !traditional::signaled( status ) );
        CHECK( traditional::exitStatus( status ) == code );
        CHECK( rw::oswin::waitIfExited( status ) );
        CHECK( !rw::oswin::waitIfSignaled( status ) );
        CHECK( rw::oswin::waitExitStatus( status ) == code );
#if OSWIN_TEST_HOST_WAIT_MACROS
        const int hostStatus = status;   // macOS's W* macros need an lvalue
        CHECK( WIFEXITED( hostStatus ) );
        CHECK( !WIFSIGNALED( hostStatus ) );
        CHECK( WEXITSTATUS( hostStatus ) == code );
#endif
    };
    const auto signaledWith = []( int status, int signal )
    {
        CHECK( traditional::signaled( status ) );
        CHECK( !traditional::exited( status ) );
        CHECK( traditional::termSig( status ) == signal );
        CHECK( rw::oswin::waitIfSignaled( status ) );
        CHECK( !rw::oswin::waitIfExited( status ) );
        CHECK( rw::oswin::waitTermSig( status ) == signal );
#if OSWIN_TEST_HOST_WAIT_MACROS
        const int hostStatus = status;
        CHECK( WIFSIGNALED( hostStatus ) );
        CHECK( !WIFEXITED( hostStatus ) );
        CHECK( WTERMSIG( hostStatus ) == signal );
#endif
    };
    for( const std::uint32_t code : { 0u, 1u, 2u, 3u, 42u, 126u, 127u, 255u } )
    {
        CAPTURE( code );
        exitedWith( waitStatusFromExit( code ), int( code ) );
    }
    exitedWith( waitStatusFromExit( 256 ), 0 );   // POSIX keeps the low 8 bits too
    for( const auto& [ code, signal ] : { std::pair{ 0xC0000005u, 11 }, std::pair{ 0xC00000FDu, 11 }, std::pair{ 0xC000001Du, 4 },
                                          std::pair{ 0xC0000094u, 8 }, std::pair{ 0x80000003u, 5 }, std::pair{ 0xC0000409u, 6 },
                                          std::pair{ 0xC000013Au, 2 } } )
    {
        CAPTURE( code );
        signaledWith( waitStatusFromExit( code ), signal );
    }
    signaledWith( waitStatusFromSignal( kSignalKill ), 9 );
}

TEST_CASE( "SO_RCVTIMEO: a nonzero timeval never becomes Winsock's 0 = wait forever" )
{
    CHECK( millisecondsFromTimeval( 10, 0 ) == 10000u );
    CHECK( millisecondsFromTimeval( 0, 500 ) == 1u );          // PR #44 truncated this to 0: an infinite wait
    CHECK( millisecondsFromTimeval( 0, 1000 ) == 1u );
    CHECK( millisecondsFromTimeval( 0, 1001 ) == 2u );
    CHECK( millisecondsFromTimeval( 0, 0 ) == 0u );
    CHECK( millisecondsFromTimeval( -1, 0 ) == 0u );
    CHECK( millisecondsFromTimeval( 5000000, 0 ) == 0xFFFFFFFEu );
}

TEST_CASE( "socket descriptors: a range the CRT never hands out" )
{
    CHECK( kSocketFdBase > 8192 );
    CHECK( !isSocketFd( 0 ) );
    CHECK( !isSocketFd( 8191 ) );
    CHECK( !isSocketFd( -1 ) );
    CHECK( isSocketFd( kSocketFdBase ) );
    CHECK( isSocketFd( kSocketFdBase + kSocketFdCount - 1 ) );
    CHECK( !isSocketFd( kSocketFdBase + kSocketFdCount ) );
    CHECK( isDirwatchFd( kDirwatchFdBase ) );
    CHECK( !isDirwatchFd( kSocketFdBase ) );
    CHECK( !isSocketFd( kDirwatchFdBase ) );
    CHECK( !isDirwatchFd( 3 ) );
}

// ── 7. the shell ────────────────────────────────────────────────────────────────────────────────────────────
TEST_CASE( "shell: only an absolute, non-WSL bash is acceptable" )
{
    CHECK( isAcceptableShell( "C:/Program Files/Git/bin/bash.exe" ) );
    CHECK( isAcceptableShell( "C:\\Program Files\\Git\\usr\\bin\\bash.exe" ) );
    CHECK( isAcceptableShell( "//server/tools/Git/bin/BASH.EXE" ) );
    CHECK( !isAcceptableShell( "C:\\Windows\\System32\\bash.exe" ) );                              // WSL launcher
    CHECK( !isAcceptableShell( "c:/windows/sysnative/bash.exe" ) );
    CHECK( !isAcceptableShell( "C:/Users/x/AppData/Local/Microsoft/WindowsApps/bash.exe" ) );      // WSL alias
    CHECK( !isAcceptableShell( "bash.exe" ) );                                                     // relative: the current directory
    CHECK( !isAcceptableShell( ".\\bash.exe" ) );
    CHECK( !isAcceptableShell( "repo/tools/bash.exe" ) );
    CHECK( !isAcceptableShell( "C:/repo/sh.exe" ) );                                               // not bash
    CHECK( !isAcceptableShell( "C:bash.exe" ) );                                                   // drive-relative
}

TEST_CASE( "doctor PATH remedy: PowerShell's assignment, native separators, never a POSIX export line (#334)" )
{
    const std::string h = powerShellPathPrependHint( "C:/Program Files/ripwire tools/ripwire-0.6.4-windows-x64" );
    CHECK( h.starts_with( "$env:Path = 'C:\\Program Files\\ripwire tools\\ripwire-0.6.4-windows-x64;' + $env:Path" ) );
    CHECK( h.find( "export PATH" ) == std::string::npos );
    CHECK( h.find( '/' ) == std::string::npos );
    CHECK( powerShellPathPrependHint( "//server/share/bin" ).starts_with( "$env:Path = '\\\\server\\share\\bin;' + $env:Path" ) );   // UNC
}

// CodeRabbit 4109273959: an unquoted (or double-quoted) directory pasted into PowerShell would let a `$`, a
// backtick or `$(...)` inside it expand or run. Single-quoting makes it a literal — asserted byte for byte,
// rather than trusting that "looks quoted" is "is safe".
TEST_CASE( "doctor PATH remedy: a directory with $, a backtick, a quote and a space stays a literal" )
{
    const std::string h = powerShellPathPrependHint( "C:/tools/$env:UserProfile `whoami` it'is weird/bin" );
    // '/' -> '\\', then the whole (dir + ";") is single-quoted; an embedded ' doubles to ''.
    CHECK( h == "$env:Path = 'C:\\tools\\$env:UserProfile `whoami` it''is weird\\bin;' + $env:Path"
                " in PowerShell (this window; add the directory to your user Path for new ones)" );
}

// PowerShell's tokenizer also closes a single-quoted literal on the typographic quotes U+2018..U+201B, so a directory
// named with one (a curly apostrophe, as in O’Brien) must have it doubled like the ASCII quote, or the rest of the name
// runs as code when the hint is pasted.
TEST_CASE( "doctor PATH remedy: PowerShell's typographic single quotes are doubled too" )
{
    CHECK( powerShellPathPrependHint( "C:/O\xE2\x80\x99" "Brien/bin" )
           == "$env:Path = 'C:\\O\xE2\x80\x99\xE2\x80\x99" "Brien\\bin;' + $env:Path"
              " in PowerShell (this window; add the directory to your user Path for new ones)" );
    CHECK( powerShellSingleQuote( "\xE2\x80\x98|\xE2\x80\x9A|\xE2\x80\x9B" )
           == "'\xE2\x80\x98\xE2\x80\x98|\xE2\x80\x9A\xE2\x80\x9A|\xE2\x80\x9B\xE2\x80\x9B'" );
    // neighbours of the range, and a truncated sequence at the end, are not quotes and pass through once
    CHECK( powerShellSingleQuote( "\xE2\x80\x97\xE2\x80\x9C\xE2\x80" ) == "'\xE2\x80\x97\xE2\x80\x9C\xE2\x80'" );
    CHECK( powerShellSingleQuote( "it's" ) == "'it''s'" );
}

TEST_CASE( "executables: extension detection and PATHEXT membership" )
{
    CHECK( hasExtension( "tool.exe" ) );
    CHECK( hasExtension( "C:/bin/tool.CMD" ) );
    CHECK( !hasExtension( "tool" ) );
    CHECK( !hasExtension( ".profile" ) );
    CHECK( !hasExtension( "dir.d/tool" ) );
    CHECK( !hasExtension( "dir.d\\tool" ) );
    CHECK( !hasExtension( "tool." ) );
    const std::string_view pathext = ".COM;.EXE;.BAT;.CMD";
    CHECK( extensionInList( "C:/x/ripwire.exe", pathext ) );
    CHECK( extensionInList( "codex.cmd", pathext ) );
    CHECK( !extensionInList( "script.py", pathext ) );
    CHECK( !extensionInList( "ripwire", pathext ) );
    CHECK( !extensionInList( "a.exe", "" ) );
    CHECK( extensionInList( "a.exe", ";;.exe;" ) );
}

TEST_CASE( "shell: PATH entries split on ';', keep empties for the caller to skip, and unquote" )
{
    const std::string_view list = "C:\\Git\\bin;;\"C:\\odd;dir\";relative;D:/x";
    std::size_t at = 0;
    std::vector<std::string_view> entries;
    while( at <= list.size() ) { entries.push_back( nextPathListEntry( list, at ) ); }
    // a quoted entry containing ';' is split by the ';' first — the documented Windows behaviour is that PATH
    // entries cannot contain ';' at all, so the halves are what cmd.exe sees too
    CHECK( entries.front() == "C:\\Git\\bin" );
    CHECK( entries[ 1 ].empty() );
    CHECK( entries.back() == "D:/x" );
    std::size_t one = 0;
    CHECK( nextPathListEntry( "\"C:\\Program Files\\Git\\bin\"", one ) == "C:\\Program Files\\Git\\bin" );
}
