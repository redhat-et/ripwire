#pragma once
// forgraphverb.h — FOR-ROUTE-DECLINED: a --for task SPELLED as a graph question (`path from A to B`, `callers of X`,
// `common callers of A and B`) gets the graph verb it names appended after its ordinary answer, run on the
// already-built index (CLI src/verbs_for.h appendSubjectGraphVerbBlock, MCP `for` src/mcpverbs.h forTaskText — one wrapper).
//
// WHY. The ranked --for bundle answers these by subtoken overlap and misses the chain between the two names; the
// verb answers them from the call graph. Measured (ORCH reports/for-route-s0.md, train-39 binary, LARGE-DEV): appending
// the verb's DEFAULT-cap answer flips 7 rows a tier (5 to complete), recovers 13 of 15 missing chain items and loses
// none, at +1.2-4.9 KB per fired row; the parser fires on 0 of 258 non-graph subjects.
//
// WHAT. lexical.h parseGraphSubject reads the endpoints from the task's words (no plain-word fallback but `main`);
// chooseGraphSubjectArgs below tries at most kGraphSubjectAttempts candidate combinations in preference order and
// keeps the first whose every endpoint the verb's own resolver finds (the verb then never refuses). The ordinary
// answer is never replaced: the block rides after it, inside <graph_verb endpoints="subject">, whose legend says the
// endpoints were read from prose (a name match, hedged), and the verb's default caps and next= paging bound it.
// Nothing resolves → nothing is appended (byte-identical to the answer without this lane).
#include "filter.h"      // pathTierOf — name_test_hops=: the verb's own test/fixture path classifier
#include "graph.h"       // resolveAllByNameQualified / resolveFocus — the callers / connect resolvers
#include "lexical.h"     // parseGraphSubject — the subject-only half
#include "nextverb.h"    // nextFlag / nextAttrXml — verb= is a pasteable invocation
#include "pathgaps.h"    // resolvePathEndpoint — the --path resolver
#include "serialize.h"   // escapeXml

#include <cstddef>
#include <optional>
#include <string>
#include <string_view>
#include <utility>
#include <vector>

