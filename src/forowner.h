#pragma once
// forowner.h — THE QUESTION'S OWNER, one implementation for both --for dialects (the CLI lens, verbs_for.h, and the MCP
// `for` twin, mcpverbs.h): the owner match key (ownerFoldName / ownerQuestionWords), owner-hop's found set (forOwnerCandidates,
// read by verbs_for.h forOwnerHopPlan), and the ONE owner body an explanatory question carries (the body slot, lane
// for-body-slot, train 28).
//
// THE BODY SLOT. A conceptual --for question that asks how something works ("how does the JWT middleware verify a token?")
// is answered on the compact route with signatures and one-hop edges, no bodies — and on 9 of the 15 round-4 token-budget rows
// the owner symbol was ranked at R0 while the answer shipped bodies=0, one body away from complete. The slot serves ONE body,
// chosen in this order (forBodySlotOwner):
//   1. pick="name": owner-hop's owners (a callable definition in the ranked head whose whole folded name equals a question
//      word). Among them the ENTRY POINT wins — the first with a call edge to an owner named by ANOTHER word (jwt calls verify,
//      index calls walk); a self-edge, a recursion or a same-named callee (super().refresh(), an overload chain) never makes
//      one. Else the first (best rank, common words after the rest).
//   2. pick="member": no name owner — the first head-tier class/struct/interface row with a member the question names (the
//      ninja shape: Builder ranks, Builder::Build does not). Member BY THE PARSER: Symbol::scope equals the class name (C++
//      in-class and out-of-line, Rust impl/trait, Python), or the class's own parsed span contains the definition in the same
//      file (TS/JS classes and every other language whose methods nest in the class body). A common word (get, run, set …) is
//      never a member owner. NAMED FLOOR: Go receiver methods carry no scope and sit outside the type's span, so a Go type
//      donates no member until the parser records a receiver scope (forbodyslotcheck (Q1) Go floor pins it).
// Neither → no slot (the answer is the slot-off answer byte for byte). There is no subtoken fallback (owner ruling
// 2026-10-15, lane for-body-slot FIX1): a callable that merely shares one word with the question is not its owner, and
// measured over the round-4 rows it served 28 KB of mostly tangential or off-subject bodies for no substantive item.
// A class/struct/interface/type is never the body; a test symbol never is; a declaration (header prototype, .d.ts, TS overload
// signature, C++ pure virtual, Go interface method spec) never is (isDefinitionNotDeclaration). This is a choice BY NAME over
// the ranked head (pick= says which reading chose it), never a resolution: the body is the entry point among the named owners,
// not necessarily the question's subject, and not a claim that it is the only relevant body.
// RIPWIRE_NO_BODY_SLOT (any value) turns the slot off — the A/B handle, the RIPWIRE_NO_OWNER_HOP precedent; the two are
// independent (forbodyslotcheck (EV1)).

#include "filter.h"     // isTestSymbol
#include "graph.h"      // langCompatible
#include "hopbody.h"    // insertOpenTagAttrs — the one open-tag attribute splice
#include "lexical.h"    // isRouteStopword
#include "model.h"
#include "serialize.h"  // kForLensDefaultTopN, kForDocExcerptRankCount, packBodies
#include "taskroute.h"  // hasExplanatoryCue — the explanatory cues, word-bounded (the router's own reading)
#include "infra/sortutil.h"

#include <algorithm>
#include <cstddef>
#include <cstdint>
#include <cstdlib>
#include <optional>
#include <string>
#include <string_view>
#include <vector>

