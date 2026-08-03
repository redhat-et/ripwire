#pragma once

// mcpedit.h — the symbol-addressed EDIT verbs for --mcp: replace_symbol_body /
// insert_before_symbol / insert_after_symbol. The mcpedit namespace (resolve → per-file advisory
// lock → freshness byte-hash gate → in-memory splice → atomic temp-rename write) plus the
// runEditVerb() driver. The safety contract IS the feature: every refusal leaves the file
// byte-identical. Extracted from mcp.h (the mcp.h/main.cpp concern-split). Includes mcpindex.h;
// included by mcp.h (runMcp dispatches here).

#include "mcpindex.h"
#include "hashutil.h"   // sanitizer-clean modulo-2^64 FNV multiplication

namespace rw
{

// ─── symbol-addressed EDIT verbs (replace_symbol_body / insert_before_symbol / insert_after_symbol) ─────
//
// These are the FIRST write verbs — ripwire is otherwise read-only, so the safety contract IS the feature.
// Every failure path REFUSES with a JSON-RPC error and leaves the file byte-for-byte unchanged; a partial
// write is never possible (splice happens in memory, then one atomic temp-file rename). The refusals:
//   • symbol resolves to 0 defs → error listing the nearest names (agent picks a real one)
//   • symbol resolves to >1 defs → error listing every candidate as file:line (agent retries with `path`)
//   • the file changed since the index was built (byte-hash mismatch) → error telling the agent to call any
//     read verb first (which refreshes the index), so span offsets are never applied to shifted bytes
//   • the span is insane (a>=b, or b>filesize) → refuse (degrade, never splice out of bounds)
//   • the file can't be re-read → refuse
namespace mcpedit
{
    enum class Op { ReplaceBody, InsertBefore, InsertAfter };

    // the outcome of an edit attempt: either a success JSON payload, or a JSON-RPC error {code,message}.
    struct Outcome
    {
        bool        ok = false;
        int         errCode = -32602;
        std::string message;      // on error
        std::string resultJson;   // on success (a JSON object: applied span + old index stamp + refresh note)
    };

    // the K symbol names closest to `name` by a cheap edit-distance-ish score, for the "0 matches" hint. We
    // don't need true Levenshtein — a shared-prefix + length-delta ranking surfaces the obvious typo/overload,
    // which is all the hint is for. Deterministic (id-order stable sort by score then name).
    inline std::vector<std::string> nearestNames( const IngestResult& ing, const std::string& name, std::size_t k )
    {
        struct Cand { int score; std::string n; };
        std::vector<Cand> cands;
        cands.reserve( ing.symbols.size() );
        for( const Symbol& s : ing.symbols )
        {
            if( s.name.empty() )
            {
                continue;
            }
            // shared-prefix length (case-insensitive) minus length difference → higher = closer
            std::size_t pfx = 0;
            const std::size_t lim = std::min( s.name.size(), name.size() );
            while( pfx < lim && std::tolower( (unsigned char)s.name[pfx] ) == std::tolower( (unsigned char)name[pfx] ) )
            {
                ++pfx;
            }
            const int lenDelta = int( s.name.size() ) - int( name.size() );
            const int score = int( pfx ) * 4 - ( lenDelta < 0 ? -lenDelta : lenDelta );
            cands.push_back( { score, s.name } );
        }
        std::sort( cands.begin(), cands.end(),
                   []( const Cand& a, const Cand& b ) { return a.score != b.score ? a.score > b.score : a.n < b.n; } );
        std::vector<std::string> out;
        for( const Cand& c : cands )
        {
            if( out.size() >= k )
            {
                break;
            }
            if( !out.empty() && out.back() == c.n )
            {
                continue; // dedup same name (overloads)
            }
            out.push_back( c.n );
        }
        return out;
    }

