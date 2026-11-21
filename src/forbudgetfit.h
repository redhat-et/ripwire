#pragma once
// TOKEN-BUDGET-MONOTONE (found in the 0.7.0 comparison rehearsal, 2026-11-14): a budget may only TRIM an answer, never switch
// its regime. `--for --token-budget=N` (and `--detail=N --max-tokens=M`) used to re-decide the whole body posture with the
// budget in the predicate, so a budget far above the answer returned a smaller, different answer (21/21 questions under
// 16,000 est_tokens; koa-02 24,446 B -> 10,834 B on a 5,494-token answer), and --max-tokens could GROW one.
//
// THE RULE. The posture is decided as if no budget were given (runForLens renders that answer, U, into a buffer); the
// budget is then a ceiling applied by ONE fixed shed sequence over U's bytes, cheapest-to-lose first:
//   held       the blocks outside est_tokens (kForHeldBlocks: <syms>, <doc_body>, <decl_rows> …): U prices them on top of its
//              est_tokens, and when the sum does not fit the answer is rendered ONCE more with them held (Config::forHoldBudget:
//              each block's own held="budget" stub and next=, <doc_body> served into what the answer leaves); what they still
//              print comes off the target before the units below are walked
//   attrs      the <sigs> rows' optional attributes (forpage.h kForPageShedRungMetrics: cx= ccx= layer= next=)
//   tail:N     the last N <tail> rows
//   hops:N     the last N <hops> rows (the compact route's one hop of callees; all of them: the counted marker
//              <hops shown="0" total= capped="1" next=/>)
//   fold       the <fold> bodies (the top rows' whole bodies, "not the answer")
//   bodies:N   the last N bodies of the <bodies> section (--detail's, or the auto bundle's: the root's bodies= then counts
//              what is left, and bodies="0" says reason="budget")
//   docs:N     the <doc> of the N worst-ranked <sigs> rows that print one (the row stays; docs_dropped= counts it)
//   rows:N     the N worst-ranked <sigs> rows (r= from the highest; a row with no r= first), down to a floor of
//              kForBudgetRowFloor: the kept rows are the best-ranked, in U's order — against --token-budget only: a --max-tokens
//              ceiling never cuts a ranked row (METHODOLOGY §9 #2: exceed it with over_ceiling="1" rather than drop the row
//              that would have terminated the search; formaxtokenscheck (E): the body ceiling moves no row)
//              The doc rows the docs reorder moved hold the worst r= of U's shown set, so rows:N cuts them first: <sigs
//              docs_after_code=> is recounted over the rows kept (absent at 0, its reading with it) — lane DA1, gate
//              test/fordocsaftercodecheck.sh; the walk still prices U's count, so the rows kept are the ones kept before it
// answer(B) = U with the SHORTEST prefix of that sequence removed whose est_tokens (plus the held blocks' price) is <= B; the whole sequence when none
// is (the root then prices more than it names; a --max-tokens ceiling also says over_ceiling="1"). Three consequences the
// gate (test/budgetmonotonecheck.sh) holds: B >= est(U) + its held blocks' price returns U byte for byte (a budget that fits cuts nothing, so it
// says nothing: no attribute, no clause); every row kept is U's row in U's order; and B1 < B2 removes a longer prefix, so
// answer(B1)'s rows are a prefix of answer(B2)'s. A cut ranked row is a dropped positive: dropped_positive= grows by it.
//
// PRICING. est_tokens stays THE SAME FIXPOINT finishForLensHeaderPriced converged: the ledger carries the markup bytes and
// body tokens it priced (after the demote passes' edits) and the fold's / --detail section's share of them, and each shed
// unit subtracts exactly its own bytes at its own rate. The budget's disclosure — budget_tokens= / max_tokens=, shed=,
// over_ceiling=, bodies=, dropped_positive= and the clauses defining them — is markup like any other (each candidate state is
// priced with its own), so a shed answer's est_tokens= prices the document it heads (estchargecheck #11 / #19 identities).
// A ledger whose fixpoint does not reproduce U's printed est_tokens is not trusted: nothing is shed, and the answer says
// shed="unpriced" (and stderr says why) rather than cut against a number it cannot reproduce.

#include "nextverb.h"  // nextAttrXml — the cut element's next=
#include "forpage.h"   // shedRowAttrs, kForPageShedRungMetrics — the one-row page's attribute shed, the same attributes here
#include "serialize.h" // pricedRootAttrTokens, tokensForEmittedBytes, kBytesPerTokenDefault / kBytesPerTokenBody, attrOf
#include "graphlegend.h" // kForCompactSplitClause / kForSplitClause — the present-only split reading a shed may leave rowless

#include <algorithm>
#include <cstddef>
#include <cstdint>
#include <optional>
#include <span>
#include <string>
#include <string_view>
#include <utility>
#include <vector>