namespace rw
{

// owner-hop: a word on this list (verbs and function words a question USES) ranks after every other owner word; the member
// owner never takes one (every class has a get/run/set)
inline constexpr std::string_view kOwnerCommonWords[] = {
    "all", "call", "each", "from", "get", "has", "into", "new", "put", "read", "run", "set", "that", "then", "this",
    "use", "when", "with", "write" };
static_assert( std::ranges::is_sorted( kOwnerCommonWords, rw::sortutil::svLess ), "kOwnerCommonWords is binary-searched: keep it sorted" );


// ASCII fold of one name or word, leading _ # $ @ removed (the owner match key)
inline std::string ownerFoldName( std::string_view n )
{
    std::size_t i = 0;
    while( i < n.size() && ( n[i] == '_' || n[i] == '#' || n[i] == '$' || n[i] == '@' ) )
    {
        ++i;
    }
    std::string out( n.substr( i ) );
    for( char& c : out )
    {
        c = ( c >= 'A' && c <= 'Z' ) ? char( c - 'A' + 'a' ) : c;
    }
    return out;
}

// the question's distinct owner words, sorted (binary-searched below — any question length, no per-word scan)
inline std::vector<std::string> ownerQuestionWords( std::string_view task )
{
    std::vector<std::string> words;
    const auto isWordByte = []( unsigned char c ) noexcept
    { return ( c >= 'a' && c <= 'z' ) || ( c >= 'A' && c <= 'Z' ) || ( c >= '0' && c <= '9' ) || c == '_' || c >= 0x80; };
    std::size_t i = 0;
    while( i < task.size() )
    {
        if( !isWordByte( static_cast<unsigned char>( task[i] ) ) )
        {
            ++i;
            continue;
        }
        const std::size_t start = i;
        while( i < task.size() && isWordByte( static_cast<unsigned char>( task[i] ) ) )
        {
            ++i;
        }
        std::string w = ownerFoldName( task.substr( start, i - start ) );
        if( w.size() >= 3 && !rw::isRouteStopword( w ) )
        {
            words.push_back( std::move( w ) );
        }
    }
    std::sort( words.begin(), words.end() );
    words.erase( std::unique( words.begin(), words.end() ), words.end() );
    return words;
}

// One owner of the question: a ranked row of the pool, its 1-based rank, the folded word its name equals.
struct OwnerCandidate
{
    NodeId      id;
    std::size_t rank;
    std::string word;
};

// A callable DEFINITION outside the test partition: the kind/definition/test half of the owner predicate, every reading from
// the index (a C prototype and its body are one entity — the body's row is the owner).
inline bool isOwnerCallableDef( const IngestResult& ing, NodeId id ) noexcept
{
    const Symbol& s = ing.symbols[id];
    return ( s.kind == SymKind::Function || s.kind == SymKind::Method ) && isDefinitionNotDeclaration( s ) && !isTestSymbol( ing, id );
}

// OWNER-HOP'S FOUND SET (lane owner-hop-068; verbs_for.h forOwnerHopPlan states the rule in full): the callable definitions of the
// ranked pool (the first kForLensDefaultTopN rows with a positive score) whose whole folded name equals a question word, kept
// per WORD when one of that word's definitions ranks inside the head tier (rank <= kForDocExcerptRankCount); rank order, common
// words after the rest (stable). Owner-hop and the body slot read the same set; the RIPWIRE_NO_OWNER_HOP switch is owner-hop's
// own (it stays in forOwnerHopPlan), so it never reaches the slot.
inline std::vector<OwnerCandidate> forOwnerCandidates( const IngestResult& ing, const std::vector<std::string>& words,
                                                       const std::vector<NodeId>& lensSurfaceIds, const std::vector<float>& lensRank )
{
    std::vector<OwnerCandidate> found;
    if( words.empty() )
    {
        return found;
    }
    const std::size_t pool = std::min( lensSurfaceIds.size(), std::size_t( kForLensDefaultTopN ) );
    for( std::size_t i = 0; i < pool; ++i )
    {
        const NodeId id = lensSurfaceIds[i];
        if( id >= ing.symbols.size() || lensRank[id] <= 0.0f || !isOwnerCallableDef( ing, id ) )
        {
            continue;
        }
        std::string key = ownerFoldName( ing.symbols[id].name );
        if( std::binary_search( words.begin(), words.end(), key ) )
        {
            found.push_back( OwnerCandidate{ id, i + 1, std::move( key ) } );
        }
    }
    // the head-tier gate, per WORD: a word qualifies when one of its definitions ranks inside the head tier
    std::vector<std::string> headWords;
    for( const OwnerCandidate& o : found )
    {
        if( o.rank <= kForDocExcerptRankCount )
        {
            headWords.push_back( o.word );
        }
    }
    std::sort( headWords.begin(), headWords.end() );
    std::erase_if( found, [ & ]( const OwnerCandidate& o ) { return !std::binary_search( headWords.begin(), headWords.end(), o.word ); } );
    // rank order, common words after the rest (stable: rank order inside each group)
    std::stable_partition( found.begin(), found.end(), []( const OwnerCandidate& o )
                           { return !std::ranges::binary_search( kOwnerCommonWords, std::string_view( o.word ), rw::sortutil::svLess ); } );   // svLess: #345
    return found;
}

// The full dialect's reading of the slot, shared word for word by the CLI lens (which adds its root clause) and the MCP twin:
// present-only. What it does NOT mean is in it: not a resolution, not necessarily the subject, not the only relevant body.
// No "--": it rides inside an XML comment.
inline constexpr std::string_view kForBodySlotLegend =
    "; owner body: an explanatory question (how does, what does) also carries ONE body, in a bodies section near the end. It is "
    "chosen BY NAME in the ranked head, not resolved: pick=name its name equals a question word (among several such owners, the "
    "one calling an owner another word names), pick=member a method of a ranked class the question names (by the parser's scope "
    "or the class's own span); no such owner, no body. It is not necessarily the question's "
    "subject nor the only relevant body. Over 6000 B it is cut at a line end (b truncated=1 lines= next= the rest); a budget too "
    "small for it skips it: bodies shown=0 capped=1 next= the call that serves it";

// ── THE BODY SLOT ───────────────────────────────────────────────────────────────────────────────────────────────────────────
// The CDATA cap of the one body: a larger owner is head-cut at a line end (UTF-8 safe, packBodies' cutOversizedBody) with
// truncated="1" lines= next= naming the rest; one first line over it is served whole with over_ceiling="1". A content cap with
// a disclosed, recoverable cut (knob census).
inline constexpr std::size_t kForBodySlotMaxBytes = 6000;
static_assert( kForBodySlotMaxBytes == 6000 && kForBodySlotLegend.find( "Over 6000 B" ) != std::string_view::npos,
               "the slot legend states the cap: move both together" );

enum class BodySlotPick : std::uint8_t { None, Name, Member };

// pick= spellings, indexed by BodySlotPick (None has none)
inline constexpr std::string_view kBodySlotPickNames[] = { "", "name", "member" };
static_assert( std::size( kBodySlotPickNames ) == std::size_t( BodySlotPick::Member ) + 1, "one pick= spelling per BodySlotPick" );

struct ForBodySlotOwner
{
    NodeId       id   = kNoNode;
    BodySlotPick pick = BodySlotPick::None;
    bool any() const noexcept { return id != kNoNode; }
};

// Does the slot fire for this question at all: an explanatory cue (taskroute.h, word-bounded — `show documentation` holds no
// `how do`) and the A/B switch not set. The caller adds the posture (compact route, XML dialect, no caller-chosen bodies).
inline bool forBodySlotAsked( std::string_view task )
{
    return std::getenv( "RIPWIRE_NO_BODY_SLOT" ) == nullptr && rw::taskroute::hasExplanatoryCue( rw::queryshape::detail::lowerAscii( task ) );
}

// THE ENTRY POINT among the name owners: the first (in their order) with an out-edge — resolved or by name — to ANOTHER owner
// named by a DIFFERENT word. Same-word edges (a recursion the graph keeps, super().refresh(), an overload chain) are not
// entry-point evidence: they say nothing about which of two subjects the question's words name drives the other.
inline NodeId forOwnerEntryPoint( const std::vector<OwnerCandidate>& owners, const std::vector<std::uint32_t>& outOff,
                                  const std::vector<NodeId>& outTargets )
{
    for( const OwnerCandidate& o : owners )
    {
        if( std::size_t( o.id ) + 1 >= outOff.size() )
        {
            continue;
        }
        for( std::uint32_t e = outOff[o.id]; e < outOff[o.id + 1] && e < outTargets.size(); ++e )
        {
            const NodeId t   = outTargets[e];
            const auto   hit = std::ranges::find_if( owners, [ & ]( const OwnerCandidate& c ) { return c.id == t; } );
            if( hit != owners.end() && hit->id != o.id && hit->word != o.word )
            {
                return o.id;
            }
        }
    }
    return owners.empty() ? kNoNode : owners.front().id;
}

// Is `m` a member of the class row `c` BY THE PARSER: its scope names the class, or the class's own span contains it.
inline bool isParsedMemberOf( const Symbol& m, const Symbol& c ) noexcept
{
    if( m.id == c.id || !langCompatible( m.lang, c.lang ) )
    {
        return false;
    }
    if( !m.scope.empty() && m.scope == c.name )
    {
        return true;
    }
    return m.fileId == c.fileId && c.sigStartByte <= m.sigStartByte && m.endByte <= c.endByte && c.endByte > c.sigStartByte;
}

// The head-tier (rank <= kForDocExcerptRankCount) class/struct/interface rows, rank order: the classes that may donate a member.
inline std::vector<NodeId> headTierClassRows( const IngestResult& ing, const std::vector<NodeId>& lensSurfaceIds, const std::vector<float>& lensRank )
{
    std::vector<NodeId> rows;
    const std::size_t   head = std::min( lensSurfaceIds.size(), std::size_t( kForDocExcerptRankCount ) );
    for( std::size_t i = 0; i < head; ++i )
    {
        const NodeId id = lensSurfaceIds[i];
        if( id >= ing.symbols.size() || lensRank[id] <= 0.0f )
        {
            continue;
        }
        const SymKind k = ing.symbols[id].kind;
        if( k == SymKind::Class || k == SymKind::Struct || k == SymKind::Interface )
        {
            rows.push_back( id );
        }
    }
    return rows;
}

// Every callable definition outside the tests whose folded name is a NON-common question word, in id order — one pass over the
// symbols (the fold allocates, so the cheap kind test runs first), read once by every head-tier class.
inline std::vector<NodeId> memberWordDefs( const IngestResult& ing, const std::vector<std::string>& words )
{
    std::vector<std::string> memberWords = words;
    std::erase_if( memberWords, []( const std::string& w ) { return std::ranges::binary_search( kOwnerCommonWords, std::string_view( w ), rw::sortutil::svLess ); } );
    std::vector<NodeId> named;
    for( NodeId id = 0; id < ing.symbols.size() && !memberWords.empty(); ++id )
    {
        const SymKind k = ing.symbols[id].kind;
        if( ( k == SymKind::Function || k == SymKind::Method ) && isOwnerCallableDef( ing, id )
            && std::binary_search( memberWords.begin(), memberWords.end(), ownerFoldName( ing.symbols[id].name ) ) )
        {
            named.push_back( id );
        }
    }
    return named;
}

// THE MEMBER OWNER: the first head-tier class/struct/interface row (rank order) with a member definition the question names
// (a non-common word); among that class's members the highest lens score, then the lowest id. kNoNode when none has one.
inline NodeId forMemberOwner( const IngestResult& ing, const std::vector<std::string>& words, const std::vector<NodeId>& lensSurfaceIds,
                              const std::vector<float>& lensRank )
{
    const std::vector<NodeId> classRows = headTierClassRows( ing, lensSurfaceIds, lensRank );
    const std::vector<NodeId> named     = classRows.empty() ? std::vector<NodeId>{} : memberWordDefs( ing, words );
    const auto score = [ & ]( NodeId id ) { return id < lensRank.size() ? lensRank[id] : 0.0f; };
    for( NodeId cls : classRows )
    {
        NodeId best = kNoNode;
        for( NodeId m : named )
        {
            // `named` is in id order, so a tie in score keeps the lower id
            if( isParsedMemberOf( ing.symbols[m], ing.symbols[cls] ) && ( best == kNoNode || score( m ) > score( best ) ) )
            {
                best = m;
            }
        }
        if( best != kNoNode )
        {
            return best;
        }
    }
    return kNoNode;
}

// The slot's one owner, in the order the header comment states; {kNoNode, None} when the question names none.
inline ForBodySlotOwner forBodySlotOwner( const IngestResult& ing, const std::vector<std::uint32_t>& outOff, const std::vector<NodeId>& outTargets,
                                          std::string_view task, const std::vector<NodeId>& lensSurfaceIds, const std::vector<float>& lensRank )
{
    const std::vector<std::string> words = ownerQuestionWords( task );
    if( words.empty() )
    {
        return {};
    }
    const std::vector<OwnerCandidate> owners = forOwnerCandidates( ing, words, lensSurfaceIds, lensRank );
    ForBodySlotOwner out;
    if( !owners.empty() )
    {
        out = ForBodySlotOwner{ forOwnerEntryPoint( owners, outOff, outTargets ), BodySlotPick::Name };
    }
    else if( const NodeId m = forMemberOwner( ing, words, lensSurfaceIds, lensRank ); m != kNoNode )
    {
        out = ForBodySlotOwner{ m, BodySlotPick::Member };
    }
    const bool ownerIsCallableDef = !out.any() || ( out.id < ing.symbols.size() && isOwnerCallableDef( ing, out.id ) );
    ENSURES( ownerIsCallableDef, "the body slot's owner is one indexed callable definition outside the test partition" );
    return out;
}

// pick= on the rendered <bodies> element (packBodies writes the element; the slot names how its one body was chosen)
inline void spliceBodySlotPick( std::string& xml, BodySlotPick pick )
{
    insertOpenTagAttrs( xml, "<bodies shown=", std::string( " pick=\"" ) + std::string( kBodySlotPickNames[std::size_t( pick )] ) + "\"" );
}

// The slot SKIPPED under an explicit target (its whole render did not fit the share the rows at the cut left it): the element
// says so the house way — shown="0" of total="1", capped="1" — and next= is the call that serves the owner's body
// (--expand=PATH:LINE:NAME, the entity, not just the name).
inline std::string bodySlotSkippedXml( const IngestResult& ing, NodeId id, BodySlotPick pick, std::string_view rootArg )
{
    EXPECTS( id < ing.symbols.size(), "a skipped slot names an indexed owner" );
    const Symbol&     s          = ing.symbols[id];
    const std::string rootPrefix = rootArg.empty() ? std::string() : rw::sarif::rootPrefixOf( rootArg );
    const std::string path       = rootArg.empty() ? std::string( ing.files[s.fileId] ) : std::string( rw::sarif::rootRelativeUri( ing.files[s.fileId], rootPrefix ) );
    std::vector<char> esc;
    std::string       x = "<bodies shown=\"0\" total=\"1\" capped=\"1\" pick=\"";
    x += kBodySlotPickNames[std::size_t( pick )];
    x += "\" next=\"";
    x += escapeXml( nextFlag( "--expand=", path + ":" + std::to_string( s.line ) + ":" + s.name ), esc );   // quoted only where a shell would split it
    x += "\"></bodies>";
    return x;
}

// THE SLOT'S RENDER, one for both dialects: the owner's body through packBodies (the --expand shape, <calls> kept), cut at
// kForBodySlotMaxBytes; pick= spliced on <bodies>. `share` is what an explicit target left this section (nullopt: the default
// regime, the body rides on top): a render over it is replaced by the skip disclosure and its redaction count taken back.
struct BodySlotRender
{
    std::string xml;               // the served <bodies> element, or the skip disclosure; empty when nothing rides (degrade)
    std::size_t bodyTokens  = 0;   // a served body, priced at the body rate (the T3 bodies' rate)
    std::size_t markupBytes = 0;   // a skip disclosure, priced with the rest of the markup
    bool        served      = false;
    bool        skipped     = false;
};
struct BodySlotInputs
{
    const IngestResult&               ing;
    const std::vector<std::uint32_t>& outOff;
    const std::vector<NodeId>&        outTargets;
    const std::vector<std::uint8_t>&  outNameOnly;
    const std::vector<float>&         lensRank;      // orders a cut <calls> listing, as every --for body's
    std::string_view                  rootArg;
    RedactCounts*                     redact;
    const notes::NoteIndex*           notes;
    bool                              viaLegendInHead;   // the header already defines via="name"
    bool                              compress;          // --compress (the CLI only; the MCP twin never sets it)
    // train 28 (for-body-slot x attrib-multidef): the slot's <calls> rows carry prov="split" like every other --for body's, so
    // a split arm reads as one here too; the split reading rides beside the rows unless the header already defines it
    const std::vector<std::uint8_t>*  outProv           = nullptr;   // Graph::outProv (nullptr: no split labels)
    bool                              splitLegendInHead = false;     // the header already defines prov="split"
    const std::vector<std::uint8_t>*  outAnchor         = nullptr;   // Graph::outAnchorMiss (nullptr: no anchor="missing")
};
inline BodySlotRender renderForBodySlot( const BodySlotInputs& in, ForBodySlotOwner owner, std::optional<std::size_t> share )
{
    EXPECTS( owner.any() && owner.id < in.ing.symbols.size(), "the slot renders one indexed owner" );
    BodySlotRender                    out;
    const std::optional<RedactCounts> before = in.redact != nullptr ? std::optional<RedactCounts>( *in.redact ) : std::nullopt;
    ChargedSection sec = chargeSection( [ & ]( std::FILE* f )
        { packBodies( f, in.ing, { owner.id }, kForBodySlotMaxBytes, in.outOff, in.outTargets, withAnchorEdge( CalleeEdgeBytes( in.outNameOnly, in.outProv, nullptr ), in.outAnchor ),
                      in.compress, in.redact, /*ranges=*/nullptr, in.notes, /*outEmitted=*/nullptr, /*truncateOversizedFirst=*/true,
                      /*withFileContext=*/false, in.rootArg, &in.lensRank, CalleeLegendsInHead( in.viaLegendInHead, in.splitLegendInHead ) ); },
        kBytesPerTokenBody );
    if( !sec.isRendered )
    {
        // chargeSection DISCLOSEd the failed buffer into `sec` (its alert is on stderr): the slot rides nowhere and the caller drops
        // its clause, so nothing names a body that is not there (the T3 auto bundle's degrade contract)
        rw::redactTakeBack( in.redact, before, in.redact != nullptr ? std::optional<RedactCounts>( *in.redact ) : std::nullopt );
        return out;
    }
    spliceBodySlotPick( sec.xml, owner.pick );
    if( share && sec.xml.size() > *share )
    {
        rw::redactTakeBack( in.redact, before, in.redact != nullptr ? std::optional<RedactCounts>( *in.redact ) : std::nullopt );   // not served
        out.xml         = bodySlotSkippedXml( in.ing, owner.id, owner.pick, in.rootArg );
        out.markupBytes = out.xml.size();
        out.skipped     = true;
        return out;
    }
    out.xml        = std::move( sec.xml );
    out.bodyTokens = tokensForEmittedBytes( out.xml.size(), kBytesPerTokenBody );
    out.served     = true;
    return out;
}

}   // namespace rw
