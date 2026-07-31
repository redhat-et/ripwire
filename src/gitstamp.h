#pragma once

// gitstamp.h — r26-stamp (Task A): the `at="<sha>[+dirty]"` anchor stamped on every repo-reading verb's root
// element. Motivation: a prior session watched the dogfood repo's HEAD move THREE times mid-session, and
// --abi's own `head=` attribute was the ONLY reason its numbers stayed comparable across those moves. Every
// other verb (--doc-drift, --pr-context, --edit-check, --hotspots, --quality-delta, --doctor, --test-gate,
// --whereis, ...) emits numbers with NO such anchor — a number quoted from one of them into a handoff is an
// unanchored claim, not a checkable fact, until it carries this stamp.
//
// WIDTH matches --abi's own precedent EXACTLY: abicheck.h's root `<abi ...>` element prints `head="%.9s"`,
// a 9-hex-char truncation of the full 40-char sha (crossref.h's `<stray-content>`/`<landing-plan>` roots
// independently converged on the same 9-char width). This module reuses that width rather than inventing a
// second one (notes.h's `shortSha` truncates to 7 for a DIFFERENT, older purpose — an inline note stamp —
// and is left alone; see this header's callers for the "keep both / converge" decision made at each site).
//
// DIRTY matches mergescout.h's own existing precedent (its `dirty` local, computed from a bare
// `git status --porcelain` with no `--uno`): a non-empty porcelain listing marks the tree dirty, and
// porcelain's default already reports UNTRACKED files alongside modified-tracked ones — so "+dirty" here
// means "tracked changes OR untracked files", not "tracked changes only". This converges onto the one dirty
// check already in the tree instead of inventing a second, narrower definition.
//
// NOT A GIT REPO (or no resolvable HEAD): `stampAt` returns "" and the caller OMITS the `at=` attribute
// entirely — never `at="none"`. This matches the codebase's existing convention for an inapplicable
// attribute (serialize.h's `precAttr`/`rootsAttr`/`changedAttr`, abicheck.h's `ref_size` omission comment):
// omit rather than print a value that reads as data.
//
// COST: two git subprocesses per call (`rev-parse` + `status --porcelain`). Every call site is an EXPLICIT
// verb invocation whose own computation already shells out to git for a diff/history/blame/staleness answer
// (or is cheap enough — a doctor/quality-delta health check — that two more subprocess calls are noise next
// to what it already pays). The one path this must NEVER touch is the bare default map (serialize.h's `<r>`
// root with no verb flag): that path reads no git today, costs ~0.02-0.10s warm, and must stay that way —
// `stampAt`/`atAttr` are simply never called from it.

#include "quality.h"   // gitHeadSha / gitOneLine — the SAME git plumbing --abi's own head= already uses

#include <string>

namespace ctx { namespace gitstamp
{

// The stamp value itself: "<9-hex-char sha>[+dirty]", or "" when `root` is not a git repo with a resolvable
// HEAD (the caller's job is to omit the attribute on empty, never to print a placeholder).
inline std::string stampAt( const std::string& root )
{
    const std::string sha = quality::gitHeadSha( root );
    if( sha.empty() ) return {};                                                     // not a git repo / no HEAD
    const bool dirty = !quality::gitOneLine( root, "status --porcelain 2>/dev/null" ).empty();
    return sha.substr( 0, 9 ) + ( dirty ? "+dirty" : "" );
}

// Formats a ready-to-splice ` at="VALUE"` (leading space included) — or "" when `root` isn't a git repo, so
// a caller can simply concatenate the result into its printf/snprintf attribute list and the attribute is
// OMITTED entirely on a non-repo target. The value is always plain hex + the literal "+dirty" (never user
// content), so it is deliberately NOT run through escapeXml.
inline std::string atAttr( const std::string& root )
{
    const std::string v = stampAt( root );
    return v.empty() ? std::string() : ( " at=\"" + v + "\"" );
}

}}   // namespace ctx::gitstamp
