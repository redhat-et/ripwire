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
// different retry syntax, JSON-RPC framing). What the two share is didyoumean.h, which both already call.

#include "model.h"
#include "graph.h"          // splitQualifiedSpec / resolveAllByName — the SAME grammar the callers resolve with
#include "didyoumean.h"     // §P12.1: the near-miss suggester, for the "the name is wrong too" fallback

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

// The distinct files defining `name`, in index order (first occurrence wins), so the message is deterministic.
inline std::vector<std::string> definingFilesOf( const IngestResult& ing, std::string_view name )
{
    std::vector<std::string> files;
    for( NodeId n : resolveAllByName( ing, name ) )
    {
        const std::string& path = ing.files[ ing.symbols[n].fileId ];
        if( std::find( files.begin(), files.end(), path ) == files.end() ) files.push_back( path );
    }
    return files;
}

// Does the FILE half of a `file:name` selector name anything in the index at all? Asked with filePathContains
// — the identical predicate resolveFocus/resolveAllByNameQualified match the file half with — so this answers
// exactly the question the resolver asked, never an approximation of it. Written as any_of rather than a
// hand-rolled loop: the loop form is a 31-token for/if/return-true/return-false stream that --clones pairs
// with every other tiny predicate in the tree (docdrift's declKeywordOnLine, for one), which is noise.
inline bool indexHasFileMatching( const IngestResult& ing, std::string_view file )
{
    return std::any_of( ing.files.begin(), ing.files.end(),
                        [ file ]( const std::string& path ) { return filePathContains( path, file ); } );
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
inline std::string selectorFaultClause( const IngestResult& ing, std::string_view spec, std::string_view retryForm )
{
    std::string_view file, bareName;
    splitQualifiedSpec( spec, file, bareName );      // did-you-mean and the site match both want the NAME half only
    const bool fileQualified = spec.find( "::" ) == std::string_view::npos && spec.find( ':' ) != std::string_view::npos;

    if( fileQualified && !file.empty() && !indexHasFileMatching( ing, file ) )
        return " (no indexed file matches '" + std::string( file ) + "' — the PATH half is the fault, so nothing is claimed "
               "about '" + std::string( bareName ) + "'; drop the qualifier (" + std::string( retryForm ) + std::string( bareName )
             + ") to search every file, or pass a path the map lists)";

    if( fileQualified )
    {
        const std::vector<std::string> definingFiles = definingFilesOf( ing, bareName );
        if( !definingFiles.empty() )
        {
            const std::size_t shownCount = std::min( definingFiles.size(), kSelectorFilesShown );
            std::string       clause     = " (that file defines no '" + std::string( bareName ) + "' — defined in ";
            for( std::size_t fileIndex = 0; fileIndex < shownCount; ++fileIndex ) clause += ( fileIndex ? ", " : "" ) + definingFiles[ fileIndex ];
            if( definingFiles.size() > shownCount ) clause += " (+" + std::to_string( definingFiles.size() - shownCount ) + " more files)";
            return clause + " — e.g. " + std::string( retryForm ) + definingFiles[0] + ":" + std::string( bareName ) + ")";
        }
    }
    return withDidYouMean( ing, bareName, {} );      // "" when no near name exists — the historic behaviour
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

}   // namespace rw