namespace rw
{
inline constexpr std::size_t kForBudgetRowFloor = 4;   // the <sigs> rows never shed: kForSoftBudgetNote's "rank 1..4 rows always ship"

// What the unbudgeted answer's est_tokens was converged from, and the shares of it a shed unit can remove whole.
struct ForAnswerLedger
{
    bool        priced          = false; // the root carries an est_tokens= this ledger converged
    std::size_t markupBytes     = 0;     // every priced markup byte, est_tokens= itself excluded (after the demote edits)
    std::size_t bodyTokens      = 0;     // the body-rate sections, priced
    std::size_t foldXmlBytes    = 0;     // the <fold> element as emitted (0: none)
    std::size_t foldMarkupBytes = 0;     // its markup share (inside markupBytes)
    std::size_t foldBodyTokens  = 0;     // its body share (inside bodyTokens)
    std::size_t detailXmlBytes  = 0;     // the --detail section as charged (legend comments + <bodies>; 0: none)
    std::size_t detailTokens    = 0;     // its tokens (inside bodyTokens), tokensForEmittedBytes( detailXmlBytes, body rate )
    bool        autoBodies      = false; // that section is the auto bundle's <bodies> (no --detail): the root's bodies= counts it
    std::vector<std::uint32_t> docsAfterCodeRanks;   // the r= of the <sigs> doc rows the docs reorder moved (docs_after_code=; lane DA1)
};

// The budget asked: a soft target (--token-budget) and/or a ceiling (--max-tokens under --detail). 0 = not asked.
struct ForBudgetAsk
{
    std::size_t      targetTokens  = 0;
    std::size_t      ceilingTokens = 0;
    std::string_view continuation;   // the call without the budget (it serves what was shed): next= on every element a unit cut
    bool             heldPass = false; // the answer is the re-render with kForHeldBlocks held: shed= names held, their price comes off the target
};

// The blocks printed outside est_tokens that a budget holds (each renders its own held="budget" stub and next= under
// Config::forHoldBudget). <doc_body> prices itself (its est_tokens=); the others are priced at the markup rate.
inline constexpr std::string_view kForHeldBlocks[] = { "syms", "doc_body", "decl_rows", "exemplar_family", "manifest_rows", "graph_verb", "reexports", "shortkey", "aliases" };

// The budget's legend clauses. The fixed shed order is named once; only the units this answer took are defined (an untouched unit
// costs no bytes: the whole list was ~940 B of every shed answer's header, six sigs rows at --token-budget=2160 on forrankordercheck's
// fxcut). The target clause's first sentence is the spelling estchargecheck greps.
inline constexpr std::string_view kForBudgetTargetLegendHead =
    " [budget_tokens=: the token target asked. The answer is the one asked without it; only past the target is it shed, in one"
    " order, shed= naming what went:";
inline constexpr std::string_view kForBudgetTargetLegendTail =
    "; a cut block's next= is the call without it, its shown= what is left (other counts are the whole answer's); est_tokens prices"
    " this answer and may exceed the target]";
inline constexpr std::string_view kForBudgetCeilingLegendHead =
    " [max_tokens=: the token ceiling asked. The answer is the one asked without it; only past the ceiling is it shed, in one"
    " order (never a ranked sigs row), shed= naming what went:";
inline constexpr std::string_view kForBudgetCeilingLegendTail =
    "; a cut block's next= is the call without it, its shown= what is left (other counts are the whole answer's); est_tokens prices"
    " this answer, over_ceiling=1 when it still exceeds the ceiling]";
// beside a target, whose clause already defines shed=
inline constexpr std::string_view kForBudgetCeilingBesideTarget =
    " [max_tokens=: the token ceiling asked; shed past it as budget_tokens= is, but a ranked sigs row is never cut against the"
    " ceiling; over_ceiling=1 when est_tokens still exceeds it]";

namespace budgetfit_detail
{
// The tag opening at `lt`: one past its '>' (npos when unterminated) and whether it self-closes. The answer's attribute values are escapeXml'd (serialize.h:
// '>' is &gt;), so the first '>' closes the tag; a section the walk cannot close is never cut (sectionOf).
struct TagSpan
{
    std::size_t end         = std::string_view::npos;   // one past the '>'
    bool        selfClosing = false;                    // `<x …/>`
};
inline TagSpan tagSpan( std::string_view s, std::size_t lt ) noexcept
{
    const std::size_t gt = s.find( '>', lt );
    if( gt == std::string_view::npos )
    {
        return {};
    }
    return { gt + 1, gt > lt && s[gt - 1] == '/' };
}

// One element child of an element: its bytes [at, end) and its tag name.
struct Child
{
    std::size_t      at = 0, end = 0;
    std::string_view name;
};

inline std::string_view tagName( std::string_view s, std::size_t lt ) noexcept
{
    std::size_t j = lt + 1;
    while( j < s.size() && s[j] != ' ' && s[j] != '>' && s[j] != '/' )
    {
        ++j;
    }
    return s.substr( lt + 1, j - lt - 1 );
}

// The element children of the element opening at `open` (comments and CDATA skipped, nesting followed), and one past its
// close tag in `closeEnd`. Empty with closeEnd npos when the element does not close.
inline std::vector<Child> childrenOf( std::string_view s, std::size_t open, std::size_t& closeEnd )
{
    std::vector<Child> out;
    closeEnd             = std::string_view::npos;
    const TagSpan     ot = tagSpan( s, open );
    const std::size_t oe = ot.end;
    if( oe == std::string_view::npos || ot.selfClosing )
    {
        closeEnd = oe;
        return out;
    }
    std::size_t depth = 0, childAt = 0;
    for( std::size_t i = s.find( '<', oe ); i != std::string_view::npos; i = s.find( '<', i ) )
    {
        const std::string_view rest = s.substr( i );
        if( rest.starts_with( "<!--" ) || rest.starts_with( "<![CDATA[" ) )
        {
            const std::size_t e = s.find( rest[1] == '!' && rest[2] == '-' ? "-->" : "]]>", i );
            if( e == std::string_view::npos )
            {
                return {};
            }
            i = e + 3;
            continue;
        }
        const TagSpan     t = tagSpan( s, i );
        const std::size_t e = t.end;
        if( e == std::string_view::npos )
        {
            return {};
        }
        if( rest.starts_with( "</" ) )
        {
            if( depth == 0 )
            {
                closeEnd = e;
                return out;
            }
            if( --depth == 0 )
            {
                out.push_back( Child{ childAt, e, tagName( s, childAt ) } );
            }
        }
        else if( t.selfClosing )
        {
            if( depth == 0 )
            {
                out.push_back( Child{ i, e, tagName( s, i ) } );
            }
        }
        else
        {
            childAt = depth == 0 ? i : childAt;
            ++depth;
        }
        i = e;
    }
    return {};
}

// [at, end) of ` name="…"` inside one open tag (serialize.h attrOf finds the value), {npos, npos} when absent.
inline std::pair<std::size_t, std::size_t> attrSpan( std::string_view tag, std::string_view name ) noexcept
{
    const std::string_view value = attrOf( tag, name );
    if( value.data() == nullptr )
    {
        return { std::string_view::npos, std::string_view::npos };
    }
    const std::size_t valueAt = std::size_t( value.data() - tag.data() );
    return { valueAt - name.size() - 3, valueAt + value.size() + 1 };   // ` name="` before the value, `"` after it
}
// `tag` (an open tag) with ` name="value"` set: replaced in place when present, else added before its '>'.
inline std::string withAttr( std::string_view tag, std::string_view name, std::string_view value )
{
    const auto [ at, end ]  = attrSpan( tag, name );
    const std::size_t gt    = tag.size() >= 2 && tag[tag.size() - 2] == '/' ? tag.size() - 2 : tag.size() - 1;
    const std::size_t from  = at != std::string_view::npos ? at : gt;
    const std::size_t resume = at != std::string_view::npos ? end : gt;
    return std::string( tag.substr( 0, from ) ) + " " + std::string( name ) + "=\"" + std::string( value ) + "\"" + std::string( tag.substr( resume ) );
}
// `tag` without ` name="…"` (unchanged when absent).
inline std::string withoutAttr( std::string_view tag, std::string_view name )
{
    const auto [ at, end ] = attrSpan( tag, name );
    return at == std::string_view::npos ? std::string( tag ) : std::string( tag.substr( 0, at ) ) + std::string( tag.substr( end ) );
}
inline std::size_t attrNumber( std::string_view tag, std::string_view name ) noexcept
{
    std::size_t n = 0;
    for( const char c : attrOf( tag, name ) )
    {
        if( c < '0' || c > '9' )
        {
            return 0;
        }
        n = n * 10 + std::size_t( c - '0' );
    }
    return n;
}

// One element of the answer that a shed unit rewrites: where it sits in U, its open tag, its children, and its close.
struct Section
{
    std::size_t        at = std::string_view::npos, end = 0, openEnd = 0;
    std::vector<Child> kids;
    bool               found() const noexcept { return at != std::string_view::npos; }
};
inline Section sectionOf( std::string_view doc, const std::vector<Child>& top, std::string_view name )
{
    Section sec;
    for( const Child& c : top )
    {
        if( c.name == name )
        {
            std::size_t closeEnd = 0;
            sec.kids             = childrenOf( doc, c.at, closeEnd );
            if( closeEnd != c.end )
            {
                return Section{};   // an element the child scan could not walk is not cut
            }
            sec.at      = c.at;
            sec.end     = c.end;
            sec.openEnd = tagSpan( doc, c.at ).end;
            return sec;
        }
    }
    return sec;
}

// `sec` re-rendered with only the first `keep` children named `row` (any other child kept in place), its open tag passed
// through `retag`, and every kept row passed through `rowEdit`.
template <class Retag, class RowEdit>
std::string keepRows( std::string_view doc, const Section& sec, std::string_view row, std::size_t keep, Retag&& retag, RowEdit&& rowEdit )
{
    std::string out = retag( doc.substr( sec.at, sec.openEnd - sec.at ) );
    std::size_t at  = sec.openEnd, seen = 0;
    for( const Child& c : sec.kids )
    {
        out.append( doc.substr( at, c.at - at ) );   // anything between children (none in practice) rides through
        if( c.name == row )
        {
            if( seen++ < keep )
            {
                out += rowEdit( doc.substr( c.at, c.end - c.at ) );
            }
        }
        else
        {
            out.append( doc.substr( c.at, c.end - c.at ) );
        }
        at = c.end;
    }
    out.append( doc.substr( at, sec.end - at ) );
    return out;
}
template <class IsRow>
std::size_t countRows( const Section& sec, IsRow&& isRow ) noexcept
{
    return std::size_t( std::count_if( sec.kids.begin(), sec.kids.end(), [ & ]( const Child& c ) { return isRow( c.name ); } ) );
}
// How much of each shed unit a candidate answer has removed (the sequence's prefix, unit by unit).
struct ShedState
{
    bool        attrs = false, fold = false;
    std::size_t tailCut = 0, hopCut = 0, detailCut = 0, docCut = 0, rowCut = 0;
};

// Where held block `c` starts with its own legend: the XML comment right before it that names it (`<!-- syms: …-->`,
// `<!-- reexports held="budget": …-->`, `<!-- ripwire for manifest_rows: …-->`), printed with the block and outside est_tokens
// like it; c.at when there is none. childrenOf skips comments, so the block alone was charged (CodeRabbit #665: <syms>' 265 B
// legend rode free; CodeRabbit #686: every `<!-- ripwire for NAME` legend did, syms, decl_rows, manifest_rows and the rest).
inline std::size_t heldLegendAt( std::string_view answer, const Child& c )
{
    constexpr std::string_view kOpen = "<!-- ", kForPrefix = "ripwire for ";
    const std::size_t open = answer.substr( 0, c.at ).ends_with( "-->" ) ? answer.rfind( kOpen, c.at ) : std::string_view::npos;
    if( open == std::string_view::npos )
    {
        return c.at;
    }
    const std::string_view named = answer.substr( open + kOpen.size() );
    const std::string_view name  = named.starts_with( kForPrefix ) ? named.substr( kForPrefix.size() ) : named;
    if( name.size() <= c.name.size() || !name.starts_with( c.name ) )
    {
        return c.at;
    }
    const char after = name[c.name.size()];
    return after == ':' || after == ' ' ? open : c.at;
}

// The price of the root's kForHeldBlocks children and their legends: <doc_body>'s own est_tokens=, the rest at the markup rate.
inline std::size_t heldBlocksPrice( std::string_view answer, std::span<const Child> top )
{
    std::size_t tokens = 0;
    for( const Child& c : top )
    {
        if( std::find( std::begin( kForHeldBlocks ), std::end( kForHeldBlocks ), c.name ) == std::end( kForHeldBlocks ) )
        {
            continue;
        }
        const TagSpan     open   = tagSpan( answer, c.at );
        const std::size_t legend = c.at - heldLegendAt( answer, c );
        const std::size_t priced = c.name == "doc_body" ? attrNumber( answer.substr( c.at, open.end - c.at ), "est_tokens" ) : 0;
        tokens += priced > 0 ? priced + ( legend > 0 ? tokensForEmittedBytes( legend, kBytesPerTokenDefault ) : 0 )
                             : tokensForEmittedBytes( c.end - c.at + legend, kBytesPerTokenDefault );
    }
    return tokens;
}

// One unbudgeted answer U, parsed once: its sections, their row counts, and whether its price can be reproduced. walk() finds the
// shortest prefix of the shed sequence whose price fits; render() writes U with that prefix removed and the disclosure added.
class ForBudgetFitter
{
public:
    ForBudgetFitter( std::string_view answer, const ForBudgetAsk& ask, const ForAnswerLedger& ledger )
        : answer_( answer ), ask_( ask ), ledger_( ledger )
    {
        const std::size_t rootAt = answer.find( "<ctx " );
        top_ = rootAt == std::string_view::npos ? std::vector<Child>{} : childrenOf( answer, rootAt, rootClose_ );
        parsed_ = rootAt == 0 && rootClose_ != std::string_view::npos;
        if( !parsed_ )
        {
            return;
        }
        rootEnd_ = tagSpan( answer, 0 ).end;
        rootTag_ = answer.substr( 0, rootEnd_ );
        target_  = ask.targetTokens > 0 && ask.ceilingTokens > 0 ? std::min( ask.targetTokens, ask.ceilingTokens ) : std::max( ask.targetTokens, ask.ceilingTokens );
        nextVal_ = std::string( attrOf( nextAttrXml( ask.continuation ), "next" ) );   // ` next="…"`, escaped once
        // the ledger must reproduce the number U prints before anything is cut against it
        const std::string_view printed = attrOf( rootTag_, "est_tokens" );
        trusted_ = ledger.priced && !printed.empty() && pricedRootAttrTokens( ledger.markupBytes, kBytesPerTokenDefault, ledger.bodyTokens, &estU_ ).size() > 0
                && std::to_string( estU_ ) == printed;
        sigs_   = sectionOf( answer, top_, "sigs" );
        tail_   = sectionOf( answer, top_, "tail" );
        hops_   = sectionOf( answer, top_, "hops" );
        fold_   = sectionOf( answer, top_, "fold" );
        detail_ = ledger.detailXmlBytes > 0 ? sectionOf( answer, top_, "bodies" ) : Section{};
        foldShed_ = fold_.found() && fold_.end - fold_.at == ledger.foldXmlBytes;
        const bool detailShed = detail_.found() && tokensForEmittedBytes( ledger.detailXmlBytes, kBytesPerTokenBody ) == ledger.detailTokens;
        sigRows_    = sigs_.found() ? countRows( sigs_, isSigRow ) : 0;
        rowCutPos_  = rowCutOrder();
        docCutPos_  = docCutOrder();
        findDocsAfterCode();
        tailRows_   = tail_.found() ? countRows( tail_, []( std::string_view name ) { return name == "t"; } ) : 0;
        hopRows_    = hops_.found() ? countRows( hops_, []( std::string_view name ) { return name == "h"; } ) : 0;
        detailRows_ = detailShed ? countRows( detail_, []( std::string_view name ) { return name == "b"; } ) : 0;
        legendEnd_  = answer.substr( rootEnd_ ).starts_with( "<!--" ) ? answer.find( " -->", rootEnd_ ) : std::string_view::npos;
        heldTokens_ = heldBlocksPrice( answer, top_ );
        const std::size_t heldOff = ask.heldPass ? heldTokens_ : 0;   // what the held re-render's blocks still print comes off each target
        walkTarget_ = target_ - std::min( target_, heldOff );
        rowTarget_  = ask.targetTokens - std::min( ask.targetTokens, heldOff );   // 0: no --token-budget, no ranked row is cut
        // U's own dropped_positive= (the default ceiling's cut) rides the header comments before <sigs>: it grows by the rows cut here
        const std::string_view key = "dropped_positive=\"";
        const std::size_t      keyAt = answer.substr( 0, sigs_.found() ? sigs_.at : rootEnd_ ).find( key, rootEnd_ );
        if( keyAt != std::string_view::npos )
        {
            droppedValAt_  = keyAt + key.size();
            droppedValEnd_ = answer.find( '"', droppedValAt_ );
            droppedHad_    = attrNumber( answer.substr( keyAt - 1, droppedValEnd_ + 1 - ( keyAt - 1 ) ), "dropped_positive" );
        }
        findSplitReading();
    }

