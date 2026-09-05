#pragma once

#include "mcpedit.h"

#include <memory>

namespace rw::editplan
{

// A plan is preflighted in full before any write. Apply holds every target
// file lock, rechecks the indexed bytes, and rolls back earlier per-file
// atomic writes if a later write fails. A process or machine crash between
// file renames remains intentionally disclosed as not multi-file atomic.

struct Outcome
{
    bool ok = false;
    std::string message;
    std::string receipt;
};

struct Edit
{
    mcpedit::Op op = mcpedit::Op::ReplaceBody;
    std::string opName;
    std::string target;
    std::string fileHint;
    std::string payload;
    std::string payloadPath;   // A5: the RESOLVED path the bytes were read from — surfaced in the receipt
    NodeId node = kNoNode;
    std::uint32_t fileId = 0;
    std::size_t a = 0;
    std::size_t b = 0;
    std::size_t point = 0;
    // P9 (capture-audit 2026-09-04, lens 8 §(4)): what a reviewer needs BEFORE --apply. The dry-run
    // receipt named the target as the caller SPELLED it and the payload path it would read, and stopped —
    // so "is this the definition I meant, and who breaks if it moves" was still one --edit-check per op
    // after the fact. Resolved at prepare time, where the index is already open and the node already known.
    std::string   symName;                 // the RESOLVED definition name (a seed/handle target says nothing)
    std::uint32_t line = 0;                // its 1-based defining line — emitted with the file as at="file:line"
    std::vector<NodeId> callers;           // its 1-hop callers, deduped and sorted (the union feeds the root)
};

struct FileStage
{
    std::uint32_t fileId = 0;
    std::string identity;
    std::string disk;
    std::string original;
    std::string edited;
    std::uint64_t baseHash = 0;
    std::vector<std::size_t> edits;
};

inline std::string siblingPath( std::string_view planPath, std::string_view payload )
{
    if( payload.empty() || payload.front() == '/' ) { return std::string( payload ); }
    const std::size_t slash = planPath.find_last_of( '/' );
    return slash == std::string_view::npos ? std::string( payload ) : std::string( planPath.substr( 0, slash + 1 ) ) + std::string( payload );
}

// The directory a plan's payloads must live in: the plan file's own, canonicalized. "" when it cannot be
// resolved, which the confinement check below treats as "cannot prove containment" and therefore refuses.
inline std::string planDirAbs( const std::string& planPath )
{
    const std::size_t slash = planPath.find_last_of( '/' );
    const std::string dir   = slash == std::string::npos ? std::string( "." ) : planPath.substr( 0, slash );
    char              buf[ PATH_MAX ];
    return ::realpath( dir.empty() ? "/" : dir.c_str(), buf ) != nullptr ? std::string( buf ) : std::string();
}

// A5: a plan's `payload` names a file whose BYTES are spliced into a source file, so an unconfined payload
// path is a READ primitive: "payload":"../../../../etc/hosts" — or any absolute path — inlines that file's
// contents into a tracked source file. No write ever lands outside the crawl root, which is why this is a
// low-severity finding and not a write escape; but a plan arriving from a shared repo, a PR, or another
// agent could quietly bake a secret into a file the next commit publishes.
//
// Payloads must live beside the plan. Both checks run, because each catches what the other cannot: the
// LEXICAL pass judges a path that does not exist (realpath would simply fail and the refusal would be a
// misleading "cannot read"), and REALPATH catches a symlink that sits inside the plan directory and points
// out of it. `resolved` is filled either way, so the refusal can name the path it actually judged rather
// than the spelling the plan wrote.
inline bool payloadWithinPlanDir( const std::string& planPath, const std::string& payloadPath, std::string& resolved )
{
    const std::string dir = planDirAbs( planPath );
    if( dir.empty() )
    {
        resolved = payloadPath;
        return false;
    }
    // `payloadPath` is siblingPath's output: already joined to the plan file's own spelling, and therefore
    // relative to the CWD (not to `dir` — joining it to `dir` a second time would silently un-escape a
    // "../" payload, which is the exact bug this function exists to catch).
    char cwdBuf[ PATH_MAX ];
    const std::string cwd = ::getcwd( cwdBuf, sizeof( cwdBuf ) ) != nullptr ? std::string( cwdBuf ) : std::string();
    if( cwd.empty() && payloadPath.front() != '/' )
    {
        resolved = payloadPath;
        return false;   // cannot place a relative path in any frame ⇒ cannot prove containment ⇒ refuse
    }
    // rw::lexicalNormalize (resolve.h) is the house's segment-stack `.`/`..` folder — the SAME primitive the
    // include resolver keys every path index through. It returns "" for a relative `..` that escapes above
    // its own base, which is already the answer this check wants.
    const std::string lexical = lexicalNormalize( payloadPath.front() == '/' ? payloadPath : cwd + "/" + payloadPath );
    if( lexical.empty() )
    {
        resolved = payloadPath;
        return false;
    }

    // realpath is the AUTHORITY when the payload exists: `dir` is canonical, so only a canonical candidate
    // is comparable to it (a symlinked prefix such as /tmp -> /private/tmp otherwise reads as an escape),
    // and it is what catches a symlink sitting INSIDE the plan directory that points out of it.
    char buf[ PATH_MAX ];
    if( ::realpath( lexical.c_str(), buf ) != nullptr )
    {
        resolved = std::string( buf );
        return pathIsUnder( resolved, dir );
    }
    // The payload does not exist. realpath cannot speak, so judge it lexically: "../../../../etc/nope" must
    // still read as an escape rather than as a merely unreadable payload.
    resolved = lexical;
    return pathIsUnder( lexical, dir );
}

inline bool hasOnlyKeys( const std::string& object, std::initializer_list<std::string_view> allowed )
{
    std::vector<std::string> keys = mcpdetail::objectKeys( object );
    std::sort( keys.begin(), keys.end() );
    if( std::adjacent_find( keys.begin(), keys.end() ) != keys.end() ) { return false; }
    for( const std::string& key : keys )
    {
        if( std::find( allowed.begin(), allowed.end(), key ) == allowed.end() ) { return false; }
    }
    return true;
}

inline bool objectOnlyArray( const std::string& array, const std::vector<std::string>& objects )
{
    if( array.size() < 2 || array.front() != '[' || array.back() != ']' ) { return false; }
    std::size_t at = 1;
    at = array.find_first_not_of( " \t\r\n", at );
    for( std::size_t objectIndex = 0; objectIndex < objects.size(); ++objectIndex )
    {
        if( objectIndex != 0 && ( at >= array.size() || array[at++] != ',' ) ) { return false; }
        at = array.find_first_not_of( " \t\r\n", at );
        const std::string& object = objects[objectIndex];
        if( at == std::string::npos || array.compare( at, object.size(), object ) != 0 ) { return false; }
        at = array.find_first_not_of( " \t\r\n", at + object.size() );
    }
    return at == array.size() - 1;
}

inline bool parseOp( std::string_view name, mcpedit::Op& op ) noexcept
{
    struct Row { std::string_view name; mcpedit::Op op; };
    static constexpr Row kOps[] = {
        { "replace_symbol_body", mcpedit::Op::ReplaceBody },
        { "insert_before_symbol", mcpedit::Op::InsertBefore },
        { "insert_after_symbol", mcpedit::Op::InsertAfter }
    };
    for( const Row& row : kOps ) { if( row.name == name ) { op = row.op; return true; } }
    return false;
}

// F15: the op vocabulary, RENDERED from the same table parseOp matches against — it was published nowhere,
// not in --help and not in the refusal ("unknown edit-plan op 'replace'"), while every other enum in the
// tool prints "(supported: …)". A closed set the caller cannot enumerate is a guessing game.
inline std::string supportedOpsList()
{
    return "replace_symbol_body, insert_before_symbol, insert_after_symbol";
}

inline bool editsOverlap( const Edit& a, const Edit& b ) noexcept
{
    const bool ar = a.op == mcpedit::Op::ReplaceBody;
    const bool br = b.op == mcpedit::Op::ReplaceBody;
    if( ar && br ) { return a.a < b.b && b.a < a.b; }
    if( !ar && !br ) { return a.point == b.point; }
    const Edit& range = ar ? a : b;
    const Edit& point = ar ? b : a;
    return point.point >= range.a && point.point <= range.b;
}

inline bool parseEdit( const McpIndex& ix, const std::string& object, const std::string& planPath,
                       std::size_t maxBytes, Edit& edit, std::string& error )
{
    if( !hasOnlyKeys( object, { "op", "target", "file", "payload" } ) ) { error = "edit object has an unknown or duplicate field"; return false; }
    edit.opName   = mcpdetail::findString( object, "op" );
    edit.target   = mcpdetail::findString( object, "target" );
    edit.fileHint = mcpdetail::findString( object, "file" );
    const std::string payloadName = mcpdetail::findString( object, "payload" );
    if( !parseOp( edit.opName, edit.op ) )
    { error = "--edit-plan: unknown op '" + edit.opName + "' (supported: " + supportedOpsList() + ")"; return false; }
    if( edit.target.empty() || payloadName.empty() ) { error = "every edit needs string target and payload fields"; return false; }
    const std::string payloadPath = siblingPath( planPath, payloadName );
    if( !payloadWithinPlanDir( planPath, payloadPath, edit.payloadPath ) )
    {
        error = "payload '" + payloadName + "' resolves to '" + edit.payloadPath + "', outside the plan's own "
                "directory; an edit plan may only read payloads that sit beside it";
        return false;
    }
    bool payloadOk = false;
    edit.payload = mcpdetail::readFileBytes( payloadPath, payloadOk );
    if( !payloadOk || edit.payload.empty() ) { error = "cannot read non-empty payload '" + payloadPath + "'"; return false; }
    if( edit.payload.size() > maxBytes ) { error = "payload '" + payloadPath + "' exceeds --max-file-size"; return false; }
    // A1: the plan path does not route through runEditVerb, so it carries the same third payload arm itself.
    // Preflight, like every other plan refusal — no file in the plan is written when any one edit is bad.
    if( looksBinary( edit.payload ) ) { error = "payload '" + payloadPath + "' " + std::string( mcpedit::kBinaryPayloadRefusal ); return false; }
    const mcpedit::EditTarget target = mcpedit::resolveTarget( ix, edit.target, edit.fileHint );
    if( target.id == kNoNode || target.id >= ix.ing.symbols.size() ) { error = target.error; return false; }
    edit.node = target.id;
    const Symbol& symbol = ix.ing.symbols[edit.node];
    edit.fileId = symbol.fileId;
    edit.a = symbol.sigStartByte;
    edit.b = symbol.endByte;
    edit.point = edit.op == mcpedit::Op::InsertAfter ? edit.b : edit.a;
    return true;
}

inline FileStage* ensureStage( const McpIndex& ix, const Edit& edit, std::vector<FileStage>& files,
                               const std::string& root, std::string& error )
{
    const auto staged = std::find_if( files.begin(), files.end(), [ & ]( const FileStage& file ) { return file.fileId == edit.fileId; } );
    if( staged != files.end() ) { return &*staged; }
    FileStage fresh;
    fresh.fileId = edit.fileId;
    // M12 (capture-audit 2026-09-04, lane L9) applied to the sibling it missed: the single-edit receipt's
    // "file" is root-relative, and this one printed the raw ingest spelling ("./geo.py" on a relative root)
    // in its own receipt, its refusals and its rollback message. One identity, one spelling — and P9's
    // per-op post-check has to look the file up by it, so a second spelling here is not cosmetic.
    // Single-root only (realPaths.empty()); a merged multi-root identity is already `<label>/<rel>`.
    fresh.identity = ix.ing.realPaths.empty()
                   ? std::string( rw::sarif::rootRelativeUri( ix.ing.files[edit.fileId], rw::sarif::rootPrefixOf( root ) ) )
                   : ix.ing.files[edit.fileId];
    fresh.disk = diskPath( ix.ing, edit.fileId );
    struct stat link{};
    if( ::lstat( fresh.disk.c_str(), &link ) == 0 && S_ISLNK( link.st_mode ) ) { error = "refusing edit plan target symlink '" + fresh.identity + "'"; return nullptr; }
    bool readOk = false;
    fresh.original = mcpdetail::readFileBytes( fresh.disk, readOk );
    fresh.baseHash = readOk ? mcpdetail::byteHash( fresh.original.data(), fresh.original.size() ) : 0;
    const std::uint64_t indexedHash = edit.fileId < ix.fileByteHash.size() ? ix.fileByteHash[edit.fileId] : 0;
    if( !readOk || fresh.baseHash == 0 || fresh.baseHash != indexedHash ) { error = "file '" + fresh.identity + "' changed since index was built"; return nullptr; }
    fresh.edited = fresh.original;
    files.push_back( std::move( fresh ) );
    return &files.back();
}

inline bool stageEdits( std::vector<Edit>& edits, std::vector<FileStage>& files, std::string& error )
{
    for( FileStage& file : files )
    {
        for( std::size_t i = 0; i < file.edits.size(); ++i ) for( std::size_t j = i + 1; j < file.edits.size(); ++j )
        {
            if( editsOverlap( edits[file.edits[i]], edits[file.edits[j]] ) ) { error = "edit plan contains overlapping edits in '" + file.identity + "'"; return false; }
        }
        std::sort( file.edits.begin(), file.edits.end(), [ & ]( std::size_t a, std::size_t b ) { return edits[a].point > edits[b].point; } );
        for( const std::size_t index : file.edits )
        {
            std::size_t start = 0, end = 0;
            const Edit& edit = edits[index];
            file.edited = mcpedit::applyEdit( edit.op, file.edited, edit.a, edit.b, edit.payload, start, end );
        }
    }
    return true;
}

inline Outcome prepare( const std::string& root, const std::string& planPath, std::size_t maxBytes,
                        std::vector<Edit>& edits, std::vector<FileStage>& files )
{
    Outcome out;
    bool planOk = false;
    const std::string plan = mcpdetail::readFileBytes( planPath, planOk );
    if( !planOk ) { out.message = "--edit-plan: cannot read edit plan '" + planPath + "'"; return out; }
    if( plan.size() > maxBytes ) { out.message = "edit plan exceeds --max-file-size"; return out; }
    if( mcpdetail::checkFrame( plan ).shape != mcpdetail::FrameShape::Object ) { out.message = "edit plan is not one complete JSON object"; return out; }
    if( !hasOnlyKeys( plan, { "version", "edits" } ) ) { out.message = "edit plan has an unknown or duplicate root field"; return out; }
    const mcpdetail::RawValue version = mcpdetail::findRawValue( plan, "version" );
    // A7: findRawValue strips the quotes and sets isQuoted, so `1` and `"1"` both arrive as text=="1". The
    // spec and this very message say NUMERIC 1, so the string form has to be rejected here or the refusal
    // is describing a rule the code does not enforce. (`1.0` was already refused — only `"1"` slipped past.)
    if( !version.isPresent || version.isQuoted || version.text != "1" ) { out.message = "edit plan needs numeric version 1"; return out; }
    const std::string editArray = mcpdetail::findArray( plan, "edits" );
    const std::vector<std::string> objects = mcpdetail::arrayObjects( editArray );
    if( objects.empty() || objects.size() > 64 || !objectOnlyArray( editArray, objects ) ) { out.message = "edit plan needs 1..64 edit objects and no other array values"; return out; }

    const McpIndex& ix = getIndex( root );
    edits.reserve( objects.size() );
    for( const std::string& object : objects )
    {
        Edit edit;
        if( !parseEdit( ix, object, planPath, maxBytes, edit, out.message ) ) { return out; }
        FileStage* file = ensureStage( ix, edit, files, root, out.message );
        if( file == nullptr ) { return out; }
        if( !( edit.a < edit.b && edit.b <= file->original.size() ) ) { out.message = "invalid definition span for '" + edit.target + "'"; return out; }
        // P9: the resolved identity + its 1-hop callers, from the index this loop already holds open. The
        // caller walk is editcheck.h's OWN (editCheckCallers over the overload set), so the number a
        // dry-run shows and the number an --apply's per-op edit_check shows are one walk, not two.
        if( edit.node < ix.ing.symbols.size() )
        {
            const Symbol& target = ix.ing.symbols[ edit.node ];
            edit.symName = target.name;
            edit.line    = target.line;
            const auto [ callerIds, callerIncompatible ] =
                editCheckCallers( ix.ing, ix.g, editCheckOverloadSet( ix.ing, ix.g, edit.node ), target.name );
            (void) callerIncompatible;   // the FLAGS are an after-the-edit question; a dry-run has no edit yet
            edit.callers = callerIds;
        }
        file->edits.push_back( edits.size() );
        edits.push_back( std::move( edit ) );
    }
    if( !stageEdits( edits, files, out.message ) ) { return out; }
    out.ok = true;
    return out;
}

inline std::string receipt( const std::vector<Edit>& edits, const std::vector<FileStage>& files, bool apply,
                            const std::string& root = {} )
{
    std::string out = "{\"schema\":\"ripwire.edit-plan/v1\",\"mode\":\"";
    out += apply ? "apply" : "dry-run";
    out += "\",\"edits\":" + std::to_string( edits.size() ) + ",\"files\":" + std::to_string( files.size() );
    // P9: the DISTINCT 1-hop callers across every op — the blast radius of the whole transaction, which is
    // the number a reviewer judges an --apply by and which no per-op count adds up to (two ops on the same
    // hot helper share most of their callers).
    {
        std::vector<NodeId> union_;
        for( const Edit& e : edits ) { union_.insert( union_.end(), e.callers.begin(), e.callers.end() ); }
        std::sort( union_.begin(), union_.end() );
        union_.erase( std::unique( union_.begin(), union_.end() ), union_.end() );
        out += ",\"callers_union\":" + std::to_string( union_.size() );
    }
    if( apply ) { out += ",\"applied\":" + std::to_string( edits.size() ) + ",\"atomic_files\":" + std::to_string( files.size() ); }
    // recheck_before_each_write: every file's indexed byte-hash is re-verified immediately before ITS OWN
    // write, not once for all files up front (A6). It is the observable half of a contract whose race a
    // deterministic gate cannot stage, so the receipt states it and a gate asserts the statement.
    out += ",\"atomic_scope\":\"per-file\",\"rollback_on_write_error\":true,\"recheck_before_each_write\":true"
           ",\"multifile_crash_atomic\":false";
    out += ",\"operations\":[";
    for( std::size_t i = 0; i < edits.size(); ++i )
    {
        if( i ) { out += ','; }
        const auto staged = std::find_if( files.begin(), files.end(), [ & ]( const FileStage& file ) { return file.fileId == edits[i].fileId; } );
        const FileStage* file = staged == files.end() ? nullptr : &*staged;
        // A5: the resolved payload path, so a human reviewing a --dry-run before --apply can see which bytes
        // each operation will READ. The plan names a spelling; this is what that spelling resolved to.
        out += "{\"op\":\"" + mcpdetail::jsonEscape( edits[i].opName ) + "\",\"target\":\"" + mcpdetail::jsonEscape( edits[i].target )
             + "\",\"file\":\"" + mcpdetail::jsonEscape( file == nullptr ? std::string() : file->identity )
             // P9: `target` is what the CALLER SPELLED (possibly a seed or a handle); `at` and `sym` are what
             // it RESOLVED TO, so a dry-run can be judged without a second --edit-check per op, and `callers`
             // says who is downstream of this one op.
             + "\",\"sym\":\"" + mcpdetail::jsonEscape( edits[i].symName )
             + "\",\"at\":\"" + mcpdetail::jsonEscape( file == nullptr ? std::string() : file->identity )
             + ":" + std::to_string( edits[i].line )
             + "\",\"callers\":" + std::to_string( edits[i].callers.size() )
             + ",\"payload_path\":\"" + mcpdetail::jsonEscape( edits[i].payloadPath ) + "\"";
        // …and on an APPLY, the contract question answered against the tree as it now stands — the same
        // fold the single-edit receipt carries, per op (mcpedit::postCheckJson, withTests=false: a plan's
        // ops can touch several files, so the tests half would be one list repeated N times).
        if( apply && !root.empty() && file != nullptr && !edits[i].symName.empty() )
        {
            std::string pc = mcpedit::postCheckJson( root, file->identity, edits[i].symName, false );
            if( !pc.empty() && pc.front() == ',' ) { out += pc; }
        }
        out += "}";
    }
    return out + "]}";
}

// A3: roll the prefix [0, failedAt) back and say what ACTUALLY happened. The old message was
// unconditional — "edit-plan commit failed; prior files rolled back" — but the rollback loop is
// `while( written > 0 )`, a no-op when the failure is on the FIRST file. The commonest plan failure
// therefore claimed a rollback that never ran, over files that were never written. An agent reading it
// has to go and check the tree by hand to find out which of the two worlds it is in, which is exactly
// what a refusal message exists to spare it.
//
// Three outcomes, three sentences, and the count is stated rather than implied:
//   failedAt == 0            → nothing was written; there is nothing to roll back.
//   failedAt > 0, rolled ok  → N prior files restored, N named as a number, not left to inference.
//   rollback failed          → the loud one, unchanged: the tree is in a state only a human can judge.
// `files` is in disk-path order (sorted just above), so failedAt indexes the file that failed.
inline std::string rollbackMessage( const std::vector<FileStage>& files, std::size_t failedAt, std::string_view cause )
{
    bool        rollbackOk = true;
    std::size_t undone     = failedAt;
    while( undone > 0 )
    {
        --undone;
        rollbackOk = mcpedit::atomicWrite( files[undone].disk, files[undone].original ) && rollbackOk;
    }
    if( !rollbackOk )
    {
        return std::string( cause ) + " and rollback failed; inspect files immediately";
    }
    const std::string at = failedAt < files.size() ? files[failedAt].identity : std::string( "?" );
    if( failedAt == 0 )
    {
        return std::string( cause ) + " on the first file ('" + at + "'); no files were written";
    }
    return std::string( cause ) + " at '" + at + "'; " + std::to_string( failedAt ) + " prior file"
         + ( failedAt == 1 ? "" : "s" ) + " rolled back";
}

inline Outcome run( const std::string& root, const std::string& planPath, bool apply, std::size_t maxBytes )
{
    std::vector<Edit> edits;
    std::vector<FileStage> files;
    Outcome out = prepare( root, planPath, maxBytes, edits, files );
    if( !out.ok ) { return out; }
    if( !apply ) { out.receipt = receipt( edits, files, false, root ); return out; }

    std::sort( files.begin(), files.end(), []( const FileStage& a, const FileStage& b ) { return a.disk < b.disk; } );
    std::vector<std::unique_ptr<mcpedit::EditLock>> locks;
    for( const FileStage& file : files ) { locks.push_back( std::make_unique<mcpedit::EditLock>( file.disk ) ); }
    for( const FileStage& file : files )
    {
        bool readOk = false;
        const std::string current = mcpdetail::readFileBytes( file.disk, readOk );
        if( !readOk || mcpdetail::byteHash( current.data(), current.size() ) != file.baseHash ) { out.ok = false; out.message = "concurrent write detected before edit-plan commit; no files written"; return out; }
    }
    std::size_t written = 0;
    for( ; written < files.size(); ++written )
    {
        // A6: re-hash THIS file immediately before ITS OWN write. The loop above checks every file up front,
        // which is the clean fast path (nothing is written at all when a plan is already stale) — but on a
        // K-file plan it left the LAST file's stale-detection window spanning the fsync of every earlier
        // write. The single-edit path deliberately does the opposite: mcpedit.h re-hashes immediately before
        // its rename, "collapsing the lost-update window to the tiny gap between this re-hash and the
        // rename". The plan surface, written later, reintroduced that residual and made it wider. Both
        // checks now stand: the up-front one to fail clean, this one to close the window.
        //
        // WHO THIS IS FOR: not another ripwire process — the advisory EditLocks above already serialize a
        // cooperating writer. It is the NON-cooperating external writer (an editor or formatter saving
        // mid-commit) that takes no lock, which is the same residual mcpedit.h names in its own comment.
        bool              stillFresh = false;
        const std::string current    = mcpdetail::readFileBytes( files[written].disk, stillFresh );
        if( !stillFresh || mcpdetail::byteHash( current.data(), current.size() ) != files[written].baseHash )
        {
            out.ok      = false;
            out.message = rollbackMessage( files, written, "edit-plan commit aborted (a concurrent write was detected)" );
            return out;
        }
        if( mcpedit::atomicWrite( files[written].disk, files[written].edited ) ) { continue; }
        out.ok      = false;
        out.message = rollbackMessage( files, written, "edit-plan commit failed" );
        return out;
    }
    invalidateMcpIndex();
    out.receipt = receipt( edits, files, true, root );
    return out;
}

} // namespace rw::editplan
