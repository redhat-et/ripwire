#pragma once

// mcpedit.h — the shared symbol-addressed EDIT engine for CLI and MCP: replace_symbol_body /
// insert_before_symbol / insert_after_symbol. The mcpedit namespace (resolve → per-file advisory
// lock → freshness byte-hash gate → in-memory splice → atomic temp-rename write) plus the
// runEditVerb() driver. The safety contract IS the feature: every refusal leaves the file
// byte-identical. Extracted from mcp.h (the mcp.h/main.cpp concern-split). Includes mcpindex.h;
// included by mcp.h (runMcp dispatches here).

#include "mcpindex.h"
#include "editcheck.h"        // P9: the SAME four computations --edit-check renders as XML — folded into the receipt as JSON
#include "testmap.h"          // P9: testsReachingFile + runFieldJsonDisclosed — the SAME rows --affected=FILE emits
#include "didyoumean.h"       // M9: boundedEditDistance / nearestIndexedFileClause — ONE near-miss policy for read and edit
#include "selectorrefuse.h"   // atSeedFaultClause + indexHasFileMatching — the @FILE:LINE at-diagnosis, ONE set of fault sentences on every surface
#include "infra/hashutil.h"   // sanitizer-clean modulo-2^64 FNV multiplication

#include <climits>            // PATH_MAX — the AbsHintFrame realpath/getcwd buffers (A2)

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

    // A1: the ONE wording for the binary-payload refusal, shared by the CLI arm (which names the flag),
    // the engine arm (which also covers MCP) and the edit-plan arm — three call sites, one sentence, so a
    // reader who has seen it once recognizes it everywhere and no copy can drift from the others.
    //
    // WHY this is a refusal and not a warning: a payload carrying a NUL byte writes fine and reports
    // success, but on the NEXT run ingest's own binary sniff (rw::looksBinary) drops the file from the
    // index entirely. Its whole symbol table vanishes, so every later edit to ANY symbol in that file
    // refuses with "symbol 'X' not found" — a statement about the tree that is simply false. The gate uses
    // rw::looksBinary itself rather than a second NUL rule, so the refusal's claim ("would drop it from the
    // index") is EXACTLY the condition that would cause the drop: same 4096-byte window, same predicate.
    // A NUL past that window is honestly not refused, because it honestly would not drop the file.
    // The constant is the PREDICATE TAIL only ("contains a NUL byte; ..."); each site supplies the subject it
    // wants in front of it ("--edit-payload", "payload", "payload '<path>'"), so no site reads doubled.
    inline constexpr std::string_view kBinaryPayloadRefusal =
        "contains a NUL byte; writing it would make the target unparseable and drop it from the index";

    // the outcome of an edit attempt: either a success JSON payload, or a JSON-RPC error {code,message}.
    struct Outcome
    {
        bool        ok = false;
        int         errCode = -32602;
        std::string message;      // on error
        std::string resultJson;   // on success (a JSON object: applied span + old index stamp + refresh note)

        // A4: the RESOLVED identity of what was edited, so a caller can print advice that actually runs.
        // The CLI used to echo the caller's own `sym` argument back into "verify with --edit-check=<sym>",
        // which is wrong twice: --edit-check does not accept a sym# handle at all (so the printed command
        // always failed after a handle-addressed edit), and a bare name disambiguated by --edit-target-file
        // would send --edit-check to a DIFFERENT same-named definition. These two fields are what the engine
        // actually wrote to; they are already inside resultJson, and are surfaced here so no caller has to
        // parse its own receipt back out to say something true.
        std::string symbol;       // on success — the resolved definition name
        std::string file;         // on success — the indexed identity of the file that was written
    };

    // The K symbol names closest to `name`, for the "0 matches" hint — by the SAME bounded edit distance
    // every read verb's did-you-mean uses (didyoumean.h::boundedEditDistance), and cut off at the same
    // bandwidth.
    //
    // M9 / lens 6 F8 (capture-audit 2026-09-04). This used to be its own ranker: case-folded shared-prefix
    // length × 4 minus the length delta, over the WHOLE symbol table, with no cutoff — the exact score
    // §P12.1 replaced on the read side, plus the missing cutoff. So the edit verbs answered
    // `--replace-symbol-body=DoesNotExist` with "nearest: do_snake_one, do_snake_two, docDriftText,
    // dogfood-gaps, download_raw" — five alphabetical neighbours of "Do", none of them related to
    // anything, in front of an agent about to overwrite a function body. A prefix neighbour of a name with
    // no near-miss is noise dressed as help; the read verbs have long since decided that no plausible
    // candidate is an honest answer, and this is the surface where acting on a bad guess WRITES.
    //
    // The cutoff is what makes the list empty when nothing is close, so the caller drops the "nearest:"
    // clause entirely rather than printing a header over five wrong names. Deterministic: distance first,
    // then longer case-insensitive shared prefix, then lexicographic — the tie-break contract
    // nearestNameByEditDistance states for the single-candidate case, applied to the whole ordered list.
    inline std::vector<std::string> nearestNames( const IngestResult& ing, const std::string& name, std::size_t k )
    {
        constexpr int     kMaxEditDistance = 3;   // the read verbs' bandwidth (didyoumean.h::didYouMean)
        struct Cand { int dist; std::size_t prefixLen; std::string n; };
        std::vector<Cand> cands;
        for( const Symbol& s : ing.symbols )
        {
            if( s.name.empty() || s.kind == SymKind::Section )
            {
                continue;   // X9(e): a markdown heading is never the answer to a code-symbol typo
            }
            const int dist = boundedEditDistance( s.name, name, kMaxEditDistance );
            if( dist > kMaxEditDistance )
            {
                continue;
            }
            std::size_t       pfx = 0;
            const std::size_t lim = std::min( s.name.size(), name.size() );
            while( pfx < lim && std::tolower( (unsigned char)s.name[pfx] ) == std::tolower( (unsigned char)name[pfx] ) )
            {
                ++pfx;
            }
            cands.push_back( { dist, pfx, s.name } );
        }
        std::sort( cands.begin(), cands.end(),
                   []( const Cand& a, const Cand& b )
                   {
                       if( a.dist != b.dist ) { return a.dist < b.dist; }
                       if( a.prefixLen != b.prefixLen ) { return a.prefixLen > b.prefixLen; }
                       return a.n < b.n;
                   } );
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

    // A2: an ABSOLUTE path hint — the spelling an agent pastes back from a receipt, a stack trace or its own
    // shell, and the most natural thing to type — could never substring-match `ing.files`' root-relative
    // identities ("corpus/a.py"). So `--edit-target-file=/abs/.../a.py` refused with "symbol 'alpha' not
    // found under path '/abs/.../a.py'" about a file that DEFINES alpha: a false statement about the tree.
    // The fix is not a second path vocabulary — it lifts the indexed FILE into the absolute frame the hint
    // is already in, and runs the same substring rule there. Built once per resolve, and empty (so free) for
    // the ordinary relative hint, which keeps the existing fast path byte-for-byte.
    //
    // realpath() on the hint so a symlinked prefix (/tmp vs /private/tmp on macOS) lands in the same frame
    // getcwd() reports; a hint naming nothing on disk keeps its literal spelling rather than being dropped.
    struct AbsHintFrame
    {
        std::string hint;   // canonical absolute hint — empty when the hint is relative (nothing to do)
        std::string cwd;    // getcwd, to absolutize a relative on-disk spelling; empty ⇒ degrade to no match

        explicit AbsHintFrame( const std::string& pathHint )
        {
            if( pathHint.empty() || pathHint.front() != '/' )
            {
                return;
            }
            char buf[ PATH_MAX ];
            hint = ::realpath( pathHint.c_str(), buf ) != nullptr ? std::string( buf ) : pathHint;
            cwd  = ::getcwd( buf, sizeof( buf ) ) != nullptr ? std::string( buf ) : std::string();
        }

        bool matches( const IngestResult& ing, std::uint32_t fileId ) const
        {
            if( hint.empty() || cwd.empty() )
            {
                return false;
            }
            const std::string& disk = diskPath( ing, fileId );   // the on-disk spelling, never the label
            const std::string  abs  = !disk.empty() && disk.front() == '/' ? disk : cwd + "/" + disk;
            return abs.find( hint ) != std::string::npos;
        }
    };

    // The ONE "does this indexed file satisfy the caller's path hint" predicate, so the symbol scan and the
    // never-parsed disclosure below cannot disagree about which files a hint names. Relative substring test
    // first — unchanged, and the only test a relative hint ever runs.
    inline bool editHintMatches( const IngestResult& ing, std::uint32_t fileId,
                                 const std::string& pathHint, const AbsHintFrame& frame )
    {
        return filePathContains( ing.files[ fileId ], pathHint ) || frame.matches( ing, fileId );
    }

    // A1 (secondary): "symbol 'X' not found under path 'F'" is a TRUE statement with a misleading cause when
    // F is indexed but was never PARSED — the ingest's not-measured sentinel (fileHealth.fileBytes == 0: a
    // binary sniff, a read failure, or a doc-format file the doc pass extracted instead). Such a file has no
    // symbol table at all, so EVERY name in it reports as absent and the nearest-names list below is pure
    // noise. Say which file, and why, instead of letting the agent hunt for a name that is there.
    // Returns "" when the hint names nothing indexed, or names anything that WAS measured (then the plain
    // not-found is the honest answer). Names at most 3 files — this is a hint, not a report.
    inline std::string unmeasuredHintNote( const IngestResult& ing, const std::string& pathHint, const AbsHintFrame& frame )
    {
        std::vector<std::string> unmeasured;
        for( std::size_t f = 0; f < ing.files.size(); ++f )
        {
            if( !editHintMatches( ing, std::uint32_t( f ), pathHint, frame ) )
            {
                continue;
            }
            if( f < ing.fileHealth.size() && ing.fileHealth[f].fileBytes == 0 )
            {
                unmeasured.push_back( ing.files[f] );
                continue;
            }
            return std::string();   // a measured file matches the hint — the plain not-found stands
        }
        if( unmeasured.empty() )
        {
            return std::string();
        }
        std::string note = " — that path is indexed but was never parsed (binary content, an unreadable file, "
                           "or a doc-format extraction), so it contributes NO symbols and no name in it resolves: ";
        for( std::size_t i = 0; i < unmeasured.size() && i < 3; ++i )
        {
            if( i )
            {
                note += ", ";
            }
            note += unmeasured[i];
        }
        if( unmeasured.size() > 3 )
        {
            note += " (+" + std::to_string( unmeasured.size() - 3 ) + " more)";
        }
        return note;
    }

    // resolve `symbol` to exactly one def, optionally narrowed by `pathHint` (a substring match on the file
    // path, mirroring resolveFocus's "file:name" file filter). Returns kNoNode and fills `err` with a ready
    // JSON-RPC message on any non-unique outcome (0 → nearest-names hint; >1 → candidate file:line list).
    inline NodeId resolveOneForEdit( const IngestResult& ing, const std::string& symbol,
                                     const std::string& pathHint, std::string& err )
    {
        const AbsHintFrame  frame( pathHint );   // A2: absolute-hint frame; inert for a relative hint
        std::vector<NodeId> matches;
        for( const Symbol& s : ing.symbols )
        {
            if( s.name != symbol )
            {
                continue;
            }
            if( !pathHint.empty() && !editHintMatches( ing, s.fileId, pathHint, frame ) )
            {
                continue; // `<label>/<rel>`-matching (post-M12; filePathContains' `/./` fallback is legacy), and absolute-spelling-tolerant
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
            // M9 / lens 6 F8: when the PATH half names nothing indexed, the path is the fault and nothing
            // can honestly be said about the symbol — `--edit-target-file=svectr.h` used to report
            // "symbol 'size' not found under path 'svectr.h'; nearest: sized, size_of, Side, Site, sink",
            // sending the reader after a rename in a header that was never indexed under that spelling.
            // Same verdict, same words as the read verbs' file-half diagnosis (selectorrefuse.h).
            if( !pathHint.empty() && !indexHasFileMatching( ing, pathHint ) )
            {
                err = "no indexed file matches '" + pathHint + "' — the PATH half is the fault, so nothing is claimed about '"
                    + symbol + "'; drop the file qualifier to search every file, or pass a path the map lists"
                    + nearestIndexedFileClause( ing, pathHint );
                return kNoNode;
            }
            std::string m = "symbol '" + symbol + "' not found";
            if( !pathHint.empty() )
            {
                m += " under path '" + pathHint + "'";
                m += unmeasuredHintNote( ing, pathHint, frame );
            }
            // A2: ask for one extra and drop any suggestion EQUAL to the name requested. This branch is
            // reached only when no definition of `symbol` survived the filter, so leading the did-you-mean
            // list with `symbol` itself ("not found ...; nearest: alpha") reads as a bug in the tool.
            std::vector<std::string> near = nearestNames( ing, symbol, 6 );
            near.erase( std::remove( near.begin(), near.end(), symbol ), near.end() );
            if( near.size() > 5 ) { near.resize( 5 ); }
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

    // F-07: the target file's dominant line ending, so a payload can be harmonized to match it before it is
    // spliced in. Counts CRLF pairs and BARE LF (a '\n' with no preceding '\r') separately, so a file that
    // is genuinely mixed already is reported as such rather than forced into one bucket. `None` is a file
    // with no newline at all (e.g. single statement, or empty) — nothing for a payload to match.
    enum class EolStyle : std::uint8_t { None, Lf, Crlf, Mixed };

    inline EolStyle detectDominantEol( const std::string& bytes )
    {
        std::size_t crlf = 0, bareLf = 0;
        for( std::size_t i = 0; i < bytes.size(); ++i )
        {
            if( bytes[i] != '\n' )
            {
                continue;
            }
            if( i > 0 && bytes[i - 1] == '\r' ) { ++crlf; }
            else                                { ++bareLf; }
        }
        if( crlf == 0 && bareLf == 0 ) { return EolStyle::None; }
        if( bareLf == 0 )              { return EolStyle::Crlf; }
        if( crlf == 0 )                { return EolStyle::Lf; }
        return EolStyle::Mixed;
    }

    // Declarative table over a switch/case (CONTRIBUTING.md §3): EolStyle's enumerators are declared
    // None,Lf,Crlf,Mixed in that order, so the enum value IS the index — no case labels to keep in sync.
    inline const char* eolStyleName( EolStyle e ) noexcept
    {
        static constexpr const char* kNames[] = { "none", "lf", "crlf", "mixed" };
        const std::size_t             i       = static_cast<std::size_t>( e );
        return ( i < sizeof( kNames ) / sizeof( kNames[0] ) ) ? kNames[i] : "none";
    }

    // F-07: rewrite every BARE '\n' in `text` to '\r\n', so a payload written in plain LF (the shape almost
    // every agent emits) does not leave a CRLF-dominant target file with a mixed-ending tail after the
    // splice. Idempotent — a '\n' already preceded by '\r' is left alone, never doubled, so a payload that
    // is already CRLF (or already mixed) is not corrupted by a second pass.
    inline std::string normalizeToCrlf( const std::string& text )
    {
        std::string out;
        out.reserve( text.size() + text.size() / 16 );
        for( std::size_t i = 0; i < text.size(); ++i )
        {
            if( text[i] == '\n' && ( i == 0 || text[i - 1] != '\r' ) )
            {
                out += '\r';
            }
            out += text[i];
        }
        return out;
    }

    // A3-F8: the advisory edit lock lives in the per-user CACHE DIR, keyed by an FNV-1a-64 hash of the
    // absolute target path — NOT as a "<path>.ripwire-lock" sidecar next to the target. The old sidecar was
    // created and never unlinked, so every MCP edit left permanent litter in the user's repo (git-status
    // noise). The cache-dir path is a deterministic pure function of the target path, so two ripwire processes
    // editing the SAME file still open the SAME lock file and flock still serializes them cross-process (the F1
    // guarantee is preserved) — it just never lands in the repo tree. Locks have their own sharded subtree:
    // cache eviction never scans or removes a possibly-live advisory-lock inode.
    inline std::string editLockPath( const std::string& targetPath )
    {
        std::uint64_t h = 1469598103934665603ULL;      // FNV-1a-64 of the target path → a stable per-file lock name
        for( char c : targetPath ) { h ^= static_cast<unsigned char>( c ); h = hashutil::fnv1aMultiply( h ); }
        char name[ 64 ];
        std::snprintf( name, sizeof( name ), "ripwire-edit-%016llx.lock", (unsigned long long)h );
        const std::string lockDir = quality::cacheDirLadder() + "/locks";
        ::mkdir( lockDir.c_str(), 0700 );
        ::chmod( lockDir.c_str(), 0700 );
        return quality::resolveCacheBlobPath( lockDir, name );
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

    struct EditTarget
    {
        NodeId      id = kNoNode;
        bool        byHandle = false;
        bool        bySeed   = false;   // target was an @FILE:LINE line-seed (receipt discloses the rebind)
        std::string error;
    };

    // @FILE:LINE line-seed target (2026-08-30 decision round): the agent editing from a diff hunk holds
    // exactly FILE:LINE, so the seed addresses the edit target directly — resolved through the SAME
    // resolveAtSeed + at-diagnosis every read verb uses; everything downstream of the returned NodeId
    // (freshness hash, lock, pre-rename recheck, atomic write) is untouched, so the edit-safety contract
    // is unchanged.
    inline EditTarget resolveSeedTarget( const McpIndex& ix, const std::string& target, const std::string& pathHint )
    {
        EditTarget out;
        out.bySeed = true;
        if( !pathHint.empty() )
        { // mirror the handle arm's posture: the seed already identifies one file (and one line)
            out.error = "a file hint cannot narrow a line seed: '" + target
                      + "' already names exactly one file and line — drop the file/--edit-target-file argument";
            return out;
        }
        const AtSeed seed = resolveAtSeed( ix.ing, std::string_view( target ).substr( 1 ) );
        if( seed.fault != AtFault::None )
        {
            out.error = "line seed '" + target + "' does not resolve" + atSeedFaultClause( ix.ing, seed );
            return out;
        }
        const Symbol& s = ix.ing.symbols[ seed.chain.back() ];   // innermost — the SYM-selector pick (atcheck (12))
        if( s.kind == SymKind::Section )
        { // the resolveOneForEdit KIND GUARD, replicated verbatim in spirit: a Section's span does not
          // delimit an editable definition, and for html/csv/ipynb it is extracted-text coordinates —
          // splicing through one silently corrupts the doc/data file while reporting success.
            out.error = "line seed '" + target + "' resolves to '" + s.name + "', a document heading/section ("
                      + ix.ing.files[ s.fileId ] + "), not an editable code definition — refusing to avoid "
                        "corrupting the doc/data file";
            return out;
        }
        out.id = seed.chain.back();
        return out;
    }

    inline EditTarget resolveTarget( const McpIndex& ix, const std::string& target, const std::string& pathHint )
    {
        EditTarget out;

        if( !target.empty() && target.front() == '@' )
        {
            return resolveSeedTarget( ix, target, pathHint );   // @FILE:LINE line-seed — see its contract above
        }

        std::uint64_t handleId = 0, handleContent = 0;
        out.byHandle = mcpdetail::parseHandle( target, handleId, handleContent );
        if( !out.byHandle )
        {
            if( target.rfind( "sym#", 0 ) == 0 )
            {
                out.error = "malformed edit handle '" + target + "' (expected sym#<16hex>@<16hex>)";
                return out;
            }
            out.id = resolveOneForEdit( ix.ing, target, pathHint, out.error );
            return out;
        }
        if( !pathHint.empty() )
        {
            out.error = "--edit-target-file cannot modify a content handle: the handle already identifies one file";
            return out;
        }

        std::vector<NodeId> matches;
        out.id = resolveHandleAll( ix, handleId, matches );
        if( out.id == kNoNode )
        {
            out.error = "edit handle '" + target + "' no longer resolves; rerun --grep --handles";
            return out;
        }
        if( matches.size() != 1 )
        {
            out.id = kNoNode;
            out.error = "edit handle '" + target + "' is ambiguous across " + std::to_string( matches.size() )
                      + " definitions; refresh with --grep --handles and target a unique enclosing definition";
            return out;
        }
        const Symbol& s = ix.ing.symbols[out.id];
        const std::uint64_t builtHash = ( s.fileId < ix.fileByteHash.size() ) ? ix.fileByteHash[s.fileId] : 0;
        if( handleContent == 0 || handleContent != builtHash )
        {
            out.id = kNoNode;
            out.error = "stale edit handle '" + target + "': file '" + ix.ing.files[s.fileId]
                      + "' changed after grep minted it; rerun --grep --handles and use the new handle";
        }
        return out;
    }

    // ── P9 (capture-audit 2026-09-04) — THE POST-EDIT VERIFICATION, FOLDED INTO THE RECEIPT ───────────
    //
    // The receipt used to end with a stderr line saying "verify with --edit-check=F:S, then --affected=F":
    // two more calls the tool already knows it wants, on an index it has just invalidated and is about to
    // rebuild for whoever calls next anyway. Claude Code's own policy makes an agent Read before it edits;
    // other agents do not, and the receipt is the one document an editing agent is guaranteed to read.
    //
    // Both halves are the STANDALONE verbs' own computations, called directly rather than re-derived:
    // editcheck.h's editCheckOverloadSet / editCheckContractVsHead / editCheckCallers / editCheckVerdict /
    // editCheckCallSites are exactly what editCheckBundleText renders as XML, and testsReachingFile is what
    // runAffected walks. That is what lets test/receiptpostcheck.sh assert the receipt EQUALS a separate
    // --edit-check and a separate --affected: not a promise, a shared call.

    // the post-edit LINE range of the applied text, from the NEW bytes. Every other verb in this tool
    // speaks FILE:LINE; the receipt spoke only bytes. `end` is the line holding the applied text's LAST
    // byte — a payload ending in "\n" therefore reports its last CONTENT line, not the empty one after it.
    struct LineRange { std::uint32_t start; std::uint32_t end; };
    inline LineRange lineRangeOf( std::string_view bytes, std::size_t startByte, std::size_t endByte )
    {
        const auto lineAt = [ & ]( std::size_t upto ) -> std::uint32_t
        {
            std::uint32_t line = 1;
            for( std::size_t i = 0; i < upto && i < bytes.size(); ++i )
            {
                if( bytes[i] == '\n' ) { ++line; }
            }
            return line;
        };
        const std::uint32_t first = lineAt( startByte );
        const std::size_t   last  = ( endByte > startByte ) ? endByte - 1 : startByte;
        return { first, std::max( first, lineAt( last ) ) };
    }

    // `"edit_check":{...}` for a definition ALREADY RESOLVED in the post-edit tree, or "" when the edit
    // left nothing of that name in that file to ask about (a replace whose payload defines something else).
    // The empty case is why the caller emits a `post_check_unavailable` reason rather than a silent gap.
    inline std::string editCheckReceiptJson( const IngestResult& ing, const Graph& g, const std::string& root,
                                             NodeId focus, const std::string& pathRel )
    {
        const std::vector<NodeId> overloadNodes = editCheckOverloadSet( ing, g, focus );
        const EditCheckContract   contract      = editCheckContractVsHead( ing, g, root, kDefaultMaxFileBytes, {}, focus, overloadNodes );
        const auto [ callerIds, callerIncompatible ] = editCheckCallers( ing, g, overloadNodes, ing.symbols[ focus ].name );
        std::size_t incompatibleCount = 0;
        for( NodeId c : callerIds )
        {
            if( callerIncompatible[c] ) { ++incompatibleCount; }
        }
        const EditCheckVerdict verdict = editCheckVerdict( contract, incompatibleCount );
        const std::vector<std::pair<NodeId, std::uint32_t>> callSites =
            incompatibleCount > 0 ? editCheckCallSites( ing, ing.symbols[ focus ].name, callerIncompatible )
                                  : std::vector<std::pair<NodeId, std::uint32_t>>{};

        std::string out = std::string( ",\"edit_check\":{\"status\":\"" ) + verdict.status
                        + "\",\"callers\":" + std::to_string( callerIds.size() )
                        + ",\"incompatible\":" + std::to_string( incompatibleCount )
                        + ",\"sites\":[";
        bool first = true;
        for( NodeId c : callerIds )
        {
            if( !callerIncompatible[c] )
            {
                continue;   // sites is the BROKEN set — the rows an agent must open, not the caller listing
            }
            const Symbol& cs = ing.symbols[c];
            if( !first ) { out += ","; }
            first = false;
            out += "{\"n\":\"" + mcpdetail::jsonEscape( cs.name )
                 + "\",\"p\":\"" + mcpdetail::jsonEscape( std::string( rw::sarif::rootRelativeUri( ing.files[ cs.fileId ], rw::sarif::rootPrefixOf( root ) ) ) )
                 + ":" + std::to_string( cs.line ) + "\",\"l\":[";
            bool firstLine = true;
            for( auto it = std::lower_bound( callSites.begin(), callSites.end(), std::make_pair( c, std::uint32_t( 0 ) ) );
                 it != callSites.end() && it->first == c; ++it )
            {
                if( !firstLine ) { out += ","; }
                firstLine = false;
                out += std::to_string( it->second );
            }
            out += "]}";
        }
        out += "]";
        // F3 (capture-audit verify-wave2 2026-09-05): the COMPLETENESS KEYS the standalone twin carries.
        // The fold was measured equal to `--edit-check` field for field on the fields it COPIES, and that was
        // the gap — the standalone root carries the resolver gauge and the floor marker and the fold did not,
        // so `"callers":2` read as a total where `<edit-check … callers="2" graph_ambiguous="5923"
        // graph_unresolved="2952" counts_floor="1">` says it is a floor off a name-based call graph. Same
        // helper, same JSON spelling every other folded surface uses: a disclosure survives into every
        // sibling surface or is DECLARED, and this one had been neither.
        out += graphCountFloorAttrJson( g );
        out += "}";
        (void) pathRel;
        return out;
    }

    // `"tests_to_run":[{"p":…,"run":…|"run_unknown":true}]` — the SAME rows --affected=<that file> emits,
    // through the SAME TestRunnerIndex and the SAME not-derivable disclosure the whole row family shares.
    inline std::string testsToRunReceiptJson( const IngestResult& ing, const Graph& g, const std::string& root, std::uint32_t fileId )
    {
        const std::vector<std::uint32_t> testFiles = testsReachingFile( ing, g, fileId );
        const TestRunnerIndex            runners( ing );
        const auto                       jesc = []( std::string_view t ) { return mcpdetail::jsonEscape( std::string( t ) ); };
        const std::string                prefix = rw::sarif::rootPrefixOf( root );
        std::string                      out = ",\"tests_to_run\":[";
        for( std::size_t i = 0; i < testFiles.size(); ++i )
        {
            if( i ) { out += ","; }
            out += "{\"p\":\"" + mcpdetail::jsonEscape( std::string( rw::sarif::rootRelativeUri( ing.files[ testFiles[i] ], prefix ) ) ) + "\""
                 + rw::runFieldJsonDisclosed( runners, testFiles[i], jesc ) + "}";
        }
        out += "]";
        // F3: `"tests_to_run":[]` was an UNLABELLED ZERO. Its twin says "0 modelled tests, N shell gates the
        // call-graph walk cannot see, counts are floors"; the fold said `[]`, which a reader takes for
        // "nothing tests this" rather than "nothing that is a CALL EDGE tests this" (a shell harness runs the
        // compiled binary as a subprocess, which is not an edge). An ARRAY cannot carry attributes, so the
        // keys ride beside it — the same place --affected puts them relative to its own <test> rows, the same
        // counter (testmap.h::scriptGatesUnmodelledCount) and the same key names writeTestGateReportJson and
        // MCP situational_awareness already use. Never a second number.
        out += ",\"tests\":" + std::to_string( testFiles.size() );
        out += ",\"script_gates_unmodelled\":" + std::to_string( scriptGatesUnmodelledCount( ing ) );
        out += graphCountFloorAttrJson( g );
        return out;
    }

    // The whole post-check, for a file that has just been written: rebuild the index (the invalidation the
    // edit already forced — this pays the cost the NEXT verb call would have paid), find the edited
    // definition again, and render both halves. Returns "" when the caller opted out; returns a
    // `post_check_unavailable` reason rather than silence when the target can no longer be resolved.
    // `withTests=false` is the edit-plan's shape: a plan's ops can touch several files, so the CONTRACT
    // half is per op while the tests half would be a per-file list repeated N times. The plan receipt
    // carries the contract per op; --affected stays the caller's own call for the tests.
    inline std::string postCheckJson( const std::string& root, const std::string& fileIdentity, const std::string& symbolName,
                                      bool withTests = true )
    {
        const McpIndex&     ix  = getIndex( root );   // the edit invalidated it; this is the rebuild
        const IngestResult& ing = ix.ing;
        const Graph&        g   = ix.g;
        const std::string   prefix = rw::sarif::rootPrefixOf( root );

        NodeId focus  = kNoNode;
        std::uint32_t editedFile = std::uint32_t( -1 );
        for( NodeId i = 0; i < NodeId( ing.symbols.size() ); ++i )
        {
            const Symbol& s = ing.symbols[i];
            const std::string rel = ing.realPaths.empty()
                                  ? std::string( rw::sarif::rootRelativeUri( ing.files[ s.fileId ], prefix ) )
                                  : ing.files[ s.fileId ];
            if( rel != fileIdentity )
            {
                continue;
            }
            editedFile = s.fileId;
            if( focus == kNoNode && s.name == symbolName && s.kind != SymKind::Section )
            {
                focus = i;
            }
        }
        if( editedFile == std::uint32_t( -1 ) )
        {
            return ",\"post_check_unavailable\":\"the edited file is not in the refreshed index\"";
        }
        std::string out;
        if( focus == kNoNode )
        {
            // Honest, and it happens: a replace whose payload defines a DIFFERENT name leaves no definition
            // to ask the contract question about. Say which half is missing rather than omitting both.
            out += ",\"post_check_unavailable\":\"'" + mcpdetail::jsonEscape( symbolName )
                 + "' is no longer defined in the edited file — the contract check has no target\"";
        }
        else
        {
            out += editCheckReceiptJson( ing, g, root, focus, fileIdentity );
        }
        if( withTests )
        {
            out += testsToRunReceiptJson( ing, g, root, editedFile );
        }
        return out;
    }

}   // namespace mcpedit

// perform an edit verb end-to-end (resolve → verify freshness → splice → atomic write → invalidate index).
// `root` = repo path, `symbol` = the def name, `pathHint` = optional disambiguating file-path substring,
// `text` = new_body (ReplaceBody) or the inserted text (InsertBefore/After). Never throws for expected
// failures — returns an Outcome carrying either the success JSON or a JSON-RPC error {code,message}.
inline mcpedit::Outcome runEditVerb( const std::string& root, mcpedit::Op op, const std::string& symbol,
                                     const std::string& pathHint, const std::string& text, bool postCheck = true )
{
    mcpedit::Outcome oc;

    // A1: the ENGINE-level payload text gate (kBinaryPayloadRefusal above carries the why), before the index
    // is touched. Here and not only in the CLI arm: an MCP string carries an escaped NUL as easily as a file.
    if( looksBinary( text ) )
    {
        oc.ok = false; oc.errCode = -32602;
        oc.message = "payload " + std::string( mcpedit::kBinaryPayloadRefusal );
        return oc;
    }

    const McpIndex&     ix  = getIndex( root );
    const IngestResult& ing = ix.ing;

    // 1. resolve either a plain name or a grep-issued, freshness-pinned handle to exactly one definition.
    const mcpedit::EditTarget target = mcpedit::resolveTarget( ix, symbol, pathHint );
    const NodeId f = target.id;
    if( f == kNoNode || f >= ing.symbols.size() )
    {
        oc.ok = false; oc.errCode = -32602;
        oc.message = target.error.empty() ? ( "symbol '" + symbol + "' not found" ) : target.error;
        return oc;
    }

    const Symbol&      s      = ing.symbols[f];
    const std::uint32_t fileId = s.fileId;
    // M12 (capture-audit-2026-09-04, lane L9): root-relative, not the raw ingest-stored spelling — before
    // this fix, every message below and the JSON receipt's "file" field printed "./src/…" on a relative
    // root, and the CLI's --edit-check=<file>:<sym> stderr hint pasted that same "./"-prefixed spelling
    // into an argument --edit-check itself never prints that way (src/…, no "./"). Single-root only
    // (ing.realPaths.empty()); multi-root already carries the correct `<label>/<rel>` identity as-is.
    const bool         epSingleRoot = ing.realPaths.empty();
    const std::string  path = epSingleRoot ? std::string( rw::sarif::rootRelativeUri( ing.files[ fileId ], rw::sarif::rootPrefixOf( root ) ) )
                                           : ing.files[ fileId ];   // LABELED identity — user-facing messages / candidate lists
    // A11 (decided 2026-07-11): all disk I/O goes to the REAL on-disk path via the
    // diskPath seam, NEVER the labeled spelling. `disk` is the RAW ingest spelling regardless of `path`'s
    // own root-relative cosmetic above — the two can differ by a leading "./" on a single-root run without
    // affecting I/O, which reads/writes `disk` exclusively.
    // Multi-root writes land in the correct root's file even though the index identity is `<label>/<rel>`.
    const std::string& disk   = diskPath( ing, fileId );

    const std::uint64_t builtHash = ( fileId < ix.fileByteHash.size() ) ? ix.fileByteHash[ fileId ] : 0;
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

    // F-07: harmonize the payload's line endings to the TARGET's own dominant ending before splicing. A
    // payload written in plain LF (the common agent shape) spliced verbatim into a CRLF-dominant file used
    // to leave the file silently MIXED — nothing on the receipt said so. Only the Crlf case is normalized
    // (Lf targets already match a plain-LF payload; None/Mixed targets have no single convention to match,
    // so the payload is left exactly as given rather than guessed into one). Disclosed on the receipt below
    // either way via file_eol=/eol_normalized=, so an agent never has to re-read the file to find out.
    const mcpedit::EolStyle fileEol       = mcpedit::detectDominantEol( src );
    const bool              eolNormalized = ( fileEol == mcpedit::EolStyle::Crlf ) && ( text.find( '\n' ) != std::string::npos );
    const std::string       editText      = eolNormalized ? mcpedit::normalizeToCrlf( text ) : text;

    // 4. splice in memory, then ONE atomic temp-rename write (no partial write is possible).
    std::size_t newStart = 0, newEnd = 0;
    const std::string newBytes = mcpedit::applyEdit( op, src, a, b, editText, newStart, newEnd );

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
    oc.ok     = true;
    oc.symbol = s.name;
    oc.file   = path;
    // P9: copied out BEFORE the receipt is assembled, because the post-check below rebuilds the ONE cached
    // McpIndex — every reference into `ing` (and therefore `s`) is dangling from that point on. The three
    // values the post-check needs are plain strings, taken here while they are still valid.
    const std::string pcFileIdentity = path;
    const std::string pcSymbolName   = s.name;
    const mcpedit::LineRange pcLines = mcpedit::lineRangeOf( newBytes, newStart, newEnd );
    oc.resultJson = std::string( "{\"applied\":\"" ) + opName
                  // resolved_from_handle / resolved_from_seed: "symbol" above reports the RESOLVED name, so an
                  // indirect target (handle or @FILE:LINE seed) survives as typed for the agent to audit the
                  // resolution — the of=-echo posture, receipt-side. Absent for a plain-name target.
                  + "\",\"symbol\":\"" + mcpdetail::jsonEscape( s.name )
                  + ( target.byHandle ? "\",\"resolved_from_handle\":\"" + mcpdetail::jsonEscape( symbol ) : std::string() )
                  + ( target.bySeed   ? "\",\"resolved_from_seed\":\""   + mcpdetail::jsonEscape( symbol ) : std::string() )
                  + "\",\"file\":\"" + mcpdetail::jsonEscape( path )
                  // F-16: span is the POST-EDIT byte range in the NEW file (where the applied text now
                  // sits), not the region overwritten in the old one — for ReplaceBody those two lengths
                  // usually differ. replaced_bytes is that separate number: how many OLD bytes this op
                  // overwrote (b-a for ReplaceBody; 0 for the two insert ops, which overwrite nothing).
                  + "\",\"span\":{\"start\":" + std::to_string( newStart ) + ",\"end\":" + std::to_string( newEnd ) + "}"
                  // P9: the same region as FILE:LINE. Free (one scan of the new bytes, no index work), so it
                  // rides even under --no-post-check — every other verb in this tool speaks lines.
                  + ",\"lines\":{\"start\":" + std::to_string( pcLines.start ) + ",\"end\":" + std::to_string( pcLines.end ) + "}"
                  + ",\"replaced_bytes\":" + std::to_string( op == mcpedit::Op::ReplaceBody ? ( b - a ) : 0 )
                  + ",\"old_file_bytes\":" + std::to_string( src.size() )
                  + ",\"new_file_bytes\":" + std::to_string( newBytes.size() )
                  // F-07: the TARGET's own dominant line ending, and whether the payload was rewritten to
                  // match it (Crlf targets only — see above). A caller that cares whether its LF payload
                  // just got silently rewritten reads this instead of re-hashing the file.
                  + ",\"file_eol\":\"" + mcpedit::eolStyleName( fileEol )
                  + "\",\"eol_normalized\":" + ( eolNormalized ? "true" : "false" )
                  + ",\"stale_index\":\"" + mcpdetail::jsonEscape( oldStamp )
                  + "\",\"note\":\"index invalidated; the next verb call rebuilds from disk\"";
    // P9: the folded verification, LAST — it rebuilds the index, so nothing above may be read after it.
    if( postCheck )
    {
        oc.resultJson += mcpedit::postCheckJson( root, pcFileIdentity, pcSymbolName );
    }
    oc.resultJson += "}";
    return oc;
}

}   // namespace rw
