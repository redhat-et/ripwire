#pragma once

// skilleval.h — deterministic, LLM-free skill-ROUTING eval (--eval-skills=FILE): given a realistic
// developer/agent prompt, does the right skill under ROOT (a skills/ directory, one SKILL.md per subdir)
// get selected — and does every skill stay quiet on prompts that belong to none of them? The production
// selector is an LLM reading each skill's frontmatter `description:`; that cannot be scored
// deterministically, so this harness scores the ROUTING SURFACE itself — how discriminable the
// descriptions are under a family of deterministic selectors — against a hand-labelled corpus
// (test/skillevalfix/prompts.tsv; provenance per row).
//
// Metric posture (the measurement-design decisions, each argued in the research doc):
//   * permitted SETS, not single labels — several moments legitimately map to 2 skills
//     (change-check+quality-bar at "am I ready to push"; fresh-eyes+orient at "unfamiliar module").
//     hit@1 = the top-1 ranked skill is IN the row's permitted set (an agent loads ONE skill; the
//     question is whether the one loaded is acceptable, not whether a unique answer was divined).
//   * NEGATIVES are first-class: rows labelled `none` (a CSS question, a git-rebase question) measure
//     "does the wrong skill stay quiet". Threshold-free separation = AUC( top-1 score | positive vs
//     negative rows ): 0.5 = the scores carry no fire/abstain signal, < 0.5 = INVERTED (the negative
//     class scores HIGHER — the exact failure mode the --eval-stray round caught three times). The
//     fire/abstain accuracy at the single best threshold is also printed but is an ORACLE upper bound
//     (the threshold is chosen on the same labels it is scored on) — never quote it as an expectation.
//   * the TRIVIAL baseline (raw keyword-overlap-with-the-description) is always measured and printed —
//     an arm that cannot beat it is measuring nothing.
//   * ripwire-router is NEVER a candidate: it is the fallback moment→skill map, not a destination, and
//     it quotes every trigger phrase — a lexical keyword magnet. Its magnet-ness is measured separately
//     (the router-magnet diagnostic row) instead of letting it silently eat every top-1.
// Deterministic: no wall clock, no sampling, fixed iteration order, name-ascending tie-breaks; two runs
// are byte-identical. Plain-text report like --eval/--eval-retrieval (not XML, so G4 does not apply).

#include "model.h"
#include "graph.h"
#include "lexical.h"      // subtokens() / chooseForRanker / lexicalScores* — the shipping --for ranker
#include "eval.h"         // maxPoolToFiles — the file-pooling convention shared with --eval-mined
#include "search.h"       // normSet — sorted-unique for the query token set
#include "infra/Diagnostics.h"   // VERIFY

#include <algorithm>
#include <cmath>
#include <cstdint>
#include <cstdio>
#include <filesystem>
#include <fstream>
#include <limits>
#include <sstream>
#include <string>
#include <string_view>
#include <vector>

