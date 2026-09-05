#pragma once

// testmap.h — the test<->code map, both directions (§P11.2 and §P11.4).
//
// §P11.2 recorded the map as "one-directional and file-granular": the tool could answer "which tests reach
// this FILE" and nothing else. The two questions an agent actually has were unanswerable —
//
//   planning a change     "which tests cover this SYMBOL?"      → --affected=SYM   (resolveAffectedSeeds)
//   fixing a failing test "what does this test EXERCISE?"       → --exercises=FILE
//
// — and §P11.4 recorded that even when the map named a test it named a bare `.cpp` harness path, which is
// not a command: the verb created an obligation its own output could not discharge (--test-gate exits 4 on
// it).
//
// Everything here is SEEDING and PRESENTATION over traversals that already exist. The reachability itself is
// graph.h's transitiveCallers / forwardReach and filter.h's isTestPath — this header adds no new traversal,
// which is why --affected=SYM is a seeding change rather than a second verb. Its own file (not main.cpp)
// because more than one verb reads it, the same reason ownersview.h and pageview.h exist.
//
// Deterministic by construction: every returned list is sorted (symbol id, or path) and every scan runs in
// file/symbol id order.

#include "model.h"
#include "graph.h"        // filePathContains / splitQualifiedSpec / resolveAllByNameQualified — reused, not re-rolled
#include "filter.h"       // isTestPath — the ONE test-path convention the whole tool shares
#include "docparse.h"     // docparse::detail::readWholeFile — the canonical whole-file byte read (reused, not re-rolled)
#include "mention.h"      // mention_detail::baseNameOf + stripExt — the ONE basename/stem pair binstale.h/gitmine.h reuse
#include "infra/namesplit.h" // namesplit::isIdentChar — the canonical ASCII identifier-byte predicate

#include <algorithm>
#include <string>
#include <string_view>
#include <vector>