    bool parsed() const noexcept { return parsed_; }
    // B >= est(U) + the held blocks' price: nothing to shed
    bool fitsWhole() const noexcept { return trusted_ && estU_ + heldTokens_ <= target_; }
    // the answer prints blocks a budget holds: re-render it with them held before walking the sequence
    bool holdsBlocks() const noexcept { return heldTokens_ > 0; }

    // the first state, in sequence order, whose price (its own disclosure included) fits; the whole sequence when none does
    ShedState walk() const
    {
        ShedState  st;
        bool       fits = !trusted_ || walkPriceOf( st ) <= walkTarget_;   // the held re-render may fit with nothing more shed
        const auto step = [ & ]( auto&& apply, std::size_t times )
        {
            for( std::size_t k = 0; k < times && !fits; ++k )
            {
                apply();
                fits = walkPriceOf( st ) <= walkTarget_;
            }
        };
        const bool attrsShed = sigs_.found() && sigRows_ > 0 && sigsXml( ShedState{ .attrs = true } ).size() != sigs_.end - sigs_.at;
        step( [ & ] { st.attrs = true; }, attrsShed ? 1 : 0 );
        step( [ & ] { ++st.tailCut; }, tailRows_ );
        step( [ & ] { ++st.hopCut; }, hopRows_ );
        step( [ & ] { st.fold = true; }, foldShed_ ? 1 : 0 );
        step( [ & ] { ++st.detailCut; }, detailRows_ );
        step( [ & ] { ++st.docCut; }, docRows_ );
        fits = fits || ask_.targetTokens == 0 || rowsPriceOf( st ) <= rowTarget_;   // rows answer to the token target alone
        for( std::size_t k = 0, rowsCuttable = sigRows_ - std::min( sigRows_, kForBudgetRowFloor ); k < rowsCuttable && !fits; ++k )
        {
            ++st.rowCut;
            fits = rowsPriceOf( st ) <= rowTarget_;
        }
        return st;
    }

