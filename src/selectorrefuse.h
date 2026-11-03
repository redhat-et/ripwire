#pragma once

// selectorrefuse.h — THE ONE "that selector named no symbol" refusal every SYM-taking CLI verb prints.
//
// WHY THIS FILE EXISTS (§B4.2). Six verbs take the same `file:name` selector grammar and six verbs refused a
// BAD one in two different dialects. --uses had grown the honest message: it says what is actually wrong
// ("that file defines no 'rankGraphTeleport'"), names the files that DO define the name, and hands back a
// runnable retry. Its five siblings — --edit-check / --callers / --callees / --impact / --around / --lego —
// answered a bare "symbol not found" about a symbol that plainly EXISTS, which reads as "you typed a name
// that isn't here" when the true fault is the file half. An agent believes the first message and goes
// looking for a rename that never happened.
//
// The asymmetry was not a decision, it was one enrichment that landed on one arm — the same "one shared
// guard, N arms" class as the V2-1 qualified-spelling guard. So the message moves HERE and every arm calls
// it; a seventh SYM-taking verb inherits the enrichment by calling the function, not by remembering to copy
// a paragraph. --uses' own wording is preserved verbatim (it was the good one), so its bytes are unchanged
// except for the shared file-list cap below.
//
// Deliberately CLI-side: the MCP arms have their own refusal vocabulary in mcprefusal.h (different surface,
// different retry syntax, JSON-RPC framing). What the two share is didyoumean.h, which both already call —
// and, since the @FILE:LINE round, atSeedFaultClause below: the at-diagnosis sentences are per-fault FACTS,
// not surface prose, so mcprefusal.h speaks them verbatim (mcprefuse::atSeedClause) rather than re-wording
// the same seven faults a second time.

#include "model.h"
#include "graph.h"   // filePathContainsRootRel / resolveAllByName — A1 (found-items 2026-09-17): this file's
                      // own diagnosis must match the file half the SAME way resolveAllByNameQualified does
#include "graph.h"          // splitQualifiedSpec / resolveAllByName — the SAME grammar the callers resolve with
#include "memberowner.h"    // qualifiedMemberName: the n= a candidate row prints, so the refusal lists names the answer would
#include "didyoumean.h"     // §P12.1: the near-miss suggester, for the "the name is wrong too" fallback
#include "degradedscan.h"   // degradedTextHit — the ONE degraded-parse text scan (mcprefusal.h words the same facts for MCP)
#include "crossref.h"       // worktreeRenameOf — the not-found answer offers the working tree's rename first
#include "serialize.h"      // escapeXml / jsonStr — the not-found answer document

#include <cstdio>
#include <utility>

#include <algorithm>
#include <cstddef>
#include <string>
#include <string_view>
#include <vector>

