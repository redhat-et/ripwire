#pragma once
// exemplarfamily.h — EXEMPLAR-STAIRS: on an add-a-new-X task, the FAMILY of existing X (the siblings a new one joins). One shared
// helper (exemplarTasksOf / exemplarFamily) so --for, and later --exemplar, --lego and MCP, read the same family. (CLI src/verbs_for.h
// appendForTaskRowBlocks, MCP `for` src/mcpverbs.h forTaskText — one renderer, renderForExemplarFamily.)
//
// WHY. Stage 0 (reports/exemplar-e0.md): on the add-a-new-X rows --exemplar picked an unrelated symbol on 6 of 6, --lego lists
// implementors=0 for a Go interface or a C vtable struct, and --for printed no sibling of X at all, while 11 of the 14 gold items
// on those rows are where the siblings are registered.
//
// WHEN (present-only). The task reads as adding one more X (exemplarTasksOf): a creation verb (add, create, register, write, implement,
// introduce, define) with an article (a, an, another), `I need|want a new X`, `another X like ..`, or `a new X` after a
// creation verb (`add support for a new database (a new dialect)`). X is the noun phrase after it, up to a stop word (that, to, for, in,
// like, where, ..) or punctuation; its last word is the head. A head that names a change to one existing symbol (parameter, argument,
// field, test, comment, ..) is no family. The block prints only when a family resolves.
//
// FAMILY, a rule cascade (each rule yields candidate families of 3 or more non-test members; members are scoped to the deepest
// directory holding at least half of them; test paths, test scopes and test-helper directories hold no member):
//   (a) base      — the implementors of one base class / interface / trait (the graph's implementors list);
//   (b) registry  — the entries of one registry map or dispatch table: a variable or function whose lines are `key: value,`,
//                   `{ "key", value },`, `"key" => value,` or `m[key] = value;` (three or more, at least half its lines);
//   (c) typed     — typed instances of one struct type in C or C++ (htop `const MeterClass CpuMeter_class = {`);
//   (d) attribute — items carrying one attribute macro or decorator (Rust `#[function("..")]`, Python / TS `@register_x`);
//   (e) affix     — three or more classes in one directory whose names end with the head word.
// A candidate counts only when the head word is in its key (the base / registry / type / attribute / affix name, or the scope's
// path). Score = the task words in the key and scope, plus one when the key names X itself (it ends with the head, or with the head
// and a kind or registry word: `MeterClass`, `kCodecRegistry`; not an affix key, the head by construction). The highest score wins; the cascade order (a)..(e) breaks a tie,
// then the larger family. The rows are where existing siblings live, read off the index and the files: not a guarantee.
#include "docparse.h" // detail::readWholeFile
#include "filter.h" // isTestPath
#include "graph.h"
#include "infra/enumcount.h" // enumCountIsExact — kExemplarRuleTags has one row per ExemplarRule value
#include "infra/sortutil.h" // svLess — the portable string_view order
#include "infra/namesplit.h" // isIdentChar, stripQuotePair — the shared identifier byte and quote strip
#include "langfacts.h" // typedInstanceRows, xMacroRows, bracedPropertyRows
#include "lexical.h" // forEachLexSubtoken / lexLowerByte — the one identifier splitter
#include "memberowner.h" // TOUCH-SYM: MemberOwners / qualifiedMemberName — a <touch> row's n= as every member row spells it
#include "model.h"
#include "resolve.h" // trimWs, includerDir
#include "serialize.h" // escapeXml

#include <algorithm>
#include <array>
#include <cstddef>
#include <cstdint>
#include <iterator>
#include <optional>
#include <span>
#include <string>
#include <string_view>
#include <tuple>
#include <utility>
#include <vector>

namespace rw
{
inline constexpr std::size_t kExemplarFamilyMin = 3; // members a family needs (a pair is not a pattern)
inline constexpr std::size_t kExemplarMemberRows = 4; // <m> rows printed (typical first); the rest are counted in n=
inline constexpr std::size_t kExemplarPhraseWordsMax = 4; // words of X read after the trigger
inline constexpr std::size_t kExemplarBodyScanMaxLoc = 4000; // a registry or instance candidate longer than this is not read (runaway guard)
inline constexpr std::size_t kExemplarTaskReadings = 3; // add-a-new-X readings of one task tried

enum class ExemplarRule : std::uint8_t
{
    Base,
    Registry,
    Typed,
    Attribute,
    Affix
};

inline constexpr std::array kExemplarRuleTags = { std::string_view( "base" ), std::string_view( "registry" ), std::string_view( "typed" ), std::string_view( "attribute" ),
                                                  std::string_view( "affix" ) }; // indexed by ExemplarRule
inline constexpr std::size_t kExemplarRuleCount = 5;
static_assert( enumCountIsExact<ExemplarRule, kExemplarRuleCount>(), "kExemplarRuleCount must equal the ExemplarRule count — raise it with the append" );
static_assert( kExemplarRuleTags.size() == kExemplarRuleCount, "one kExemplarRuleTags row per ExemplarRule value (the extent is deduced from the rows)" );

// What the task asks to add: the phrase as written, its words (lowercased, split on '-' and '_', plural -s dropped), the head word.
struct ExemplarTask
{
    std::string phrase;
    std::vector<std::string> words;
    std::string head;
    std::vector<std::string> others; // the task's other content words (outside X): a holder may be named by one (E3a-INTO)
};

struct ExemplarMember
{
    std::string name; // the member's name (an entry's key, an instance's name, a class)
    std::uint32_t fileId = 0;
    std::uint32_t line = 0;
    std::uint32_t loc = 0; // the member's own size in lines (0: not read)
    std::string alt; // a second name the repo spells it by (an attribute's registered name: `#[function("upper(..)")]` → upper)
    NodeId sym = kNoNode; // the member's own definition (kNoNode: a registry entry, a row, no definition of its own)
};

// E3a-INTO: when the members are holders of X (`ServerSettingsImpl`, `MergeTreeSettingsImpl` for a new setting; `CompilerOptions`
// for a new compiler option) a new X is not one more member: it is one more ROW inside one of them. `member` is that holder (index
// into members), `rows` the existing X rows in it (the siblings to copy), read off its fields, its `name: type` property lines, or
// the largest X-macro list in its file (C, C++: `#define COMMON_SETTINGS(DECLARE, ..)` with one `DECLARE(Type, name, ..)` per row).
struct ExemplarInto
{
    std::size_t member = SIZE_MAX; // SIZE_MAX: not a holder family
    bool bare = false; // picked as the one holder whose name carries no other kind word (no holder name matched a task word)
    std::string word; // else the task word the holder's name carries
    std::string_view by; // where the rows came from: "macro", "field" or "line" ("" when no rows were read)
    std::string list; // by="macro": the list macro's name
    std::uint32_t listLine = 0;
    std::vector<ExemplarMember> rows;
};

struct ExemplarFamily
{
    ExemplarRule rule = ExemplarRule::Base;
    std::string key; // the base / registry / type / attribute / affix the members share
    std::uint32_t keyFile = 0; // where key= is defined (base and registry only: keyAt)
    std::uint32_t keyLine = 0;
    bool keyAt = false;
    std::string scope; // the directory the members were scoped to ("" = the root)
    std::size_t score = 0; // task words in the key and scope, +1 when the key names X
    std::string matched; // those task words, space-joined: why this family won (the words of of= it holds)
    std::vector<ExemplarMember> members; // every non-test member in scope, typical first
    std::uint32_t unread = 0; // what the scan that found this family could not look at (set by the renderer; printed as unread= / oversized=)
    std::uint32_t oversized = 0;
    ExemplarInto into; // E3a-INTO: the members hold X (plural names), so a new X goes INTO one of them (see settleInto)

