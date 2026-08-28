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
    NodeId node = kNoNode;
    std::uint32_t fileId = 0;
    std::size_t a = 0;
    std::size_t b = 0;
    std::size_t point = 0;
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
    if( !parseOp( edit.opName, edit.op ) ) { error = "unknown edit-plan op '" + edit.opName + "'"; return false; }
    if( edit.target.empty() || payloadName.empty() ) { error = "every edit needs string target and payload fields"; return false; }
    const std::string payloadPath = siblingPath( planPath, payloadName );
    bool payloadOk = false;
    edit.payload = mcpdetail::readFileBytes( payloadPath, payloadOk );
    if( !payloadOk || edit.payload.empty() ) { error = "cannot read non-empty payload '" + payloadPath + "'"; return false; }
    if( edit.payload.size() > maxBytes ) { error = "payload '" + payloadPath + "' exceeds --max-file-size"; return false; }
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

inline FileStage* ensureStage( const McpIndex& ix, const Edit& edit, std::vector<FileStage>& files, std::string& error )
{
    const auto staged = std::find_if( files.begin(), files.end(), [ & ]( const FileStage& file ) { return file.fileId == edit.fileId; } );
    if( staged != files.end() ) { return &*staged; }
    FileStage fresh;
    fresh.fileId = edit.fileId;
    fresh.identity = ix.ing.files[edit.fileId];
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
    if( !planOk ) { out.message = "cannot read edit plan '" + planPath + "'"; return out; }
    if( plan.size() > maxBytes ) { out.message = "edit plan exceeds --max-file-size"; return out; }
    if( mcpdetail::checkFrame( plan ).shape != mcpdetail::FrameShape::Object ) { out.message = "edit plan is not one complete JSON object"; return out; }
    if( !hasOnlyKeys( plan, { "version", "edits" } ) ) { out.message = "edit plan has an unknown or duplicate root field"; return out; }
    const mcpdetail::RawValue version = mcpdetail::findRawValue( plan, "version" );
    if( !version.isPresent || version.text != "1" ) { out.message = "edit plan needs numeric version 1"; return out; }
    const std::string editArray = mcpdetail::findArray( plan, "edits" );
    const std::vector<std::string> objects = mcpdetail::arrayObjects( editArray );
    if( objects.empty() || objects.size() > 64 || !objectOnlyArray( editArray, objects ) ) { out.message = "edit plan needs 1..64 edit objects and no other array values"; return out; }

    const McpIndex& ix = getIndex( root );
    edits.reserve( objects.size() );
    for( const std::string& object : objects )
    {
        Edit edit;
        if( !parseEdit( ix, object, planPath, maxBytes, edit, out.message ) ) { return out; }
        FileStage* file = ensureStage( ix, edit, files, out.message );
        if( file == nullptr ) { return out; }
        if( !( edit.a < edit.b && edit.b <= file->original.size() ) ) { out.message = "invalid definition span for '" + edit.target + "'"; return out; }
        file->edits.push_back( edits.size() );
        edits.push_back( std::move( edit ) );
    }
    if( !stageEdits( edits, files, out.message ) ) { return out; }
    out.ok = true;
    return out;
}

inline std::string receipt( const std::vector<Edit>& edits, const std::vector<FileStage>& files, bool apply )
{
    std::string out = "{\"schema\":\"ripwire.edit-plan/v1\",\"mode\":\"";
    out += apply ? "apply" : "dry-run";
    out += "\",\"edits\":" + std::to_string( edits.size() ) + ",\"files\":" + std::to_string( files.size() );
    if( apply ) { out += ",\"applied\":" + std::to_string( edits.size() ) + ",\"atomic_files\":" + std::to_string( files.size() ); }
    out += ",\"atomic_scope\":\"per-file\",\"rollback_on_write_error\":true,\"multifile_crash_atomic\":false";
    out += ",\"operations\":[";
    for( std::size_t i = 0; i < edits.size(); ++i )
    {
        if( i ) { out += ','; }
        const auto staged = std::find_if( files.begin(), files.end(), [ & ]( const FileStage& file ) { return file.fileId == edits[i].fileId; } );
        const FileStage* file = staged == files.end() ? nullptr : &*staged;
        out += "{\"op\":\"" + mcpdetail::jsonEscape( edits[i].opName ) + "\",\"target\":\"" + mcpdetail::jsonEscape( edits[i].target )
             + "\",\"file\":\"" + mcpdetail::jsonEscape( file == nullptr ? std::string() : file->identity ) + "\"}";
    }
    return out + "]}";
}

inline Outcome run( const std::string& root, const std::string& planPath, bool apply, std::size_t maxBytes )
{
    std::vector<Edit> edits;
    std::vector<FileStage> files;
    Outcome out = prepare( root, planPath, maxBytes, edits, files );
    if( !out.ok ) { return out; }
    if( !apply ) { out.receipt = receipt( edits, files, false ); return out; }

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
        if( mcpedit::atomicWrite( files[written].disk, files[written].edited ) ) { continue; }
        bool rollbackOk = true;
        while( written > 0 ) { --written; rollbackOk = mcpedit::atomicWrite( files[written].disk, files[written].original ) && rollbackOk; }
        out.ok = false;
        out.message = rollbackOk ? "edit-plan commit failed; prior files rolled back" : "edit-plan commit and rollback failed; inspect files immediately";
        return out;
    }
    invalidateMcpIndex();
    out.receipt = receipt( edits, files, true );
    return out;
}

} // namespace rw::editplan
