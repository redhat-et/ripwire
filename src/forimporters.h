#pragma once
// forimporters.h — EXEMPLAR importer sub-block: a --for task that adds a new thing modeled on a NAMED one ("add a new editor
// contribution ... use BracketMatchingController as the model") carries the files that import the model's file, so the agent
// learns the new file needs the same import. (CLI src/verbs_for.h appendForTaskRowBlocks, MCP `for` src/mcpverbs.h forTaskText —
// one renderer.)
//
// WHY. ld-vscode-06 asks what must import the new file; the answer is src/vs/editor/editor.all.ts, which a ranked answer has no
// reason to print: the file defines nothing the task's words match. The import tier of --impact already holds the row.
//
// WHEN (present-only). Outside code spans the task says add|write|implement|create|build ... new|another, and it names the model
// after use / copy / following / like / alongside / modeled on|after as a capitalised identifier that resolves to a non-test
// definition, and that file has a non-test importer. The block names one model, as an example: the hedge is in its legend.
#include "defslookup.h"    // lookupDefs — the model's definition
#include "fordeclrow.h"    // forTaskMaskCodeSpans — the masked reading of the task
#include "graph.h"         // impactImportTier — the --impact import tier, one derivation
#include "mapinventory.h"  // isInventoryCodeSymbol — a file of only data sections defines no code
#include "nextverb.h"      // nextFlag / nextAttrXml
#include "serialize.h"     // escapeXml

#include <algorithm>
#include <array>
#include <cctype>
#include <cstddef>
#include <string>
#include <string_view>
#include <vector>