    void add( const Symbol& s ) { members.push_back( ExemplarMember { s.name, s.fileId, s.line, s.loc, {}, s.id } ); }
};

namespace exemplar_detail
{
using namesplit::isIdentChar;
using namesplit::stripQuotePair;

// A word's singular: a trailing `s` goes when the word is longer than three letters and does not end in `ss` / `us` / `is`.
inline std::string singular( std::string w )
{
    const bool plural = w.size() > 3 && w.back() == 's' && !w.ends_with( "ss" ) && !w.ends_with( "us" ) && !w.ends_with( "is" );
    if( plural )
    {
        w.pop_back();
        if( w.size() > 3 && w.ends_with( "ie" ) )
        {
            w.replace( w.size() - 2, 2, "y" ); // registries → registry
        }
    }
    return w;
}

// The task as lowercased words; a punctuation boundary (, ; : ? ! ( ) ` ") is an empty word and a sentence end (a word's trailing `.`)
// is the word ".", which stops a phrase like a boundary and ends a creation verb's reach (exemplarTasksOf).
inline std::vector<std::string> taskWords( std::string_view task )
{
    static constexpr std::string_view kBoundary = ",;:?!()`\"";
    std::vector<std::string> out;
    std::string cur;
    const auto flush = [&]
    {
        bool sentence = false;
        while( !cur.empty() && ( cur.back() == '.' || cur.back() == '\'' || cur.back() == '-' ) )
        {
            sentence = sentence || cur.back() == '.';
            cur.pop_back();
        }
        if( !cur.empty() )
        {
            out.push_back( cur );
        }
        if( sentence )
        {
            out.emplace_back( "." );
        }
        cur.clear();
    };
    for( const char c : task )
    {
        if( isIdentChar( c ) || c == '-' || c == '.' || c == '\'' )
        {
            cur.push_back( char( lexLowerByte( static_cast<unsigned char>( c ) ) ) );
            continue;
        }
        flush();
        if( kBoundary.find( c ) != std::string_view::npos )
        {
            out.emplace_back();
        }
    }
    flush();
    return out;
}

inline constexpr std::array<std::string_view, 7> kVerbs { "add", "create", "register", "write", "implement", "introduce", "define" }; // not build / make: `build a target`, `build an executor` (fire list)
inline constexpr std::array<std::string_view, 3> kArticles { "a", "an", "another" };
// The phrase ends at one of these: what follows says where or how, not what.
inline constexpr std::array<std::string_view, 31> kPhraseStops { "that", "which", "who", "to", "for", "in", "into", "on", "with", "so", "where",
                                                                 "like", "and", "or", "as", "from", "by", "under", "at", "of", "called", "named",
                                                                 "similar", "i", "we", "how", "what", "when", "the", "using", "inside" };
// Words of X that carry no family meaning.
inline constexpr std::array<std::string_view, 10> kPhraseFiller { "new", "custom", "own", "my", "our", "in", "the", "a", "an", "one" };
// A head that names a change to one existing symbol, or nothing at all: no family to join.
inline constexpr std::array<std::string_view, 24> kNotFamilyHeads { "parameter", "param", "argument", "arg", "field", "test", "check", "comment",
                                                                    "log", "line", "case", "way", "thing", "feature", "support", "step", "call",
                                                                    "version", "file", "fix", "flag", "note", "link", "bug" };

// Where X starts after a creation verb or `need` / `want` at w[i] (npos: no X there).
inline std::size_t phraseAfterVerb( const std::vector<std::string>& w, std::size_t i )
{
    const bool verb = std::ranges::contains( kVerbs, w[i] );
    if( !verb && w[i] != "need" && w[i] != "want" )
    {
        return std::string::npos;
    }
    std::size_t j = i + 1;
    if( verb && j + 1 < w.size() && w[j] == "and" && std::ranges::contains( kVerbs, w[j + 1] ) )
    {
        j += 2; // write and register a pydantic plugin
    }
    if( j >= w.size() || !std::ranges::contains( kArticles, w[j] ) )
    {
        return std::string::npos;
    }
    const bool newWord = j + 1 < w.size() && w[j + 1] == "new";
    return verb || newWord || w[j] == "another" ? j + 1 : std::string::npos; // need / want only with `a new` or `another`
}

// `another X like Y` with no verb before it: X starts after `another` when a `like` follows within the phrase.
inline std::size_t phraseAfterAnother( const std::vector<std::string>& w, std::size_t i )
{
    if( w[i] != "another" || ( i > 0 && std::ranges::contains( kVerbs, w[i - 1] ) ) )
    {
        return std::string::npos;
    }
    for( std::size_t k = i + 1; k < w.size() && k <= i + kExemplarPhraseWordsMax && !w[k].empty() && w[k] != "."; ++k )
    {
        if( w[k] == "like" )
        {
            return i + 1;
        }
    }
    return std::string::npos;
}

// Append the parts of one phrase word (split on '-', '_', '\''), singular, filler and repeats dropped.
inline void appendPhraseParts( std::string_view word, std::vector<std::string>& words )
{
    for( std::size_t p = 0; p <= word.size(); )
    {
        const std::size_t q = std::min( word.find_first_of( "-_'", p ), word.size() );
        std::string part = singular( std::string( word.substr( p, q - p ) ) );
        if( part.size() >= 2 && !std::ranges::contains( kPhraseFiller, part ) && !std::ranges::contains( words, part ) )
        {
            words.push_back( std::move( part ) );
        }
        p = q + 1;
    }
}

// X read from w[start]: filler skipped, then up to kExemplarPhraseWordsMax words before a stop word, a boundary or a dotted name.
inline std::optional<ExemplarTask> readPhrase( const std::vector<std::string>& w, std::size_t start )
{
    while( start < w.size() && std::ranges::contains( kPhraseFiller, w[start] ) )
    {
        ++start; // `a new`, `my own`: not words of X
    }
    ExemplarTask t;
    for( std::size_t k = start; k < w.size() && k < start + kExemplarPhraseWordsMax; ++k )
    {
        if( w[k].empty() || std::ranges::contains( kPhraseStops, w[k] ) || w[k].find( '.' ) != std::string::npos )
        {
            break; // a dotted name is a model to copy, not a word of X
        }
        t.phrase += ( t.phrase.empty() ? "" : " " ) + w[k];
        appendPhraseParts( w[k], t.words );
    }
    if( t.words.empty() )
    {
        return std::nullopt;
    }
    t.head = t.words.back();
    const bool alpha = std::ranges::all_of( t.head, []( char c )
                                            { return c >= 'a' && c <= 'z'; } );
    if( t.head.size() < 3 || !alpha || std::ranges::contains( kNotFamilyHeads, t.head ) )
    {
        return std::nullopt;
    }
    return t;
}

// `a new X` right after a creation verb's earlier words (add support for a new database (a new dialect)), unless the verb is right before it.
inline bool isBareNew( const std::vector<std::string>& w, std::size_t i, bool verbSeen )
{
    return verbSeen && std::ranges::contains( kArticles, w[i] ) && i + 1 < w.size() && w[i + 1] == "new" && ( i == 0 || !std::ranges::contains( kVerbs, w[i - 1] ) );
}

// The task's content words outside X (3 or more letters, no creation verb or stop word), each split and singular, once each.
inline std::vector<std::string> otherTaskWords( const std::vector<std::string>& w, const ExemplarTask& t )
{
    std::vector<std::string> out;
    for( const std::string& word : w )
    {
        std::vector<std::string> parts;
        appendPhraseParts( word, parts );
        for( std::string& part : parts )
        {
            const bool content = part.size() >= 3 && !std::ranges::contains( kVerbs, part ) && !std::ranges::contains( kPhraseStops, part ) &&
                                 !std::ranges::contains( t.words, part ) && !std::ranges::contains( out, part );
            if( content )
            {
                out.push_back( std::move( part ) );
            }
        }
    }
    return out;
}
} // namespace exemplar_detail

// The add-a-new-X readings of a task, in task order (see WHEN above); empty when it reads as none.
namespace exemplar_detail
{
// One reading of the task at `start`, with the task's other content words (ExemplarTask.others) filled in.
inline std::optional<ExemplarTask> readTaskAt( const std::vector<std::string>& w, std::size_t start )
{
    std::optional<ExemplarTask> t = readPhrase( w, start );
    if( t )
    {
        t->others = otherTaskWords( w, *t );
    }
    return t;
}
} // namespace exemplar_detail

inline std::vector<ExemplarTask> exemplarTasksOf( std::string_view task )
{
    using namespace exemplar_detail;
    std::vector<ExemplarTask> out;
    const std::vector<std::string> w = taskWords( task );
    bool verbSeen = false;
    for( std::size_t i = 0; i < w.size() && out.size() < kExemplarTaskReadings; ++i )
    {
        if( w[i] == "." )
        {
            verbSeen = false; // `Add a field to Foo. A new handler needs wiring`: the verb reaches to the end of its sentence
            continue;
        }
        std::size_t start = isBareNew( w, i, verbSeen ) ? i + 1 : phraseAfterVerb( w, i );
        start = start != std::string::npos ? start : phraseAfterAnother( w, i );
        verbSeen = verbSeen || std::ranges::contains( kVerbs, w[i] );
        if( start == std::string::npos )
        {
            continue;
        }
        std::optional<ExemplarTask> t = readTaskAt( w, start );
        if( t && std::ranges::none_of( out, [&]( const ExemplarTask& o )
                                       { return o.words == t->words; } ) )
        {
            out.push_back( std::move( *t ) );
        }
    }
    return out;
}

namespace exemplar_detail
{
// Does one subtoken of `name` equal `word`, or its plural (`plugins`, `registries`)? No allocation: a lowercase compare per subtoken.
inline bool subtokenIs( std::string_view name, std::string_view word )
{
    bool hit = false;
    forEachLexSubtoken( name, [&]( std::size_t b, std::size_t e )
                        {
        const std::string_view tok = name.substr( b, e - b );
        const auto             eqAt = [ & ]( std::string_view stem, std::string_view tail )
        {
            if( tok.size() != stem.size() + tail.size() )
            {
                return false;
            }
            for( std::size_t k = 0; k < tok.size(); ++k )
            {
                const char want = k < stem.size() ? stem[k] : tail[ k - stem.size() ];
                if( char( lexLowerByte( static_cast<unsigned char>( tok[k] ) ) ) != want )
                {
                    return false;
                }
            }
            return true;
        };
        hit = hit || eqAt( word, "" ) || eqAt( word, "s" ) || ( word.ends_with( 'y' ) && eqAt( word.substr( 0, word.size() - 1 ), "ies" ) ); } );
    return hit;
}

// The last subtoken of a name, lowercased and singular (`kCodecRegistry` → registry; `MeterClass` → class).
inline std::vector<std::string> keyWords( std::string_view name )
{
    std::vector<std::string> out;
    forEachLexSubtoken( name, [&]( std::size_t b, std::size_t e )
                        {
        std::string tok;
        for( std::size_t k = b; k < e; ++k )
        {
            tok.push_back( char( lexLowerByte( static_cast<unsigned char>( name[k] ) ) ) );
        }
        out.push_back( singular( std::move( tok ) ) ); } );
    return out;
}

// Does one subtoken of `name` spell `word`'s plural (`Settings` for setting, `Registries` for registry, `Keys` for key)?
inline bool subtokenIsPlural( std::string_view name, std::string_view word )
{
    const bool consonantY = word.size() >= 2 && word.ends_with( 'y' ) && !std::string_view( "aeiou" ).contains( word[word.size() - 2] );
    const std::string plural = consonantY ? std::string( word.substr( 0, word.size() - 1 ) ) + "ies" : std::string( word ) + "s";
    bool hit = false;
    forEachLexSubtoken( name, [&]( std::size_t b, std::size_t e )
                        {
        const std::string_view tok = name.substr( b, e - b );
        hit = hit || ( tok.size() == plural.size() && std::ranges::equal( tok, plural, []( char x, char y )
                                                                         { return char( lexLowerByte( static_cast<unsigned char>( x ) ) ) == y; } ) ); } );
    return hit;
}

// The words of a holder's name other than X's head and kind words (`ServerSettingsImpl` → server; `SettingsImpl` → none).
inline std::vector<std::string> holderWords( std::string_view name, std::string_view head )
{
    static constexpr std::array<std::string_view, 14> kKind { "impl", "base", "class", "interface", "type", "abstract", "default", "struct",
                                                              "i", "t", "data", "info", "object", "obj" };
    std::vector<std::string> out = keyWords( name );
    std::erase_if( out, [&]( const std::string& w )
                   { return w == head || std::ranges::contains( kKind, w ); } );
    return out;
}

inline bool inScope( std::string_view dir, std::string_view scope ) noexcept
{
    return scope.empty() || dir == scope || ( dir.starts_with( scope ) && dir.size() > scope.size() && dir[scope.size()] == '/' );
}

// The deepest directory holding at least half of the members (and kExemplarFamilyMin): members outside it are dropped.
inline std::string scopeMembers( const IngestResult& ing, std::vector<ExemplarMember>& ms )
{
    std::vector<std::string_view> dirs;
    for( const ExemplarMember& m : ms )
    {
        dirs.push_back( includerDir( rootRelPath( ing, m.fileId ) ) );
    }
    std::ranges::sort( dirs, sortutil::svLess );
    std::vector<std::string_view> anc; // every ancestor of every member's directory
    for( std::string_view d : dirs )
    {
        for( std::string_view a = d;; a = includerDir( a ) )
        {
            anc.push_back( a );
            if( a.empty() )
            {
                break;
            }
        }
    }
    std::ranges::sort( anc, sortutil::svLess );
    anc.erase( std::unique( anc.begin(), anc.end() ), anc.end() );
    const std::size_t need = std::max( kExemplarFamilyMin, ( ms.size() + 1 ) / 2 );
    std::string_view best;
    std::size_t bestDepth = 0;
    for( std::string_view a : anc )
    {
        // the directories under `a` are one contiguous run of the sorted dirs
        std::size_t n = 0;
        for( auto it = std::ranges::lower_bound( dirs, a, sortutil::svLess ); it != dirs.end() && it->starts_with( a ); ++it )
        {
            n += inScope( *it, a ) ? 1 : 0;
        }
        const std::size_t depth = a.empty() ? 0 : std::size_t( std::ranges::count( a, '/' ) ) + 1;
        if( n >= need && depth > bestDepth )
        {
            best = a;
            bestDepth = depth;
        }
    }
    std::string scope( best );
    std::erase_if( ms, [&]( const ExemplarMember& m )
                   { return !inScope( includerDir( rootRelPath( ing, m.fileId ) ), scope ); } );
    return scope;
}

// The task words found in the family's key name and its scope path; `headIn`: the head word is one of them; `words`: those words.
inline std::size_t matchedWords( const ExemplarTask& t, std::string_view keyName, std::string_view scope, bool& headIn, std::string& words )
{
    std::size_t n = 0;
    headIn = false;
    words.clear();
    for( const std::string& w : t.words )
    {
        bool hit = subtokenIs( keyName, w );
        for( std::size_t p = 0; !hit && p <= scope.size(); )
        {
            const std::size_t q = std::min( scope.find( '/', p ), scope.size() );
            hit = subtokenIs( scope.substr( p, q - p ), w );
            p = q + 1;
        }
        n += hit ? 1 : 0;
        words += hit ? ( words.empty() ? "" : " " ) + w : std::string();
        headIn = headIn || ( hit && w == t.head );
    }
    return n;
}

// The key names X itself: its last word is the head (`Dialect`, `#[function]`), or the head and a kind or registry word
// (`MeterClass`, `RouterBase`, `kCodecRegistry`).
inline bool keyNamesHead( const ExemplarTask& t, std::string_view key )
{
    static constexpr std::array<std::string_view, 12> kKindWords { "class", "base", "interface", "trait", "type", "impl", "kind", "registry", "factory", "table", "map", "list" };
    const std::vector<std::string> kw = keyWords( key );
    if( kw.empty() )
    {
        return false;
    }
    return kw.back() == t.head || ( kw.size() >= 2 && std::ranges::contains( kKindWords, kw.back() ) && kw[kw.size() - 2] == t.head );
}

// The higher score first; the cascade order (a)..(e) breaks a tie, then the larger family, then the key (a total order).
inline bool familyBetter( const ExemplarFamily& a, const ExemplarFamily& b )
{
    return std::tuple( b.score, a.rule, b.members.size(), std::string_view( a.key ) ) < std::tuple( a.score, b.rule, a.members.size(), std::string_view( b.key ) );
}

// Test code is no member: a test path (filter.h isTestPath), an in-file test scope, or a test-helper directory (`testing/`, `fake/`,
// `mocks/`: kubernetes' pkg/scheduler/testing/framework holds fake plugins, not plugins to copy), or a sample / example / benchmark
// directory (nest's sample/ copies of a pipe, hono's benchmarks/ routers: a demo of the family, not a member).
inline bool memberEligible( const IngestResult& ing, const Symbol& s ) noexcept
{
    static constexpr std::array<std::string_view, 18> kHelperDirs { "testing", "testutil", "testutils", "fake", "fakes", "mock", "mocks", "testdata", "fixtures", "e2e",
                                                                    "sample", "samples", "example", "examples", "benchmark", "benchmarks", "bench", "benches" }; // demo and benchmark copies are no sibling to follow
    const std::string_view path = rootRelPath( ing, s.fileId );
    if( isTestPath( path ) || s.testScope )
    {
        return false;
    }
    for( std::size_t p = 0; p < path.size(); )
    {
        const std::size_t q = std::min( path.find( '/', p ), path.size() );
        if( q < path.size() && std::ranges::contains( kHelperDirs, path.substr( p, q - p ) ) )
        {
            return false;
        }
        p = q + 1;
    }
    return true;
}

// Typical first: nearest the family's median size, then name, then place (a total order).
inline void orderTypical( const IngestResult& ing, std::vector<ExemplarMember>& ms )
{
    std::vector<std::uint32_t> locs;
    for( const ExemplarMember& m : ms )
    {
        locs.push_back( m.loc );
    }
    std::ranges::sort( locs );
    const std::uint32_t median = locs.empty() ? 0 : locs[( locs.size() - 1 ) / 2];
    const auto gap = [&]( const ExemplarMember& m )
    { return m.loc > median ? m.loc - median : median - m.loc; };
    std::ranges::sort( ms, [&]( const ExemplarMember& a, const ExemplarMember& b )
                       { return std::tuple( gap( a ), std::string_view( a.name ), rootRelPath( ing, a.fileId ), a.line ) < std::tuple( gap( b ), std::string_view( b.name ), rootRelPath( ing, b.fileId ), b.line ); } );
}

// The bytes of the file being read. Every scan walks the symbols in id order, and a file's symbols are contiguous there, so
// one slot reads each file once per scan (a lookup is O(1), not a search over the files read so far).
struct FamilyFileText
{
    const IngestResult& ing;
    std::uint32_t fileId = UINT32_MAX;
    std::string bytes;
    std::uint32_t unread = 0; // files the scan could not read: their registries and decorators are not in the answer (disclosed as unread=)
    const std::string& text( std::uint32_t f )
    {
        if( f != fileId )
        {
            fileId = f;
            std::optional<std::string> read = docparse::detail::readWholeFile( diskPath( ing, f ) );
            unread += read ? 0 : 1;
            bytes = std::move( read ).value_or( std::string() );
        }
        return bytes;
    }
};

inline std::string_view symbolText( FamilyFileText& fc, const Symbol& s )
{
    const std::string& t = fc.text( s.fileId );
    if( s.sigStartByte >= t.size() || s.endByte <= s.sigStartByte )
    {
        return {};
    }
    return std::string_view( t ).substr( s.sigStartByte, std::min<std::size_t>( s.endByte, t.size() ) - s.sigStartByte );
}

// The identifier run ending at `e` (exclusive) after trailing non-identifier bytes are skipped: `names.NodeAffinity` → NodeAffinity.
inline std::string_view lastIdent( std::string_view k ) noexcept
{
    const auto runEnd = std::find_if( k.rbegin(), k.rend(), isIdentChar );
    const auto runStart = std::find_if_not( runEnd, k.rend(), isIdentChar );
    return k.substr( std::size_t( k.rend() - runStart ), std::size_t( runStart - runEnd ) );
}

// The first identifier run: `dynamicresources.Name` → dynamicresources.
inline std::string_view firstIdent( std::string_view k ) noexcept
{
    const auto b = std::ranges::find_if( k, isIdentChar );
    const auto e = std::find_if_not( b, k.end(), isIdentChar );
    return k.substr( std::size_t( b - k.begin() ), std::size_t( e - b ) );
}

// A key expression as written, trimmed and unquoted: `names.NodeAffinity`, `gzip`, `Kind::Foo`.
inline std::string_view keyExpr( std::string_view k ) noexcept
{
    return stripQuotePair( trimWs( k ) );
}

// Each entry's name: the key's last segment, or its first when the last segments repeat (`dynamicresources.Name`,
// `imagelocality.Name`: the package names the entry, `Name` does not).
inline void nameRegistryEntries( std::vector<ExemplarMember>& ms )
{
    std::vector<std::string_view> last;
    for( const ExemplarMember& m : ms )
    {
        last.push_back( lastIdent( m.name ) );
    }
    std::ranges::sort( last, sortutil::svLess );
    const std::size_t distinct = std::size_t( std::unique( last.begin(), last.end() ) - last.begin() );
    const bool byFirst = distinct * 2 < ms.size();
    for( ExemplarMember& m : ms )
    {
        m.name = std::string( byFirst ? firstIdent( m.name ) : lastIdent( m.name ) );
    }
    std::erase_if( ms, []( const ExemplarMember& m )
                   { return m.name.size() < 2; } );
}

// A registry value: an expression, not a block or a long statement.
inline bool registryValueOk( std::string_view v ) noexcept
{
    v = trimWs( v );
    while( !v.empty() && std::string_view( ",;}) " ).find( v.back() ) != std::string_view::npos )
    {
        v.remove_suffix( 1 );
    }
    return !v.empty() && v.size() <= 160 && ( isIdentChar( v.front() ) || std::string_view( "&\"'[{(<:" ).find( v.front() ) != std::string_view::npos );
}

// `{ key, value },` (a C / C++ initializer row)
inline std::string_view braceEntryKey( std::string_view line ) noexcept
{
    const std::size_t comma = line.find( ',' );
    if( !line.starts_with( '{' ) || comma == std::string_view::npos || line.find( '}' ) == std::string_view::npos )
    {
        return {};
    }
    return registryValueOk( line.substr( comma + 1 ) ) ? keyExpr( line.substr( 1, comma - 1 ) ) : std::string_view();
}

// `key => value,` (PHP / Ruby hash, a Rust match arm)
inline std::string_view arrowEntryKey( std::string_view line ) noexcept
{
    const std::size_t arrow = line.find( "=>" );
    if( arrow == std::string_view::npos || arrow == 0 )
    {
        return {};
    }
    const std::string_view k = line.substr( 0, arrow );
    return k.find_first_of( "(=" ) == std::string_view::npos && registryValueOk( line.substr( arrow + 2 ) ) ? keyExpr( k ) : std::string_view();
}

// `m[key] = value;`: a name before the bracket (a C designated initializer `[K] = v` is an indexed array, not a registry) and no
// declaration that opens an initializer (`static const int X[N] = {`)
inline std::string_view indexEntryKey( std::string_view line ) noexcept
{
    const std::size_t br = line.find( '[' );
    const std::size_t eq = line.find( "] =" );
    const bool ok = br != std::string_view::npos && eq != std::string_view::npos && br > 0 && br < eq && isIdentChar( line[br - 1] ) && line.find( "==" ) == std::string_view::npos && !line.ends_with( '{' );
    return ok && registryValueOk( line.substr( eq + 3 ) ) ? keyExpr( line.substr( br + 1, eq - br - 1 ) ) : std::string_view();
}

// `key: value,` — the key a (dotted) name or a quoted string, the colon not `::`, and the line ends with a comma
inline std::string_view colonEntryKey( std::string_view line ) noexcept
{
    if( !line.ends_with( ',' ) )
    {
        return {};
    }
    for( std::size_t i = 0; i < line.size(); ++i )
    {
        const char c = line[i];
        if( c == ':' && i + 1 < line.size() && line[i + 1] == ':' )
        {
            ++i; // a scope `::` is part of the key
        }
        else if( c == ':' )
        {
            return i > 0 && registryValueOk( line.substr( i + 1 ) ) ? keyExpr( line.substr( 0, i ) ) : std::string_view();
        }
        else if( c == '"' || c == '\'' )
        {
            i = line.find( c, i + 1 ); // a quoted key: its colons are text
            if( i == std::string_view::npos )
            {
                return {};
            }
        }
        else if( !isIdentChar( c ) && c != '.' && c != ' ' )
        {
            return {};
        }
    }
    return {};
}

// One registry entry line, or "" (the four shapes above; a comment line is none).
inline std::string_view registryEntryKey( std::string_view line ) noexcept
{
    line = trimWs( line );
    if( line.empty() || line.starts_with( "//" ) || line.starts_with( '#' ) || line.starts_with( '*' ) || line.starts_with( "/*" ) )
    {
        return {};
    }
    if( line.starts_with( '{' ) )
    {
        return braceEntryKey( line );
    }
    const std::string_view arrow = arrowEntryKey( line );
    if( !arrow.empty() )
    {
        return arrow;
    }
    const std::string_view index = indexEntryKey( line );
    return !index.empty() ? index : colonEntryKey( line );
}

inline constexpr std::array<std::string_view, 12> kRegistryNameWords { "registry", "factory", "table", "map", "handler", "builtin", "plugin",
                                                                       "provider", "default", "all", "dispatch", "lookup" };

// The type a C/C++ instance definition names: `static const MeterClass CpuMeter_class = {` → MeterClass ("" when not that shape).
inline std::string_view instanceTypeOf( std::string_view sig, std::string_view name ) noexcept
{
    static constexpr std::array<std::string_view, 7> kNotType { "const", "static", "int", "char", "auto", "unsigned", "" };
    const std::size_t eq = sig.find( '=' );
    std::string_view head = trimWs( sig.substr( 0, eq == std::string_view::npos ? 0 : eq ) );
    if( eq == std::string_view::npos || !head.ends_with( name ) )
    {
        return {};
    }
    head = trimWs( head.substr( 0, head.size() - name.size() ) );
    const std::string_view type = lastIdent( head );
    return std::ranges::contains( kNotType, type ) ? std::string_view() : type;
}

// An attribute line's name: `#[function("..")]` → function, `@register_handler(..)` → register_handler ("" otherwise).
inline std::string_view attributeNameOf( std::string_view line ) noexcept
{
    line = trimWs( line );
    const std::size_t b = line.starts_with( "#[" ) ? 2 : line.starts_with( '@' ) ? 1
                                                                                 : 0;
    if( b == 0 )
    {
        return {};
    }
    std::size_t e = b;
    while( e < line.size() && ( isIdentChar( line[e] ) || line[e] == ':' || line[e] == '.' ) )
    {
        ++e;
    }
    return lastIdent( line.substr( b, e - b ) );
}

// The name an attribute registers: the leading identifier of its first string argument (`#[function("upper(varchar)")]` → upper).
inline std::string_view attributeArgName( std::string_view line ) noexcept
{
    const std::size_t q = line.find_first_of( "\"'" ); // `@register("name")` and `@register('name')`
    if( q == std::string_view::npos )
    {
        return {};
    }
    const std::string_view rest = line.substr( q + 1 );
    return rest.substr( 0, std::size_t( std::ranges::find_if_not( rest, isIdentChar ) - rest.begin() ) );
}

inline constexpr std::array<Lang, 7> kAttributeLangs { Lang::Rust, Lang::Python, Lang::TypeScript, Lang::JavaScript, Lang::Java, Lang::Kotlin, Lang::CSharp };

// A family of holders of X (most member names carry its plural) where the task picks ONE holder by a word of X or of the task: the
// pick settleInto makes (a tie between two holders is no pick, and earns no bonus). Defined below holderByWord.
inline bool holderNamedByTask( const ExemplarTask& t, const ExemplarFamily& fam );

// A candidate family: scoped, scored and kept when it beats the best so far.
inline void consider( const IngestResult& ing, const ExemplarTask& t, std::optional<ExemplarFamily>& best, ExemplarFamily fam )
{
    if( fam.members.size() < kExemplarFamilyMin )
    {
        return;
    }
    fam.scope = scopeMembers( ing, fam.members );
    bool headIn = false;
    fam.score = matchedWords( t, fam.key, fam.scope, headIn, fam.matched ) + ( fam.rule != ExemplarRule::Affix && keyNamesHead( t, fam.key ) ? 1 : 0 ); // an affix key is the head by construction
    fam.score += holderNamedByTask( t, fam ) ? 1 : 0; // E3a-INTO: holders of X, one named by a word of the task (`option for the compiler`)
    if( fam.members.size() >= kExemplarFamilyMin && headIn && ( !best || familyBetter( fam, *best ) ) )
    {
        best = std::move( fam );
    }
}

// (a) base: the implementors of one base / interface / trait whose name holds the head word
inline void familiesByBase( const IngestResult& ing, const Graph& g, const ExemplarTask& t, std::optional<ExemplarFamily>& best )
{
    for( std::size_t b = 0; b < g.implementors.size() && b < ing.symbols.size(); ++b )
    {
        const Symbol& base = ing.symbols[b];
        if( g.implementors[b].size() < kExemplarFamilyMin || !subtokenIs( base.name, t.head ) )
        {
            continue;
        }
        ExemplarFamily fam { .rule = ExemplarRule::Base, .key = base.name, .keyFile = base.fileId, .keyLine = base.line, .keyAt = true };
        for( const NodeId d : g.implementors[b] )
        {
            if( d < ing.symbols.size() && memberEligible( ing, ing.symbols[d] ) )
            {
                fam.add( ing.symbols[d] );
            }
        }
        consider( ing, t, best, std::move( fam ) );
    }
}

// The text a registry is read from, and the byte its entries start at. A function's parameter list is no registry: entries are read from
// the body (sigEndByte) on, so the `timeout: int,` lines of a typed signature (TypeScript, typed Python) are not entries; the signature
// lines still count as lines of the function (a function that is mostly a struct literal is not a registry). A variable is read whole.
inline std::string_view registryText( FamilyFileText& fc, const Symbol& s, std::size_t& bodyAt )
{
    const std::string_view all = symbolText( fc, s );
    bodyAt = 0;
    if( s.kind == SymKind::Function && !all.empty() && s.sigEndByte > s.sigStartByte && s.sigEndByte < s.endByte )
    {
        bodyAt = std::min<std::size_t>( s.sigEndByte - s.sigStartByte, all.size() );
    }
    return all;
}

// The part of the line text[p, nl) from the body on (empty for a signature line, which holds no entry).
inline std::string_view bodyPart( std::string_view text, std::size_t p, std::size_t nl, std::size_t bodyAt ) noexcept
{
    const std::size_t from = std::max( p, bodyAt );
    return from >= nl ? std::string_view() : text.substr( from, nl - from );
}

// The registry family a variable or function's body holds, when its entries are at least half its non-blank lines.
// `bodyAt`: entries are read from this byte of `text` on. `structNames` (sorted): a block opened by `Name{` where Name is a struct is a
// struct literal — its `field: value,` lines are field inits, not registry entries (kubernetes' `return Features{ EnableX: ..., }`
// beside the plugin registry).
inline std::optional<ExemplarFamily> registryOf( const Symbol& s, std::string_view text, std::size_t bodyAt, const std::vector<std::string_view>& structNames )
{
    std::string_view opener; // the last line opening a block before the first entry
    ExemplarFamily fam { .rule = ExemplarRule::Registry, .key = s.name, .keyFile = s.fileId, .keyLine = s.line, .keyAt = true };
    std::size_t lines = 0;
    std::uint32_t ln = s.line;
    for( std::size_t p = 0; p < text.size(); ++ln )
    {
        const std::size_t nl = std::min( text.find( '\n', p ), text.size() );
        const std::string_view whole = text.substr( p, nl - p );
        lines += trimWs( whole ).empty() ? 0 : 1;
        const std::string_view line = bodyPart( text, p, nl, bodyAt );
        const std::string_view k = registryEntryKey( line );
        if( k.empty() && fam.members.empty() && trimWs( line ).ends_with( '{' ) )
        {
            opener = trimWs( line );
        }
        if( k.size() >= 2 && std::ranges::none_of( fam.members, [&]( const ExemplarMember& m )
                                                   { return m.name == k; } ) )
        {
            fam.members.push_back( ExemplarMember { std::string( k ), s.fileId, ln, 0, {}, kNoNode } );
        }
        p = nl + 1;
    }
    if( fam.members.empty() || fam.members.size() * 2 < lines )
    {
        return std::nullopt; // a function that merely contains a map literal is not a registry
    }
    const std::string_view openerType = lastIdent( opener.substr( 0, opener.size() - ( opener.empty() ? 0 : 1 ) ) );
    if( !openerType.empty() && std::ranges::binary_search( structNames, openerType, sortutil::svLess ) )
    {
        return std::nullopt;
    }
    nameRegistryEntries( fam.members );
    return fam;
}

// A variable or function whose name holds a word of the task or a registry word is read as a registry candidate.
inline bool registryNamed( const ExemplarTask& t, std::string_view name )
{
    return std::ranges::any_of( t.words, [&]( const std::string& w )
                                { return subtokenIs( name, w ); } ) ||
           std::ranges::any_of( kRegistryNameWords, [&]( std::string_view w )
                                { return subtokenIs( name, w ); } );
}

// What the files say, read ONCE for every reading of the task (HOISTING: the readings of one task differ only in the words they filter
// by, so the symbols and the file text are walked one time, not once per reading; each rule below filters this by its reading).
struct ExemplarScan
{
    std::vector<std::pair<NodeId, ExemplarFamily>> registries; // (variable or function, its entries): the candidates named by some reading
    std::vector<std::pair<std::string, NodeId>> typed; // (type, instance) of C / C++ instances whose type holds some reading's head
    std::vector<std::tuple<std::string, NodeId, std::string>> attr; // (attribute, item, registered name) whose attribute holds some head
    std::uint32_t unread = 0; // files of the scan that could not be read
    std::uint32_t oversized = 0; // registry candidates (named for a reading or a registry word) over kExemplarBodyScanMaxLoc, not read
};

// One file's attribute lines: the item an attribute line decorates is the first definition on or after it (`syms`: the file's symbols).
inline void scanAttributeLines( const IngestResult& ing, std::span<const Symbol> syms, std::string_view txt, std::span<const ExemplarTask> readings, ExemplarScan& out )
{
    std::size_t symAt = 0;
    std::uint32_t ln = 1;
    for( std::size_t p = 0; p < txt.size(); ++ln )
    {
        const std::size_t nl = std::min( txt.find( '\n', p ), txt.size() );
        const std::string_view line = txt.substr( p, nl - p );
        const std::string_view a = attributeNameOf( line );
        p = nl + 1;
        if( a.empty() )
        {
            continue;
        }
        while( symAt < syms.size() && syms[symAt].line < ln )
        {
            ++symAt; // a definition on the attribute's own line (`#[function("x")] fn x() {}`) is the item it decorates
        }
        // the head is matched by subtoken, so `@Widget()` holds the head `widget` (no case-sensitive text prefilter)
        if( symAt < syms.size() && memberEligible( ing, syms[symAt] ) && std::ranges::any_of( readings, [&]( const ExemplarTask& r )
                                                                                              { return subtokenIs( a, r.head ); } ) )
        {
            out.attr.emplace_back( std::string( a ), syms[symAt].id, std::string( attributeArgName( line ) ) );
        }
    }
}

// One variable or function symbol of the scan: a C / C++ typed instance and / or a registry candidate (see ExemplarScan).
inline void scanSymbol( FamilyFileText& fc, const std::vector<std::string_view>& structNames, std::span<const ExemplarTask> readings, const Symbol& s, ExemplarScan& out )
{
    const IngestResult& ing = fc.ing;
    const bool candidate = ( s.kind == SymKind::Var || s.kind == SymKind::Function ) && s.loc >= 2;
    if( !candidate || !memberEligible( ing, s ) )
    {
        return;
    }
    const bool named = std::ranges::any_of( readings, [&]( const ExemplarTask& r )
                                            { return registryNamed( r, s.name ); } );
    if( s.loc > kExemplarBodyScanMaxLoc )
    {
        out.oversized += std::uint32_t( named ); // skipped, and said so (oversized=): it may be the one registry the task means
        return;
    }
    if( s.kind == SymKind::Var && langFacts( s.lang ).typedInstanceRows )
    {
        const std::string_view text = symbolText( fc, s );
        const std::string_view type = instanceTypeOf( text.substr( 0, text.find( '\n' ) ), s.name );
        if( !type.empty() && std::ranges::any_of( readings, [&]( const ExemplarTask& r )
                                                  { return subtokenIs( type, r.head ); } ) )
        {
            out.typed.emplace_back( std::string( type ), s.id );
        }
    }
    if( s.loc <= kExemplarFamilyMin || !named )
    {
        return;
    }
    std::size_t bodyAt = 0;
    const std::string_view text = registryText( fc, s, bodyAt );
    if( std::optional<ExemplarFamily> fam = registryOf( s, text, bodyAt, structNames ); fam && fam->members.size() >= kExemplarFamilyMin )
    {
        out.registries.emplace_back( s.id, std::move( *fam ) );
    }
}

// One pass over the files and symbols for every reading: registry candidates, typed instances and attribute lines.
inline ExemplarScan scanExemplarFiles( const IngestResult& ing, std::span<const ExemplarTask> readings )
{
    ExemplarScan out;
    FamilyFileText fc { ing };
    std::vector<std::string_view> structNames;
    for( const Symbol& s : ing.symbols )
    {
        if( s.kind == SymKind::Struct )
        {
            structNames.push_back( s.name );
        }
    }
    std::ranges::sort( structNames, sortutil::svLess );
    for( std::size_t i = 0; i < ing.symbols.size(); )
    {
        const std::uint32_t f = ing.symbols[i].fileId;
        std::size_t end = i; // the file's symbols are contiguous and line-ordered
        while( end < ing.symbols.size() && ing.symbols[end].fileId == f )
        {
            ++end;
        }
        const std::span<const Symbol> syms( ing.symbols.data() + i, end - i );
        for( const Symbol& s : syms )
        {
            scanSymbol( fc, structNames, readings, s, out );
        }
        if( std::ranges::contains( kAttributeLangs, syms.front().lang ) && !isTestPath( rootRelPath( ing, f ) ) )
        {
            scanAttributeLines( ing, syms, fc.text( f ), readings, out );
        }
        i = end;
    }
    out.unread = fc.unread;
    return out;
}

// (b) registry: the candidates of the scan whose name holds a task word or a registry word
inline void familiesByRegistry( const IngestResult& ing, const ExemplarScan& scan, const ExemplarTask& t, std::optional<ExemplarFamily>& best )
{
    for( const auto& [sym, fam] : scan.registries )
    {
        if( registryNamed( t, ing.symbols[sym].name ) )
        {
            consider( ing, t, best, ExemplarFamily( fam ) );
        }
    }
}

// (c) typed: C / C++ instances grouped by the struct type they name, when the type holds the head word
inline void familiesByTyped( const IngestResult& ing, const ExemplarScan& scan, const ExemplarTask& t, std::optional<ExemplarFamily>& best )
{
    std::vector<std::pair<std::string, NodeId>> typed; // (type, instance)
    std::ranges::copy_if( scan.typed, std::back_inserter( typed ), [&]( const auto& x )
                          { return subtokenIs( x.first, t.head ); } );
    std::ranges::sort( typed );
    for( auto run = typed.begin(); run != typed.end(); )
    {
        const auto end = std::find_if( run, typed.end(), [&]( const auto& x )
                                       { return x.first != run->first; } );
        ExemplarFamily fam { .rule = ExemplarRule::Typed, .key = run->first };
        for( auto it = run; it != end; ++it )
        {
            fam.add( ing.symbols[it->second] );
        }
        consider( ing, t, best, std::move( fam ) );
        run = end;
    }
}

// (d) attribute: items under one attribute macro / decorator whose name holds the head word; the item is the next definition
inline void familiesByAttribute( const IngestResult& ing, const ExemplarScan& scan, const ExemplarTask& t, std::optional<ExemplarFamily>& best )
{
    auto attr = std::vector<std::tuple<std::string, NodeId, std::string>>(); // (attribute, item, registered name)
    std::ranges::copy_if( scan.attr, std::back_inserter( attr ), [&]( const auto& x )
                          { return subtokenIs( std::get<0>( x ), t.head ); } );
    std::ranges::sort( attr ); // one member per item: an item under several attributes keeps its first registered name
    const auto sameItem = []( const auto& x, const auto& y )
    { return std::get<0>( x ) == std::get<0>( y ) && std::get<1>( x ) == std::get<1>( y ); };
    attr.erase( std::unique( attr.begin(), attr.end(), sameItem ), attr.end() );
    for( auto run = attr.begin(); run != attr.end(); )
    {
        const auto end = std::find_if( run, attr.end(), [&]( const auto& x )
                                       { return std::get<0>( x ) != std::get<0>( *run ); } );
        ExemplarFamily fam { .rule = ExemplarRule::Attribute, .key = std::get<0>( *run ) };
        for( auto it = run; it != end; ++it )
        {
            fam.add( ing.symbols[std::get<1>( *it )] );
            fam.members.back().alt = std::get<2>( *it );
        }
        consider( ing, t, best, std::move( fam ) );
        run = end;
    }
}

// An affix family is names alone, so it needs more than names: members in at least kExemplarFamilyMin different files (one file full
// of `*Options` interfaces is a type list, not siblings to copy), and not only in `.d.ts` declaration files (typescript's lib/*.d.ts).
inline bool affixHasFiles( const IngestResult& ing, const ExemplarFamily& fam )
{
    std::vector<std::uint32_t> files;
    bool code = false;
    for( const ExemplarMember& m : fam.members )
    {
        files.push_back( m.fileId );
        code = code || !rootRelPath( ing, m.fileId ).ends_with( ".d.ts" );
    }
    std::ranges::sort( files );
    return code && std::ranges::unique( files ).begin() - files.begin() >= std::ptrdiff_t( kExemplarFamilyMin );
}

// The class-kind symbols whose name ends with the head word, each with its directory, sorted by directory.
inline std::vector<std::pair<std::string_view, NodeId>> affixCandidates( const IngestResult& ing, const ExemplarTask& t )
{
    std::vector<std::pair<std::string_view, NodeId>> byDir;
    for( const Symbol& s : ing.symbols )
    {
        const bool kind = s.kind == SymKind::Class || s.kind == SymKind::Struct || s.kind == SymKind::Interface;
        if( kind && memberEligible( ing, s ) )
        {
            const std::vector<std::string> kw = keyWords( s.name );
            if( kw.size() >= 2 && kw.back() == t.head )
            {
                byDir.emplace_back( includerDir( rootRelPath( ing, s.fileId ) ), s.id );
            }
        }
    }
    std::ranges::sort( byDir, []( const auto& a, const auto& b )
                       { return sortutil::svLess( a.first, b.first ) || ( a.first == b.first && a.second < b.second ); } );
    return byDir;
}

// (e) affix: classes in one directory whose names end with the head word (a function name ending in the head is a
// verb phrase, not a sibling: tmux `cmd_*_command`, helix `execute_command`, the TypeScript `getSyntaxKind`)
inline void familiesByAffix( const IngestResult& ing, const ExemplarTask& t, std::optional<ExemplarFamily>& best )
{
    const std::vector<std::pair<std::string_view, NodeId>> byDir = affixCandidates( ing, t );
    for( auto run = byDir.begin(); run != byDir.end(); )
    {
        const auto end = std::find_if( run, byDir.end(), [&]( const auto& x )
                                       { return x.first != run->first; } );
        ExemplarFamily fam { .rule = ExemplarRule::Affix, .key = t.head };
        for( auto it = run; it != end; ++it )
        {
            const Symbol& s = ing.symbols[it->second];
            if( std::ranges::none_of( fam.members, [&]( const ExemplarMember& m )
                                      { return m.name == s.name; } ) )
            {
                fam.add( s );
            }
        }
        if( affixHasFiles( ing, fam ) )
        {
            consider( ing, t, best, std::move( fam ) );
        }
        run = end;
    }
}
} // namespace exemplar_detail

// The family of the task's X, or nothing: no rule yields 3 or more members whose key holds the head word. `scan`: the files read once
// for every reading of the task (scanExemplarFiles).
inline std::optional<ExemplarFamily> exemplarFamily( const IngestResult& ing, const Graph& g, const ExemplarTask& t, const exemplar_detail::ExemplarScan& scan )
{
    using namespace exemplar_detail;
    std::optional<ExemplarFamily> best;
    familiesByBase( ing, g, t, best );
    familiesByRegistry( ing, scan, t, best );
    familiesByTyped( ing, scan, t, best );
    familiesByAttribute( ing, scan, t, best );
    familiesByAffix( ing, t, best );
    if( best && best->rule != ExemplarRule::Registry )
    {
        orderTypical( ing, best->members ); // registry entries keep their listing order: they have no size of their own
    }
    return best;
}

// ── E3a-INTO: a family of HOLDERS of X ─────────────────────────────────────────────────────────────────────────────────────────
// A member whose name carries the head word in its PLURAL form (`ServerSettingsImpl` for `setting`, `CompilerOptions` for `option`)
// holds X's; when most members do, the family is one of holders, and a new X goes into ONE of them. Which one: the holder whose
// name carries a word of X (`compiler option` → CompilerOptions), else a word of the task outside X, else the one holder whose name
// carries no other word than X's and a kind word (`SettingsImpl` beside ServerSettingsImpl and MergeTreeSettingsImpl: the general
// one, for `a query-level setting`, which no holder is named for). No such holder, or two that tie: the block is withheld (the other
// holders are other scopes, never siblings to copy). The rows of the picked holder are its existing X's: the largest X-macro list in its
// file (C, C++), its field definitions, or its `name: type` / `name?: type` property lines at the top of its body (TS, JS).
namespace exemplar_detail
{
// The words of the task a holder name is matched by: X's words but the head, or (`also`) the task's other content words.
inline std::vector<std::string> intoWords( const ExemplarTask& t, bool also )
{
    if( also )
    {
        return t.others;
    }
    std::vector<std::string> out;
    std::ranges::copy_if( t.words, std::back_inserter( out ), [&]( const std::string& w )
                          { return w != t.head; } );
    return out;
}

// Is this a family of holders of X (most member names carry its plural)?
inline bool isHolderFamily( const ExemplarTask& t, const ExemplarFamily& fam )
{
    const std::size_t holders = std::size_t( std::ranges::count_if( fam.members, [&]( const ExemplarMember& m )
                                                                   { return subtokenIsPlural( m.name, t.head ); } ) );
    return holders * 2 > fam.members.size();
}

// Each member's holder words (holderWords), in member order; none for a member that is not a holder (its name does not carry X's
// plural: `CompilerOption` beside `ServerOptions` is an X, never the holder a task word picks).
inline std::vector<std::vector<std::string>> holderWordsOf( const ExemplarTask& t, const ExemplarFamily& fam )
{
    std::vector<std::vector<std::string>> hw( fam.members.size() );
    std::ranges::transform( fam.members, hw.begin(), [&]( const ExemplarMember& m )
                            { return subtokenIsPlural( m.name, t.head ) ? holderWords( m.name, t.head ) : std::vector<std::string>(); } );
    return hw;
}

// The holder whose name carries one of `words` (the most of them, then the fewest other words; a tie between two holders is no
// pick): its index, or SIZE_MAX. A tie and no match are both SIZE_MAX on purpose: a word that names several holders equally (`query`
// for QueryPlanSettings and QueryTreeSettings) names none of them, so the caller goes on to the task's other words and then to the
// general (bare) holder, the measured home of `a query-level setting`. Two members of ONE name (a declaration and its .d.ts copy)
// are one holder, not a tie.
inline std::size_t holderByWord( const ExemplarFamily& fam, const std::vector<std::vector<std::string>>& hw, const std::vector<std::string>& words, std::string& word )
{
    std::size_t best = SIZE_MAX, bestHits = 0;
    bool tie = false;
    for( std::size_t m = 0; m < fam.members.size(); ++m )
    {
        std::size_t hits = 0;
        std::string first;
        for( const std::string& w : words )
        {
            if( std::ranges::contains( hw[m], w ) )
            {
                first = first.empty() ? w : first;
                ++hits;
            }
        }
        // more task words first, then fewer other words (`CompilerOptions` before `WatchCompilerHostOfFilesAndCompilerOptions`)
        const bool better = hits > bestHits || ( hits > 0 && hits == bestHits && hw[m].size() < hw[best].size() );
        if( better )
        {
            best = m;
            bestHits = hits;
            word = first;
            tie = false;
        }
        else if( hits > 0 && hits == bestHits && hw[m].size() == hw[best].size() && fam.members[m].name != fam.members[best].name )
        {
            tie = true;
        }
    }
    return tie ? SIZE_MAX : best;
}

inline bool holderNamedByTask( const ExemplarTask& t, const ExemplarFamily& fam )
{
    if( !isHolderFamily( t, fam ) )
    {
        return false;
    }
    const std::vector<std::vector<std::string>> hw = holderWordsOf( t, fam );
    std::string word;
    return holderByWord( fam, hw, intoWords( t, false ), word ) != SIZE_MAX || holderByWord( fam, hw, intoWords( t, true ), word ) != SIZE_MAX;
}

// One `P(..)` line of an X-macro list: its line and its leading arguments.
struct MacroRow
{
    std::uint32_t line;
    std::vector<std::string_view> args;
};

inline bool macroRowIdent( std::string_view v )
{
    return !v.empty() && !( v[0] >= '0' && v[0] <= '9' ) && std::ranges::all_of( v, isIdentChar );
}

// The argument position that names a list's rows: the one with the most distinct identifier values, kExemplarFamilyMin or more.
// SIZE_MAX when no position has that many, or two positions tie (a type column whose values are all distinct beside the name column:
// which one names the rows is not known, so the list claims none).
inline std::size_t macroNameColumn( const std::vector<MacroRow>& rows )
{
    std::size_t pos = SIZE_MAX, posDistinct = 0;
    bool tie = false;
    for( std::size_t k = 0; k < 8; ++k )
    {
        std::vector<std::string_view> vals;
        for( const MacroRow& r : rows )
        {
            if( k < r.args.size() && macroRowIdent( r.args[k] ) )
            {
                vals.push_back( r.args[k] );
            }
        }
        std::ranges::sort( vals, sortutil::svLess );
        const std::size_t distinct = std::size_t( std::unique( vals.begin(), vals.end() ) - vals.begin() );
        if( distinct > posDistinct )
        {
            pos = k;
            posDistinct = distinct;
            tie = false;
        }
        else if( distinct > 0 && distinct == posDistinct )
        {
            tie = true;
        }
    }
    return posDistinct >= kExemplarFamilyMin && !tie ? pos : SIZE_MAX;
}

// The terminator of a C / C++ raw-string literal (`)delim"`) or block comment (`*/`) that `s` leaves open, or "". Ordinary string and
// character literals and a `//` comment are skipped, so an `R"(` or `/*` inside them opens nothing.
inline std::string openSpanAfter( std::string_view s )
{
    for( std::size_t i = 0; i < s.size(); )
    {
        const char ch = s[i];
        if( s.substr( i, 2 ) == "//" )
        {
            break;
        }
        static constexpr std::array<std::string_view, 5> kRawPrefix { "R", "u8R", "uR", "UR", "LR" };
        const std::size_t pre = ch == '"' ? s.substr( 0, i ).find_last_not_of( "RuUL8" ) : 0; // the prefix run before a quote
        const std::size_t from = pre == std::string_view::npos ? 0 : pre + 1;
        const bool raw = ch == '"' && std::ranges::contains( kRawPrefix, s.substr( from, i - from ) ) && ( from == 0 || !isIdentChar( s[from - 1] ) );
        const std::size_t paren = raw ? s.find( '(', i ) : std::string_view::npos;
        const bool comment = s.substr( i, 2 ) == "/*";
        if( comment || ( paren != std::string_view::npos && paren - i <= 17 ) )
        {
            const std::string term = comment ? std::string( "*/" ) : ")" + std::string( s.substr( i + 1, paren - i - 1 ) ) + "\"";
            const std::size_t c = s.find( term, comment ? i + 2 : paren + 1 );
            if( c == std::string_view::npos )
            {
                return term;
            }
            i = c + term.size();
            continue;
        }
        if( ch == '"' || ( ch == '\'' && ( i == 0 || !isIdentChar( s[i - 1] ) ) ) ) // `1'000` is a digit separator, not a literal
        {
            std::size_t k = i + 1;
            while( k < s.size() && s[k] != ch )
            {
                k += s[k] == '\\' ? 2 : 1;
            }
            i = k + 1;
            continue;
        }
        ++i;
    }
    return {};
}

// The directive word of a preprocessor line (`#  define X` → define), or "".
inline std::string_view directiveWord( std::string_view line )
{
    const std::string_view d = line.starts_with( "#" ) ? trimWs( line.substr( 1 ) ) : std::string_view();
    return d.substr( 0, std::size_t( std::ranges::find_if_not( d, isIdentChar ) - d.begin() ) );
}

// A `#define NAME(P, ..) \` line: its parameters into `params`, and NAME. "" (and no parameters) when it is not a function-like macro,
// or its replacement text is this line alone (no row can follow it).
inline std::string_view macroParams( std::string_view line, std::vector<std::string_view>& params )
{
    const std::string_view d = trimWs( trimWs( line.substr( 1 ) ).substr( 6 ) );
    const std::size_t paren = d.find( '(' );
    const std::string_view name = d.substr( 0, paren );
    if( paren == std::string_view::npos || name.empty() || !std::ranges::all_of( name, isIdentChar ) || !line.ends_with( '\\' ) )
    {
        return {};
    }
    const std::size_t shut = d.find( ')', paren );
    for( std::string_view ps = d.substr( paren + 1, shut == std::string_view::npos ? std::string_view::npos : shut - paren - 1 ); !ps.empty(); )
    {
        const std::size_t c = std::min( ps.find( ',' ), ps.size() );
        params.push_back( trimWs( ps.substr( 0, c ) ) );
        ps = c < ps.size() ? ps.substr( c + 1 ) : std::string_view();
    }
    return name;
}

// One row line's leading arguments (`a`: the text after `P(`), before a string or a nested call.
inline MacroRow macroRow( std::string_view a, std::uint32_t ln )
{
    MacroRow r { ln, {} };
    a = a.substr( 0, std::min( a.find_first_of( "\"()" ), a.size() ) );
    while( !a.empty() )
    {
        const std::size_t c = std::min( a.find( ',' ), a.size() );
        r.args.push_back( trimWs( a.substr( 0, c ) ) );
        a = c < a.size() ? a.substr( c + 1 ) : std::string_view();
    }
    return r;
}

// The X-macro list rows of a C / C++ file: per `#define NAME(P, ..)` block, the lines that start with one of its parameters
// `P(`, up to the end of its replacement text (a line that does not end in `\`, outside a raw-string literal or block comment that
// spans lines, as a description's often does); the largest block of kExemplarFamilyMin or more rows whose name column is known
// (macroNameColumn) wins. A row's name is the argument at that position (`DECLARE(UInt64, max_threads, 0, ..)` → max_threads, not
// UInt64). A line inside a multi-line literal or comment is text: its `#include` or `P(` neither ends the list nor adds a row.
inline void macroListRows( std::string_view txt, std::uint32_t fileId, ExemplarInto& into )
{
    std::vector<MacroRow> best, cur;
    std::string_view bestName, curName;
    std::uint32_t bestLine = 0, curLine = 0;
    std::size_t bestPos = SIZE_MAX;
    std::vector<std::string_view> params;
    const auto close = [&]
    {
        const std::size_t pos = cur.size() > best.size() ? macroNameColumn( cur ) : SIZE_MAX;
        if( pos != SIZE_MAX )
        {
            best = std::move( cur );
            bestName = curName;
            bestLine = curLine;
            bestPos = pos;
        }
        cur.clear();
        params.clear();
    };
    std::string open; // inside a multi-line raw string or block comment: its terminator
    std::uint32_t ln = 0;
    for( std::size_t p = 0; p < txt.size(); )
    {
        const std::size_t nl = std::min( txt.find( '\n', p ), txt.size() );
        std::string_view line = txt.substr( p, nl - p );
        p = nl + 1;
        ++ln;
        const std::size_t shut = open.empty() ? 0 : line.find( open );
        if( shut == std::string_view::npos )
        {
            continue; // text inside the literal or comment
        }
        line = trimWs( open.empty() ? line : line.substr( shut + open.size() ) );
        const std::string_view word = open.empty() ? directiveWord( line ) : std::string_view();
        static constexpr std::array<std::string_view, 9> kDirectives { "define", "undef", "if", "ifdef", "ifndef", "elif", "else", "endif", "include" };
        if( std::ranges::contains( kDirectives, word ) ) // a preprocessor line ends a list; `### Heading` inside a row's text does not
        {
            close();
            curName = word == "define" ? macroParams( line, params ) : std::string_view();
            curLine = ln;
            continue;
        }
        const std::size_t paren = open.empty() ? line.find( '(' ) : std::string_view::npos;
        if( !params.empty() && paren != std::string_view::npos && std::ranges::contains( params, trimWs( line.substr( 0, paren ) ) ) )
        {
            cur.push_back( macroRow( line.substr( paren + 1 ), ln ) );
        }
        open = openSpanAfter( line );
        if( open.empty() && !params.empty() && !line.ends_with( '\\' ) )
        {
            close(); // the end of the macro's replacement text: a later `P(` line is a call, not a row
        }
    }
    close();
    if( best.size() < kExemplarFamilyMin )
    {
        return;
    }
    into.by = "macro";
    into.list = std::string( bestName );
    into.listLine = bestLine;
    for( const MacroRow& r : best )
    {
        if( bestPos < r.args.size() && macroRowIdent( r.args[bestPos] ) )
        {
            into.rows.push_back( ExemplarMember { std::string( r.args[bestPos] ), fileId, r.line, 0, {}, kNoNode } );
        }
    }
}

// The field definitions inside a holder's own span (the field side table: a field is never in `symbols`, and its id is a FieldId, so
// the row carries no NodeId). One or two fields are rows too: n= counts what was found, and only none leaves `by` empty.
inline void fieldRows( const IngestResult& ing, const Symbol& h, ExemplarInto& into )
{
    for( const Symbol& s : ing.fields )
    {
        if( s.fileId == h.fileId && s.sigStartByte > h.sigStartByte && s.endByte <= h.endByte )
        {
            into.rows.push_back( ExemplarMember { s.name, s.fileId, s.line, s.loc, {}, kNoNode } );
        }
    }
    into.by = into.rows.empty() ? "" : "field";
}

// The brace depth change of one line of a TS / JS body: structural braces only, not those in a string, a template literal or a
// comment (`/** e.g. {foo */`, `"{"`). `inComment`: the line starts inside a block comment; updated for the next line.
inline int structuralBraces( std::string_view line, bool& inComment )
{
    int depth = 0;
    for( std::size_t i = 0; i < line.size(); ++i )
    {
        if( inComment )
        {
            const std::size_t c = line.find( "*/", i );
            inComment = c == std::string_view::npos;
            i = inComment ? line.size() : c + 1;
            continue;
        }
        const char ch = line[i];
        if( line.substr( i, 2 ) == "//" )
        {
            break;
        }
        if( line.substr( i, 2 ) == "/*" )
        {
            inComment = true;
            ++i;
            continue;
        }
        if( ch == '"' || ch == '\'' || ch == '`' )
        {
            std::size_t k = i + 1;
            while( k < line.size() && line[k] != ch )
            {
                k += line[k] == '\\' ? 2 : 1;
            }
            i = k;
            continue;
        }
        depth += ch == '{' ? 1 : ch == '}' ? -1 : 0;
    }
    return depth;
}

// The `name: type;` / `name?: type;` / `readonly name: type;` lines at the top brace depth of a holder's body (a TS interface).
inline void propertyLineRows( std::string_view body, std::uint32_t fileId, std::uint32_t firstLine, ExemplarInto& into )
{
    int depth = 0;
    bool inComment = false;
    std::uint32_t ln = firstLine;
    for( std::size_t p = 0; p < body.size(); )
    {
        const std::size_t nl = std::min( body.find( '\n', p ), body.size() );
        std::string_view line = trimWs( body.substr( p, nl - p ) );
        const int at = depth;
        const bool startsInComment = inComment;
        depth += structuralBraces( body.substr( p, nl - p ), inComment );
        p = nl + 1;
        const std::uint32_t here = ln++;
        if( at != 1 || startsInComment )
        {
            continue;
        }
        line = line.starts_with( "readonly " ) ? trimWs( line.substr( 9 ) ) : line;
        const std::size_t e = std::size_t( std::ranges::find_if_not( line, isIdentChar ) - line.begin() );
        std::string_view rest = line.substr( e );
        rest = rest.starts_with( '?' ) ? rest.substr( 1 ) : rest;
        if( e > 0 && !( line[0] >= '0' && line[0] <= '9' ) && rest.starts_with( ':' ) )
        {
            into.rows.push_back( ExemplarMember { std::string( line.substr( 0, e ) ), fileId, here, 0, {}, kNoNode } );
        }
    }
    into.by = into.rows.empty() ? "" : "line"; // one or two property lines are rows too (n= counts what was found)
}

// The rows of the picked holder (see the banner); none read leaves `by` empty and the holder is printed alone.
inline void holderRows( const IngestResult& ing, const ExemplarMember& holder, ExemplarInto& into )
{
    if( holder.sym >= ing.symbols.size() )
    {
        return;
    }
    const Symbol& h = ing.symbols[holder.sym];
    const std::optional<std::string> txt = docparse::detail::readWholeFile( diskPath( ing, h.fileId ) );
    if( !txt )
    {
        return;
    }
    if( langFacts( h.lang ).xMacroRows )
    {
        macroListRows( *txt, h.fileId, into );
    }
    if( into.by.empty() )
    {
        fieldRows( ing, h, into );
    }
    if( into.by.empty() && langFacts( h.lang ).bracedPropertyRows && h.sigStartByte < h.endByte && h.endByte <= txt->size() )
    {
        const std::string_view span = std::string_view( *txt ).substr( h.sigStartByte, h.endByte - h.sigStartByte );
        const std::size_t open = span.find( '{' );
        if( open != std::string_view::npos )
        {
            const std::uint32_t first = h.line + std::uint32_t( std::ranges::count( span.substr( 0, open ), '\n' ) );
            propertyLineRows( span.substr( open ), h.fileId, first, into );
        }
    }
}
} // namespace exemplar_detail

// Settle a family of holders (see the banner): false when the block is withheld (holders, and no single one the task points into).
// A family that is not one of holders is left as it is (true).
inline bool settleInto( const IngestResult& ing, const ExemplarTask& t, ExemplarFamily& fam )
{
    using namespace exemplar_detail;
    if( !isHolderFamily( t, fam ) )
    {
        return true;
    }
    const std::vector<std::vector<std::string>> hw = holderWordsOf( t, fam );
    ExemplarInto& into = fam.into;
    into.member = holderByWord( fam, hw, intoWords( t, false ), into.word );
    into.member = into.member != SIZE_MAX ? into.member : holderByWord( fam, hw, intoWords( t, true ), into.word );
    if( into.member == SIZE_MAX )
    {
        std::vector<std::size_t> bare;
        for( std::size_t m = 0; m < fam.members.size(); ++m )
        {
            if( hw[m].empty() && subtokenIsPlural( fam.members[m].name, t.head ) && ( bare.empty() || fam.members[bare.front()].name != fam.members[m].name ) )
            {
                bare.push_back( m );
            }
        }
        if( bare.size() != 1 )
        {
            return false;
        }
        into.member = bare.front();
        into.bare = true;
        into.word.clear();
    }
    holderRows( ing, fam.members[into.member], into );
    return true;
}

// ── E3a TOUCH LIST (co-mention) ────────────────────────────────────────────────────────────────────────────────────────────────
// Where a new X must also go: the files that mention at least half of the family (half the units),
// outside the members' own files. The count is over DISTINCT units (see TouchUnits): distinct member names (the registered name, else the
// name), or distinct member file stems when there are at least kExemplarFamilyMin of them; a name or stem that several members share is
// one unit, so one shared token (django's `Command`, helix's `typed`) never credits every member. A unit is mentioned by any of its
// FORMS, folded (lowercase, `_` and `-` dropped, so snake_case, CamelCase, kebab-case and UPPER_CASE meet): its name, its registered
// name (alt), or its file's module stem (`mod upper;`, `import './contrib/bracketMatching/browser/bracketMatching'`). Forms shorter
// than kExemplarFormMinBytes and generic stems (index, main, utils, ..) are not read. Test paths, test-helper, sample, example and
// benchmark directories, docs (.md .rst .adoc .txt .html, and docs/ or doc/ trees: a site generator's copies), vendored trees, generated files (a generator banner, or `generated` /
// `.pb.` / `_pb2` in the path) and files marked frozen or baseline (a path segment holding `baseline` or `frozen`) are not read.
// Ranked by share, then count, then path.
// HOISTING: the forms are hashed once into one sorted array; each file is read and tokenized once, and every token is one bit test
// plus a binary search on a hit (files x bytes, never files x members x lines).
inline constexpr std::size_t kExemplarTouchRows = 5; // <touch> rows printed; <touch_list total=> counts all
inline constexpr std::size_t kExemplarTouchLineMax = 120; // bytes of the mentioning line printed (cut="1" when longer)
inline constexpr std::size_t kExemplarFormMinBytes = 4; // a folded form shorter than this is not a name (`id`, `max`)

struct ExemplarTouch
{
    std::uint32_t fileId = 0;
    std::size_t nameHits = 0; // distinct member names the file mentions (a unit of its own members is not counted)
    std::size_t stemHits = 0; // distinct member file stems the file mentions
    std::size_t mentioned = 0; // the share shown: the channel (names, or stems) the file names the larger part of, units it mentions
    std::size_t of = 0; // ... out of this many distinct units
    bool byStem = false; // the share counts file stems, not names
    std::uint32_t line = 0; // the line to copy: the first naming the typical member, else the first code line, an import, a comment
    std::string text; // that line, trimmed
    std::uint32_t byte = 0; // TOUCH-SYM: the file offset of text's first byte (the definition holding the line is looked up by it)
};

namespace exemplar_detail
{
inline std::uint64_t foldHashStep( std::uint64_t h, char c ) noexcept
{
    return ( h ^ std::uint64_t( lexLowerByte( static_cast<unsigned char>( c ) ) ) ) * 1099511628211ull;
}
inline constexpr std::uint64_t kFoldHashSeed = 14695981039346656037ull;

// The folded hash of a spelling and its folded length: `_` and `-` dropped, letters lowercased.
inline std::pair<std::uint64_t, std::size_t> foldHash( std::string_view s ) noexcept
{
    std::uint64_t h = kFoldHashSeed;
    std::size_t n = 0;
    for( const char c : s )
    {
        if( c != '_' && c != '-' )
        {
            h = foldHashStep( h, c );
            ++n;
        }
    }
    return { h, n };
}


// A file stem that names no one member: a package entry, a helpers file.
inline constexpr std::array<std::string_view, 14> kGenericStems { "index", "main", "util", "utils", "types", "type", "base", "common",
                                                                  "helpers", "helper", "mod", "lib", "init", "__init__" };
// The heads of an import / include / re-export line.
inline constexpr std::array<std::string_view, 8> kImportLineHeads { "import ", "from ", "#include", "use ", "pub use ", "export * from", "export {", "require(" };

// The units a share counts. A name or a stem that several members share is ONE unit, so a token that is a shared name credits once,
// not n times (django's 23 `Command` classes are one name; helix's typed.rs holds every member and is one stem): the share is
// distinct names mentioned / distinct names, or distinct file stems mentioned / distinct stems. A channel with fewer than
// kExemplarFamilyMin units is off (two names are no pattern), the name channel is also off when the distinct names are fewer than
// half the members (330 codec classes under 3 names), and a registry has no stems (its entries live in the registry itself).
// A name unit is a member's registered name (alt, else its name); its name is a second spelling of the same unit.
struct TouchUnits
{
    std::vector<std::pair<std::uint64_t, std::uint32_t>> forms; // (folded hash, unit), sorted: every spelling a unit is mentioned by
    std::vector<std::pair<std::uint32_t, std::uint32_t>> homes; // (unit, file), sorted: the files holding a member of the unit
    std::uint32_t names = 0; // name units are 0..names-1 (0: the channel is off)
    std::uint32_t stems = 0; // stem units are names..names+stems-1 (0: off)
    std::uint32_t typicalName = UINT32_MAX; // the units of members[0], the typical sibling
    std::uint32_t typicalStem = UINT32_MAX;
};

// The module stem of a member's file (`mod upper;`, `import './contrib/bracketMatching/browser/bracketMatching'`); the directory name for
// a package entry (index, mod, __init__). A generic stem (utils, types) is still a unit of the count; it is just never read as a mention.
inline std::string_view memberStem( const IngestResult& ing, const ExemplarMember& mem )
{
    const std::string_view rel = rootRelPath( ing, mem.fileId );
    std::string_view stem = rel.substr( rel.rfind( '/' ) + 1 );
    stem = stem.substr( 0, stem.find( '.' ) );
    if( stem == "index" || stem == "mod" || stem == "__init__" )
    {
        const std::string_view dir = includerDir( rel );
        stem = dir.substr( dir.rfind( '/' ) + 1 );
    }
    return stem;
}

// The dense unit id of each member for the keys given (the sorted distinct keys are the units, in key order).
inline std::vector<std::uint32_t> unitIdsOf( std::vector<std::uint64_t> keys, std::vector<std::uint64_t>& distinct )
{
    distinct = keys;
    std::ranges::sort( distinct );
    distinct.erase( std::unique( distinct.begin(), distinct.end() ), distinct.end() );
    std::vector<std::uint32_t> ids;
    for( const std::uint64_t k : keys )
    {
        ids.push_back( std::uint32_t( std::ranges::lower_bound( distinct, k ) - distinct.begin() ) );
    }
    return ids;
}

// The spelling's folded hash as a form of `unit`, unless it is too short to be a name.
inline void addUnitForm( TouchUnits& u, std::string_view spelling, std::uint32_t unit )
{
    const auto [h, n] = foldHash( spelling );
    if( n >= kExemplarFormMinBytes )
    {
        u.forms.emplace_back( h, unit );
    }
}

inline constexpr std::uint32_t kNoUnit = UINT32_MAX; // the channel is off

// One member's forms and homes: its name and registered name under `nameUnit`, its file stem under `stemUnit` (kNoUnit: that channel is off).
inline void addMemberForms( TouchUnits& u, const IngestResult& ing, const ExemplarMember& mem, std::uint32_t nameUnit, std::uint32_t stemUnit )
{
    if( nameUnit != kNoUnit )
    {
        addUnitForm( u, mem.name, nameUnit );
        addUnitForm( u, mem.alt, nameUnit );
        u.homes.emplace_back( nameUnit, mem.fileId );
    }
    if( stemUnit != kNoUnit )
    {
        const std::string_view stem = memberStem( ing, mem );
        if( !std::ranges::contains( kGenericStems, stem ) )
        {
            addUnitForm( u, stem, stemUnit );
        }
        u.homes.emplace_back( stemUnit, mem.fileId );
    }
}

inline TouchUnits touchUnits( const IngestResult& ing, const ExemplarFamily& fam )
{
    TouchUnits u;
    std::vector<std::uint64_t> nameKeys, stemKeys, nameDistinct, stemDistinct;
    for( const ExemplarMember& mem : fam.members )
    {
        nameKeys.push_back( foldHash( mem.alt.empty() ? mem.name : mem.alt ).first );
        stemKeys.push_back( fam.rule == ExemplarRule::Registry ? 0 : foldHash( memberStem( ing, mem ) ).first );
    }
    const std::vector<std::uint32_t> nameId = unitIdsOf( nameKeys, nameDistinct );
    const std::vector<std::uint32_t> stemId = unitIdsOf( stemKeys, stemDistinct );
    const bool namesOn = nameDistinct.size() >= kExemplarFamilyMin && nameDistinct.size() * 2 >= fam.members.size(); // 330 members under 3 names: a mention of the names says nothing per member
    const bool stemsOn = fam.rule != ExemplarRule::Registry && stemDistinct.size() >= kExemplarFamilyMin;
    u.names = namesOn ? std::uint32_t( nameDistinct.size() ) : 0;
    u.stems = stemsOn ? std::uint32_t( stemDistinct.size() ) : 0;
    for( std::uint32_t m = 0; m < fam.members.size(); ++m )
    {
        const std::uint32_t nameUnit = namesOn ? nameId[m] : kNoUnit, stemUnit = stemsOn ? u.names + stemId[m] : kNoUnit;
        addMemberForms( u, ing, fam.members[m], nameUnit, stemUnit );
        u.typicalName = m == 0 ? nameUnit : u.typicalName;
        u.typicalStem = m == 0 ? stemUnit : u.typicalStem;
    }
    std::ranges::sort( u.forms );
    u.forms.erase( std::unique( u.forms.begin(), u.forms.end() ), u.forms.end() );
    std::ranges::sort( u.homes );
    u.homes.erase( std::unique( u.homes.begin(), u.homes.end() ), u.homes.end() );
    return u;
}

// A file the touch scan does not read (see the E3a banner).
inline bool touchSkipPath( std::string_view p ) noexcept
{
    static constexpr std::array<std::string_view, 7> kDocExt { ".md", ".rst", ".adoc", ".txt", ".html", ".htm", ".mdx" };
    static constexpr std::array<std::string_view, 19> kSkipSeg { "vendor/", "third_party/", "node_modules/", "testing/", "testdata/", "fixtures/", "mocks/", "fake/", "docs/", "doc/", "unittests/",
                                                                 "sample/", "samples/", "example/", "examples/", "benchmark/", "benchmarks/", "bench/", "benches/" };
    if( isTestPath( p ) || std::ranges::any_of( kDocExt, [&]( std::string_view e )
                                                { return endsWithLowerAscii( p, e ); } ) ||
        std::ranges::any_of( kSkipSeg, [&]( std::string_view s )
                             { return hasDirSegment( p, s ); } ) )
    {
        return true;
    }
    static constexpr std::array<std::string_view, 6> kMarked { "generated", ".pb.", "_pb2", "baseline", "frozen", ".min." };
    return std::ranges::any_of( kMarked, [&]( std::string_view m )
                                { return p.find( m ) != std::string_view::npos; } );
}


// One file's mentions: distinct members (not its own) and the line to copy.
// Every token of a file, folded and hashed: identifier runs ([A-Za-z0-9_], `_` dropped); a run joined to the previous one by a single
// '-' also yields the joined (kebab) form. `onLine( next )` at each newline with the offset the next line starts at.
template<class OnToken, class OnLine>
inline void forEachFoldedToken( std::string_view txt, OnToken&& onToken, OnLine&& onLine )
{
    std::uint64_t run = kFoldHashSeed, chain = kFoldHashSeed;
    bool inRun = false, chained = false;
    for( std::size_t i = 0; i <= txt.size(); ++i )
    {
        const char c = i < txt.size() ? txt[i] : '\n';
        if( isIdentChar( c ) )
        {
            run = c == '_' ? run : foldHashStep( run, c );
            chain = c == '_' ? chain : foldHashStep( chain, c );
            inRun = true;
            continue;
        }
        if( inRun )
        {
            onToken( run );
        }
        if( inRun && chained )
        {
            onToken( chain );
        }
        const bool joins = inRun && c == '-' && i + 1 < txt.size() && isIdentChar( txt[i + 1] );
        chained = joins;
        chain = joins ? chain : kFoldHashSeed;
        run = kFoldHashSeed;
        inRun = false;
        if( c == '\n' && i < txt.size() )
        {
            onLine( i + 1 );
        }
    }
}

// A mentioning line's rank as the line to copy (lower is better): one naming the typical member (members[0]), any other code
// line, an import line, a comment (a license header that happens to hold a member's word: risingwave's `version` function).
inline int touchLineRank( std::string_view line, bool typical ) noexcept
{
    static constexpr std::array<std::string_view, 5> kComment { "//", "#", "/*", "*", "--" };
    line = trimWs( line );
    if( std::ranges::any_of( kComment, [&]( std::string_view c )
                             { return line.starts_with( c ); } ) &&
        !line.starts_with( "#include" ) && !line.starts_with( "#[" ) )
    {
        return 3;
    }
    const bool imports = std::ranges::any_of( kImportLineHeads, [&]( std::string_view h )
                                              { return line.starts_with( h ); } );
    return imports ? 2 : typical ? 0
                                 : 1;
}

// The forms of one family, hashed: a presence map in front of the sorted (hash, unit) array, so a token that names no member (nearly
// all of them) costs one bit test, not a binary search.
struct TouchForms
{
    TouchUnits units;
    std::vector<std::uint64_t> bits = std::vector<std::uint64_t>( 1024, 0 );
    explicit TouchForms( TouchUnits u ) : units( std::move( u ) )
    {
        for( const auto& [h, unit] : units.forms )
        {
            bits[( h >> 6 ) & 1023] |= std::uint64_t( 1 ) << ( h & 63 );
        }
    }
    bool maybe( std::uint64_t h ) const noexcept { return ( bits[( h >> 6 ) & 1023] >> ( h & 63 ) ) & 1; }
};

// Credit one hit of unit `unit` to file `f`: false when the unit is one of the file's own members' (not a mention); a unit counts once.
inline bool creditUnit( const TouchUnits& u, std::uint32_t unit, std::uint32_t f, std::vector<std::uint32_t>& stamp, ExemplarTouch& out )
{
    if( std::ranges::binary_search( u.homes, std::pair( unit, f ) ) )
    {
        return false;
    }
    if( stamp[unit] != f + 1 )
    {
        stamp[unit] = f + 1;
        ( unit < u.names ? out.nameHits : out.stemHits ) += 1;
    }
    return true;
}

// One file's mentions: distinct member names and stems (not those of its own members) and the line to copy (touchLineRank, then the
// earliest). `stamp[unit] == f + 1`: the unit is counted for this file already.
inline ExemplarTouch scanTouchFile( std::uint32_t f, std::string_view txt, const TouchForms& tf, std::vector<std::uint32_t>& stamp )
{
    const TouchUnits& u = tf.units;
    ExemplarTouch out { .fileId = f };
    std::uint32_t ln = 1;
    std::size_t lineStart = 0, bestStart = std::string_view::npos;
    int bestRank = 4;
    const auto hit = [&]( std::uint64_t h )
    {
        if( !tf.maybe( h ) )
        {
            return;
        }
        for( auto it = std::ranges::lower_bound( u.forms, std::pair( h, std::uint32_t( 0 ) ) ); it != u.forms.end() && it->first == h; ++it )
        {
            if( !creditUnit( u, it->second, f, stamp, out ) )
            {
                continue; // a file's own members are not mentions
            }
            const int rank = touchLineRank( txt.substr( lineStart, txt.find( '\n', lineStart ) - lineStart ), it->second == u.typicalName || it->second == u.typicalStem );
            if( rank < bestRank )
            {
                bestRank = rank;
                bestStart = lineStart;
                out.line = ln;
            }
        }
    };
    forEachFoldedToken( txt, hit, [&]( std::size_t next )
                        {
        ++ln;
        lineStart = next; } );
    if( bestStart != std::string_view::npos )
    {
        const std::string_view trimmed = trimWs( txt.substr( bestStart, txt.find( '\n', bestStart ) - bestStart ) );
        out.text = std::string( trimmed );
        out.byte = std::uint32_t( trimmed.data() - txt.data() );
    }
    return out;
}

// Settle a scanned file's share: the channel (names or stems) it names the larger part of, when that part is at least half; a tie is
// the names. False when neither channel reaches half.
inline bool settleShare( ExemplarTouch& t, const TouchUnits& u )
{
    const bool nameOk = u.names > 0 && t.nameHits * 2 >= u.names;
    const bool stemOk = u.stems > 0 && t.stemHits * 2 >= u.stems;
    t.byStem = stemOk && ( !nameOk || t.stemHits * u.names > t.nameHits * u.stems );
    t.mentioned = t.byStem ? t.stemHits : t.nameHits;
    t.of = t.byStem ? u.stems : u.names;
    return nameOk || stemOk;
}
} // namespace exemplar_detail

// A listing candidate's text, or nullopt: unreadable or over kDefaultMaxFileBytes now (counted in `unread`, which is not the same as not
// listed), or generated (skipped on purpose).
inline std::optional<std::string> readTouchCandidate( const IngestResult& ing, std::uint32_t f, std::uint32_t& unread )
{
    std::optional<std::string> txt = docparse::detail::readWholeFile( diskPath( ing, f ) );
    if( !txt || txt->size() > kDefaultMaxFileBytes )
    {
        ++unread;
        return std::nullopt;
    }
    return docparse::hasGeneratedMarker( *txt ) ? std::nullopt : std::move( txt );
}

// The rows of a touch list and what the scan could not look at: `unread` files that were indexed but could not be read, or are over
// kDefaultMaxFileBytes now, make total= a floor (a qualifying file among them is missing, and a zero is not "none").
struct ExemplarTouchList
{
    std::vector<ExemplarTouch> rows;
    std::uint32_t unread = 0;
};

// The touch list of a family: every file that names at least half of the distinct names, or of the distinct file stems, by the larger
// share, then the count, then the path.
inline ExemplarTouchList exemplarTouchList( const IngestResult& ing, const ExemplarFamily& fam )
{
    using namespace exemplar_detail;
    const TouchForms forms( touchUnits( ing, fam ) );
    const TouchUnits& u = forms.units;
    std::vector<std::uint32_t> stamp( std::size_t( u.names ) + u.stems, 0 );
    ExemplarTouchList list;
    std::vector<ExemplarTouch>& rows = list.rows;
    if( u.names + u.stems == 0 )
    {
        return list; // too few distinct names and stems to call a mention a pattern
    }
    std::vector<std::uint32_t> memberFiles; // a member's file is where the members are, not where they are listed
    std::ranges::transform( fam.members, std::back_inserter( memberFiles ), &ExemplarMember::fileId );
    std::ranges::sort( memberFiles );
    for( std::uint32_t f = 0; f < ing.files.size(); ++f )
    {
        const std::string_view rel = rootRelPath( ing, f );
        if( touchSkipPath( rel ) || std::ranges::binary_search( memberFiles, f ) )
        {
            continue;
        }
        const std::optional<std::string> txt = readTouchCandidate( ing, f, list.unread );
        if( !txt )
        {
            continue;
        }
        ExemplarTouch t = scanTouchFile( f, *txt, forms, stamp );
        if( settleShare( t, u ) )
        {
            rows.push_back( std::move( t ) );
        }
    }
    std::ranges::sort( rows, [&]( const ExemplarTouch& a, const ExemplarTouch& b )
                       {
        const std::size_t fa = a.mentioned * b.of, fb = b.mentioned * a.of; // a's share over b's, cross-multiplied
        if( fa != fb )
        {
            return fa > fb;
        }
        return a.mentioned != b.mentioned ? a.mentioned > b.mentioned : sortutil::svLess( rootRelPath( ing, a.fileId ), rootRelPath( ing, b.fileId ) ); } );
    return list;
}

// The family line of a family grouped by names alone (rule=affix): a weak guess, said on the row itself and not only in the legend.
inline constexpr std::string_view kAffixGrouping = "affix-only, weak: verify one m before copying";

inline constexpr std::string_view kForExemplarFamilyLegend =
    "<!-- ripwire for exemplar_family: the task reads as adding one more of=; these are the EXISTING siblings it would join, read off the "
    "index (not a guarantee that a new one needs each row). rule= how they were grouped: base (implementors of key=), registry (the entries "
    "of the map or table key=), typed (instances of the struct type key=), attribute (items under the attribute or decorator key=), affix "
    "(classes in one directory whose names end in key=: names alone, the weakest grouping; the block then says so in grouping=, and its <m> and <touch> rows are leads to verify, not rows to copy). matched= the words of of= found in key= or scope=: why this family and not another "
    "(a family that matches few of the words is a weak guess). key_p= where key= is defined (file:line), scope= the directory the members "
    "were narrowed to (the deepest holding half of them), n= the members in scope (test, sample, example and benchmark code excluded). "
    "<m> n= a member, p=file:line, loc= its lines (a registry entry has none); the first <m> is the typical sibling (nearest the median "
    "size), except under rule=registry, where the <m> rows are the first entries in listing order; shown= and capped=\"1\" when fewer <m> rows "
    "are printed than n=. A registry or instance candidate over 4000 lines is not read: oversized=N counts the registry candidates (a function or variable named for a task word or a registry word) skipped for it, and unread=N the files the scan could not read; either may hide a family, and found=\"0\" with one of them means none resolved and a skipped one may be why. <touch_list> the files outside the members' own that "
    "mention at least half of them: where existing siblings are registered or listed (a registry, a name list, an exhaustive match, an "
    "import list), a candidate to edit, not a guarantee; a member is matched by its name, its registered name or its file's stem, with "
    "snake, Camel, kebab and UPPER forms folded, and a name or stem shared by several members counts once. total= such files, shown= and "
    "capped=\"1\" when fewer rows are printed; floor=\"1\" unread=K when K listing files could not be read or are over 4 MiB (total= then counts only the others). <touch> p=file:line the line to copy (a lead to verify when grouping= is weak): the first naming the typical member (the first <m>), "
    "else the first other code line mentioning one, an import line or a comment only when no code line does; n= the innermost definition holding "
    "that line (a member as Owner.name, as the <d> rows spell it; no n= when no definition holds it); share=named/of the distinct "
    "member names the file mentions out of the distinct names (by=\"stem\": the distinct file stems it mentions out of the distinct stems), "
    "its text that line, cut=\"1\" when cut to 120 bytes. Test, docs, vendored, generated, frozen and baseline files are not read. The "
    "answer above is unchanged, and these bytes are not in est_tokens -->";
// The --legend=compact posture (the CLI default); the long text rides --legend=full and the MCP tool. Both define every attribute printed.
inline constexpr std::string_view kForExemplarFamilyCompactLegend =
    "<!-- ripwire for exemplar_family: existing siblings a new of= would join, not a guarantee; not in est_tokens. rule= base (implementors of "
    "key=), registry (entries of map key=), typed (instances of struct key=), attribute (items under macro or decorator key=), affix (classes "
    "in one dir named for key=: names alone, weak: grouping= says so); matched= words of of= found in key= or scope= (few: a weak guess); key_p= key's file:line; scope= dir holding "
    "half of them; n= members (tests, samples, examples, benchmarks out); <m> p= file:line, loc= lines, the first nearest the median size (registry: "
    "listing order); shown=/capped=\"1\": rows cut; oversized=N registry candidates over 4000 lines and unread=N files not read were skipped (a family may hide there; found=\"0\": none resolved). <touch_list> total= files outside the members' own naming at least half of them (by name, "
    "registered name or file stem; a shared name or stem counts once): where siblings are registered; shown=/capped=\"1\": cut; floor=\"1\" unread=K: K files unreadable or over 4 MiB, total= is a floor. <touch> p= "
    "the line to copy, n= the innermost def holding it (a member: Owner.name), share=named/of distinct names (by=\"stem\": distinct file stems), cut=\"1\": text cut to 120 bytes. Tests, docs, "
    "vendored, generated, frozen, baseline files unread. -->";
// E3a-INTO: the legend of into= and <rows>, spliced in before <touch_list> only when the family prints into= (familyLegend), so a family
// that is not one of holders keeps its legend bytes.
inline constexpr std::string_view kForExemplarIntoLegend =
    "into= when the members HOLD of= (their names carry its plural: ServerSettingsImpl for a setting), a new one is a row inside one "
    "of them, not a new member: into= that holder, into_p= its file:line, into_by=\"word\" when its name carries into_word= (a word of "
    "the task), \"bare\" when no holder is named for the task and it is the one holder named by nothing but of= and a kind word (the "
    "general one); n= then counts the holders and the other holders (other scopes) are not printed, and no holder the task points into "
    "prints no block. <rows> the existing rows of the holder (the siblings to copy): by=\"macro\" the largest X-macro list in its "
    "file, list= that macro, list_p= its #define, by=\"field\" its field definitions, by=\"line\" its name: type lines; n= the rows, "
    "<m> the first in listing order, shown=/capped=\"1\" when cut; n=\"0\": none could be read. The <touch_list> then counts mentions "
    "of the rows. ";
inline constexpr std::string_view kForExemplarIntoCompactLegend =
    "into= the members hold of= (plural names): a new one is a row in this holder, into_p= its file:line, into_by= \"word\" (its name "
    "has into_word=, a task word) or \"bare\" (the one general holder); n= counts holders, others unprinted. <rows> its existing rows: "
    "by= macro (list= X-macro, list_p= its #define), field or line (name: type); n= rows, <m> first rows in order, "
    "shown=/capped=\"1\": cut; n=\"0\": unread. ";
// The legend of the no-family form (found="0"): short, since it carries no rows to define.
inline constexpr std::string_view kForExemplarNoFamilyLegend =
    "<!-- ripwire for exemplar_family: the task reads as adding one more of=, and no family of existing siblings resolved (found=\"0\"), "
    "but the scan skipped something that may have been it: oversized=N registry candidates (a function or variable named for a task word or "
    "a registry word) over 4000 lines were not read, unread=N files could not be read. Not in est_tokens -->";
static_assert( kForExemplarFamilyLegend.find( "--", 4 ) == kForExemplarFamilyLegend.size() - 3 && kForExemplarFamilyCompactLegend.find( "--", 4 ) == kForExemplarFamilyCompactLegend.size() - 3
                   && kForExemplarNoFamilyLegend.find( "--", 4 ) == kForExemplarNoFamilyLegend.size() - 3,
               "the only double hyphen in a legend comment is its closing: one inside is not well-formed XML" );

// TOUCH-SYM: the innermost indexed definition holding each touch row's line (kNoNode: none does), by byte-span containment as
// @FILE:LINE resolves a line (graph.h resolveAtSeed): a definition holds the line when its [sigStartByte, endByte) meets the line's
// text, the innermost is the latest start, then the shorter span, then the one declared ON the line. Two DISJOINT definitions sharing
// the line, or two with the same span neither or both declared on it (a Go `const (` group stores the group's span on every
// constant), are no claim: kNoNode, never a pick. A file's module-scope pseudo-definition holds every line and names none.
// HOISTING: one pass over the symbols for all the rows (at most kExemplarTouchRows), never one pass per row.
namespace exemplar_detail
{
// One touch row's holder search: the innermost holder so far, whether another shares its whole rank, and the earliest holder end.
struct TouchHolderPick
{
    const Symbol* best = nullptr;
    bool tied = false; // best shares its whole rank with another holder
    std::uint32_t minEnd = UINT32_MAX; // the earliest end among the holders: before best's start = two disjoint holders

