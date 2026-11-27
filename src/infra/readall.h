#pragma once

// readall.h — the ONE body that reads a stream to its end and says whether it got there.
//
// WHY. `while( ( n = fread( ... ) ) > 0 ) append;` stops the same way at end of file and at a read error: fread's short
// count cannot tell them apart, only the stream's error flag can, and a loop that never asks hands its caller the prefix
// it got as if it were the whole file. The answer built on it is plausible and silently short (TIDY-TRIAGE C2: the
// compact-legend capture read back, --batch=FILE, --arch=FILE, --slice's definition file). Every read-to-the-end loop
// goes through here, so the question is asked in one place.
//
// THE CONTRACT
//   - appendRestOf appends the bytes from the stream's position to its end and returns false when the read stopped on an
//     error. `out` then ends in an unknown prefix: the caller reports the failure and never serves it as the whole;
//   - the loop stops at the first short count (end of file and error alike: fread retries a short read itself, a pipe
//     included), so it never reads a stream already at its end (clang-analyzer-unix.Stream; darkflags.h readWhole is the
//     same loop with a size cap);
//   - readFileToEnd is the path form: nullopt when the file cannot be opened or read to its end; an empty file is an
//     engaged empty string. A directory opens on macOS and Linux and its first read fails (EISDIR): unreadable here.
//
// TEST SEAM. setReadErrorSeam( SUBSTR ) (the host binary feeds it from a test-only environment variable, so this layer
// names no host): a read whose `what` (the path, or the caller's label for a nameless stream)
// contains SUBSTR keeps the first half of its bytes and reports an error, as a mid-file EIO would. Deterministic and
// LD_PRELOAD-free. test/readerrorcheck.sh drives it where no real error can be provoked from outside (a temp file the
// process wrote, an indexed source file) and passes a directory where the path is the caller's.

#include "ownedfile.h"   // OwnedFile — the stream is owned before any other line runs

#include <cstdio>
#include <optional>
#include <string>
#include <string_view>

namespace rw
{

// The seam's one piece of state: the substring a failing read must contain, empty when the seam is off.
inline std::string& readErrorSeamSubstr() noexcept
{
    static std::string substr;
    return substr;
}

// Turn the seam on for this process (null or empty turns it off). Called once at startup, before any read.
inline void setReadErrorSeam( const char* substr )
{
    readErrorSeamSubstr() = substr != nullptr ? substr : "";
}

// The test seam above, asked by name: true when a seam is set and `what` contains it.
inline bool readErrorInjected( std::string_view what ) noexcept
{
    const std::string& seam = readErrorSeamSubstr();
    return !seam.empty() && what.find( seam ) != std::string_view::npos;
}

// After a read loop has stopped: true when it stopped at the end, false when on an error (the stream's flag, or the seam).
// A reader that streams instead of buffering (ccjson.h ccCountLoc, quality.h forEachGitNulRecord) asks this.
inline bool readEndedWhole( std::FILE* f, std::string_view what ) noexcept
{
    return std::ferror( f ) == 0 && !readErrorInjected( what );
}

// Every byte from `f`'s position to its end, appended to `out`. False when the read ended on a stream error.
[[nodiscard]] inline bool appendRestOf( std::FILE* f, std::string& out, std::string_view what = {} )
{
    const std::size_t from = out.size();
    char              buf[ 65536 ];
    for( std::size_t n = sizeof( buf ); n == sizeof( buf ); )
    {
        n = std::fread( buf, 1, sizeof( buf ), f );
        out.append( buf, n );
    }
    if( readErrorInjected( what ) )
    {
        out.resize( from + ( out.size() - from ) / 2 );   // the seam keeps half, as a mid-file EIO would
    }
    return readEndedWhole( f, what );
}

// The whole file, or nullopt when it cannot be opened or read to its end. An empty file is an engaged empty string.
[[nodiscard]] inline std::optional<std::string> readFileToEnd( const std::string& path )
{
    OwnedFile in = openOwnedFile( path.c_str(), "rb" );
    if( !in )
    {
        return std::nullopt;
    }
    std::string out;
    if( !appendRestOf( in.file, out, path ) )
    {
        return std::nullopt;
    }
    return out;
}

}   // namespace rw