    // U's bytes with the state's sections replaced, its disclosure on the root and in the legend, est_tokens= its price
    std::string render( const ShedState& st ) const
    {
        const bool  over = overCeiling( st );
        std::string root = rootFor( st, over );
        const std::size_t estT = trusted_ ? priceOf( st, over ) : estU_;
        root = trusted_ && estT != estU_ ? withAttr( root, "est_tokens", std::to_string( estT ) ) : root;
        std::vector<Swap> swaps = swapsFor( st );
        std::string       out   = root;
        std::size_t       at    = rootEnd_;
        if( legendKept( swaps ) )
        {
            out += legendFor( st, swaps, over );
            at = legendEnd_;
        }
        for( const Swap& s : swaps )
        {
            out.append( answer_.substr( at, s.at - at ) );
            out += s.xml;
            at = s.end;
        }
        out.append( answer_.substr( at ) );
        return out;
    }

private:
    struct Swap
    {
        std::size_t at, end;
        std::string xml;
    };
    static bool isSigRow( std::string_view name ) noexcept { return name == "d" || name == "t"; }   // a row, or the pointer a demote put in its place
    // Each <sigs> row's place in the cut order (rows:N cuts places 0..N-1): the worst rank first — a row with no r= before every
    // ranked one, then r= from the highest — so the kept rows are always the best-ranked ones (ranks 1..4 ship), in U's order.
    // U's document order is not rank order when the head round-robin interleaves files (forbodyslotcheck E2h/E3h).
    std::vector<std::size_t> rowCutOrder() const
    {
        std::vector<std::pair<std::size_t, std::size_t>> byRank;   // (rank, document index); no r= = the worst rank
        for( const Child& c : sigs_.kids )
        {
            if( isSigRow( c.name ) )
            {
                const std::size_t r = attrNumber( answer_.substr( c.at, tagSpan( answer_, c.at ).end - c.at ), "r" );
                byRank.emplace_back( r == 0 ? SIZE_MAX : r, byRank.size() );
            }
        }
        std::sort( byRank.begin(), byRank.end(), []( const auto& a, const auto& b ) { return a.first != b.first ? a.first > b.first : a.second > b.second; } );
        std::vector<std::size_t> pos( byRank.size() );
        for( std::size_t k = 0; k < byRank.size(); ++k )
        {
            pos[byRank[k].second] = k;
        }
        return pos;
    }
    // Each <sigs> row's place in the docs:N order (the rows that print a <doc>, in the cut order; SIZE_MAX: none to cut).
    std::vector<std::size_t> docCutOrder()
    {
        std::vector<std::size_t> byCut( sigRows_, SIZE_MAX ), pos( sigRows_, SIZE_MAX );
        std::size_t              seen = 0;
        for( const Child& c : sigs_.kids )
        {
            if( isSigRow( c.name ) )
            {
                const bool doc = c.name == "d" && answer_.substr( c.at, c.end - c.at ).find( "<doc>" ) != std::string_view::npos;
                byCut[rowCutPos_[seen]] = doc ? seen : SIZE_MAX;
                ++seen;
            }
        }
        for( const std::size_t row : byCut )
        {
            if( row != SIZE_MAX )
            {
                pos[row] = docRows_++;
            }
        }
        return pos;
    }
    // the row's <doc>…</doc> child removed (the row's attributes and its other children kept)
    // the row's own <doc> child element (its body text is plain text, so the child walk never meets a "<doc>" inside it)
    static void cutRowDoc( std::string& piece )
    {
        std::size_t closeEnd = 0;
        for( const Child& c : childrenOf( piece, 0, closeEnd ) )
        {
            if( c.name == "doc" )
            {
                piece.erase( c.at, c.end - c.at );
                return;
            }
        }
    }

    std::string withNext( std::string open ) const { return nextVal_.empty() ? std::move( open ) : withAttr( open, "next", nextVal_ ); }