    // resolve `symbol` to exactly one def, optionally narrowed by `pathHint` (a substring match on the file
    // path, mirroring resolveFocus's "file:name" file filter). Returns kNoNode and fills `err` with a ready
    // JSON-RPC message on any non-unique outcome (0 → nearest-names hint; >1 → candidate file:line list).
    inline NodeId resolveOneForEdit( const IngestResult& ing, const std::string& symbol,
                                     const std::string& pathHint, std::string& err )
    {
        std::vector<NodeId> matches;
        for( const Symbol& s : ing.symbols )
        {
            if( s.name != symbol )
            {
                continue;
            }
            if( !pathHint.empty() && !filePathContains( ing.files[s.fileId], pathHint ) )
            {
                continue; // `<label>/./<rel>`-tolerant
            }
            matches.push_back( s.id );
        }
        std::sort( matches.begin(), matches.end() );

        if( matches.size() == 1 )
        {
            // KIND GUARD (edit path only): a doc `Section` — a markdown heading, or a whole-file section for
            // .html/.csv/.ipynb — is NOT an editable code definition. Its stored span does not delimit a
            // definition, and for html/csv/ipynb `endByte` is the EXTRACTED-text length, unrelated to raw-file
            // byte coordinates; splicing it silently corrupts the doc/data file (e.g. deletes an HTML <head>)
            // while reporting success. The freshness + `a<b && b<=size` gates cannot catch a span that is
            // spatially in-bounds but semantically meaningless. Refuse — the read verbs may still surface
            // Section handles, but nothing may WRITE through one.
            const Symbol& s = ing.symbols[ matches[0] ];
            if( s.kind == SymKind::Section )
            {
                err = "symbol '" + symbol + "' is a document heading/section (" + ing.files[ s.fileId ]
                    + "), not an editable code definition — refusing to avoid corrupting the doc/data file";
                return kNoNode;
            }
            return matches[0];
        }

        if( matches.empty() )
        {
            std::string m = "symbol '" + symbol + "' not found";
            if( !pathHint.empty() )
            {
                m += " under path '" + pathHint + "'";
            }
            const std::vector<std::string> near = nearestNames( ing, symbol, 5 );
            if( !near.empty() )
            {
                m += "; nearest: ";
                for( std::size_t i = 0; i < near.size(); ++i )
                {
                    if( i )
                    {
                        m += ", ";
                    }
                    m += near[i];
                }
            }
            err = m;
            return kNoNode;
        }

        // >1 — list every candidate as file:line so the agent can retry with a disambiguating `file`. On a
        // multi-root index (A11, decided 2026-07-11) the candidate paths carry their ROOT LABEL, so a
        // same-named symbol in >1 root is disambiguated by passing the label/rel spelling as `file` (e.g.
        // `file:"svc/"`); the write always lands in the real disk file behind that labeled identity.
        const bool  isWorkspace = !ing.fileRoot.empty();
        std::string m = "symbol '" + symbol + "' is ambiguous (" + std::to_string( matches.size() )
                      + " definitions) — retry with a 'file' substring to disambiguate"
                      + ( isWorkspace ? " (in a multi-root workspace, pass the root-labeled path form, e.g. file:\"svc/\")" : "" )
                      + ". candidates: ";
        for( std::size_t i = 0; i < matches.size(); ++i )
        {
            const Symbol& s = ing.symbols[ matches[i] ];
            if( i )
            {
                m += "; ";
            }
            m += ing.files[ s.fileId ] + ":" + std::to_string( s.line );
        }
        err = m;
        return kNoNode;
    }