namespace rw
{

// ── §P11.2a — the --affected argument, read under the FILE-FIRST rule ────────────────────────────────
// One argument string can name a path or a symbol, and the two readings answer different questions over
// the same bytes. The rule is: an item matching ANY indexed path is a path (so every argument shape that
// worked before --affected took symbols means exactly what it meant before), and only an item matching NO
// indexed path is offered to the symbol resolver. `file:NAME` and `path::scope::name` reach the symbol
// reading explicitly — the same two spellings --callers/--impact/--around already accept.
//
// A refusal is per-ITEM, not "the whole list resolved to nothing": before this, `--affected=src/x.cpp,typo`
// silently dropped the typo and answered confidently for the half it understood (§P0's class exactly).
struct AffectedSeeds
{
    std::vector<NodeId> seeds;                  // deduped seed symbols, id asc
    bool                sawFileItem   = false;  // at least one item read as a path pattern
    bool                sawSymbolItem = false;  // at least one item read as a symbol
    bool                ok            = true;   // false ⇒ badItem resolved under NEITHER reading
    std::string         badItem;                // the offending item, for the caller's did-you-mean refusal
};

// seeded_by= — which reading fired. A fact about the measurement (the two readings return different test
// sets from the same argument), so it is disclosed on the root element rather than left to be inferred.
inline const char* affectedSeededBy( const AffectedSeeds& sel ) noexcept
{
    if( sel.sawFileItem && sel.sawSymbolItem )
    {
        return "mixed";
    }
    return sel.sawSymbolItem ? "symbol" : "file";
}

inline AffectedSeeds resolveAffectedSeeds( const IngestResult& ing, std::string_view spec )
{
    AffectedSeeds sel;
    for( std::size_t start = 0; start < spec.size(); )
    {
        std::size_t comma = spec.find( ',', start );
        if( comma == std::string_view::npos )
        {
            comma = spec.size();
        }
        const std::string_view item = spec.substr( start, comma - start );
        start = comma + 1;
        if( item.empty() )
        {
            continue;
        }

        // §P8 seam 2: the PATH reading is stripLineLocator'd, so a `./src/graph.h:1148` row pasted out of
        // --hotspots/--clones/--grep/--lint/--quality-delta means the bare path. The SYMBOL reading gets
        // the item VERBATIM — its own `file:NAME` colon must survive.
        const std::string_view pathPattern = stripLineLocator( item );
        bool                   fileMatched = false;
        for( const std::string& f : ing.files )
        {
            if( filePathContains( f, pathPattern ) )
            {
                fileMatched = true;
                break;
            }
        }
        if( fileMatched )
        {
            sel.sawFileItem = true;
            for( NodeId i = 0; i < NodeId( ing.symbols.size() ); ++i )
            {
                if( filePathContains( ing.files[ing.symbols[i].fileId], pathPattern ) )
                {
                    sel.seeds.push_back( i );
                }
            }
            continue;
        }

        const std::vector<NodeId> defs = resolveAllByNameQualified( ing, item );
        if( defs.empty() ) { sel.ok = false;  sel.badItem.assign( item );  return sel; }
        sel.sawSymbolItem = true;
        sel.seeds.insert( sel.seeds.end(), defs.begin(), defs.end() );
    }
    std::sort( sel.seeds.begin(), sel.seeds.end() );
    sel.seeds.erase( std::unique( sel.seeds.begin(), sel.seeds.end() ), sel.seeds.end() );
    return sel;
}

// ── §P11.2b — the INVERSE: what does this test exercise? ─────────────────────────────────────────────
// Seeds are every symbol of every matched TEST file; the answer is graph.h's forwardReach from them, minus
// everything that is itself test code. Refusal on a non-test path is deliberate and is stated in --help:
// the verb's whole content is the test/non-test PARTITION (it SUBTRACTS test code from the answer), and on
// a non-test file that subtraction is meaningless — "everything this file transitively calls" is a
// different question, already answered by --callees (1 hop) and --graph-query's bounded callees closure.
// Answering it generically here would make one verb quietly mean two things depending on its argument.
struct ExerciseSeeds
{
    std::vector<NodeId>        seeds;              // every symbol of the matched test files, id asc
    std::vector<std::uint32_t> testFiles;          // the matched TEST files, path asc
    std::uint32_t              nonTestMatches = 0; // matched files that are NOT test paths (the refusal reason)
    bool                       anyFileMatched = false;
};

inline ExerciseSeeds resolveExerciseSeeds( const IngestResult& ing, std::string_view spec )
{
    ExerciseSeeds          sel;
    const std::string_view pathPattern = stripLineLocator( spec );      // §P8 seam 2: a pasted `path:line` row means the path
    std::vector<char>      isSeedFile( ing.files.size(), 0 );
    for( std::uint32_t f = 0; f < std::uint32_t( ing.files.size() ); ++f )
    {
        if( !filePathContains( ing.files[f], pathPattern ) )
        {
            continue;
        }
        sel.anyFileMatched = true;
        if( !isTestPath( ing.files[f] ) ) { ++sel.nonTestMatches;  continue; }
        isSeedFile[f] = 1;
        sel.testFiles.push_back( f );
    }
    std::sort( sel.testFiles.begin(), sel.testFiles.end(), [ & ]( std::uint32_t a, std::uint32_t b ) { return ing.files[a] < ing.files[b]; } );
    for( NodeId i = 0; i < NodeId( ing.symbols.size() ); ++i )
    {
        if( isSeedFile[ing.symbols[i].fileId] )
        {
            sel.seeds.push_back( i );
        }
    }
    return sel;
}

// The non-test symbols the seeds transitively call. The seeds are test symbols, so the isTestPath filter
// removes them for free — no separate "minus the seeds" pass that could disagree with the partition.
inline std::vector<NodeId> exercisedSymbols( const IngestResult& ing, const Graph& g, const std::vector<NodeId>& seeds )
{
    const std::vector<char> reached = forwardReach( g, seeds );
    std::vector<NodeId>     out;
    for( NodeId i = 0; i < NodeId( reached.size() ) && i < NodeId( ing.symbols.size() ); ++i )
    {
        if( reached[i] && !isTestPath( ing.files[ing.symbols[i].fileId] ) )
        {
            out.push_back( i );
        }
    }
    return out;
}

// ── §P11.4 — run=, the runner hint on a test row ─────────────────────────────────────────────────────
// --affected/--situ/--test-gate NAME `.cpp` harnesses; the runners are `test/*.sh` (or `*.py`). --test-gate
// EXITS 4 on that obligation, so the one verb family whose job is "here is what to run before you ship"
// produced an obligation its own output could not discharge.
//
// TWO evidence kinds, both REAL — never a guess. An ABSENT run= means "not derivable", and that is the
// whole contract: falling back to the repo's suite runner would emit a plausible command that may not run
// the named harness at all — §P0's fabricated confidence, in command form, on a row the agent is being
// told to act on.
//   (1) STEM    — a runner whose basename stem equals the harness's        (samename.cpp <-> samename.sh)
//   (2) MENTION — a runner whose TEXT contains the harness's basename      (clonebandcheck.sh names
//                 cloneband_harness.cpp). This is the shape that dominates in practice: none of this
//                 repo's four *_harness.cpp files stem-matches its gate.
// Stem beats mention; among several mentioners the path-ascending first wins, so the hint is deterministic.
// Both are honest evidence: a script that names the harness does drive it.
//
// COST: the candidate scripts' texts are read at most ONCE per invocation and only LAZILY — nothing is read
// until a row actually asks for a hint, so every verb that emits no test row pays nothing at all.
class TestRunnerIndex
{
public:
    explicit TestRunnerIndex( const IngestResult& ing ) : ing_( &ing )
    {
        for( std::uint32_t f = 0; f < std::uint32_t( ing.files.size() ); ++f )
        {
            if( isTestPath( ing.files[f] ) && runnerVerb( ing.files[f] ) != nullptr )
            {
                runners_.push_back( f );
            }
        }
        std::sort( runners_.begin(), runners_.end(), [ & ]( std::uint32_t a, std::uint32_t b ) { return ing.files[a] < ing.files[b]; } );
    }