namespace rw
{
inline constexpr std::size_t kForImporterRowsCap = 6;   // <f> rows in one <importers> (a cut says shown= and next=)
inline constexpr std::size_t kForModelTries      = 3;   // model spellings resolved per task
inline constexpr std::size_t kForAddNewGapBytes  = 40;  // add ... new: how far apart in one sentence, in bytes

struct ForTaskWord
{
    std::size_t begin = 0;
    std::size_t end   = 0;
};

inline std::vector<ForTaskWord> forTaskWordSpans( std::string_view text )
{
    std::vector<ForTaskWord> out;
    for( std::size_t i = 0; i < text.size(); )
    {
        if( !namesplit::isIdentChar( text[i] ) )
        {
            ++i;
            continue;
        }
        std::size_t e = i;
        while( e < text.size() && namesplit::isIdentChar( text[e] ) )
        {
            ++e;
        }
        out.push_back( { i, e } );
        i = e;
    }
    return out;
}

// add|write|implement|create|build ... new|another, same sentence and close together, outside code spans.
inline bool forAddNewAsked( std::string_view task )
{
    static constexpr std::array<std::string_view, 9> kAdd{ "add", "adding", "write", "writing", "implement", "implementing", "create", "creating", "build" };
    static constexpr std::array<std::string_view, 2> kNew{ "new", "another" };
    const std::string              masked = forTaskMaskCodeSpans( task );
    const std::string              lower  = routeLower( masked );
    const std::vector<ForTaskWord> spans  = forTaskWordSpans( lower );
    const auto word = [ & ]( const ForTaskWord& w ) { return std::string_view( lower ).substr( w.begin, w.end - w.begin ); };
    for( std::size_t i = 0; i < spans.size(); ++i )
    {
        if( !std::ranges::contains( kAdd, word( spans[i] ) ) )
        {
            continue;
        }
        for( std::size_t k = i + 1; k < spans.size() && spans[k].begin - spans[i].end <= kForAddNewGapBytes; ++k )
        {
            const std::string_view between = std::string_view( lower ).substr( spans[i].end, spans[k].begin - spans[i].end );
            if( between.find_first_of( ".?!" ) != std::string_view::npos )
            {
                break;
            }
            if( std::ranges::contains( kNew, word( spans[k] ) ) )
            {
                return true;
            }
        }
    }
    return false;
}

// The capitalised identifier right after a use/copy/following/like/alongside/modeled on|after cue (an optional backtick between),
// in task order; the cue is matched in any case, the name keeps its own.
inline std::vector<std::string> forTaskModelNames( std::string_view task )
{
    static constexpr std::array<std::string_view, 5> kCue{ "use", "copy", "following", "like", "alongside" };
    static constexpr std::array<std::string_view, 2> kModeled{ "model", "modeled" };
    static constexpr std::array<std::string_view, 2> kOnAfter{ "on", "after" };
    const std::string              lower = routeLower( task );
    const std::vector<ForTaskWord> spans = forTaskWordSpans( lower );
    const auto word = [ & ]( std::size_t i ) { return std::string_view( lower ).substr( spans[i].begin, spans[i].end - spans[i].begin ); };
    std::vector<std::string> out;
    for( std::size_t i = 0; i + 1 < spans.size(); ++i )
    {
        const bool plain   = std::ranges::contains( kCue, word( i ) );
        const bool modeled = !plain && i + 2 < spans.size() && std::ranges::contains( kModeled, word( i ) ) && std::ranges::contains( kOnAfter, word( i + 1 ) );
        if( !plain && !modeled )
        {
            continue;
        }
        const ForTaskWord& cueEnd = spans[ modeled ? i + 1 : i ];
        const ForTaskWord& name   = spans[ modeled ? i + 2 : i + 1 ];
        const std::string_view gap = task.substr( cueEnd.end, name.begin - cueEnd.end );
        if( ( gap == " " || gap == " `" ) && std::isupper( static_cast<unsigned char>( task[ name.begin ] ) ) != 0 )
        {
            out.emplace_back( task.substr( name.begin, name.end - name.begin ) );
        }
    }
    return out;
}

inline std::string forImportersXml( const IngestResult& ing, const std::string& model, const std::vector<std::uint32_t>& source, std::size_t testRows, std::uint64_t unresolved )
{
    std::vector<std::uint32_t> ordered = source;   // the lists of imports first, each kind in the tier's own order
    std::vector<char>          holdsCode( ing.files.size(), 0 );   // a file with no code symbol holds only imports and data: a list of what gets loaded
    for( const Symbol& s : ing.symbols )
    {
        holdsCode[ s.fileId ] = holdsCode[ s.fileId ] != 0 || isInventoryCodeSymbol( s ) ? 1 : 0;
    }
    std::ranges::stable_partition( ordered, [ & ]( std::uint32_t f ) { return holdsCode[f] == 0; } );
    std::string       rows;
    std::vector<char> esc;
    const std::size_t shown = std::min( ordered.size(), kForImporterRowsCap );
    for( std::size_t i = 0; i < shown; ++i )
    {
        rows += "<f p=\"" + std::string( escapeXml( rootRelPath( ing, ordered[i] ), esc ) ) + "\"";
        rows += holdsCode[ ordered[i] ] == 0 ? " aggregator=\"1\"/>" : "/>";
    }
    std::string out = "<!-- ripwire for importers: the task adds a new thing modeled on of= (named in the task, matched by name; an exemplar, not the only "
                      "valid model), so the source files importing its file follow: a new file may need the same import to be loaded. <f> p= the importer; "
                      "aggregator=\"1\": that file defines no code, it is a list of imports, the likeliest place to add one; importers= counts source importers, "
                      "shown= and next= only when the list is cut; test_importers= importers in test paths, not listed; imports_unresolved=N: N imports drew "
                      "no edge, so importers= is a floor; the answer above is unchanged, and these bytes are not in est_tokens -->";
    out += "<importers of=\"" + std::string( escapeXml( model, esc ) ) + "\" importers=\"" + std::to_string( ordered.size() ) + "\"";
    if( shown < ordered.size() )
    {
        out += " shown=\"" + std::to_string( shown ) + "\"" + nextAttrXml( nextFlag( "--impact=", model ) );
    }
    out += testRows > 0 ? " test_importers=\"" + std::to_string( testRows ) + "\"" : "";
    out += unresolved > 0 ? " imports_unresolved=\"" + std::to_string( unresolved ) + "\"" : "";
    return out + ">" + rows + "</importers>";
}

// The <importers> block of this task, or "" (see WHEN above).
inline std::string renderForImporters( const IngestResult& ing, const Graph& g, std::string_view task )
{
    if( !forAddNewAsked( task ) )
    {
        return {};
    }
    std::vector<std::string> models = forTaskModelNames( task );
    if( models.size() > kForModelTries )
    {
        models.resize( kForModelTries );
    }
    for( const std::string& model : models )
    {
        const DefLookup L   = lookupDefs( ing, g, model );
        const auto      def = std::ranges::find_if( L.rows, [ ]( const DefRow& r ) { return !r.test; } );
        if( def == L.rows.end() )
        {
            continue;
        }
        const ImportTier           tier = impactImportTier( ing, { def->rep } );
        std::vector<std::uint32_t> source;
        for( const std::uint32_t f : tier.files )
        {
            if( pathTierOf( rootRelPath( ing, f ) ) != PathTier::TestOrBench )
            {
                source.push_back( f );
            }
        }
        if( !source.empty() )
        {
            return forImportersXml( ing, model, source, tier.files.size() - source.size(), tier.importsUnresolved );
        }
    }
    return {};
}
}   // namespace rw