    // U's own <sigs next=> when it is the signatures-only re-call (it serves every row unshrunk: the call without the budget would
    // serve U's head, itself shrunk past its target — forrankordercheck (9)); else the call without the budget
    std::string sigsWithNext( std::string open ) const
    {
        return attrOf( open, "next" ).find( "--signatures-only" ) != std::string_view::npos ? open : withNext( std::move( open ) );
    }
    std::string sigsOpen( const ShedState& st ) const
    {
        const std::size_t keep = sigRows_ - st.rowCut;
        std::string       out( answer_.substr( sigs_.at, sigs_.openEnd - sigs_.at ) );
        // docs_dropped= counts the shown rows that print no <doc>: the docs cut join it, the doc-less rows cut leave it (forrankordercheck (8))
        std::size_t docless = 0, docsCut = 0, seen = 0;
        for( const Child& c : sigs_.kids )
        {
            if( isSigRow( c.name ) )
            {
                const bool cut = rowCutPos_[seen] < st.rowCut;
                docless += cut && c.name == "d" && answer_.substr( c.at, c.end - c.at ).find( "<doc>" ) == std::string_view::npos ? 1 : 0;   // a pointer prints no doc either way
                docsCut += !cut && docCutPos_[seen] < st.docCut ? 1 : 0;
                ++seen;
            }
        }
        const std::size_t docsDropped = attrNumber( out, "docs_dropped" ) + docsCut - std::min( attrNumber( out, "docs_dropped" ) + docsCut, docless );
        out = docsDropped > 0 ? withAttr( out, "docs_dropped", std::to_string( docsDropped ) ) : withoutAttr( out, "docs_dropped" );
        if( st.rowCut == 0 )
        {
            return st.docCut > 0 ? sigsWithNext( std::move( out ) ) : out;
        }
        out = withAttr( out, "shown", std::to_string( keep ) );
        out = attrOf( out, "total" ).empty() ? withAttr( out, "total", std::to_string( sigRows_ ) ) : out;   // U served every row it ranked
        out = withAttr( out, "capped", "1" );
        const std::size_t past = attrNumber( out, "past_target" );   // the rows past the 7.5 KB target are the last ones: the cut ones leave it
        out = past > st.rowCut ? withAttr( out, "past_target", std::to_string( past - st.rowCut ) ) : withoutAttr( out, "past_target" );
        out = attrNumber( out, "files_first" ) > keep ? withAttr( out, "files_first", std::to_string( keep ) ) : out;
        // lane DA1: docs_after_code= reads "N doc rows of the SHOWN set moved": the moved doc rows hold the worst r= the reorder
        // handed out, so rows:N cuts them first — count the ones still shown (absent at 0, its reading with it: docsClauseShed)
        const std::size_t docsMoved = keptMovedDocs( st );
        out = docsMoved > 0 ? withAttr( out, "docs_after_code", std::to_string( docsMoved ) ) : withoutAttr( out, "docs_after_code" );
        return sigsWithNext( std::move( out ) );   // the r=1 row keeps its own --expand next=; the block's names the shed rows' call
    }
    std::string sigsXml( const ShedState& st ) const
    {
        std::string       out  = sigsOpen( st );
        std::size_t       at   = sigs_.openEnd, seen = 0;
        for( const Child& c : sigs_.kids )
        {
            out.append( answer_.substr( at, c.at - at ) );
            at = c.end;
            const bool        row = isSigRow( c.name );
            const std::size_t idx = row ? seen++ : 0;
            if( row && rowCutPos_[idx] < st.rowCut )
            {
                continue;
            }
            std::string piece( answer_.substr( c.at, c.end - c.at ) );
            if( row && st.attrs )
            {
                shedRowAttrs( piece, kForPageShedRungMetrics );
            }
            if( row && docCutPos_[idx] < st.docCut )
            {
                cutRowDoc( piece );
            }
            out += piece;
        }
        out.append( answer_.substr( at, sigs_.end - at ) );
        return out;
    }
    std::string tailOpen( std::string_view open, std::size_t tailCut ) const
    {
        std::string o = withAttr( withAttr( open, "shown", std::to_string( tailRows_ - tailCut ) ), "capped", "1" );
        // p_only= counts the p=-only rows, which are the LAST rows: the cut ones leave the count
        std::size_t pOnlyCut = 0, seen = 0;
        for( const Child& c : tail_.kids )
        {
            pOnlyCut += c.name == "t" && seen++ >= tailRows_ - tailCut && attrOf( answer_.substr( c.at, c.end - c.at ), "sym" ).empty() ? 1 : 0;
        }
        const std::size_t pOnly = attrNumber( o, "p_only" );
        o = pOnly == 0 ? o : pOnly > pOnlyCut ? withAttr( o, "p_only", std::to_string( pOnly - pOnlyCut ) ) : withoutAttr( o, "p_only" );
        // U's tail continues on the --for file page (FOLD C: from its first unprinted row, --offset=K): the cut rows sit before
        // K, so the page from its first row covers them (fordisclosurecheck #1c); a tail with no page call takes the block's
        const std::string_view uNext = attrOf( open, "next" );
        if( uNext.find( " --limit=" ) == std::string_view::npos )
        {
            return withNext( std::move( o ) );
        }
        std::string       page( uNext );
        const std::size_t offAt = page.find( " --offset=" );
        if( offAt != std::string::npos )
        {
            const std::size_t offEnd = page.find( ' ', offAt + 1 );
            page.erase( offAt, ( offEnd == std::string::npos ? page.size() : offEnd ) - offAt );
        }
        return withAttr( o, "next", page );
    }
    std::string tailXml( const ShedState& st ) const
    {
        return keepRows( answer_, tail_, "t", tailRows_ - st.tailCut, [ & ]( std::string_view open ) { return tailOpen( open, st.tailCut ); },
                         []( std::string_view r ) { return std::string( r ); } );
    }
    std::string hopsXml( const ShedState& st ) const
    {
        const std::size_t keep = hopRows_ - st.hopCut;
        const auto        open = [ & ]( std::string_view tag )
        {
            const std::size_t shown = attrNumber( tag, "shown" );
            return withNext( withAttr( withAttr( tag, "shown", std::to_string( shown - std::min( shown, st.hopCut ) ) ), "capped", "1" ) );
        };
        std::string xml = keepRows( answer_, hops_, "h", keep, open, []( std::string_view r ) { return std::string( r ); } );
        constexpr std::string_view kEmptyClose = "></hops>";
        if( keep == 0 && xml.ends_with( kEmptyClose ) )   // nothing left inside: the counted marker, self-closed
        {
            xml.resize( xml.size() - kEmptyClose.size() );
            xml += "/>";
        }
        return xml;
    }
    std::string detailXml( const ShedState& st ) const
    {
        const auto open = [ & ]( std::string_view tag )
        {
            const std::size_t shown = attrNumber( tag, "shown" );
            return withNext( withAttr( withAttr( tag, "shown", std::to_string( shown - std::min( shown, st.detailCut ) ) ), "capped", "1" ) );
        };
        return keepRows( answer_, detail_, "b", detailRows_ - st.detailCut, open, []( std::string_view r ) { return std::string( r ); } );
    }

    // the state's price: U's ledger less each shed unit's own bytes at its own rate, plus `disclosureMarkup` bytes
    std::size_t estOf( const ShedState& st, std::ptrdiff_t disclosureMarkup ) const
    {
        const auto     delta  = [ & ]( const Section& sec, const std::string& xml ) { return std::ptrdiff_t( xml.size() ) - std::ptrdiff_t( sec.end - sec.at ); };
        std::ptrdiff_t markup = std::ptrdiff_t( ledger_.markupBytes ) + disclosureMarkup;
        std::size_t    body   = ledger_.bodyTokens;
        markup += sigs_.found() && ( st.attrs || st.docCut > 0 || st.rowCut > 0 ) ? delta( sigs_, sigsXml( st ) ) : 0;
        markup += st.tailCut > 0 ? delta( tail_, tailXml( st ) ) : 0;
        markup += st.hopCut > 0 ? delta( hops_, hopsXml( st ) ) : 0;
        markup -= st.fold ? std::ptrdiff_t( ledger_.foldMarkupBytes ) : 0;
        body -= st.fold ? std::min( body, ledger_.foldBodyTokens ) : 0;
        if( st.detailCut > 0 )
        {
            const std::size_t left = ledger_.detailXmlBytes - ( detail_.end - detail_.at ) + detailXml( st ).size();
            body = body - std::min( body, ledger_.detailTokens ) + tokensForEmittedBytes( left, kBytesPerTokenBody );
        }
        std::size_t est = 0;
        (void)pricedRootAttrTokens( std::size_t( std::max<std::ptrdiff_t>( markup, 0 ) ), kBytesPerTokenDefault, body, &est );
        return est;
    }