    // The pasteable command for `fileId`, or "" when no REAL runner is derivable.
    const std::string& commandFor( std::uint32_t fileId ) const
    {
        static const std::string kNoRunner;
        if( fileId >= ing_->files.size() )
        {
            return kNoRunner;
        }
        const auto cached = cache_.find( fileId );
        if( cached != cache_.end() )
        {
            return cached->second;
        }
        return cache_.emplace( fileId, derive( fileId ) ).first->second;
    }

    std::string commandForScript( std::uint32_t fileId ) const
    { return fileId < ing_->files.size() && runnerVerb( ing_->files[fileId] ) != nullptr ? spell( fileId ) : std::string(); }

private:
    // A runner is a script we know how to invoke. A TABLE, not a switch (house style): extension → verb.
    static const char* runnerVerb( std::string_view path ) noexcept
    {
        struct RunnerRow { std::string_view ext; const char* verb; };
        static constexpr RunnerRow kRunnerKinds[] = { { ".sh", "bash" }, { ".py", "python3" } };
        for( const RunnerRow& r : kRunnerKinds )
        {
            if( path.size() > r.ext.size() && path.compare( path.size() - r.ext.size(), r.ext.size(), r.ext ) == 0 )
            {
                return r.verb;
            }
        }
        return nullptr;
    }

    // basename / stem come from mention.h's ONE pair (mention_detail::baseNameOf + stripExt) — the same
    // primitives binstale.h, gitmine.h and docdrift.h already stem paths with. Re-rolling them here is
    // exactly the new-clone-of-a-reused-helper --quality-delta reports, and it would also fork the
    // "strip the LAST dot" convention that every other stemming call site in this repo shares.
    static std::string_view stemOf( std::string_view p ) noexcept
    { return mention_detail::stripExt( mention_detail::baseNameOf( p ) ); }

    void loadTexts() const
    {
        if( textsLoaded_ )
        {
            return;
        }
        textsLoaded_ = true;
        texts_.resize( runners_.size() );
        for( std::size_t i = 0; i < runners_.size(); ++i )
        {
            if( !docparse::detail::readWholeFile( diskPath( *ing_, runners_[i] ), texts_[i] ) )
            {
                texts_[i].clear(); // unreadable ⇒ no evidence, never a guess
            }
        }
    }