namespace rw
{

// A name defined in forty files must not print forty paths into one stderr line — same reasoning (and the
// same remainder shape) as editcheck.h's kEditCheckSpellingsShown: the count already tells the reader how
// many were left unsaid, and the first one is all a retry needs.
inline constexpr std::size_t kSelectorFilesShown = 6;

// The distinct files defining `name`, in index order (first occurrence wins), so the message is
// deterministic. A1 (review round, found-items 2026-09-17): root-relative (rootRelPath), never
// ing.files[fileId] raw — this list feeds selectorFaultClause's "e.g. --verb=FILE:name" retry text below,
// and a retry must actually RUN: under an absolute root spelling the raw stored path is LONGER than the
// root-relative haystack every matcher now compares against (filePathContainsRootRel), so a raw absolute
// echo can no longer even substring-match its own file — the retry regressed to unrunnable, not merely
// differently spelled. selectorrefusecheck.sh's §B4.2/§B11.1 arms execute the offered retry, not just print it.
inline std::vector<std::string> definingFilesOf( const IngestResult& ing, std::string_view name )
{
    std::vector<std::string> files;
    for( NodeId n : resolveAllByName( ing, name ) )
    {
        const std::string path( rootRelPath( ing, ing.symbols[n].fileId ) );
        if( std::find( files.begin(), files.end(), path ) == files.end() )
        {
            files.push_back( path );
        }
    }
    return files;
}

// Does the FILE half of a `file:name` selector name anything in the index at all? Asked with
// filePathContainsRootRel — the identical predicate resolveFocus/resolveAllByNameQualified match the file
// half with (graph.h) — so this answers exactly the question the resolver asked, never an approximation of
// it. A fileId loop rather than any_of-over-paths (the shape this used before A1, found-items 2026-09-17):
// the root-relative view is keyed by fileId, so any_of's by-path lambda can no longer express it.
inline bool indexHasFileMatching( const IngestResult& ing, std::string_view file )
{
    for( std::uint32_t fileId = 0; fileId < std::uint32_t( ing.files.size() ); ++fileId )
    {
        if( filePathContainsRootRel( ing, fileId, file ) )
        {
            return true;
        }
    }
    return false;
}

// DEGRADED-PARSE routing (degradedhintcheck, 2026-08-30). A symbol sitting in a shredded file (the
// looksObjC misroute: src/ingest_model.h, err=190) used to answer a bare "symbol not found" and send an
// agent hunting for a rename that never happened. The facts — WHICH parse-degraded file textually holds
// the missing name, and how degraded it is — come from degradedscan.h's shared scan (mcprefusal.h words
// the same facts for the MCP surface); this clause is only the CLI wording of them.
inline std::string degradedParseClause( const IngestResult& ing, std::string_view name )
{
    const DegradedTextHit hit = degradedTextHit( ing, name );
    if( !hit.found )
    {
        return {};
    }
    return " (note: '" + std::string( name ) + "' occurs textually in " + ing.files[ hit.fileIndex ]
         + ", whose parse is DEGRADED (err_ratio=" + hit.errRatio + ") — symbols there may be unextracted; "
           "the skipped verb itemizes)";
}

// THE DIAGNOSIS — the parenthetical alone, "" when there is nothing honest to add. Separated from the
// sentence below (W3FIX) because the five arms this round routed here spell their verdict AFTER the echoed
// selector ("ripwire: --expand=SEL matched no symbol"), so they need the clause without the sentence. A
// defaulted `specTail` parameter on selectorNotFoundMessage would have done the same job while CHANGING that
// function's arity, i.e. its contract, for every existing caller — a clause of its own costs nothing and
// leaves the shared sentence untouched.
//
// THREE outcomes, and which one fires is a FACT about the selector, never a guess:
//   • a `file:name` spelling whose FILE half matches no indexed path ⇒ the path is the fault, and nothing can
//     be said about the name half. Say that instead (§M7 partial, W3FIX: the enriched branch used to assert
//     "that file defines no 'X'" for a file that was never indexed — a claim about a file the tool never read,
//     which sends an agent hunting for a rename in a header that does not exist under that spelling).
//   • a `file:name` spelling whose FILE half IS indexed and whose NAME half resolves somewhere ⇒ the file half
//     is the fault. Say so, name every file that does define it, and give the first as a ready-to-run retry.
//   • anything else ⇒ the name itself is unknown: a near-miss if one exists, otherwise nothing.
// A canonical id ("path::scope::name") is NOT file-qualified — splitQualifiedSpec would cut it at its last
// colon and the resulting "file" half is a scope, not a path — so it takes the last branch, exactly as
// resolveUsesSelector already ruled for --uses.
// The @FILE:LINE half of the diagnosis — ONE sentence per AtFault value, shared verbatim between the at
// flag's own refusal and every SYM-taking verb's selector clause, so the same fault is never described two
// ways. Each sentence states the FACT the resolver established and the retry that acts on it; the resolver
// itself never guesses (graph.h::resolveAtSeed), so neither does the prose.
inline std::string atSeedFaultClause( const IngestResult& ing, const AtSeed& seed )
{
    switch( seed.fault )
    {
        case AtFault::Malformed:
            return " (the line-seed grammar is FILE:LINE — a path or unique path suffix, a colon, then a 1-based "
                   "line number, e.g. @src/main.cpp:120 in a selector position)";
        case AtFault::FileUnmatched:
            return " (no indexed file matches '" + std::string( seed.fileHalf ) + "' — pass a path the map lists, or a longer suffix)";
        case AtFault::FileAmbiguous:
        {
            const std::size_t shownCount = std::min( seed.fileMatches.size(), kSelectorFilesShown );
            std::string clause = " ('" + std::string( seed.fileHalf ) + "' matches " + std::to_string( seed.fileMatches.size() )
                               + " indexed files — ";
            for( std::size_t matchIndex = 0; matchIndex < shownCount; ++matchIndex )
            {
                clause += ( matchIndex ? ", " : "" ) + ing.files[ seed.fileMatches[ matchIndex ] ];
            }
            if( seed.fileMatches.size() > shownCount )
            {
                clause += " (+" + std::to_string( seed.fileMatches.size() - shownCount ) + " more files)";
            }
            return clause + "; qualify more of the path)";
        }
        case AtFault::FileUnreadable:
            return " (" + ing.files[ seed.fileId ] + " is indexed but could not be read from disk — moved or deleted "
                   "since the crawl? re-run to reindex)";
        case AtFault::LineOutOfRange:
            return " (" + ing.files[ seed.fileId ] + " has only " + std::to_string( seed.fileLines )
                 + " lines — the seed asked for line " + std::to_string( seed.line ) + ")";
        case AtFault::NoCoverer:
            return " (no indexed symbol spans line " + std::to_string( seed.line ) + " of " + ing.files[ seed.fileId ]
                 + " — top-level blank, comment or preprocessor text sits inside no definition; seed a line of a "
                   "definition instead)";
        case AtFault::SiblingTie:
            return " (line " + std::to_string( seed.line ) + " of " + ing.files[ seed.fileId ]
                 + " touches more than one definition — " + ing.symbols[ seed.chain[ seed.tieAt - 1 ] ].name + ", "
                 + ing.symbols[ seed.chain[ seed.tieAt ] ].name + "; a line seed cannot pick between them: use the "
                   "file:line:name selector instead, e.g. " + ing.files[ seed.fileId ] + ":" + std::to_string( seed.line )
                 + ":" + ing.symbols[ seed.chain[ seed.tieAt - 1 ] ].name + ")";
        case AtFault::None:
            return {};
    }
    return {};
}

// lane js-def-naming fix 1: the clause for a selector refused because SEVERAL definitions fit it ("" when it is simply absent). A printed
// p= (`file:LINE`) where several definitions start lists each n= the answer would print, never the innermost of them; a written spelling
// that several definitions fit says how many and how to qualify it.
inline std::string fittedRefusalClause( const IngestResult& ing, std::string_view spec, std::string_view retryForm )
{
    const std::vector<NodeId> starts = defLineStarts( ing, spec );
    if( starts.size() > 1 )
    {
        const MemberOwners owners( ing );
        const std::size_t  colon  = spec.rfind( ':' );
        std::string        clause = " (" + std::to_string( starts.size() ) + " definitions start on line " + std::string( spec.substr( colon + 1 ) )
                                  + " of " + std::string( spec.substr( 0, colon ) ) + ", so a line selector cannot pick one: ";
        for( std::size_t i = 0; i < starts.size() && i < kSelectorFilesShown; ++i )
        {
            clause += ( i ? ", " : "" ) + std::string( "n=" ) + qualifiedMemberName( owners, ing.symbols[ starts[ i ] ] );
        }
        return clause + "; select one by its name, e.g. " + std::string( retryForm ) + std::string( ing.symbols[ starts[ 0 ] ].name ) + ")";
    }
    const std::size_t fitted = refusedMatchCount( ing, spec );
    return fitted != 0 ? " (" + std::to_string( fitted ) + " definitions fit '" + std::string( spec ) + "' and the spelling cannot tell which, so none is chosen; "
                        "qualify it with its file, e.g. " + std::string( retryForm ) + "FILE:" + std::string( spec ) + ")"
                      : std::string();
}

inline std::string selectorFaultClause( const IngestResult& ing, std::string_view spec, std::string_view retryForm )
{
    if( !spec.empty() && spec.front() == '@' )
    { // a line seed that resolved to nothing — re-run the SAME diagnosis the resolver made and speak it
        return atSeedFaultClause( ing, resolveAtSeed( ing, spec.substr( 1 ) ) );
    }
    if( std::string refusal = fittedRefusalClause( ing, spec, retryForm ); !refusal.empty() )
    {   // lane js-def-naming fix 1: refused over several fitting definitions, not absent
        return refusal;
    }
    std::string_view file, bareName;
    splitQualifiedSpec( spec, file, bareName );      // did-you-mean and the site match both want the NAME half only
    const bool fileQualified = spec.find( "::" ) == std::string_view::npos && spec.find( ':' ) != std::string_view::npos;

    if( fileQualified && !file.empty() && !indexHasFileMatching( ing, file ) )
    {
        return " (no indexed file matches '" + std::string( file ) + "' — the PATH half is the fault, so nothing is claimed "
               "about '" + std::string( bareName ) + "'; drop the qualifier (" + std::string( retryForm ) + std::string( bareName )
             + ") to search every file, or pass a path the map lists)";
    }

    if( fileQualified )
    {
        const std::vector<std::string> definingFiles = definingFilesOf( ing, bareName );
        if( !definingFiles.empty() )
        {
            const std::size_t shownCount = std::min( definingFiles.size(), kSelectorFilesShown );
            std::string       clause     = " (that file defines no '" + std::string( bareName ) + "' — defined in ";
            for( std::size_t fileIndex = 0; fileIndex < shownCount; ++fileIndex )
            {
                clause += ( fileIndex ? ", " : "" ) + definingFiles[fileIndex];
            }
            if( definingFiles.size() > shownCount )
            {
                clause += " (+" + std::to_string( definingFiles.size() - shownCount ) + " more files)";
            }
            return clause + " — e.g. " + std::string( retryForm ) + definingFiles[0] + ":" + std::string( bareName ) + ")";
        }
    }
    return withDidYouMean( ing, bareName, {} ) + degradedParseClause( ing, bareName );
}

// The complete stderr line (no trailing newline) for a selector that resolved to nothing.
//
//   `prefix`    the verb's own opening clause, INCLUDING its noun and the trailing ": " — "ripwire: --lego
//               type not found: " reads differently from "--callers symbol not found: " and both are what
//               agents grep for, so the noun stays the caller's.
//   `spec`      the selector exactly as typed (echoed, always — a refusal that does not repeat the input
//               cannot be matched to the command that caused it in a log).
//   `retryForm` the surface's retry syntax for the runnable example ("--callers=", "--uses=", …).
//
// A verb whose verdict follows the selector instead of preceding it composes the two pieces itself:
//   "ripwire: --expand=" + sel + " matched no symbol" + selectorFaultClause( ing, sel, "--expand=" )
inline std::string selectorNotFoundMessage( const IngestResult& ing, std::string prefix, std::string_view spec,
                                            std::string_view retryForm )
{
    return std::move( prefix ) + std::string( spec ) + selectorFaultClause( ing, spec, retryForm );
}

// ── the NOT-FOUND ANSWER (2026-10-01, the comparison table's fix list #2) ─────────────────────────────────────
//
// A selector that matches no indexed definition is a REFUSAL, exit 1 (README §6.2; docs/COMMANDS.md --callers), and
// that contract stays. But a refusal used to print NOTHING on stdout, so an agent that reads stdout got no answer at
// all: on the comparison table a correct "that name is gone" (a rename in the working tree) scored as an ERROR. The
// refusal now ALSO prints a one-element answer document — the verb's own root, the selector echoed in the verb's own
// attribute names, found="0", and the name to retry with — under its own legend. stderr is unchanged except that a
// working-tree rename, when there is one, is offered FIRST: spelling-distance ranks a token swap (line_trim →
// trim_line) far below an unrelated near-spelling, and the working tree holds better evidence than spelling.

// The name to offer: the working tree's rename of the selector's NAME half first, else the spelling near-miss.
struct NotFoundNear
{
    std::string name;
    bool        renamed = false;   // a changed file's HEAD copy holds the selector's name and not this one
};

inline NotFoundNear notFoundNear( const IngestResult& ing, std::string_view spec, const std::string& gitRoot )
{
    if( spec.empty() || spec.front() == '@' )
    {
        return {};   // a line seed is diagnosed by its own fault sentences; it has no name to rename
    }
    std::string_view file, name;
    splitQualifiedSpec( spec, file, name );
    if( !gitRoot.empty() )
    {
        std::string renamed = crossref::worktreeRenameOf( ing, name, gitRoot );
        if( !renamed.empty() )
        {
            return { std::move( renamed ), true };
        }
    }
    std::string near = didYouMean( ing, name );
    return near == name ? NotFoundNear{} : NotFoundNear{ std::move( near ), false };
}

// The clause that puts a working-tree rename ahead of the shared fault clause on stderr ("" when there is none).
inline std::string notFoundRenameClause( const NotFoundNear& near )
{
    return near.renamed ? " (renamed in the working tree: did you mean '" + near.name + "'?)" : std::string();
}

// The same clause inside an MCP refusal sentence, right after the quoted echo of the spelling that missed. Those
// sentences echo as `'X'` (mcprefuse::notFound) or as `from='A'` / `to='B'` (path_between), so `endpoint` ("from",
// "to", "both" or "") picks which echo it follows. One insertion rule for the live arm and the batch arm.
inline std::string withRenameClause( std::string msg, const NotFoundNear& near, std::string_view endpoint = {} )
{
    if( !near.renamed )
    {
        return msg;
    }
    const std::string anchor = ( endpoint == "from" || endpoint == "to" ) ? std::string( endpoint ) + "='" : std::string( "'" );
    const std::size_t at     = msg.find( anchor );
    const std::size_t open   = at == std::string::npos ? std::string::npos : at + anchor.size() - 1;
    const std::size_t close  = open == std::string::npos ? std::string::npos : msg.find( '\'', open + 1 );
    msg.insert( close == std::string::npos ? msg.size() : close + 1, notFoundRenameClause( near ) );
    return msg;
}

// The answer document a not-found refusal prints on stdout beside its exit 1. `echo` is the selector in the verb's
// own attribute names (of=, or from=/to= for path), `missing` names the endpoint that matched nothing — "from", "to" or
// "both" ("" for a one-selector verb); near= then retries the first endpoint it names. XML under the verb's root tag with its legend comment, or one JSON object under --json.
struct NotFoundAnswer
{
    std::string_view                                       tag;
    std::vector<std::pair<std::string_view, std::string>> echo;
    std::string_view                                       missing;
    NotFoundNear                                           near;
    std::size_t                                            refused = 0;   // N != 0 (> 1): N definitions fit the selector and none was chosen (a refusal, not an absence); found= stays 0, the contract