namespace rw
{
namespace skilleval
{

// ── the routing surface: one skill = one SKILL.md, identified by its directory name ─────────────────────

struct SkillDoc
{
    std::string dirName;    // "ripwire-orient" — the corpus's label vocabulary
    std::string descText;   // the frontmatter `description:` block (what an LLM selector actually reads)
    std::string bodyText;   // everything after the closing frontmatter fence (for the bm25-full arm)
};

inline std::string readWholeFileText( const std::filesystem::path& p )
{
    std::ifstream in( p, std::ios::binary );
    if( !in )
    {
        return {};
    }
    std::ostringstream ss;
    ss << in.rdbuf();
    return ss.str();
}

// split text into lines (no trailing-\r; a final empty line is dropped) — mirrors skillscan.h's splitter.
inline std::vector<std::string> splitTextLines( const std::string& text )
{
    std::vector<std::string> lines;
    std::size_t              start = 0;
    while( start <= text.size() )
    {
        const std::size_t nl  = text.find( '\n', start );
        const std::size_t end = ( nl == std::string::npos ) ? text.size() : nl;
        std::string       line = text.substr( start, end - start );
        if( !line.empty() && line.back() == '\r' )
        {
            line.pop_back();
        }
        lines.push_back( std::move( line ) );
        if( nl == std::string::npos )
        {
            break;
        }
        start = nl + 1;
    }
    if( !lines.empty() && lines.back().empty() )
    {
        lines.pop_back();
    }
    return lines;
}

// parse ONE SKILL.md into {description, body}. The frontmatter is the block between the first two `---`
// lines; `description:` is a YAML block scalar (`description: >` + indented continuation lines) or a
// single inline value. Continuation ends at the next unindented `key:` line or the closing `---`.
inline void parseSkillMd( const std::string& text, std::string& descOut, std::string& bodyOut )
{
    const std::vector<std::string> lines = splitTextLines( text );

    // locate the frontmatter fence pair
    int frontEndLineIndex = 0;                       // index of the closing `---` line (0 = no frontmatter)
    if( !lines.empty() && lines[0] == "---" )
    {
        for( int i = 1; i < int( lines.size() ); ++i )
        {
            if( lines[i] == "---" ) { frontEndLineIndex = i; break; }
        }
    }

    // description: value + indented continuations
    bool inDesc = false;
    for( int i = 1; i < frontEndLineIndex; ++i )
    {
        const std::string& line = lines[i];
        if( !inDesc )
        {
            if( line.rfind( "description:", 0 ) != 0 )
            {
                continue;
            }
            std::string_view rest = std::string_view( line ).substr( 12 );
            while( !rest.empty() && ( rest.front() == ' ' || rest.front() == '\t' ) )
            {
                rest.remove_prefix( 1 );
            }
            if( rest != ">" && rest != ">-" && rest != "|" && rest != "|-" && !rest.empty() )
            { descOut.append( rest ); descOut.push_back( ' ' ); }
            inDesc = true;
            continue;
        }
        const bool isContinuation = !line.empty() && ( line.front() == ' ' || line.front() == '\t' );
        if( !isContinuation )
        {
            break; // next frontmatter key ends the block scalar
        }
        std::string_view body = line;
        while( !body.empty() && ( body.front() == ' ' || body.front() == '\t' ) )
        {
            body.remove_prefix( 1 );
        }
        descOut.append( body );
        descOut.push_back( ' ' );
    }

    // body = everything after the closing fence
    for( int i = frontEndLineIndex + 1; i < int( lines.size() ); ++i )
    { bodyOut.append( lines[i] ); bodyOut.push_back( '\n' ); }
}

struct SkillSet
{
    std::vector<SkillDoc> candidates;   // name-sorted, EXCLUDING ripwire-router
    SkillDoc              router;       // kept out-of-band for the magnet diagnostic
    bool                  hasRouter = false;
};

inline SkillSet discoverSkills( const std::string& root )
{
    SkillSet        set;
    std::error_code ec;
    for( const std::filesystem::directory_entry& entry : std::filesystem::directory_iterator( root, ec ) )
    {
        if( ec )
        {
            break;
        }
        if( !entry.is_directory() )
        {
            continue;
        }
        const std::filesystem::path md = entry.path() / "SKILL.md";
        if( !std::filesystem::exists( md ) )
        {
            continue;
        }

        SkillDoc doc;
        doc.dirName = entry.path().filename().string();
        parseSkillMd( readWholeFileText( md ), doc.descText, doc.bodyText );

        if( doc.dirName == "ripwire-router" ) { set.router = std::move( doc ); set.hasRouter = true; }
        else
        {
            set.candidates.push_back( std::move( doc ) );
        }
    }
    std::sort( set.candidates.begin(), set.candidates.end(),
               []( const SkillDoc& a, const SkillDoc& b ) { return a.dirName < b.dirName; } );
    return set;
}

// ── the labelled corpus: prompt<TAB>skill[,skill]|none<TAB>provenance<TAB>split ─────────────────────────

enum class Prov : std::uint8_t { Router, Desc, Judged, Neg };
inline constexpr const char* kProvName[] = { "router", "desc", "judged", "neg" };

// split (added round r26): test = the FROZEN held-out benchmark (never tune a skill
// description against these SAME rows and re-measure — train-on-test with extra steps); dev = rows
// meant for iterating on a description change, reported separately so the two numbers can never be
// silently conflated. A row with no 4th column defaults to Test (back-compat for ad-hoc TSVs other
// gates build on the fly) — the committed test/skillevalfix/prompts.tsv states it explicitly instead.
enum class Split : std::uint8_t { Test, Dev };
inline constexpr const char* kSplitName[] = { "test", "dev" };

struct PromptRow
{
    std::string                prompt;
    std::vector<std::uint32_t> permitted;   // candidate indices; empty ⇒ negative row (`none`)
    Prov                       prov  = Prov::Judged;
    Split                      split = Split::Test;
    int                        lineNumber = 0;
};

inline bool parseProv( std::string_view s, Prov& out )
{
    for( std::size_t p = 0; p < 4; ++p )
    {
        if( s == kProvName[p] ) { out = Prov( p ); return true; }
    }
    return false;
}

inline bool parseSplit( std::string_view s, Split& out )
{
    for( std::size_t p = 0; p < 2; ++p )
    {
        if( s == kSplitName[p] ) { out = Split( p ); return true; }
    }
    return false;
}

// parse + VALIDATE the corpus. A measurement harness must not silently drop rows (a skipped row
// fabricates the sample), so any malformed row / unknown label / label-provenance mismatch is a hard
// error: the offending line is named on stderr and the whole run refuses (exit 1 upstream).
inline bool parseCorpus( const std::string& path, const std::vector<SkillDoc>& candidates,
                         std::vector<PromptRow>& rows )
{
    std::ifstream in( path );
    if( !in ) { std::fprintf( stderr, "ripwire --eval-skills: cannot open '%s'\n", path.c_str() ); return false; }

    HashMap<std::string, std::uint32_t> indexOfSkill;
    for( std::uint32_t c = 0; c < candidates.size(); ++c )
    {
        indexOfSkill[candidates[c].dirName] = c;
    }

    bool        ok = true;
    std::string line;
    int         lineNumber = 0;
    const auto  bad = [ & ]( const char* why )
    { std::fprintf( stderr, "ripwire --eval-skills: %s:%d: %s\n", path.c_str(), lineNumber, why ); ok = false; };

    while( std::getline( in, line ) )
    {
        ++lineNumber;
        if( !line.empty() && line.back() == '\r' )
        {
            line.pop_back();
        }
        if( line.empty() || line[0] == '#' )
        {
            continue;
        }

        const std::size_t tab1 = line.find( '\t' );
        const std::size_t tab2 = ( tab1 == std::string::npos ) ? std::string::npos : line.find( '\t', tab1 + 1 );
        if( tab2 == std::string::npos ) { bad( "expected prompt<TAB>labels<TAB>provenance[<TAB>split]" ); continue; }
        // split is an OPTIONAL 4th column: absent -> Split::Test (back-compat default, see the Split
        // comment above); present -> must parse as test|dev, same fail-loud discipline as provenance.
        const std::size_t tab3 = line.find( '\t', tab2 + 1 );
        const std::size_t provEnd = ( tab3 == std::string::npos ) ? line.size() : tab3;

        PromptRow row;
        row.prompt     = line.substr( 0, tab1 );
        row.lineNumber = lineNumber;
        const std::string labels = line.substr( tab1 + 1, tab2 - tab1 - 1 );
        if( !parseProv( line.substr( tab2 + 1, provEnd - tab2 - 1 ), row.prov ) ) { bad( "unknown provenance (router|desc|judged|neg)" ); continue; }
        if( tab3 != std::string::npos && !parseSplit( line.substr( tab3 + 1 ), row.split ) )
        { bad( "unknown split (test|dev)" ); continue; }

        if( labels == "none" )
        {
            if( row.prov != Prov::Neg ) { bad( "`none` rows must carry provenance `neg`" ); continue; }
        }
        else
        {
            if( row.prov == Prov::Neg ) { bad( "provenance `neg` requires the label `none`" ); continue; }
            std::size_t from = 0;
            bool        rowOk = true;
            while( from <= labels.size() )
            {
                const std::size_t comma = labels.find( ',', from );
                const std::string one   = labels.substr( from, ( comma == std::string::npos ? labels.size() : comma ) - from );
                const auto        it    = indexOfSkill.find( one );
                if( it == indexOfSkill.end() )
                { bad( ( "unknown skill label '" + one + "' (ripwire-router is never a legal label)" ).c_str() ); rowOk = false; break; }
                row.permitted.push_back( it->second );
                if( comma == std::string::npos )
                {
                    break;
                }
                from = comma + 1;
            }
            if( !rowOk || row.permitted.empty() )
            {
                continue;
            }
        }
        rows.push_back( std::move( row ) );
    }
    return ok;
}

// ── the selector arms ────────────────────────────────────────────────────────────────────────────────────

struct TokenBag { HashMap<std::string, int> tf; int lenTokens = 0; };

struct BagStats { std::vector<TokenBag> bags; double avgLen = 0; HashMap<std::string, int> df; };

inline TokenBag bagOfText( std::string_view text )
{
    TokenBag                 bag;
    std::vector<std::string> toks;
    subtokens( text, toks );
    for( std::string& t : toks ) { ++bag.tf[ std::move( t ) ]; ++bag.lenTokens; }
    return bag;
}

inline BagStats buildBagStats( const std::vector<std::string_view>& texts )
{
    BagStats st;
    st.bags.reserve( texts.size() );
    for( const std::string_view t : texts )
    {
        st.bags.push_back( bagOfText( t ) );
    }
    for( const TokenBag& b : st.bags )
    {
        st.avgLen += double( b.lenTokens );
    }
    st.avgLen /= double( texts.empty() ? 1 : texts.size() );
    for( const TokenBag& b : st.bags )
    {
        for( const auto& [ tok, count ] : b.tf ) { (void)count; ++st.df[ tok ]; }
    }
    return st;
}

inline std::vector<std::string> uniqueQueryTokens( std::string_view prompt )
{
    std::vector<std::string> toks;
    subtokens( prompt, toks );
    normSet( toks, std::numeric_limits<std::size_t>::max() );      // search.h's sorted-unique (cap unused here)
    return toks;
}

// THE trivial baseline: fraction of the prompt's unique subtokens present anywhere in the doc's bag.
// No tf, no idf, no length normalization — deliberately the dumbest thing that could work.
inline std::vector<double> overlapArm( const std::vector<TokenBag>& bags, const std::vector<std::string>& qUnique )
{
    std::vector<double> score( bags.size(), 0.0 );
    if( qUnique.empty() )
    {
        return score;
    }
    for( std::size_t c = 0; c < bags.size(); ++c )
    {
        std::size_t hitCount = 0;
        for( const std::string& t : qUnique )
        {
            if( bags[c].tf.find( t ) != bags[c].tf.end() )
            {
                ++hitCount;
            }
        }
        score[c] = double( hitCount ) / double( qUnique.size() );
    }
    return score;
}

// BM25 (k1/b as eval.h's bm25Seeded) of the prompt's unique subtokens against each doc bag. NOT folded
// into bm25Seeded on purpose: that one scores a SEED DOC's bag doc-vs-doc over files and must exclude the
// seed (sc[seed] = -1); this one scores a free query-token list over K skill docs — forcing both through
// one shape would contort the shipped eval to save ~15 lines (a wrong abstraction beats a low dup count).
inline std::vector<double> bm25Arm( const BagStats& st, const std::vector<std::string>& qUnique )
{
    constexpr double    k1 = 1.5, b = 0.75;
    const std::size_t   docCount = st.bags.size();
    std::vector<double> score( docCount, 0.0 );
    for( std::size_t c = 0; c < docCount; ++c )
    {
        double s = 0.0;
        for( const std::string& t : qUnique )
        {
            const auto it = st.bags[c].tf.find( t );
            if( it == st.bags[c].tf.end() )
            {
                continue;
            }
            const auto   di  = st.df.find( t );
            const int    n   = ( di == st.df.end() ) ? 1 : di->second;
            const int    tf  = it->second;
            const double idf = std::log( ( double( docCount ) - n + 0.5 ) / ( n + 0.5 ) + 1.0 );
            s += idf * ( tf * ( k1 + 1.0 ) )
               / ( tf + k1 * ( 1.0 - b + b * double( st.bags[c].lenTokens ) / ( st.avgLen > 0 ? st.avgLen : 1.0 ) ) );
        }
        score[c] = s;
    }
    return score;
}

// candidate ranking: score desc, index asc (candidates are name-sorted, so ties break alphabetically).
// Mirrors eval.h's rankFiles but stays DOUBLE-precision on purpose: routing scores are accumulated in
// double, and rounding them through rankFiles' float would merge near-ties and change top-1 — a
// measurement harness must not let a reuse nicety perturb the measurement.
inline std::vector<std::uint32_t> rankCandidates( const std::vector<double>& score )
{
    std::vector<std::uint32_t> order( score.size() );
    for( std::uint32_t c = 0; c < score.size(); ++c )
    {
        order[c] = c;
    }
    std::sort( order.begin(), order.end(), [ & ]( std::uint32_t a, std::uint32_t b )
               { return score[a] != score[b] ? score[a] > score[b] : a < b; } );
    return order;
}

// ── per-row outcome + per-arm accumulation ──────────────────────────────────────────────────────────────

struct RowOutcome
{
    std::uint32_t top1Index          = 0;
    double        top1Score          = 0.0;
    std::size_t   firstPermittedRank = 0;    // 1-based; 0 on negative rows
    bool          hit1               = false;
    bool          hit2               = false;
};

inline RowOutcome outcomeOf( const std::vector<double>& score, const PromptRow& row )
{
    const std::vector<std::uint32_t> order = rankCandidates( score );
    VERIFY( !order.empty() );
    RowOutcome out;
    out.top1Index = order[0];
    out.top1Score = score[ order[0] ];
    if( row.permitted.empty() )
    {
        return out;
    }

    const auto isPermitted = [ & ]( std::uint32_t c )
    { return std::find( row.permitted.begin(), row.permitted.end(), c ) != row.permitted.end(); };
    for( std::size_t r = 0; r < order.size(); ++r )
    {
        if( isPermitted( order[r] ) ) { out.firstPermittedRank = r + 1; break; }
    }
    out.hit1 = out.firstPermittedRank == 1;
    out.hit2 = out.firstPermittedRank >= 1 && out.firstPermittedRank <= 2;
    return out;
}

// The retrieval arms, in report order. Namespace scope (not function-local) so the per-split reporter below
// can be a free function rather than a lambda capturing runEvalSkills' whole frame.
inline constexpr std::size_t kArmCount = 5;
inline constexpr const char* kArmName[kArmCount] = { "overlap", "name", "bm25-desc", "bm25-full", "for-routed" };

// AUC( positive top-1 scores vs negative top-1 scores ) — threshold-free fire/abstain separation.
// 0.5 = no signal; < 0.5 = inverted (negatives outscore positives — the failure mode to fail loudly on).
inline double separationAuc( const std::vector<double>& posTop, const std::vector<double>& negTop )
{
    if( posTop.empty() || negTop.empty() )
    {
        return 0.5;
    }
    double sum = 0.0;
    for( const double p : posTop )
    {
        for( const double n : negTop )
        {
            sum += p > n ? 1.0 : ( p == n ? 0.5 : 0.0 );
        }
    }
    return sum / ( double( posTop.size() ) * double( negTop.size() ) );
}

// One split's per-arm table (test = the frozen held-out rows, dev = the tuning rows). The whole-corpus
// numbers printed above are unchanged and keep their bare arm-name field-1; every line here leads with
// "split=NAME" instead, so an arm-name-keyed lookup against the corpus report can never match a split row.
inline void reportSplit( const std::vector<PromptRow>& rows, const std::vector<RowOutcome>* outcomes,
                         Split target, const char* label )
{
    // The split's own row counts — an empty split still prints, so a reader sees it exists and is empty.
    std::size_t sPos = 0, sNeg = 0;
    for( const PromptRow& r : rows )
    {
        if( r.split == target )
        {
            ( r.permitted.empty() ? sNeg : sPos )++;
        }
    }
    std::printf( "  split=%s (N=%zu: %zu positive + %zu negative):\n", label, sPos + sNeg, sPos, sNeg );
    if( sPos == 0 ) { std::printf( "    split=%s (no positive rows in this split yet)\n", label ); return; }

    // Per arm: hit@1 / hit@2 / MRR over this split's positives, plus fire-abstain AUC when it has negatives.
    for( std::size_t a = 0; a < kArmCount; ++a )
    {
        double              hit1 = 0, hit2 = 0, mrr = 0;
        std::vector<double> posTop, negTop;
        for( std::size_t i = 0; i < rows.size(); ++i )
        {
            if( rows[i].split != target )
            {
                continue;
            }
            const RowOutcome& o = outcomes[a][i];
            if( rows[i].permitted.empty() ) { negTop.push_back( o.top1Score ); continue; }
            posTop.push_back( o.top1Score );
            hit1 += o.hit1 ? 1 : 0;
            hit2 += o.hit2 ? 1 : 0;
            if( o.firstPermittedRank > 0 )
            {
                mrr += 1.0 / double( o.firstPermittedRank );
            }
        }

        const double P = double( sPos );
        if( sNeg > 0 )
        {
            std::printf( "    split=%-5s %-11s %6.1f%% %6.1f%%   %5.3f     %5.3f\n", label, kArmName[a],
                         100.0 * hit1 / P, 100.0 * hit2 / P, mrr / P, separationAuc( posTop, negTop ) );
        }
        else
        {
            std::printf( "    split=%-5s %-11s %6.1f%% %6.1f%%   %5.3f       n/a (no negative rows in this split)\n",
                         label, kArmName[a], 100.0 * hit1 / P, 100.0 * hit2 / P, mrr / P );
        }
    }
}

// One arm's actionable misses. Keep this outside runEvalSkills so diagnostics for every selector do not
// multiply the already-large orchestration function's nesting and cognitive complexity.
inline void reportMisses( const std::vector<PromptRow>& rows, const std::vector<RowOutcome>& outcomes,
                          const std::vector<SkillDoc>& candidates, std::size_t arm )
{
    std::printf( "  misses (%s):\n", kArmName[arm] );
    std::size_t missCount = 0;
    for( std::size_t i = 0; i < rows.size(); ++i )
    {
        if( rows[i].permitted.empty() || outcomes[i].hit1 )
        {
            continue;
        }
        ++missCount;
        std::string want;
        for( const std::uint32_t c : rows[i].permitted )
        {
            if( !want.empty() )
            {
                want += ',';
            }
            want += candidates[c].dirName;
        }
        std::string clipped = rows[i].prompt.substr( 0, 56 );                     // corpus is ASCII by contract
        if( rows[i].prompt.size() > 56 )
        {
            clipped += "...";
        }
        std::printf( "    line %-3d want=%s got=%s \"%s\"\n", rows[i].lineNumber, want.c_str(),
                     candidates[ outcomes[i].top1Index ].dirName.c_str(), clipped.c_str() );
    }
    if( missCount == 0 )
    {
        std::printf( "    (none)\n" );
    }
}

// best single fire/abstain threshold ON THESE labels (an ORACLE upper bound, printed as such):
// fire iff top-1 score > th; a fired positive is correct only if hit@1, an abstained negative is correct.
struct OraclePoint { double acc = 0.0; double th = 0.0; };

inline OraclePoint oracleFireAbstain( const std::vector<RowOutcome>& outcomes, const std::vector<PromptRow>& rows )
{
    VERIFY( outcomes.size() == rows.size() );
    std::vector<double> thresholds;
    thresholds.push_back( -1.0 );                                  // "always fire" (every score is >= 0)
    for( const RowOutcome& o : outcomes )
    {
        thresholds.push_back( o.top1Score );
    }
    std::sort( thresholds.begin(), thresholds.end() );
    thresholds.erase( std::unique( thresholds.begin(), thresholds.end() ), thresholds.end() );

    OraclePoint best;                                              // ascending scan ⇒ ties keep the smallest th
    for( const double th : thresholds )
    {
        std::size_t correct = 0;
        for( std::size_t i = 0; i < rows.size(); ++i )
        {
            const bool isPositive = !rows[i].permitted.empty();
            const bool fired      = outcomes[i].top1Score > th;
            if( isPositive )
            {
                correct += ( fired && outcomes[i].hit1 ) ? 1 : 0;
            }
            else
            {
                correct += fired ? 0 : 1;
            }
        }
        const double acc = rows.empty() ? 0.0 : double( correct ) / double( rows.size() );
        if( acc > best.acc ) { best.acc = acc; best.th = th; }
    }
    return best;
}

// exact C(n,k) in doubles via the product form (IEEE ops are correctly rounded ⇒ cross-platform stable).
inline double binomialChoose( std::size_t n, std::size_t k )
{
    if( k > n )
    {
        return 0.0;
    }
    if( k > n - k )
    {
        k = n - k;
    }
    double c = 1.0;
    for( std::size_t i = 1; i <= k; ++i )
    {
        c = c * double( n - k + i ) / double( i );
    }
    return c;
}

}   // namespace skilleval

// ── the verb ─────────────────────────────────────────────────────────────────────────────────────────────

inline int runEvalSkills( const std::string& root, const IngestResult& ing, const Graph& g, const std::string& labelsPath )
{
    using namespace skilleval;

    const SkillSet set = discoverSkills( root );
    const std::size_t skillCount = set.candidates.size();
    if( skillCount < 2 )
    {
        std::fprintf( stderr, "ripwire --eval-skills: found %zu skill dir(s) under '%s' — ROOT must be a skills directory "
                              "(one SKILL.md per subdir), e.g. `ripwire skills --eval-skills=test/skillevalfix/prompts.tsv`\n",
                      skillCount, root.c_str() );
        return 1;
    }
    for( const SkillDoc& s : set.candidates )
    {
        if( s.descText.empty() )
        {
            std::fprintf( stderr, "ripwire --eval-skills: note: %s has an empty description: block\n", s.dirName.c_str() );
        }
    }

    std::vector<PromptRow> rows;
    if( !parseCorpus( labelsPath, set.candidates, rows ) )
    {
        return 1;
    }
    std::size_t posCount = 0, negCount = 0;
    for( const PromptRow& r : rows )
    {
        ( r.permitted.empty() ? negCount : posCount )++;
    }
    if( posCount == 0 )
    { std::fprintf( stderr, "ripwire --eval-skills: no positive rows in '%s'\n", labelsPath.c_str() ); return 1; }
    std::size_t testSplitCount = 0, devSplitCount = 0;
    for( const PromptRow& r : rows )
    {
        ( r.split == Split::Dev ? devSplitCount : testSplitCount )++;
    }

    // ---- selector inputs, built once ----
    std::vector<std::string_view> descTexts, fullTexts, nameTexts;
    std::vector<std::string>      fullOwned( skillCount );
    for( std::size_t c = 0; c < skillCount; ++c )
    {
        descTexts.push_back( set.candidates[c].descText );
        fullOwned[c] = set.candidates[c].descText + " " + set.candidates[c].bodyText;
        fullTexts.push_back( fullOwned[c] );
        nameTexts.push_back( set.candidates[c].dirName );
    }
    const BagStats descStats = buildBagStats( descTexts );
    const BagStats fullStats = buildBagStats( fullTexts );
    const BagStats nameStats = buildBagStats( nameTexts );

    // router-magnet diagnostic corpus: the SAME desc arm with ripwire-router allowed in as one more doc.
    BagStats magnetStats;
    if( set.hasRouter )
    {
        std::vector<std::string_view> magnetTexts = descTexts;
        magnetTexts.push_back( set.router.descText );
        magnetStats = buildBagStats( magnetTexts );
    }

    // for-routed arm: file → candidate attribution (a SKILL.md family lives under its skill's directory).
    const std::uint32_t       fileCount = std::uint32_t( ing.files.size() );
    std::vector<std::int32_t> skillIndexOfFile( fileCount, -1 );
    {
        std::vector<std::string> needles( skillCount );
        for( std::size_t c = 0; c < skillCount; ++c )
        {
            needles[c] = "/" + set.candidates[c].dirName + "/";
        }
        for( std::uint32_t f = 0; f < fileCount; ++f )
        {
            const std::string slashed = "/" + ing.files[f];
            for( std::uint32_t c = 0; c < skillCount; ++c )
            {
                if( slashed.find( needles[c] ) != std::string::npos ) { skillIndexOfFile[f] = std::int32_t( c ); break; }
            }
        }
    }

    // ---- run every arm over every row ----
    constexpr std::size_t kDiagArm = 2;        // bm25-desc: the per-skill / miss / provenance diagnostics arm —
                                               // the description IS what a production LLM selector reads.
    std::vector<RowOutcome> outcomes[kArmCount];
    std::size_t             routerMagnetWins = 0;

    for( const PromptRow& row : rows )
    {
        const std::vector<std::string> qUnique = uniqueQueryTokens( row.prompt );

        std::vector<double> armScore[kArmCount];
        armScore[0] = overlapArm( descStats.bags, qUnique );
        armScore[1] = overlapArm( nameStats.bags, qUnique );
        armScore[2] = bm25Arm( descStats, qUnique );
        armScore[3] = bm25Arm( fullStats, qUnique );
        {
            // the SHIPPING --for computation over the skills/ ingest (exactly --eval-mined's arm shape:
            // routed lexical scores, max-pooled to files), then max-pooled once more to skill dirs.
            const RouteChoice        rc   = chooseForRanker( ing, row.prompt );
            const std::vector<float> base = ( rc.which == LexMode::NameExact )
                                          ? lexicalScoresNameExact( ing, row.prompt )
                                          : lexicalScores( ing, g.outOff, g.outTargets, row.prompt );
            const std::vector<float> fileScore = maxPoolToFiles( ing, base, fileCount );
            std::vector<double>      pooled( skillCount, 0.0 );
            for( std::uint32_t f = 0; f < fileCount; ++f )
            {
                if( skillIndexOfFile[f] >= 0 && double( fileScore[f] ) > pooled[ std::size_t( skillIndexOfFile[f] ) ] )
                {
                    pooled[ std::size_t( skillIndexOfFile[f] ) ] = double( fileScore[f] );
                }
            }
            armScore[4] = std::move( pooled );
        }
        for( std::size_t a = 0; a < kArmCount; ++a )
        {
            outcomes[a].push_back( outcomeOf( armScore[a], row ) );
        }

        if( set.hasRouter && !row.permitted.empty() )
        {
            const std::vector<double>        magnetScore = bm25Arm( magnetStats, qUnique );
            const std::vector<std::uint32_t> order       = rankCandidates( magnetScore );
            if( order[0] == std::uint32_t( skillCount ) )
            {
                ++routerMagnetWins; // the appended router doc won
            }
        }
    }

    // ---- report ----
    std::printf( "ripwire --eval-skills  (skill routing over K=%zu candidate skills [ripwire-router excluded]; "
                 "%zu positive + %zu negative prompts; corpus '%s'; split test=%zu dev=%zu)\n",
                 skillCount, posCount, negCount, labelsPath.c_str(), testSplitCount, devSplitCount );
    std::printf( "  %-11s %7s %7s %7s   %7s   %s\n", "arm", "hit@1", "hit@2", "mrr", "sep-auc", "fire/abstain@ORACLE-th (upper bound)" );

    for( std::size_t a = 0; a < kArmCount; ++a )
    {
        double              hit1 = 0, hit2 = 0, mrr = 0;
        std::vector<double> posTop, negTop;
        for( std::size_t i = 0; i < rows.size(); ++i )
        {
            const RowOutcome& o = outcomes[a][i];
            if( rows[i].permitted.empty() ) { negTop.push_back( o.top1Score ); continue; }
            posTop.push_back( o.top1Score );
            hit1 += o.hit1 ? 1 : 0;
            hit2 += o.hit2 ? 1 : 0;
            if( o.firstPermittedRank > 0 )
            {
                mrr += 1.0 / double( o.firstPermittedRank );
            }
        }
        const double      P      = double( posCount );
        const double      auc    = separationAuc( posTop, negTop );
        const OraclePoint oracle = oracleFireAbstain( outcomes[a], rows );
        if( negCount > 0 )
        {
            std::printf( "  %-11s %6.1f%% %6.1f%%   %5.3f     %5.3f   %5.1f%% (th=%.3f)\n",
                         kArmName[a], 100.0 * hit1 / P, 100.0 * hit2 / P, mrr / P, auc, 100.0 * oracle.acc, oracle.th );
        }
        else
        {
            std::printf( "  %-11s %6.1f%% %6.1f%%   %5.3f       n/a   n/a (no negative rows)\n",
                         kArmName[a], 100.0 * hit1 / P, 100.0 * hit2 / P, mrr / P );
        }
    }

    // analytic random floor over the SAME permitted sets (uniform ranking of K candidates, no scores).
    {
        double hit1 = 0, hit2 = 0, mrr = 0;
        for( const PromptRow& row : rows )
        {
            if( row.permitted.empty() )
            {
                continue;
            }
            const std::size_t p = row.permitted.size();
            hit1 += double( p ) / double( skillCount );
            hit2 += 1.0 - binomialChoose( skillCount - p, 2 ) / binomialChoose( skillCount, 2 );
            for( std::size_t r = 1; r + p <= skillCount + 1; ++r )
            { // E[1/rank of first permitted]
                mrr += ( 1.0 / double( r ) ) * binomialChoose( skillCount - r, p - 1 ) / binomialChoose( skillCount, p );
            }
        }
        const double P = double( posCount );
        std::printf( "  %-11s %6.1f%% %6.1f%%   %5.3f     0.500   <- floor (uniform-random ranking; auc 0.5 by definition)\n",
                     "random", 100.0 * hit1 / P, 100.0 * hit2 / P, mrr / P );
    }

    // provenance split for the diagnostics arm — desc rows echo skill wording, so they are the EASY set;
    // judged rows share no description vocabulary by construction and are the number that matters.
    {
        std::size_t provHit[3] = { 0, 0, 0 }, provN[3] = { 0, 0, 0 };
        for( std::size_t i = 0; i < rows.size(); ++i )
        {
            if( rows[i].permitted.empty() )
            {
                continue;
            }
            const std::size_t p = std::size_t( rows[i].prov );
            VERIFY( p < 3 );
            ++provN[p];
            provHit[p] += outcomes[kDiagArm][i].hit1 ? 1 : 0;
        }
        std::printf( "  provenance hit@1 (%s): router %zu/%zu, desc %zu/%zu, judged %zu/%zu "
                     "(desc rows quote the descriptions - expect them easiest; judged is the honest number)\n",
                     kArmName[kDiagArm], provHit[0], provN[0], provHit[1], provN[1], provHit[2], provN[2] );

        // the honest cross-arm comparison: hit@1 on the JUDGED rows only (paraphrases that share no
        // description vocabulary by construction) — the echo-free number every arm must be judged on.
        if( provN[2] > 0 )
        {
            std::printf( "  judged-only hit@1 per arm:" );
            for( std::size_t a = 0; a < kArmCount; ++a )
            {
                std::size_t judgedHit = 0;
                for( std::size_t i = 0; i < rows.size(); ++i )
                {
                    if( !rows[i].permitted.empty() && rows[i].prov == Prov::Judged && outcomes[a][i].hit1 )
                    {
                        ++judgedHit;
                    }
                }
                std::printf( "%s %s %zu/%zu", a ? "," : "", kArmName[a], judgedHit, provN[2] );
            }
            std::printf( "\n" );
        }
    }

    if( set.hasRouter )
    {
        std::printf( "  router-magnet: with ripwire-router ADMITTED as a candidate it takes top-1 on %zu/%zu positive prompts "
                     "(%s arm) - why it is excluded above\n", routerMagnetWins, posCount, kArmName[kDiagArm] );
    }

    // per-skill table (diagnostics arm): which skills never win when permitted (mis-described), which
    // over-fire on rows that are not theirs, and which attract off-topic negatives.
    {
        struct SkillTally { std::size_t permittedRows = 0, won = 0, posFires = 0, falseFires = 0, negFires = 0; };
        std::vector<SkillTally> tally( skillCount );
        for( std::size_t i = 0; i < rows.size(); ++i )
        {
            const RowOutcome& o = outcomes[kDiagArm][i];
            if( rows[i].permitted.empty() ) { ++tally[ o.top1Index ].negFires; continue; }
            ++tally[ o.top1Index ].posFires;
            const bool top1Permitted = std::find( rows[i].permitted.begin(), rows[i].permitted.end(), o.top1Index ) != rows[i].permitted.end();
            if( !top1Permitted )
            {
                ++tally[o.top1Index].falseFires;
            }
            for( const std::uint32_t c : rows[i].permitted )
            {
                ++tally[c].permittedRows;
                if( top1Permitted && o.top1Index == c )
                {
                    ++tally[c].won;
                }
            }
        }
        std::printf( "  per-skill (%s): name / permitted-rows / won / pos-fires / false-fires / neg-fires\n", kArmName[kDiagArm] );
        for( std::size_t c = 0; c < skillCount; ++c )
        {
            std::printf( "    %-26s %3zu %5zu %5zu %5zu %5zu%s\n", set.candidates[c].dirName.c_str(),
                         tally[c].permittedRows, tally[c].won, tally[c].posFires, tally[c].falseFires, tally[c].negFires,
                         ( tally[c].permittedRows >= 2 && tally[c].won == 0 ) ? "   <- never wins its own rows (mis-described?)" : "" );
        }
    }

    // Every arm's misses. Reporting only bm25-desc left a lower-scoring for-routed arm impossible to debug.
    for( std::size_t a = 0; a < kArmCount; ++a )
    {
        reportMisses( rows, outcomes[a], set.candidates, a );
    }

    // split report (r26 P4): test/dev reported SEPARATELY so the two can never be silently conflated —
    // the whole-corpus numbers above are still exactly what they always were (unchanged format, same
    // field-1 tokens, for every existing consumer of this output); this is purely additive. Line-1 field
    // is "split=NAME" (never a bare arm name) so nothing here can collide with an arm-name-keyed lookup
    // against the report above.
    reportSplit( rows, outcomes, Split::Test, kSplitName[ std::size_t( Split::Test ) ] );
    reportSplit( rows, outcomes, Split::Dev,  kSplitName[ std::size_t( Split::Dev  ) ] );

    return 0;
}

}   // namespace rw