    std::string derive( std::uint32_t fileId ) const
    {
        const std::string& target = ing_->files[ fileId ];
        if( runnerVerb( target ) != nullptr )
        {
            // M21(b) (capture-audit 2026-09-04): a runner script IS the command, and this used to return ""
            // — which was harmless while "" meant only "nothing to ADD to p=". It stopped being harmless the
            // moment "" acquired a MEANING: run_unknown="1" asserts no runner is derivable, and for a row
            // whose own path is directly runnable that assertion is simply false. So the self-runnable case
            // now spells its own command, exactly as commandForScript already does for a shell gate.
            return spell( fileId );
        }

        for( std::uint32_t r : runners_ )
        { // (1) stem — runners_ is path-sorted, so the pick is deterministic
            if( stemOf( ing_->files[r] ) == stemOf( target ) )
            {
                return spell( r );
            }
        }

        loadTexts();                                                        // (2) mention — first (path asc) runner naming the harness's basename
        const std::string_view targetBase = mention_detail::baseNameOf( target );
        for( std::size_t i = 0; i < runners_.size(); ++i )
        {
            if( texts_[i].find( targetBase ) != std::string::npos )
            {
                return spell( runners_[i] );
            }
        }
        return {};
    }

    // Spelled against the ON-DISK path (diskPath), so a multi-root `<label>/<rel>` identity spelling — which
    // is a label, not a directory — can never leak into something a shell would mis-resolve. A leading "./"
    // is dropped for readability; the result is pasteable from the repo root.
    std::string spell( std::uint32_t runnerFile ) const
    {
        std::string_view p = diskPath( *ing_, runnerFile );
        if( p.rfind( "./", 0 ) == 0 )
        {
            p = p.substr( 2 );
        }
        return std::string( runnerVerb( p ) ) + " " + std::string( p );
    }