    // apply the edit. Pure over (span, op, text, srcBytes) → the new file bytes, plus the applied [a,b) span.
    // Newline rule (documented in the schemas so agents can rely on it):
    //   ReplaceBody   — the new bytes are EXACTLY new_body; every byte outside [sigStartByte, endByte) is
    //                   preserved verbatim (no newline added or removed at either seam).
    //   InsertBefore  — text is inserted starting at sigStartByte. If text does not END with '\n', one '\n'
    //                   is appended so the inserted block and the existing definition stay on separate lines.
    //   InsertAfter   — text is inserted at endByte (past the def's final byte). If text does not BEGIN with
    //                   '\n', one leading '\n' is prepended so the existing def and the inserted block stay
    //                   on separate lines. The byte at endByte (and everything after) is preserved verbatim.
    inline std::string applyEdit( Op op, const std::string& src, std::size_t a, std::size_t b,
                                  const std::string& text, std::size_t& outStart, std::size_t& outEnd )
    {
        std::string out;
        if( op == Op::ReplaceBody )
        {
            out.reserve( src.size() - ( b - a ) + text.size() );
            out.append( src, 0, a );
            outStart = a;
            out += text;
            outEnd = out.size();
            out.append( src, b, src.size() - b );
        }
        else if( op == Op::InsertBefore )
        {
            std::string ins = text;
            if( ins.empty() || ins.back() != '\n' )
            {
                ins += '\n';
            }
            out.reserve( src.size() + ins.size() );
            out.append( src, 0, a );
            outStart = a;
            out += ins;
            outEnd = out.size();
            out.append( src, a, src.size() - a );
        }
        else   // InsertAfter — at endByte, preserving the byte at b exactly
        {
            std::string ins = text;
            if( ins.empty() || ins.front() != '\n' )
            {
                ins.insert( ins.begin(), '\n' );
            }
            out.reserve( src.size() + ins.size() );
            out.append( src, 0, b );
            outStart = b;
            out += ins;
            outEnd = out.size();
            out.append( src, b, src.size() - b );
        }
        return out;
    }

    // A3-F8: the advisory edit lock lives in the per-user CACHE DIR, keyed by an FNV-1a-64 hash of the
    // absolute target path — NOT as a "<path>.ripwire-lock" sidecar next to the target. The old sidecar was
    // created and never unlinked, so every MCP edit left permanent litter in the user's repo (git-status
    // noise). The cache-dir path is a deterministic pure function of the target path, so two ripwire processes
    // editing the SAME file still open the SAME lock file and flock still serializes them cross-process (the F1
    // guarantee is preserved) — it just never lands in the repo tree. Same cache-dir ladder as mcpCachePath.
    inline std::string editLockPath( const std::string& targetPath )
    {
        std::uint64_t h = 1469598103934665603ULL;      // FNV-1a-64 of the target path → a stable per-file lock name
        for( char c : targetPath ) { h ^= static_cast<unsigned char>( c ); h = hashutil::fnv1aMultiply( h ); }
        char name[ 64 ];
        std::snprintf( name, sizeof( name ), "ripwire-edit-%016llx.lock", (unsigned long long)h );
        return quality::cacheDirLadder() + "/" + name;   // shared per-user cache-dir ladder (no repo-tree sidecar)
    }

    // F1: per-file advisory edit lock — serializes two COOPERATING ripwire MCP edit operations on one file so
    // they can't race a read→check→splice→rename lost-update. We lock a STABLE lockfile keyed by the target
    // path (editLockPath, A3-F8: in the per-user cache dir, not a repo-tree sidecar), NOT the target itself:
    // the atomic rename swaps the target's inode, so a flock on the target fd wouldn't cover the rename
    // destination. The keyed lockfile's inode never changes, so its lock does span the whole read-modify-write.
    // HONEST LIMIT: this is ADVISORY — a non-cooperating external writer (an editor/formatter that doesn't take
    // this lock) is not serialized by it; that residual is handled by the re-check-before-rename in runEditVerb,
    // which shrinks (but cannot fully close) the external-writer window. Never blocks forever: LOCK_NB with a
    // short bounded retry, then degrade to lock-free (the re-check still guards correctness). RAII: the fd is
    // closed (releasing the flock) at scope exit, deterministically.
    struct EditLock
    {
        int  fd     = -1;
        bool locked = false;

        explicit EditLock( const std::string& targetPath )
        {
            const std::string lockPath = editLockPath( targetPath );
            fd = ::open( lockPath.c_str(), O_RDWR | O_CREAT, 0644 );
            if( fd < 0 ) { DEGRADED_PATH_ALERT( "edit lockfile open failed; proceeding lock-free (re-check still guards)" ); return; }

            // ~200 ms bounded acquire: 20 tries × 10 ms. If a peer holds it longer, degrade rather than hang —
            // the freshness re-check before rename is the correctness floor, the lock is only the fast path.
            for( int attempt = 0; attempt < 20; ++attempt )
            {
                if( ::flock( fd, LOCK_EX | LOCK_NB ) == 0 ) { locked = true; break; }
                if( errno != EWOULDBLOCK )
                {
                    break;
                }
                struct timespec ts{ 0, 10 * 1000 * 1000 };   // 10 ms
                ::nanosleep( &ts, nullptr );
            }
            if( !locked )
            {
                DEGRADED_PATH_ALERT( "edit lock contended past timeout; proceeding lock-free (re-check still guards)" );
            }
        }