    // the legend sentence of a refused answer (refused != 0), spelled with the JSON/XML member by countFieldOrEmpty
    std::string_view refusedLegend() const
    {
        return refused != 0 ? " refused=N: found=0 counts what was listed; N indexed definitions fit the selector and it cannot pick one (a refusal, not an absence), and stderr names them." : "";
    }
};

inline void writeNotFoundAnswer( std::FILE* out, const NotFoundAnswer& a, bool json )
{
    if( json )
    {
        std::string body = "{";
        for( const auto& [ key, value ] : a.echo )
        {
            body += "\"" + std::string( key ) + "\":\"" + jsonStr( value ) + "\",";
        }
        body += "\"found\":0" + countFieldOrEmpty( "refused", a.refused, /*json=*/true );
        if( !a.missing.empty() ) { body += ",\"missing\":\"" + std::string( a.missing ) + "\""; }
        if( !a.near.name.empty() ) { body += ",\"near\":\"" + jsonStr( a.near.name ) + "\""; }
        if( a.near.renamed ) { body += ",\"near_renamed\":true"; }
        rw::emitTo( out, "{}}}\n", body );
        return;
    }
    std::vector<char> esc;
    std::string       root = "<" + std::string( a.tag );
    for( const auto& [ key, value ] : a.echo )
    {
        root += " " + std::string( key ) + "=\"" + std::string( escapeXml( value, esc ) ) + "\"";
    }
    root += " found=\"0\"" + countAttrXmlOrEmpty( "refused", a.refused );
    if( !a.missing.empty() ) { root += " missing=\"" + std::string( a.missing ) + "\""; }
    if( !a.near.name.empty() ) { root += " near=\"" + std::string( escapeXml( a.near.name, esc ) ) + "\""; }
    if( a.near.renamed ) { root += " near_renamed=\"1\""; }
    rw::emitTo( out, "<!-- ripwire {}: NOT FOUND, an answer and a refusal at once. found=0: no indexed definition matched the "
                     "selector echoed on this element, so nothing was listed or counted. Zero means none found, not none exists: "
                     "an unindexed file, a typo or an uncommitted rename can each hide the definition.{}{} near=: the indexed name "
                     "to retry with; near_renamed=1: the working tree renamed the selector to it (a DEFINITION of the selector left "
                     "a changed file that now defines near=; a mere mention is not a rename). On the CLI the exit status stays 1, a "
                     "refusal, and stderr carries the same diagnosis; over MCP this document rides the refusal's error data. -->{}/>",
                 a.tag, a.refusedLegend(),
                 a.missing.empty() ? "" : " missing=from|to|both: the endpoint(s) that matched nothing; near= retries the first.", root );
}

}   // namespace rw