    // ── the disclosure of a state: shed=, the root's budget attributes, the bodies= count, dropped_positive=, the clauses. It is
    // priced like every other markup byte (est_tokens prices the document it heads), so each state's price includes its own.
    std::string shedOf( const ShedState& st ) const
    {
        std::string shed = trusted_ ? std::string() : std::string( "unpriced" );
        const auto  note = [ & ]( bool cut, std::string_view unit, std::size_t n )
        {
            shed += !cut ? std::string() : ( shed.empty() ? "" : "," ) + std::string( unit ) + ( n > 0 ? ":" + std::to_string( n ) : std::string() );
        };
        note( ask_.heldPass, "held", 0 );
        note( st.attrs, "attrs", 0 );
        note( st.tailCut > 0, "tail", st.tailCut );
        note( st.hopCut > 0, "hops", st.hopCut );
        note( st.fold, "fold", 0 );
        note( st.detailCut > 0, "bodies", st.detailCut );
        note( st.docCut > 0, "docs", st.docCut );
        note( st.rowCut > 0, "rows", st.rowCut );
        return shed;
    }
    // the shed units this answer took, each with its definition, in the shed order (" none" when only the price was disclosed)
    std::string unitsLegendOf( const ShedState& st, std::string_view against ) const
    {
        std::string out;
        const auto  unit = [ & ]( bool cut, std::string_view text )
        {
            if( cut )
            {
                out += out.empty() ? " " : ", ";
                out += text;
            }
        };
        unit( !trusted_, "unpriced (the price could not be reproduced, so nothing was shed)" );
        unit( ask_.heldPass, "held (the blocks outside est_tokens: a held=budget stub with next=, what they print comes off the " + std::string( against ) + ")" );
        unit( st.attrs, "attrs (the sigs rows' cx= ccx= layer= next=)" );
        unit( st.tailCut > 0, "tail:N (the last N tail rows)" );
        unit( st.hopCut > 0, "hops:N (the last N hops rows)" );
        unit( st.fold, "fold (the fold bodies)" );
        unit( st.detailCut > 0, "bodies:N (the last N bodies; root bodies= counts the rest)" );
        unit( st.docCut > 0, "docs:N (the docs of the N worst-ranked sigs rows with one; docs_dropped= counts shown rows without)" );
        unit( st.rowCut > 0, "rows:N (the N worst-ranked sigs rows; ranks 1..4 always ship)" );
        return out.empty() ? std::string( " none" ) : out;
    }
    // the cut sigs rows that hold a rank are ranked candidates the ceiling removed: dropped_positive= (A2) counts them
    std::size_t cutRankedOf( const ShedState& st ) const
    {
        std::size_t cutRanked = 0, seen = 0;
        for( const Child& c : sigs_.kids )
        {
            const bool cut = isSigRow( c.name ) && rowCutPos_[seen++] < st.rowCut;
            cutRanked += cut && !attrOf( answer_.substr( c.at, tagSpan( answer_, c.at ).end - c.at ), "r" ).empty() ? 1 : 0;
        }
        return cutRanked;
    }
    bool overCeiling( const ShedState& st ) const
    {
        // the whole charge: what the held re-render's blocks still print rides on top of the answer's price, as walk()'s target
        // subtracts it (CodeRabbit #665: the verdict compared the answer alone, so an answer the held blocks put over said fits)
        const std::size_t heldOff = ask_.heldPass ? heldTokens_ : 0;
        return trusted_ && ask_.ceilingTokens > 0 && priceOf( st, false ) + heldOff > ask_.ceilingTokens && attrOf( rootTag_, "over_ceiling" ).empty();
    }
    // the auto bundle's (or the owner body slot's) count follows its <bodies>; the honest zero says reason="budget" (forautobodycheck)
    std::string withBodiesLeft( std::string root, const ShedState& st ) const
    {
        if( st.detailCut == 0 || !ledger_.autoBodies || attrOf( root, "bodies" ).empty() )
        {
            return root;
        }
        const std::size_t left = detailRows_ - st.detailCut;
        root = withAttr( root, "bodies", std::to_string( left ) );
        if( left == 0 && attrOf( root, "reason" ).empty() )
        {
            const auto [ at, end ] = attrSpan( root, "bodies" );
            root.insert( end, " reason=\"budget\"" );
        }
        else if( left == 0 && attrOf( root, "reason" ) == "owner" )
        {
            root = withAttr( root, "reason", "budget" );   // the compact route's owner body (for-body-slot) went: bodies=0 reason=budget, as its skip says
        }
        return root;
    }
    // the root with the state's disclosure, est_tokens= still U's (render replaces it with the state's price)
    std::string rootFor( const ShedState& st, bool over ) const
    {
        const std::string shed       = shedOf( st );
        std::string       disclosure = ask_.targetTokens > 0 ? " budget_tokens=\"" + std::to_string( ask_.targetTokens ) + "\"" : std::string();
        disclosure += ask_.ceilingTokens > 0 ? " max_tokens=\"" + std::to_string( ask_.ceilingTokens ) + "\"" : std::string();
        disclosure += shed.empty() ? std::string() : " shed=\"" + shed + "\"";
        disclosure += over ? " over_ceiling=\"1\"" : "";
        std::string       root  = withBodiesLeft( std::string( rootTag_ ), st );
        const std::size_t estAt = root.find( " est_tokens=\"" );
        root.insert( estAt != std::string::npos ? estAt : root.size() - 1, disclosure );
        return root;
    }
    // the clause(s) at the end of the root's first legend comment (U names no dropped_positive=: the bare attribute joins them)
    std::string clausesFor( const ShedState& st, bool over ) const
    {
        const std::size_t cutRanked = cutRankedOf( st );
        std::string clauses = cutRanked > 0 && droppedValAt_ == 0 ? " dropped_positive=\"" + std::to_string( cutRanked ) + "\"" : std::string();
        const std::string units = unitsLegendOf( st, ask_.targetTokens > 0 ? "target" : "ceiling" );
        clauses += ask_.targetTokens > 0 ? std::string( kForBudgetTargetLegendHead ) + units + std::string( kForBudgetTargetLegendTail ) : std::string();
        clauses += ask_.ceilingTokens == 0  ? std::string()
                 : ask_.targetTokens > 0    ? std::string( kForBudgetCeilingBesideTarget )
                                            : std::string( kForBudgetCeilingLegendHead ) + units + std::string( kForBudgetCeilingLegendTail );
        clauses += over ? overCeilingLegendFor( /*namesBudgetTokens=*/false, /*namesMaxTokens=*/true ) : std::string_view();   // the family's one sentence (serialize.h): only max_tokens= is a ceiling here
        return clauses;
    }
    std::string droppedValueFor( const ShedState& st ) const { return std::to_string( droppedHad_ + cutRankedOf( st ) ); }
    std::ptrdiff_t disclosureBytes( const ShedState& st, bool over ) const
    {
        std::ptrdiff_t bytes = std::ptrdiff_t( rootFor( st, over ).size() ) - std::ptrdiff_t( rootTag_.size() );
        bytes += legendEnd_ != std::string_view::npos ? std::ptrdiff_t( clausesFor( st, over ).size() ) : 0;
        bytes -= splitClauseLen_ > 0 && splitReadingShed( swapsFor( st ) ) ? std::ptrdiff_t( splitClauseLen_ ) : 0;
        bytes -= docsClauseErased( st ) ? std::ptrdiff_t( dacClauseLen_ ) : 0;
        bytes += droppedValAt_ != 0 && st.rowCut > 0 ? std::ptrdiff_t( droppedValueFor( st ).size() ) - std::ptrdiff_t( droppedValEnd_ - droppedValAt_ ) : 0;
        return bytes;
    }
    std::size_t priceOf( const ShedState& st, bool over ) const { return estOf( st, disclosureBytes( st, over ) ); }
    // lane DA1: the bytes the docs_after_code= recount takes off a state (the attribute's value or the attribute, and its reading).
    // The WALK prices them back in, so the shed chooses exactly the rows it chose before the recount existed (selection is not this
    // lane's to move); render() prices the document it prints, so est_tokens= stays that document's price.
    std::ptrdiff_t docsRecountBytes( const ShedState& st ) const
    {
        if( dacU_ == 0 || st.rowCut == 0 )
        {
            return 0;
        }
        const auto           attrBytes = []( std::size_t n ) { return n == 0 ? std::ptrdiff_t( 0 ) : std::ssize( std::string_view( " docs_after_code=\"\"" ) ) + std::ssize( std::to_string( n ) ); };
        const std::ptrdiff_t clause    = docsClauseErased( st ) ? std::ptrdiff_t( dacClauseLen_ ) : 0;
        return attrBytes( dacU_ ) - attrBytes( keptMovedDocs( st ) ) + clause;
    }
    std::size_t walkPriceOf( const ShedState& st ) const { return estOf( st, disclosureBytes( st, false ) + docsRecountBytes( st ) ); }
    // the price the token target cuts rows against: the ceiling's own disclosure (max_tokens= and its clause, beside a target) is
    // not the target's to pay, so a ceiling never moves a ranked row (formaxtokenscheck (E): the same rows with or without it)
    std::size_t rowsPriceOf( const ShedState& st ) const
    {
        const bool        both    = ask_.ceilingTokens > 0 && ask_.targetTokens > 0;
        const std::size_t ceiling = !both ? 0
                                  : std::string_view( " max_tokens=\"\"" ).size() + std::to_string( ask_.ceilingTokens ).size()
                                        + ( legendEnd_ != std::string_view::npos ? kForBudgetCeilingBesideTarget.size() : 0 );
        return estOf( st, disclosureBytes( st, false ) + docsRecountBytes( st ) - std::ptrdiff_t( ceiling ) );
    }