        ~EditLock()
        {
            if( fd >= 0 )
            {
                if( locked )
                {
                    ::flock( fd, LOCK_UN );
                }
                ::close( fd );
            }
        }

        EditLock( const EditLock& ) = delete;
        EditLock& operator=( const EditLock& ) = delete;
    };

    // atomic write: bytes → "<path>.<pid>.tmp" → rename over `path` (the saveCache pattern from ingest.cpp).
    // rename(2) is atomic, so a reader never sees a torn file and a crash mid-write leaves the original intact.
    // Returns false on any open/write/rename failure (the temp is cleaned up) — caller keeps the file as-is.
    //
    // A3-F7: PRESERVE the original's MODE and DURABLY commit. The pre-fix version created the temp via fopen()
    // (mode = 0666 & ~umask, typically 0644) and renamed it over the target, so editing an executable script
    // silently stripped +x. The fix: fstat() the ORIGINAL first, fchmod() the temp to its exact mode bits
    // before the rename (a new file — original absent — keeps the default umask mode), and fsync() the temp fd
    // before close/rename so the bytes are durable before the inode swap (a crash can't leave a renamed-but-
    // unwritten file). Uses POSIX fds (open/write/fsync/fchmod/fstat) because fchmod/fsync need a descriptor.
    // HONEST LIMIT: hard links to the target and its xattrs are still not carried across the rename — that is
    // inherent to the temp-then-rename atomicity model (a fresh inode) and is the documented trade for the
    // torn-write-free guarantee; the mode bits (the load-bearing +x case) ARE preserved.
    inline bool atomicWrite( const std::string& path, const std::string& bytes )
    {
        // capture the original's mode (if it exists) so we can restore it onto the fresh temp inode.
        struct stat orig{};
        const bool  haveOrig = ( ::stat( path.c_str(), &orig ) == 0 );

        const std::string tmp = path + "." + std::to_string( ::getpid() ) + ".tmp";
        const int fd = ::open( tmp.c_str(), O_WRONLY | O_CREAT | O_TRUNC, 0644 );
        if( fd < 0 )
        {
            return false;
        }

        // write the full buffer (a short write is a failure); a partial-write loop handles a signal-truncated write.
        bool        wErr = false;
        std::size_t off  = 0;
        while( off < bytes.size() )
        {
            const ssize_t n = ::write( fd, bytes.data() + off, bytes.size() - off );
            if( n <= 0 ) { wErr = true; break; }
            off += (std::size_t)n;
        }

        // A3-F7: restore the original mode bits onto the temp before the rename (preserve +x etc.). A new file
        // (no original) keeps the umask default. fchmod failure is non-fatal — degrade to the default mode.
        if( !wErr && haveOrig )
        {
            if( ::fchmod( fd, orig.st_mode & 07777 ) != 0 )
            {
                DEGRADED_PATH_ALERT( "atomicWrite: could not restore original file mode; wrote with default mode" );
            }
        }

        // A3-F7: fsync the data to disk BEFORE the atomic rename so a crash can't leave a renamed-but-empty file.
        if( !wErr && ::fsync( fd ) != 0 )
        {
            DEGRADED_PATH_ALERT( "atomicWrite: fsync failed; proceeding (bytes may not be durable across a crash)" );
        }

        if( ::close( fd ) != 0 )
        {
            wErr = true;
        }
        if( wErr ) { ::unlink( tmp.c_str() ); return false; }
        if( std::rename( tmp.c_str(), path.c_str() ) != 0 ) { ::unlink( tmp.c_str() ); return false; }
        return true;
    }
}   // namespace mcpedit

// perform an edit verb end-to-end (resolve → verify freshness → splice → atomic write → invalidate index).
// `root` = repo path, `symbol` = the def name, `pathHint` = optional disambiguating file-path substring,
// `text` = new_body (ReplaceBody) or the inserted text (InsertBefore/After). Never throws for expected
// failures — returns an Outcome carrying either the success JSON or a JSON-RPC error {code,message}.
inline mcpedit::Outcome runEditVerb( const std::string& root, mcpedit::Op op, const std::string& symbol,
                                     const std::string& pathHint, const std::string& text )
{
    mcpedit::Outcome oc;

    const McpIndex&     ix  = getIndex( root );
    const IngestResult& ing = ix.ing;

    // 1. resolve to exactly one def (0 → nearest-names hint; >1 → candidate file:line list; both refuse)
    std::string resolveErr;
    const NodeId f = mcpedit::resolveOneForEdit( ing, symbol, pathHint, resolveErr );
    if( f == kNoNode || f >= ing.symbols.size() )
    {
        oc.ok = false; oc.errCode = -32602;
        oc.message = resolveErr.empty() ? ( "symbol '" + symbol + "' not found" ) : resolveErr;
        return oc;
    }

    const Symbol&      s      = ing.symbols[f];
    const std::uint32_t fileId = s.fileId;
    const std::string& path   = ing.files[ fileId ];             // LABELED identity — user-facing messages / candidate lists
    // A11 (decided 2026-07-11): all disk I/O goes to the REAL on-disk path via the
    // diskPath seam, NEVER the labeled spelling. Single-root (realPaths empty) → disk == path, byte-identical.
    // Multi-root writes land in the correct root's file even though the index identity is `<label>/<rel>`.
    const std::string& disk   = diskPath( ing, fileId );

    // A4-F14: refuse to edit through a symlink. atomicWrite's temp-then-rename lands the new bytes at
    // `disk` by swapping the inode the LAST path component names — for a symlink that REPLACES the link
    // entry with a plain file, leaving the real target file completely untouched (a silent, data-losing
    // surprise: the agent thinks it edited the target, but it edited nothing it can see). lstat (not stat)
    // so we inspect the link itself rather than following it.
    struct stat linkSt{};
    if( ::lstat( disk.c_str(), &linkSt ) == 0 && S_ISLNK( linkSt.st_mode ) )
    {
        oc.ok = false; oc.errCode = -32602;
        oc.message = "refusing to edit '" + path + "': it is a symlink, and editing through it would replace "
                     "the link itself with a regular file rather than modifying the real target — the target "
                     "would be silently left unchanged. Resolve the symlink and edit the real file directly.";
        return oc;
    }

    // F1: hold a per-file advisory lock across the ENTIRE read→check→splice→rename below, so two cooperating
    //     ripwire MCP edit ops on one file serialize instead of racing (RAII: released at function return).
    //     Degrades to lock-free on contention/failure — the re-check before the rename is the correctness floor.
    //     Keyed by the REAL disk path so cross-process serialization lands on the actual file, not the label.
    const mcpedit::EditLock editLock( disk );

    // 2. staleness: re-read the file NOW and verify its bytes still match what the index was built from.
    //    A mismatch means the span offsets below may address shifted bytes → refuse, tell the agent to
    //    refresh (any read verb rebuilds the index) before retrying. This is the load-bearing safety check.
    bool readOk = false;
    const std::string src = mcpdetail::readFileBytes( disk, readOk );
    if( !readOk )
    {
        oc.ok = false; oc.errCode = -32603;
        oc.message = "cannot read file '" + path + "' to apply edit";
        return oc;
    }
    const std::uint64_t freshHash = mcpdetail::byteHash( src.data(), src.size() );
    const std::uint64_t builtHash = ( fileId < ix.fileByteHash.size() ) ? ix.fileByteHash[ fileId ] : 0;
    if( freshHash != builtHash || builtHash == 0 )
    {
        oc.ok = false; oc.errCode = -32602;
        oc.message = "file '" + path + "' changed since index was built; call any read verb to refresh the index, then retry";
        return oc;
    }
    // pin the content hash we spliced against — re-checked immediately before the rename (F1) so a concurrent
    // committed write in the [read..rename] window is DETECTED and REFUSED, never silently clobbered.
    const std::uint64_t baseHash = freshHash;

    // 3. span sanity — the FULL def span is [sigStartByte, endByte) (same span --expand slices). Degrade,
    //    never assert: an out-of-range span refuses rather than splicing out of bounds.
    const std::size_t a = s.sigStartByte, b = s.endByte;
    if( !( a < b && b <= src.size() ) )
    {
        oc.ok = false; oc.errCode = -32603;
        oc.message = "definition span for '" + symbol + "' is invalid (a=" + std::to_string( a )
                   + " b=" + std::to_string( b ) + " size=" + std::to_string( src.size() ) + ")";
        return oc;
    }

    // 4. splice in memory, then ONE atomic temp-rename write (no partial write is possible).
    std::size_t newStart = 0, newEnd = 0;
    const std::string newBytes = mcpedit::applyEdit( op, src, a, b, text, newStart, newEnd );

    // F1: RE-CHECK FRESHNESS IMMEDIATELY BEFORE THE RENAME. The advisory lock serializes cooperating ripwire
    //     edits, but a NON-cooperating external writer (editor/formatter on save) won't take the lock. So right
    //     before we swap the inode, re-read the file and compare its hash to the one we spliced against; if it
    //     changed, ABORT and refuse as stale — never rename our splice-over-stale-bytes on top of the other
    //     party's committed write. This collapses the lost-update window to the tiny gap between this re-hash
    //     and the rename (a residual that advisory locks cannot fully close vs an external writer — documented
    //     in the verb schema). Same refusal SHAPE as the pre-check freshness gate above.
    {
        bool              recheckOk = false;
        const std::string cur       = mcpdetail::readFileBytes( disk, recheckOk );
        const std::uint64_t curHash = recheckOk ? mcpdetail::byteHash( cur.data(), cur.size() ) : 0;
        if( !recheckOk || curHash != baseHash )
        {
            oc.ok = false; oc.errCode = -32602;
            oc.message = "file '" + path + "' changed since index was built; call any read verb to refresh the index, then retry"
                         " (concurrent write detected just before commit — edit aborted, file left unchanged)";
            return oc;
        }
    }

    if( !mcpedit::atomicWrite( disk, newBytes ) )
    {
        oc.ok = false; oc.errCode = -32603;
        oc.message = "atomic write failed for '" + path + "'; file left unchanged";
        return oc;
    }

    // 5. force the cached index stale so the next verb rebuilds (belt-and-braces on top of the mtime watch),
    //    and report the applied span + the OLD index stamp with a note that it will refresh.
    char oldStamp[ 96 ];
    std::snprintf( oldStamp, sizeof( oldStamp ), "[index: files=%zu symbols=%zu hash=%08x]",
                   ing.files.size(), ing.symbols.size(), (unsigned)( ix.contentHash & 0xFFFFFFFFu ) );
    invalidateMcpIndex();

    const char* opName = ( op == mcpedit::Op::ReplaceBody ) ? "replace_symbol_body"
                       : ( op == mcpedit::Op::InsertBefore ) ? "insert_before_symbol"
                       : "insert_after_symbol";
    oc.ok = true;
    oc.resultJson = std::string( "{\"applied\":\"" ) + opName
                  + "\",\"symbol\":\"" + mcpdetail::jsonEscape( symbol )
                  + "\",\"file\":\"" + mcpdetail::jsonEscape( path )
                  + "\",\"span\":{\"start\":" + std::to_string( newStart ) + ",\"end\":" + std::to_string( newEnd ) + "}"
                  + ",\"old_file_bytes\":" + std::to_string( src.size() )
                  + ",\"new_file_bytes\":" + std::to_string( newBytes.size() )
                  + ",\"stale_index\":\"" + mcpdetail::jsonEscape( oldStamp )
                  + "\",\"note\":\"index invalidated; the next verb call rebuilds from disk\"}";
    return oc;
}

}   // namespace rw