    void offer( const Symbol& s, const ExemplarTouch& r )
    {
        if( s.fileId != r.fileId || s.sigStartByte >= r.byte + r.text.size() || s.endByte <= r.byte )
        {
            return; // does not hold the line
        }
        minEnd = std::min( minEnd, s.endByte );
        const auto rank = [&]( const Symbol& x ) { return std::tuple( x.sigStartByte, ~x.endByte, x.line == r.line ); }; // larger = inner
        if( best && rank( s ) == rank( *best ) )
        {
            tied = true;
        }
        else if( !best || rank( s ) > rank( *best ) )
        {
            best = &s;
            tied = false;
        }
    }
    NodeId pick() const { return best && !tied && minEnd > best->sigStartByte ? best->id : kNoNode; }
};
} // namespace exemplar_detail

inline std::vector<NodeId> touchHolders( const IngestResult& ing, std::span<const ExemplarTouch> rows )
{
    std::vector<exemplar_detail::TouchHolderPick> picks( rows.size() );
    for( const Symbol& s : ing.symbols )
    {
        for( std::size_t i = 0; i < rows.size() && s.kind != SymKind::ModuleScope; ++i )
        {
            picks[i].offer( s, rows[i] );
        }
    }
    std::vector<NodeId> out;
    std::ranges::transform( picks, std::back_inserter( out ), &exemplar_detail::TouchHolderPick::pick );
    return out;
}

// The n= of each touch row ("" = none): the holder's name as every member row spells it (MemberOwners, built only when a holder
// could print an owner: one more pass over the symbols).
inline std::vector<std::string> touchHolderNames( const IngestResult& ing, std::span<const ExemplarTouch> rows )
{
    const std::vector<NodeId> holder = touchHolders( ing, rows );
    std::optional<MemberOwners> owners;
    if( std::ranges::any_of( holder, [&]( NodeId h ) { return h != kNoNode && memberOwnerPossible( ing.symbols[h] ); } ) )
    {
        owners.emplace( ing );
    }
    std::vector<std::string> names( holder.size() );
    for( std::size_t i = 0; i < holder.size(); ++i )
    {
        names[i] = holder[i] == kNoNode ? std::string() : owners ? qualifiedMemberName( *owners, ing.symbols[holder[i]] ) : ing.symbols[holder[i]].name;
    }
    return names;
}

// The <touch_list> element of a family: total=, the cap, and one <touch> row per listing file (see the legend).
inline std::string touchListXml( const IngestResult& ing, const ExemplarTouchList& list )
{
    const std::vector<ExemplarTouch>& touch = list.rows;
    const std::span<const ExemplarTouch> shown( touch.data(), std::min( touch.size(), kExemplarTouchRows ) );
    const std::vector<std::string> holderName = touchHolderNames( ing, shown );
    std::vector<char> esc;
    const auto e = [&]( std::string_view s )
    { return std::string( escapeXml( s, esc ) ); };
    std::string out = "<touch_list total=\"" + std::to_string( touch.size() ) + "\"";
    if( list.unread > 0 )
    {
        out += " floor=\"1\" unread=\"" + std::to_string( list.unread ) + "\""; // total= counts only the files that could be read
    }
    if( touch.size() > kExemplarTouchRows )
    {
        out += " shown=\"" + std::to_string( kExemplarTouchRows ) + "\" capped=\"1\""; // CAP-DISCLOSE
    }
    out += touch.empty() ? "/>" : ">";
    for( std::size_t i = 0; i < shown.size(); ++i )
    {
        const ExemplarTouch& r = shown[i];
        std::size_t keep = std::min( r.text.size(), kExemplarTouchLineMax );
        while( keep > 0 && keep < r.text.size() && ( static_cast<unsigned char>( r.text[keep] ) & 0xC0 ) == 0x80 )
        {
            --keep; // never split a UTF-8 sequence
        }
        out += "<touch p=\"" + e( rootRelPath( ing, r.fileId ) ) + ":" + std::to_string( r.line ) + "\"" + ( holderName[i].empty() ? "" : " n=\"" + e( holderName[i] ) + "\"" );
        out += " share=\"" + std::to_string( r.mentioned ) + "/" + std::to_string( r.of ) + "\"";
        out += r.byStem ? " by=\"stem\"" : "";
        out += ( keep < r.text.size() ? " cut=\"1\">" : ">" ) + e( std::string_view( r.text ).substr( 0, keep ) ) + "</touch>";
    }
    out += touch.empty() ? "" : "</touch_list>";
    return out;
}

// The ` unread=` / ` oversized=` attributes of a scan that skipped something ("" when it skipped nothing).
// SIZE-1 (size-trim): the scan-skip reading of each family legend, present-only beside the family row's unread=/oversized=
// (forExemplarFamilyXml erases it when the scan skipped nothing). Spelled exactly as the legends carry it.
inline constexpr std::string_view kExemplarScanSkipClause =
    "A registry or instance candidate over 4000 lines is not read: oversized=N counts the registry candidates (a function or variable named for a task word or a registry word) skipped for it, and unread=N the files the scan could not read; either may hide a family, and found=\"0\" with one of them means none resolved and a skipped one may be why. ";
inline constexpr std::string_view kExemplarCompactScanSkipClause =
    "oversized=N registry candidates over 4000 lines and unread=N files not read were skipped (a family may hide there; found=\"0\": none resolved). ";
static_assert( kForExemplarFamilyLegend.contains( kExemplarScanSkipClause ) && kForExemplarFamilyCompactLegend.contains( kExemplarCompactScanSkipClause ),
               "the scan-skip clauses are spelled as the family legends carry them" );

inline std::string scanSkipAttrs( std::uint32_t unread, std::uint32_t oversized )
{
    return ( unread > 0 ? " unread=\"" + std::to_string( unread ) + "\"" : std::string() )
           + ( oversized > 0 ? " oversized=\"" + std::to_string( oversized ) + "\"" : std::string() );
}

namespace exemplar_detail
{
// The into= / <rows> legend text joins the block legend `out` (before its <touch_list>) only when the family prints into=.
inline void addIntoLegend( std::string& out, const ExemplarFamily& fam, bool compactLegend )
{
    if( fam.into.member != SIZE_MAX )
    {
        out.insert( out.find( "<touch_list>" ), compactLegend ? kForExemplarIntoCompactLegend : kForExemplarIntoLegend );
    }
}

// The rest of an into= family's open tag and its body: the one holder picked, its <rows> and the touch list over the rows.
inline std::string intoFamilyXml( const IngestResult& ing, const ExemplarFamily& fam, const auto& e, const auto& loc, std::string out )
{
    if( fam.rule == ExemplarRule::Affix )
    {
        out += " grouping=\"" + std::string( kAffixGrouping ) + "\""; // the row says itself that names alone grouped it
    }
    const ExemplarInto& into = fam.into;
    // E3a-INTO: the members hold X; a new X is a row in the one picked (the other holders are other scopes and are not printed)
    const ExemplarMember& h = fam.members[into.member];
    out += " into=\"" + e( h.name ) + "\" into_p=\"" + loc( h.fileId, h.line ) + "\"";
    out += into.bare ? std::string( " into_by=\"bare\"" ) : " into_by=\"word\" into_word=\"" + e( into.word ) + "\"";
    out += ">";
    if( into.rows.empty() )
    {
        return out + "<rows n=\"0\"/></exemplar_family>"; // the holder is named; its rows could not be read off it
    }
    out += "<rows by=\"" + std::string( into.by ) + "\"";
    out += into.list.empty() ? std::string() : " list=\"" + e( into.list ) + "\" list_p=\"" + loc( h.fileId, into.listLine ) + "\"";
    out += " n=\"" + std::to_string( into.rows.size() ) + "\"";
    out += into.rows.size() > kExemplarMemberRows ? " shown=\"" + std::to_string( kExemplarMemberRows ) + "\" capped=\"1\">" : std::string( ">" );
    for( std::size_t i = 0; i < into.rows.size() && i < kExemplarMemberRows; ++i )
    {
        out += "<m n=\"" + e( into.rows[i].name ) + "\" p=\"" + loc( into.rows[i].fileId, into.rows[i].line ) + "\"/>";
    }
    ExemplarFamily rowFam { .rule = ExemplarRule::Registry, .key = fam.key }; // rows have no file stem of their own (all in the holder's file)
    rowFam.members = into.rows;
    out += "</rows>" + touchListXml( ing, exemplarTouchList( ing, rowFam ) );
    return out + "</exemplar_family>";
}
} // namespace exemplar_detail

inline std::string forExemplarFamilyXml( const IngestResult& ing, const ExemplarTask& t, const ExemplarFamily& fam, bool compactLegend )
{
    std::vector<char> esc;
    const auto e = [&]( std::string_view s )
    { return std::string( escapeXml( s, esc ) ); };
    const auto loc = [&]( std::uint32_t f, std::uint32_t l )
    { return e( rootRelPath( ing, f ) ) + ":" + std::to_string( l ); };
    std::string out( compactLegend ? kForExemplarFamilyCompactLegend : kForExemplarFamilyLegend );
    eraseAbsentClause( out, compactLegend ? kExemplarCompactScanSkipClause : kExemplarScanSkipClause, fam.unread + fam.oversized > 0 );   // SIZE-1
    exemplar_detail::addIntoLegend( out, fam, compactLegend );
    out += "<exemplar_family of=\"" + e( t.phrase ) + "\" rule=\"" + std::string( kExemplarRuleTags[std::size_t( fam.rule )] ) + "\" key=\"" + e( fam.key ) + "\"";
    if( fam.keyAt )
    {
        out += " key_p=\"" + loc( fam.keyFile, fam.keyLine ) + "\"";
    }
    out += " matched=\"" + e( fam.matched ) + "\" scope=\"" + e( fam.scope ) + "\" n=\"" + std::to_string( fam.members.size() ) + "\"" + scanSkipAttrs( fam.unread, fam.oversized );
    if( fam.into.member != SIZE_MAX )
    {
        return exemplar_detail::intoFamilyXml( ing, fam, e, loc, std::move( out ) ); // into= prints no member rows, so no shown=/capped=
    }
    if( fam.members.size() > kExemplarMemberRows )
    {
        out += " shown=\"" + std::to_string( kExemplarMemberRows ) + "\" capped=\"1\""; // CAP-DISCLOSE: the rows are cut, n= counts all
    }
    if( fam.rule == ExemplarRule::Affix )
    {
        out += " grouping=\"" + std::string( kAffixGrouping ) + "\""; // the row says itself that names alone grouped it
    }
    out += ">";
    for( std::size_t i = 0; i < fam.members.size() && i < kExemplarMemberRows; ++i )
    {
        const ExemplarMember& m = fam.members[i];
        out += "<m n=\"" + e( m.name ) + "\" p=\"" + loc( m.fileId, m.line ) + "\"";
        out += fam.rule != ExemplarRule::Registry ? " loc=\"" + std::to_string( m.loc ) + "\"/>" : std::string( "/>" );
    }
    out += touchListXml( ing, exemplarTouchList( ing, fam ) );
    return out + "</exemplar_family>";
}

// The <exemplar_family> block of this task, or "" (see WHEN above). `held`: a token budget is set; the block is named, not printed.
// `compactLegend`: the --legend=compact posture (the CLI default) prints the short legend; the MCP tool and --legend=full the long one.
// HOISTING: the readings share one scan of the files (scanExemplarFiles), not one per reading.
inline std::string renderForExemplarFamily( const IngestResult& ing, const Graph& g, std::string_view task, bool held = false, bool compactLegend = false )
{
    const std::vector<ExemplarTask> readings = exemplarTasksOf( task );
    const ExemplarTask* t = nullptr;
    std::optional<ExemplarFamily> fam;
    exemplar_detail::ExemplarScan scan;
    if( !readings.empty() )
    {
        scan = exemplar_detail::scanExemplarFiles( ing, readings );
        for( const ExemplarTask& r : readings )
        {
            std::optional<ExemplarFamily> f = exemplarFamily( ing, g, r, scan );
            if( f && ( !fam || exemplar_detail::familyBetter( *f, *fam ) ) )
            {
                fam = std::move( f ); // the reading whose family names X best; a tie keeps the earlier reading
                t = &r;
            }
        }
    }
    if( fam && !settleInto( ing, *t, *fam ) )
    {
        fam.reset(); // holders of X, and none the task points into: no sibling to show (E3a-INTO)
        t = nullptr;
    }
    std::vector<char> esc;
    if( t == nullptr )
    {
        if( held || readings.empty() || scan.unread + scan.oversized == 0 )
        {
            return {};
        }
        // no family resolved, and the scan skipped something that may have been it: say so instead of printing nothing
        return std::string( kForExemplarNoFamilyLegend ) + "<exemplar_family of=\"" + std::string( escapeXml( readings.front().phrase, esc ) ) + "\" found=\"0\"" + scanSkipAttrs( scan.unread, scan.oversized ) + "/>";
    }
    if( held )
    {
        return "<!-- ripwire for exemplar_family: held=\"budget\": a token budget is set, so the sibling rows of of= are not printed; the same "
               "call without the token budget prints them; the answer above is unchanged -->"
               "<exemplar_family of=\"" +
               std::string( escapeXml( t->phrase, esc ) ) + "\" held=\"budget\"/>";
    }
    fam->unread = scan.unread;
    fam->oversized = scan.oversized;
    return forExemplarFamilyXml( ing, *t, *fam, compactLegend );
}
} // namespace rw