    std::vector<Swap> swapsFor( const ShedState& st ) const
    {
        std::vector<Swap> swaps;
        const auto        add = [ & ]( bool cut, const Section& sec, auto&& xml )
        {
            if( cut )
            {
                swaps.push_back( { sec.at, sec.end, xml() } );
            }
        };
        add( sigs_.found() && ( st.attrs || st.docCut > 0 || st.rowCut > 0 ), sigs_, [ & ] { return sigsXml( st ); } );
        add( st.tailCut > 0, tail_, [ & ] { return tailXml( st ); } );
        add( st.hopCut > 0, hops_, [ & ] { return hopsXml( st ); } );
        add( st.fold, fold_, [] { return std::string(); } );
        add( st.detailCut > 0, detail_, [ & ] { return detailXml( st ); } );
        if( droppedValAt_ != 0 && st.rowCut > 0 )
        {
            swaps.push_back( { droppedValAt_, droppedValEnd_, droppedValueFor( st ) } );
        }
        if( docsClauseShed( st ) && !docsClauseInLegend() )   // the reading rides the comment before <sigs> (sigsCeilingNote's splice)
        {
            swaps.push_back( { dacClauseAt_, dacClauseAt_ + dacClauseLen_, std::string() } );
        }
        std::sort( swaps.begin(), swaps.end(), []( const Swap& a, const Swap& b ) { return a.at < b.at; } );
        return swaps;
    }

    // U's first legend comment as the state prints it: the present-only readings the shed leaves without their rows erased
    // (last-first, so each offset still holds), the state's clauses appended
    std::string legendFor( const ShedState& st, const std::vector<Swap>& swaps, bool over ) const
    {
        std::string legend( answer_.substr( rootEnd_, legendEnd_ - rootEnd_ ) );
        std::vector<std::pair<std::size_t, std::size_t>> erase;   // (offset in U, length)
        if( splitReadingShed( swaps ) )
        {
            erase.emplace_back( splitClauseAt_, splitClauseLen_ );
        }
        if( docsClauseShed( st ) && docsClauseInLegend() )
        {
            erase.emplace_back( dacClauseAt_, dacClauseLen_ );
        }
        std::sort( erase.begin(), erase.end(), []( const auto& a, const auto& b ) { return a.first > b.first; } );
        for( const auto& [ at, len ] : erase )
        {
            legend.erase( at - rootEnd_, len );
        }
        return legend + clausesFor( st, over );
    }

    // ── docs_after_code= over the kept rows (lane DA1) ───────────────────────────────────────────────────────────────────────
    // U's <sigs docs_after_code="M"> counts the doc rows the reorder moved; the ledger names them by the r= they are shown with
    // (serialize.h reorderDocsAfterCode). The count and its reading (kForDocsAfterCodeNote, present-only: it rides the comment
    // spliced before <sigs>, or the first legend) are U's until rows:N cuts one of them.
    void findDocsAfterCode()
    {
        dacU_ = sigs_.found() ? attrNumber( answer_.substr( sigs_.at, sigs_.openEnd - sigs_.at ), "docs_after_code" ) : 0;
        movedDocRow_.assign( sigRows_, 0 );
        if( dacU_ == 0 )
        {
            return;
        }
        std::size_t seen = 0, flagged = 0;
        for( const Child& c : sigs_.kids )
        {
            if( isSigRow( c.name ) )
            {
                const std::size_t r = attrNumber( answer_.substr( c.at, tagSpan( answer_, c.at ).end - c.at ), "r" );
                movedDocRow_[seen] = r > 0 && std::ranges::binary_search( ledger_.docsAfterCodeRanks, std::uint32_t( r ) ) ? 1 : 0;
                flagged += movedDocRow_[seen];
                ++seen;
            }
        }
        // the ledger is the render's own: every moved rank names one printed row (a priced U only — an unpriced one sheds nothing)
        EXPECTS( !trusted_ || flagged == dacU_, "ForBudgetFitter: docs_after_code= does not match the moved ranks the render recorded" );
        const std::string_view head = answer_.substr( rootEnd_, sigs_.at - rootEnd_ );
        if( const std::size_t at = head.rfind( kForDocsAfterCodeNote ); at != std::string_view::npos )
        {
            dacClauseAt_  = rootEnd_ + at;
            dacClauseLen_ = kForDocsAfterCodeNote.size();
        }
    }
    std::size_t keptMovedDocs( const ShedState& st ) const
    {
        std::size_t kept = 0;
        for( std::size_t i = 0; i < movedDocRow_.size(); ++i )
        {
            kept += movedDocRow_[i] != 0 && rowCutPos_[i] >= st.rowCut ? 1 : 0;
        }
        return kept;
    }
    bool docsClauseShed( const ShedState& st ) const { return dacClauseLen_ > 0 && st.rowCut > 0 && keptMovedDocs( st ) == 0; }
    bool docsClauseInLegend() const noexcept { return legendEnd_ != std::string_view::npos && dacClauseAt_ < legendEnd_; }
    // the reading leaves the printed document: by its swap before <sigs>, or by render()'s legend edit when the legend is kept
    bool docsClauseErased( const ShedState& st ) const { return docsClauseShed( st ) && ( !docsClauseInLegend() || legendKept( swapsFor( st ) ) ); }
    bool legendKept( const std::vector<Swap>& swaps ) const noexcept
    {
        return legendEnd_ != std::string_view::npos && ( swaps.empty() || legendEnd_ < swaps.front().at );
    }