namespace rw
{
inline constexpr std::size_t kGraphSubjectAttempts = 4;   // candidate combinations tried (Stage 0: <= 4)
inline constexpr std::size_t kGraphSubjectSlotCands = 3;  // per-slot candidates in a two-endpoint form (3 x 3, best 4)

struct GraphSubjectArgs
{
    GraphSubjectForm         form = GraphSubjectForm::Path;
    std::vector<std::string> endpoints;   // the resolved spellings, slot order
    std::vector<std::string> spans;       // the words each slot was read from
    std::size_t              tried = 0;   // combinations tried before this one resolved (1 = the first)
    std::vector<std::string> unresolved;  // the spellings the resolver did NOT find on the way (tried > 1 only), first-tried first
};

// How a block is opened (FOR-ROUTE fix1): `jsonDialect` = the body is the MCP callers twin's JSON in a CDATA section (S1);
// `held` = a token budget is set, so the verb did NOT run here and the tag is self-closed with the verb= handle only (S2);
// `nameTestHops` = path rows matched by name alone whose p= is a test or fixture path (S5), 0 = attribute absent.
struct GraphSubjectOpen
{
    bool        jsonDialect  = false;
    bool        held         = false;
    std::size_t nameTestHops = 0;
};

// The candidate combinations, in the order they are tried (at most kGraphSubjectAttempts). A two-endpoint form ranks (a,b) by
// index sum, then a's index (parse.py).
inline std::vector<std::vector<std::string>> graphSubjectCombinations( const GraphSubject& gs )
{
    std::vector<std::vector<std::string>> combos;
    if( gs.slots.size() == 1 )
    {
        for( std::size_t a = 0; a < gs.slots[0].size() && combos.size() < kGraphSubjectAttempts; ++a )
        {
            combos.push_back( { gs.slots[0][a] } );
        }
        return combos;
    }
    const std::size_t na = std::min( gs.slots[0].size(), kGraphSubjectSlotCands );
    const std::size_t nb = std::min( gs.slots[1].size(), kGraphSubjectSlotCands );
    for( std::size_t sum = 0; sum + 2 <= na + nb && combos.size() < kGraphSubjectAttempts; ++sum )
    {
        for( std::size_t a = 0; a < na && a <= sum && combos.size() < kGraphSubjectAttempts; ++a )
        {
            if( sum - a < nb )
            {
                combos.push_back( { gs.slots[0][a], gs.slots[1][sum - a] } );
            }
        }
    }
    return combos;
}

// The first candidate combination whose every endpoint the verb's own resolver finds; nullopt when the task is not
// a graph question or no combination resolves.
inline std::optional<GraphSubjectArgs> chooseGraphSubjectArgs( const IngestResult& ing, std::string_view task )
{
    const std::optional<GraphSubject> gs = parseGraphSubject( task );
    if( !gs )
    {
        return std::nullopt;
    }
    const auto resolves = [ & ]( const std::string& spec ) -> bool
    {
        std::size_t unproven = 0;
        bool        glob     = false;
        switch( gs->form )
        {
            case GraphSubjectForm::Path: return !resolvePathEndpoint( ing, spec, &unproven, &glob ).empty();
            case GraphSubjectForm::Callers: return !resolveAllByNameQualified( ing, spec, &unproven ).empty();
            case GraphSubjectForm::Common: return resolveFocus( ing, spec, &unproven ) != kNoNode;
        }
        return false;
    };
    const std::vector<std::vector<std::string>> combos = graphSubjectCombinations( *gs );
    std::vector<std::pair<std::string, bool>> memo;   // a spelling is resolved once however many combinations hold it
    const auto found = [ & ]( const std::string& spec ) -> bool
    {
        for( const auto& [ s, ok ] : memo )
        {
            if( s == spec ) { return ok; }
        }
        memo.emplace_back( spec, resolves( spec ) );
        return memo.back().second;
    };
    for( std::size_t k = 0; k < combos.size(); ++k )
    {
        bool all = true;
        for( const std::string& e : combos[k] )
        {
            all = all && found( e );
        }
        if( all )
        {
            GraphSubjectArgs a{ gs->form, combos[k], gs->spans, k + 1, {} };
            for( const auto& [ spelling, ok ] : memo )
            {
                if( !ok ) { a.unresolved.push_back( spelling ); }
            }
            return a;
        }
    }
    return std::nullopt;
}

// the verb's flag and its value, as the CLI spells them
inline std::pair<std::string_view, std::string> graphSubjectVerbFlag( const GraphSubjectArgs& a )
{
    std::string v = a.endpoints.empty() ? std::string() : a.endpoints[0];
    for( std::size_t k = 1; k < a.endpoints.size(); ++k )
    {
        v += "," + a.endpoints[k];
    }
    switch( a.form )
    {
        case GraphSubjectForm::Path: return { "--path=", v };
        case GraphSubjectForm::Callers: return { "--callers=", v };
        case GraphSubjectForm::Common: return { "--connect=", v };
    }
    return { "--path=", v };
}

// Path rows (`<s t= n= p="file:line" [via="name"]/>`) matched by NAME ALONE whose p= is a test or fixture path (pathTierOf, the
// classifier the verb's own from_test= uses). A text read of the verb's printed rows, so it only HEDGES: zed-03's chain crosses
// `Markdown::new(` bound by name to a test constructor, an intermediate hop the endpoint-only from_test=/to_test= cannot see.
inline std::size_t graphSubjectNameTestHops( std::string_view doc )
{
    std::size_t n = 0;
    for( std::size_t at = doc.find( "<s " ); at != std::string_view::npos; at = doc.find( "<s ", at + 3 ) )
    {
        const std::size_t end = doc.find( "/>", at );
        if( end == std::string_view::npos ) { break; }
        const std::string_view row = doc.substr( at, end - at );
        const std::size_t      p   = row.find( " p=\"" );
        if( p == std::string_view::npos || row.find( " via=\"name\"" ) == std::string_view::npos ) { continue; }
        std::string_view path = row.substr( p + 4 );
        path                  = path.substr( 0, path.find( '"' ) );
        path                  = path.substr( 0, path.rfind( ':' ) );
        n += pathTierOf( path ) == PathTier::TestOrBench ? 1 : 0;
    }
    return n;
}

// ` from_span="…" to_span="…"` | ` of_span="…" [and_span="…"]`
inline std::string graphSubjectSpanAttrs( const GraphSubjectArgs& a )
{
    static constexpr std::string_view kPathSpans[]   = { "from_span", "to_span" };
    static constexpr std::string_view kCommonSpans[] = { "of_span", "and_span" };
    std::string       out;
    std::vector<char> esc;
    for( std::size_t k = 0; k < a.spans.size() && k < 2; ++k )
    {
        const std::string_view name = a.form == GraphSubjectForm::Path ? kPathSpans[k] : a.form == GraphSubjectForm::Common ? kCommonSpans[k] : "of_span";
        out += " " + std::string( name ) + "=\"" + std::string( escapeXml( a.spans[k], esc ) ) + "\"";
    }
    return out;
}

// ` tried="N" unresolved="a b"` — only when an earlier combination did not resolve
inline std::string graphSubjectTriedAttrs( const GraphSubjectArgs& a )
{
    if( a.tried <= 1 )
    {
        return {};
    }
    std::string       out = " tried=\"" + std::to_string( a.tried ) + "\"";
    std::string       names;
    std::vector<char> esc;
    for( const std::string& u : a.unresolved ) { names += ( names.empty() ? "" : " " ) + u; }
    return out + ( names.empty() ? "" : " unresolved=\"" + std::string( escapeXml( names, esc ) ) + "\"" );
}

// The opening of the block: its own legend (present only with the block; no `--` inside the comment), then
// <graph_verb endpoints="subject" verb=… from_span=/to_span= | of_span= [| and_span=] [tried= unresolved=] [dialect=] [held=] [name_test_hops=]>.
// tried=/unresolved= are present only when an earlier combination did not resolve; every other clause only with its attribute.
inline std::string graphSubjectOpenXml( const GraphSubjectArgs& a, const GraphSubjectOpen& o = {} )
{
    std::string out = "<!-- ripwire for graph_verb: the task is spelled as a graph question, so the verb it names ran too, on the built "
                      "index with its default caps; endpoints=\"subject\": its endpoints were READ FROM THE TASK WORDS (the *_span= "
                      "attributes, cut at the first for/with/via/in/on/when/using/during/at/near, sentence end, comma or clause word "
                      "such as and/then/how/which), matched by name, not chosen "
                      "from the graph: check they are the symbols meant; verb= is the same call to paste";
    out += a.tried > 1 ? "; tried= combinations of the words were tried, the first that resolves ran; unresolved= names the spellings that did not resolve" : "";
    out += o.jsonDialect ? "; dialect=\"json\": this surface answers the verb as JSON, carried as CDATA text, not as XML rows" : "";
    out += o.nameTestHops > 0 ? "; name_test_hops=N: N path hops were matched by name alone to a definition in a test or fixture path, so they may not be the call the source makes" : "";
    out += o.held ? "; held=\"budget\": a token budget is set, so the verb did NOT run here: verb= is the one call to run; the answer above is unchanged --><graph_verb endpoints=\"subject\""
                  : "; the verb's own legend follows; the answer above is unchanged, and these bytes are not in est_tokens --><graph_verb endpoints=\"subject\"";
    const auto [ flag, value ] = graphSubjectVerbFlag( a );
    out += nextAttrXml( nextFlag( flag, value ), "verb" );
    out += graphSubjectSpanAttrs( a ) + graphSubjectTriedAttrs( a );
    out += o.jsonDialect ? " dialect=\"json\"" : "";
    out += o.held ? " held=\"budget\"" : "";
    out += o.nameTestHops > 0 ? " name_test_hops=\"" + std::to_string( o.nameTestHops ) + "\"" : "";
    out += o.held ? "/>" : ">";
    return out;
}

inline constexpr std::string_view kGraphSubjectCloseXml = "</graph_verb>";
}   // namespace rw