    const IngestResult*                         ing_;
    std::vector<std::uint32_t>                  runners_;
    mutable std::vector<std::string>            texts_;
    mutable bool                                textsLoaded_ = false;
    mutable HashMap<std::uint32_t, std::string> cache_;
};

// The ` run="…"` attribute for one test row, or "" — the ONE spelling, so the four emitters (--affected,
// --exercises' seed rows, --test-gate's XML and its JSON sibling) cannot disagree about quoting or escaping.
// ONE renderer for all four emitters (--affected, --exercises' seed rows, --test-gate's XML and its JSON
// sibling, --situ's text lines). The three output shapes differ only in their delimiters, so they are
// PARAMETERS, not three near-identical functions: the load-bearing half is the `cmd.empty()` branch — the
// "absent means not derivable" rule — and that must exist exactly once or a later edit will fix it in one
// shape and leave a fabricated command in another. `esc` is the caller's escaper (escapeXml / jsonStr /
// identity), passed in rather than included, so this header stays below serialize.h in the include order.
template<class EscapeFn>
inline std::string runHint( const TestRunnerIndex& idx, std::uint32_t fileId,
                            std::string_view open, std::string_view close, EscapeFn esc )
{
    const std::string& cmd = idx.commandFor( fileId );
    if( cmd.empty() )
    {
        return {};
    }
    return std::string( open ) + esc( cmd ) + std::string( close );
}

// The three call shapes, named so a caller never spells a delimiter by hand.
template<class EscapeFn>
inline std::string runAttr( const TestRunnerIndex& idx, std::uint32_t fileId, EscapeFn esc )
{ return runHint( idx, fileId, " run=\"", "\"", esc ); }

template<class EscapeFn>
inline std::string runFieldJson( const TestRunnerIndex& idx, std::uint32_t fileId, EscapeFn esc )
{ return runHint( idx, fileId, ",\"run\":\"", "\"", esc ); }

inline std::string runSuffixText( const TestRunnerIndex& idx, std::uint32_t fileId )
{ return runHint( idx, fileId, "   (run: ", ")", []( std::string_view s ) { return std::string( s ); } ); }

// ── M21(b), capture-audit 2026-09-04 — the NOT-DERIVABLE case, SAID ───────────────────────────────────
// The three shapes above return "" when no runner is derivable, and every emitter simply printed nothing.
// The rule behind that ("a guessed command is worse than none") is right and is unchanged here; what was
// wrong is that an ABSENCE is not a disclosure. A reader of `<t p="./test/verify_radix.cpp"/>` — a row the
// verb that emits it calls an OBLIGATION and exits 4 over — cannot tell "this harness has no runner in the
// corpus" from "this emitter never asked". It is the same class as counts_floor= and
// script_gates_unmodelled=: the gap is stated where the number is consumed. So a tests_to_run row now says
// one of two things and never neither, and test/testrowruncheck.sh asserts exactly that over every emitter
// in the family — including --handoff and --flags --flip, which asked for no runner at all.
//
// These are WRAPPERS, not copies: the ""-means-not-derivable test stays in runHint alone, so a later edit
// to what counts as derivable cannot fix one dialect and leave another fabricating.
template<class EscapeFn>
inline std::string runAttrDisclosed( const TestRunnerIndex& idx, std::uint32_t fileId, EscapeFn esc )
{
    std::string attr = runAttr( idx, fileId, esc );
    return attr.empty() ? std::string( " run_unknown=\"1\"" ) : attr;
}

template<class EscapeFn>
inline std::string runFieldJsonDisclosed( const TestRunnerIndex& idx, std::uint32_t fileId, EscapeFn esc )
{
    std::string field = runFieldJson( idx, fileId, esc );
    return field.empty() ? std::string( ",\"run_unknown\":true" ) : field;
}

inline std::string runSuffixTextDisclosed( const TestRunnerIndex& idx, std::uint32_t fileId )
{
    std::string suffix = runSuffixText( idx, fileId );
    return suffix.empty() ? std::string( "   (run: not derivable)" ) : suffix;
}

// The ONE sentence every legend that carries a tests_to_run row splices, so the seven cannot drift into
// seven wordings of one rule. Deliberately short: it rides on --test-gate's own byte ratchets.
inline constexpr std::string_view kRunHintLegendClause =
    "run= is the command that discharges a test row; run_unknown=\"1\" means none is derivable for that "
    "harness (a guess would be worse than none) — a row carries one or the other, never neither. ";

// ── §P9 N5 / §B7.3 — the blindness this whole map shares, counted ONCE ────────────────────────────────
// Every verb built on the call-graph walk (--affected, --test-gate, --situ) is blind to the same thing: a
// shell harness that runs the compiled BINARY as a subprocess is not a call edge, so those gates are
// invisible to the traversal and can never appear in a tests= or reached= count. The honest-limits rule
// (§P0.5's family) says absence of modelling must be stated WHERE THE NUMBER IS CONSUMED — and --test-gate
// is the verb that EXITS 4 calling its rows "the obligations", so it needed the disclosure most and had it
// least: six named tests, no hint that 276 shell gates were never modelled at all.
//
// It lives HERE rather than in main.cpp because three verbs must report the SAME number. A second copy
// would drift the moment the test-path convention moved, and the three would then disagree about how blind
// they are — which is worse than the original silence, because the disagreement looks like a measurement.
// Counts every corpus file under test/ ending in ".sh", regardless of whether THIS run's changed set
// reaches it: the point is disclosing what the model cannot see AT ALL, not scoping it to the query. A path
// count, deliberately — the files are never opened, so this never claims each one invokes the binary.
inline std::size_t scriptGatesUnmodelledCount( const IngestResult& ing )
{
    std::size_t gateCount = 0;
    for( const std::string& filePath : ing.files )
    {
        if( isTestPath( filePath ) && filePath.size() >= 3 && filePath.compare( filePath.size() - 3, 3, ".sh" ) == 0 )
        {
            ++gateCount;
        }
    }
    return gateCount;
}

struct ShellGateObligation
{
    std::uint32_t fileId = 0;
    const char*   evidence = nullptr;
};

struct ShellGateIndex
{
    std::vector<ShellGateObligation> obligations;
    std::size_t                      registered = 0;
    std::size_t                      mapped = 0;
    std::size_t                      unresolvedDynamic = 0;
};

namespace testmap_detail
{

inline std::string executableShellText( std::string_view source )
{
    std::string executable;
    bool comment = false;
    for( const char c : source )
    {
        if( c == '\n' )
        {
            comment = false;
            executable.push_back( c );
        }
        else if( c == '#' )
        {
            comment = true;
        }
        else if( !comment ) { executable.push_back( c ); }
    }
    return executable;
}

inline std::string_view trimShellSpace( std::string_view value ) noexcept
{
    const std::size_t first = value.find_first_not_of( " \t\r" );
    if( first == std::string_view::npos ) { return {}; }
    return value.substr( first, value.find_last_not_of( " \t\r" ) - first + 1 );
}

inline void appendManifestDependencies( std::string_view line, std::vector<std::string>& deps )
{
    constexpr std::string_view kMarker = "# RIPWIRE_TEST_DEPS:";
    line = trimShellSpace( line );
    if( line.rfind( kMarker, 0 ) != 0 ) { return; }
    line.remove_prefix( kMarker.size() );
    for( std::size_t begin = 0; begin <= line.size(); )
    {
        const std::size_t comma = line.find( ',', begin );
        const std::string_view dep = trimShellSpace( line.substr( begin, comma == std::string_view::npos ? line.size() - begin : comma - begin ) );
        if( !dep.empty() ) { deps.emplace_back( dep ); }
        if( comma == std::string_view::npos ) { return; }
        begin = comma + 1;
    }
}

inline std::vector<std::string> manifestDependencies( std::string_view source )
{
    std::vector<std::string> deps;
    for( std::size_t begin = 0; begin < source.size(); )
    {
        const std::size_t end = source.find( '\n', begin );
        appendManifestDependencies( source.substr( begin, end == std::string_view::npos ? source.size() - begin : end - begin ), deps );
        if( end == std::string_view::npos ) { break; }
        begin = end + 1;
    }
    return deps;
}

inline bool pathLiteralMatches( std::string_view indexedPath, std::string_view literal ) noexcept
{
    while( indexedPath.rfind( "./", 0 ) == 0 ) { indexedPath.remove_prefix( 2 ); }
    while( literal.rfind( "./", 0 ) == 0 ) { literal.remove_prefix( 2 ); }
    if( literal.find( '/' ) == std::string_view::npos )
    {
        return false; // a basename alone is not exact path evidence
    }
    if( indexedPath == literal )
    {
        return true;
    }
    return indexedPath.size() > literal.size() && indexedPath.ends_with( literal ) && indexedPath[indexedPath.size() - literal.size() - 1] == '/';
}

inline std::vector<std::string> shellTokens( std::string_view executable )
{
    std::vector<std::string> tokens;
    for( std::size_t begin = 0; begin < executable.size(); )
    {
        while( begin < executable.size() && executable[begin] != '/' && executable[begin] != '.' && !namesplit::isIdentChar( executable[begin] ) ) { ++begin; }
        std::size_t end = begin;
        while( end < executable.size() )
        {
            const char c = executable[end];
            if( c != '/' && c != '.' && c != '-' && !namesplit::isIdentChar( c ) ) { break; }
            ++end;
        }
        if( end > begin ) { tokens.emplace_back( executable.substr( begin, end - begin ) ); }
        begin = end == begin ? begin + 1 : end;
    }
    return tokens;
}

inline std::vector<std::string> shellPathTokens( std::string_view executable )
{
    std::vector<std::string> paths = shellTokens( executable );
    paths.erase( std::remove_if( paths.begin(), paths.end(), []( const std::string& token ) { return token.find( '/' ) == std::string::npos; } ), paths.end() );
    return paths;
}

inline bool dependenciesMatchChanged( const IngestResult& ing, const std::vector<char>& changedFiles,
                                      const std::vector<std::string>& dependencies ) noexcept
{
    for( std::uint32_t f = 0; f < std::uint32_t( ing.files.size() ) && f < changedFiles.size(); ++f )
    {
        if( !changedFiles[f] ) { continue; }
        for( const std::string& dependency : dependencies )
        {
            if( pathLiteralMatches( ing.files[f], dependency ) ) { return true; }
        }
    }
    return false;
}

inline bool dependenciesMapCorpus( const IngestResult& ing, const std::vector<std::string>& dependencies ) noexcept
{
    for( const std::string& file : ing.files )
    {
        for( const std::string& dependency : dependencies )
        {
            if( pathLiteralMatches( file, dependency ) ) { return true; }
        }
    }
    return false;
}

// The word list of every `for <var> in <members…>; do` in the token stream, one token of lookahead state.
inline void appendForListStems( const std::vector<std::string>& tokens, std::vector<std::string>& stems )
{
    enum class Loop : std::uint8_t { Scan, Var, ExpectIn, List };
    Loop state = Loop::Scan;
    for( const std::string& token : tokens )
    {
        if( token.find( '/' ) != std::string::npos )
        {
            continue;   // a path token is never a shell keyword or a bare list member
        }
        switch( state )
        {
            case Loop::Scan:     if( token == "for" ) { state = Loop::Var; }  break;
            case Loop::Var:      state = Loop::ExpectIn;  break;   // the loop variable name
            case Loop::ExpectIn: state = token == "in" ? Loop::List : Loop::Scan;  break;
            case Loop::List:
                if( token == "do" ) { state = Loop::Scan; }
                else                { stems.push_back( token ); }
                break;
        }
    }
}

inline std::vector<std::string> suiteMemberStems( const std::vector<std::string>& tokens )
{
    std::vector<std::string> stems;
    for( const std::string& token : tokens )
    {
        if( token.find( '/' ) == std::string::npos ) { continue; }
        const std::string_view stem = mention_detail::stripExt( mention_detail::baseNameOf( token ) );
        if( !stem.empty() ) { stems.emplace_back( stem ); }
    }
    appendForListStems( tokens, stems );
    return stems;
}

inline std::vector<std::string> registeredShellTokens( const IngestResult& ing )
{
    std::string manifest;
    for( std::uint32_t f = 0; f < std::uint32_t( ing.files.size() ); ++f )
    {
        if( mention_detail::baseNameOf( ing.files[f] ) == "regression.sh" && isTestPath( ing.files[f] ) )
        {
            docparse::detail::readWholeFile( diskPath( ing, f ), manifest );
            break;
        }
    }
    // A stem is REGISTERED only where regression.sh names it as a suite member: as a path-shaped token
    // (a direct `bash test/<stem>.sh` invocation), or as a word inside a `for … in <list>; do` word list
    // (the absorb loop). A bare word elsewhere in the manifest — an echo, a variable, a status label —
    // must never register a coincidentally-named script; that inflated registered/unresolved_dynamic.
    return suiteMemberStems( shellTokens( executableShellText( manifest ) ) );
}

inline void addRegisteredShellGate( const IngestResult& ing, const std::vector<char>& changedFiles, std::uint32_t fileId, ShellGateIndex& index )
{
    ++index.registered;
    std::string source;
    if( !docparse::detail::readWholeFile( diskPath( ing, fileId ), source ) ) { return; }
    const std::vector<std::string> manifestDeps = manifestDependencies( source );
    const std::vector<std::string> literalDeps  = shellPathTokens( executableShellText( source ) );
    const bool manifestMapped = dependenciesMapCorpus( ing, manifestDeps );
    const bool literalMapped  = dependenciesMapCorpus( ing, literalDeps );
    if( manifestMapped || literalMapped ) { ++index.mapped; }
    if( manifestMapped && dependenciesMatchChanged( ing, changedFiles, manifestDeps ) )
    {
        index.obligations.push_back( ShellGateObligation{ fileId, "manifest_declared" } );
    }
    else if( literalMapped && dependenciesMatchChanged( ing, changedFiles, literalDeps ) )
    {
        index.obligations.push_back( ShellGateObligation{ fileId, "script_literal" } );
    }
}

} // namespace testmap_detail

inline ShellGateIndex buildShellGateIndex( const IngestResult& ing, const std::vector<char>& changedFiles )
{
    using namespace testmap_detail;
    ShellGateIndex index;
    const std::vector<std::string> registeredTokens = registeredShellTokens( ing );
    if( registeredTokens.empty() )
    {
        return index;
    }

    for( std::uint32_t f = 0; f < std::uint32_t( ing.files.size() ); ++f )
    {
        const std::string_view path = ing.files[f];
        if( !isTestPath( path ) || !path.ends_with( ".sh" ) || mention_detail::baseNameOf( path ) == "regression.sh" ) { continue; }
        const std::string_view stem = mention_detail::stripExt( mention_detail::baseNameOf( path ) );
        if( std::find( registeredTokens.begin(), registeredTokens.end(), stem ) == registeredTokens.end() ) { continue; }
        addRegisteredShellGate( ing, changedFiles, f, index );
    }
    index.unresolvedDynamic = index.registered - index.mapped;
    std::sort( index.obligations.begin(), index.obligations.end(), [ & ]( const ShellGateObligation& a, const ShellGateObligation& b )
               { return ing.files[a.fileId] < ing.files[b.fileId]; } );
    return index;
}

}   // namespace rw