    // The split reading (attrib-multidef Q1, kForCompactSplitClause / kForSplitClause) is present-only: U's legend carries it
    // beside its prov="split" rows. A shed that removes every one of them (they ride <hops>, <tail>, <fold> and <bodies>) takes
    // the reading out of the legend too (attribmultidefcheck [S2]). Only when U printed such a row: a U whose legend defines it
    // on the over-approximated bit with no row keeps U's legend, as the unbudgeted answer does.
    static std::size_t splitRowsIn( std::string_view xml ) noexcept
    {
        constexpr std::string_view kMark = "prov=\"split\"";
        std::size_t                n     = 0;
        for( std::size_t at = xml.find( kMark ); at != std::string_view::npos; at = xml.find( kMark, at + kMark.size() ) )
        {
            ++n;
        }
        return n;
    }
    void findSplitReading()
    {
        if( legendEnd_ == std::string_view::npos )
        {
            return;
        }
        const std::string_view legend = answer_.substr( rootEnd_, legendEnd_ - rootEnd_ );
        for( const std::string_view clause : { kForCompactSplitClause, kForSplitClause } )
        {
            if( const std::size_t at = legend.find( clause ); at != std::string_view::npos )
            {
                splitClauseAt_  = rootEnd_ + at;
                splitClauseLen_ = clause.size();
                break;
            }
        }
        splitRowsU_ = splitClauseLen_ > 0 ? splitRowsIn( answer_.substr( legendEnd_ ) ) : 0;
    }
    // the state's swaps leave no prov="split" row of U's (render keeps the legend only when it precedes every swap)
    bool splitReadingShed( const std::vector<Swap>& swaps ) const
    {
        if( splitClauseLen_ == 0 || splitRowsU_ == 0 || ( !swaps.empty() && swaps.front().at < legendEnd_ ) )
        {
            return false;
        }
        std::size_t left = splitRowsU_;
        for( const Swap& s : swaps )
        {
            left = left - std::min( left, splitRowsIn( answer_.substr( s.at, s.end - s.at ) ) ) + splitRowsIn( s.xml );
        }
        return left == 0;
    }

    std::string_view       answer_;
    const ForBudgetAsk&    ask_;
    const ForAnswerLedger& ledger_;
    std::vector<Child>     top_;
    std::size_t            rootClose_ = 0, rootEnd_ = 0, target_ = 0, estU_ = 0, legendEnd_ = std::string_view::npos;
    std::size_t            heldTokens_ = 0, walkTarget_ = 0, rowTarget_ = 0;   // kForHeldBlocks' price; the targets the units / the rows are walked against
    std::string_view       rootTag_;
    std::string            nextVal_;
    bool                   parsed_ = false, trusted_ = false, foldShed_ = false;
    Section                sigs_, tail_, hops_, fold_, detail_;
    std::vector<std::size_t> rowCutPos_;   // per <sigs> row in document order: its place in the cut order (rowCutOrder)
    std::vector<std::size_t> docCutPos_;   // per <sigs> row in document order: its place in the docs:N order (docCutOrder)
    std::size_t            docRows_ = 0;   // the <sigs> rows that print a <doc>
    std::size_t            sigRows_ = 0, tailRows_ = 0, hopRows_ = 0, detailRows_ = 0;
    std::size_t            droppedValAt_ = 0, droppedValEnd_ = 0, droppedHad_ = 0;   // U's own dropped_positive= value (0: none)
    std::size_t            splitClauseAt_ = 0, splitClauseLen_ = 0, splitRowsU_ = 0;   // U's split reading in its legend, and its prov="split" rows
    std::size_t            dacU_ = 0, dacClauseAt_ = 0, dacClauseLen_ = 0;   // U's docs_after_code= and its reading's place (lane DA1)
    std::vector<char>      movedDocRow_;   // per <sigs> row in document order: a doc row the reorder moved (its r= is in the ledger's)
};
}   // namespace budgetfit_detail

// The price of a --for answer's held blocks (kForHeldBlocks children of its <ctx> root, each with its legend), as the fit charges
// them: est_tokens= plus this is what a budget must hold (ForBudgetFitter::fitsWhole). The MCP `for` holds <manifest_rows> from it
// (mcpverbs.h forTaskText). 0 when no root closes.
inline std::size_t forHeldBlocksPrice( std::string_view answer )
{
    const std::size_t rootAt = answer.find( "<ctx " );
    std::size_t       close  = std::string_view::npos;
    const std::vector<budgetfit_detail::Child> top = rootAt == std::string_view::npos ? std::vector<budgetfit_detail::Child>{} : budgetfit_detail::childrenOf( answer, rootAt, close );
    return close == std::string_view::npos ? 0 : budgetfit_detail::heldBlocksPrice( answer, top );
}

// What fitting U to a budget came to: the answer to print, or the call for the re-render that holds kForHeldBlocks.
struct ForBudgetFitResult
{
    enum class Verdict : std::uint8_t
    {
        NoRoot,       // no <ctx> root to edit: print U as it is
        Whole,        // B >= est(U) + the held blocks' price: xml is U byte for byte
        HoldBlocks,   // U prints blocks a budget holds and does not fit whole: re-render with Config::forHoldBudget, fit that (heldPass)
        Shed,         // xml is U with the shortest fitting prefix of the shed sequence removed, disclosed
    };
    Verdict     verdict = Verdict::NoRoot;
    std::string xml;
};

// U fitted to `ask` (see the header). `answer` is the whole unbudgeted document (the held re-render under ask.heldPass).
inline ForBudgetFitResult fitForAnswerToBudget( std::string_view answer, const ForBudgetAsk& ask, const ForAnswerLedger& ledger )
{
    using Verdict = ForBudgetFitResult::Verdict;
    const budgetfit_detail::ForBudgetFitter fit( answer, ask, ledger );
    if( !fit.parsed() )
    {
        return { Verdict::NoRoot, {} };
    }
    if( !ask.heldPass && fit.fitsWhole() )
    {
        return { Verdict::Whole, std::string( answer ) };   // the answer asked without the budget, byte for byte
    }
    if( !ask.heldPass && fit.holdsBlocks() )
    {
        return { Verdict::HoldBlocks, {} };
    }
    return { Verdict::Shed, fit.render( fit.walk() ) };
}
}   // namespace rw
