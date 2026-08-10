#pragma once

// flipimpact.h — `--flags --flip=NAME`, the ONE-GATE BLAST RADIUS (the sequel `--flags` demands).
//
// `--flags` answers "what is built but DARK here" and, on the motivating repo, names ~90 dark gates. A list
// that long is a MAP, not a decision. The next question is always the same one, and it is per-gate: *if I
// flip this ONE, what actually lights up, and which tests cover it?* This verb answers exactly that:
//
//   which code becomes live   — the `#if` regions AND the C++ branches the gate governs
//   how much of it            — regions / guarded LOC / branch sites
//   which SYMBOLS hold it     — the indexed defs those lit lines sit inside (the HOSTS)
//   what they then reach      — the hosts' transitive callees: the code that starts EXECUTING
//   who depends on them       — the hosts' transitive callers: where the behaviour change propagates
//   is it safe                — the tests that reach the hosts, and the hosts NO test reaches
//
// Pure COMPOSITION. Nothing here re-implements a harvest or a traversal: the gate table, its alias chain
// and its region spans come from darkflags.h::computeFlags; the radius is graph.h::transitiveCallers /
// forwardReach (the same two primitives --impact and --test-gate stand on); the test partition is
// filter.h::isTestPath. This file owns exactly ONE new piece of analysis — the value-gate lane below.
//
// ── why its own file (not a section of darkflags.h) ──────────────────────────────────────────────────────
// darkflags.h is the HARVEST: lexical, index-shaped, and deliberately independent of the graph stage (it
// needs only a file list). Flip impact is a CONSUMER that needs the call graph, the symbol table and the
// test partition. Folding it in would couple the harvest to the graph stage for every `--flags` caller,
// including the MCP verb. Same split, same reason, as crossref.h / docdrift.h / layout.h.
//
// ── subtlety 1: alias chains run in BOTH directions ──────────────────────────────────────────────────────
// `#define CANYON_RRF_WALLS CANYON_RRF_ALL` makes WALLS an alias of ALL. Flipping the MASTER lights every
// child's guarded code, so the master's true radius is its CHILDREN's — its own is zero by construction.
// Flipping a CHILD lights only that child, and the report says so while naming the parent and the siblings
// that would come with it. The walk is over darkflags' `aliasParent` (the IMMEDIATE link), not `aliasOf`
// (the chain root), so a 3-level chain A -> B -> C reports B's flip as lighting {B, A} and C's as {C, B, A}.
//
// ── subtlety 2: value-style gates are C++ branches, not `#if` regions ────────────────────────────────────
// The whole River-Raid-feel family is consumed as `inline constexpr bool kWalls = CANYON_RRF_WALLS != 0;`
// and then `if constexpr( rrf::kWalls )`. There is no `#if`, so `--flags` honestly reports regions="0" —
// and a flip verb that followed only `#if` regions would confidently report "nothing lights up" for exactly
// the gates an owner most wants to flip. So this file adds the missing hop, in two lexical passes:
//   pass A  find the gate name in ORDINARY CODE (not a directive, not a comment). A line that BINDS it to a
//           `constexpr`/`const` declarator is the value binding (`kWalls`); any other mention is a direct
//           value read (`X ? a : b`, `if( X )`).
//   pass B  find whole-identifier uses of each bound constant — those are the `if constexpr` sites, and the
//           gate's real, previously invisible surface.
// Both passes are whole-identifier (`checkWalls` never matches `kWalls`), both run on C-family source only
// (a `#define` gate is a preprocessor construct, so nothing else can consume one as a value), and pass B
// treats a file declaring its OWN constant of that name as SHADOWING the gate's — plain C++ scoping, and the
// difference between a real answer and six phantom sites on any repo with short house-style constant names.
//
// ── the three gate KINDS mean three different things by "flip" ───────────────────────────────────────────
// compile  `-DNAME=1` (or editing the header default). The regions/branches below become live code. Exact.
// cmake    `-DNAME=ON` at configure time, which the build turns into a `-DNAME=1` compile definition — so
//          the C++ side is IDENTICAL to the compile case and is reported the same way. What DIFFERS is that
//          a CMake switch also steers the BUILD GRAPH (an `if(NAME) target_sources(...)`/`target_link_...`
//          can add whole translation units, which no C++-side analysis can see). Those CMake read sites are
//          reported separately as <c/> build rows, flagged as an unfollowed reach rather than folded in.
// env      RUNTIME. There is no delimited region — the branch is taken per process, per read. The hosts are
//          the symbols that CONSULT the variable, and the radius is theirs; `runtime="1"` says the whole
//          report is conditional at every read site rather than settled at compile time.
//
// Determinism: gates iterate in name order from a gtl::btree_map; files come from the caller's sorted ingest
// list; every emitted list is sorted by an explicit total order. No wall clock, no address hashing.

#include "model.h"
#include "graph.h"        // transitiveCallers / forwardReach — the SAME primitives --impact and --test-gate use
#include "filter.h"       // isTestPath — the shared test partition
#include "arch.h"         // relForHash
#include "darkflags.h"    // the gate harvest, reused whole
#include "serialize.h"    // escapeXml
#include "infra/Diagnostics.h"   // DEGRADED_PATH_ALERT

#include "btree.hpp"      // gtl::btree_map — sorted iteration (house rule: never std::map)

#include <algorithm>
#include <cctype>
#include <cstdio>
#include <cstdlib>
#include <functional>
#include <string>
#include <string_view>
#include <vector>

namespace rw
{
namespace flipimpact
{

constexpr std::size_t   kMaxFamily     = 64;   // gates one flip may light — an alias fan-out past this is a table, not a switch
constexpr std::uint32_t kMaxChainDepth = 8;    // alias-chain depth cap (mirrors darkflags::kMaxAliasDepth)
constexpr std::size_t   kMaxBindings   = 32;   // value-style constants tracked — bounds pass B's needle count
constexpr std::size_t   kMaxFlipRows   = 25;   // per emitted list; --detail lifts every cap
constexpr std::size_t   kMaxNearMisses = 5;    // "did you mean" suggestions on an unknown gate name

// ── result model (POD-ish, ids/handles over pointers) ────────────────────────────────────────────────────

// One `#if` region the flip makes live, already joined to the symbols it sits inside.
struct LitRegion
{
    std::string   gate;                     // WHICH family member owns it (a master's rows name its children)
    std::string   path;
    std::uint32_t line     = 0;             // the `#if` line
    std::uint32_t lines    = 0;             // lines strictly inside
    std::uint32_t hostCount = 0;            // indexed defs intersecting the span (0 ⇒ file-scope declarations only)
};

// One C++ branch site the flip makes live: either a direct value read of the macro, or a use of the
// `constexpr bool` it was bound to (`via` names the binding; empty ⇒ the macro was read directly).
struct LitBranch
{
    std::string   gate;
    std::string   via;
    std::string   path;
    std::uint32_t line = 0;
    NodeId        host = kNoNode;
};

// `inline constexpr bool kWalls = CANYON_RRF_WALLS != 0;` — the bridge from a macro to ordinary C++ names.
struct ValueBinding
{
    std::string   name;                     // the declared constant (`kWalls`)
    std::string   gate;                     // the family member it reads
    std::string   path;
    std::uint32_t line = 0;
    std::uint32_t uses = 0;                 // whole-identifier use sites found in pass B
};

// One member of the family a single flip lights: the gate itself plus every gate that aliases to it.
struct FamilyMember
{
    std::string   name;
    bool          isSelf   = false;         // the gate actually named on the command line
    std::uint32_t regions  = 0;
    std::uint32_t lines    = 0;
    std::uint32_t branches = 0;
};

struct FlipResult
{
    bool                      ok          = false;   // false ⇒ refuse loudly; never emit an empty-looking success
    bool                      unknownGate = false;
    std::vector<std::string>  nearMisses;            // cheap suggestions for an unknown name

    // the flipped gate's own identity, copied from the harvest (never recomputed)
    std::string               name;
    darkflags::GateKind       kind = darkflags::GateKind::Compile;
    std::string               def;
    bool                      isDark    = true;
    bool                      isRuntime = false;     // env lane — "lights up" is conditional at every read
    darkflags::Site           defSite;
    bool                      hasAlso   = false;
    darkflags::GateKind       alsoKind  = darkflags::GateKind::Compile;
    std::string               alsoDef;
    darkflags::Site           alsoSite;

    std::string               parent;                // set when the FLIPPED gate is itself an alias child
    std::uint32_t             siblingCount = 0;      // other children of that parent (what the parent's flip adds)
    bool                      familyCapped = false;

    std::vector<FamilyMember> family;
    std::vector<LitRegion>    regions;
    std::vector<LitBranch>    branches;
    std::vector<ValueBinding> bindings;
    std::vector<darkflags::Site> buildSites;         // CMake read sites — the reach this verb does NOT follow

    std::vector<NodeId>       hosts;                 // symbols holding newly-live code (ccx desc, path, name)
    std::vector<NodeId>       untested;              // hosts no test transitively reaches
    std::vector<NodeId>       downstream;            // what the hosts transitively CALL (they start executing)
    std::vector<std::uint32_t> tests;                // test files that transitively reach the hosts (path asc)
    std::vector<char>         testReach;             // per-node coverage mask (what the test files transitively call) —
                                                     // kept so the emitter's tested= column is the SAME traversal that
                                                     // decided `untested`, never a second one that could disagree

    std::uint32_t             totalRegions = 0, totalLines = 0;
    std::uint32_t             fileScopeLights = 0;   // lit sites (regions OR branches) that sit in no indexed def —
                                                     // a guarded member field, a file-scope constexpr, a doc code
                                                     // fence. Real code, no host: counted rather than silently lost.
    std::size_t               dependents = 0;        // transitive callers of the hosts
    std::size_t               filesScanned = 0;
};

// ── lexical helpers (whole-identifier matching is the whole ballgame — `checkWalls` is not `kWalls`) ─────
// All of these live in darkflags.h beside identByte and are shared with layout.h / docdrift.h — imported,
// never re-rolled. `checkWalls` is not `kWalls`, and exactly one function in the tree decides that.
using darkflags::wholeWordAt;
using darkflags::containsWord;
using darkflags::firstWordAt;
using darkflags::endsWithView;
using darkflags::forEachLine;

// The value lane runs on C-FAMILY SOURCE ONLY, by an allowlist rather than a prose denylist. That is not a
// convenience: a `#ifndef`/`#define` gate and a CMake `-DNAME=1` compile definition are C-preprocessor
// constructs, so the only place a gate can be consumed AS A VALUE is a translation unit the preprocessor
// runs over. A denylist gets this wrong the first time it meets a file type nobody listed — measured: a
// committed HTML audit report quoting the gate name produced eight phantom "branch sites". (The env lane
// does not use this table: `getenv` is language-agnostic and takes its sites from the harvest instead.)
inline constexpr std::string_view kCFamilyExtTable[] = {
    ".h", ".hpp", ".hh", ".hxx", ".h++", ".inl", ".ipp",
    ".c", ".cc", ".cpp", ".cxx", ".c++", ".m", ".mm", ".metal", ".cu", ".cuh",
};

template<std::size_t N>
inline bool hasAnyExt( std::string_view p, const std::string_view ( &table )[N] ) noexcept
{
    for( std::string_view e : table )
    {
        if( endsWithView( p, e ) )
        {
            return true;
        }
    }
    return false;
}

inline bool isCFamilyPath( std::string_view p ) noexcept { return hasAnyExt( p, kCFamilyExtTable ); }

// The ENV lane cannot use the allowlist above — `getenv` / `os.environ.get` is language-agnostic and the
// harvest finds it in Python and shell too — so it screens the other way: drop the file types where a gate
// name is being TALKED ABOUT rather than read (a fenced snippet in a design doc, a committed audit report).
inline constexpr std::string_view kProseExtTable[] = {
    ".md", ".markdown", ".mdx", ".txt", ".rst", ".adoc", ".html", ".htm", ".csv", ".tsv", ".ipynb",
};

inline bool isProsePath( std::string_view p ) noexcept { return hasAnyExt( p, kProseExtTable ); }

inline bool isCMakePath( std::string_view p ) noexcept
{
    return endsWithView( p, "CMakeLists.txt" ) || endsWithView( p, ".cmake" );
}

// A line the VALUE lane is allowed to read: ordinary code. A `#` line belongs to the directive lane (which
// darkflags already harvested), and a line-comment / block-comment continuation is prose about the gate,
// not a use of it. Single-line judgement — see the LIMITS note in the help text.
inline bool isCodeLine( std::string_view trimmed ) noexcept
{
    if( trimmed.empty() )
    {
        return false;
    }
    if( trimmed[0] == '#' )
    {
        return false;
    }
    if( trimmed[0] == '*' )
    {
        return false;
    }
    if( trimmed.size() >= 2 && trimmed[0] == '/' && ( trimmed[1] == '/' || trimmed[1] == '*' ) )
    {
        return false;
    }
    return true;
}

// `inline constexpr bool kWalls = CANYON_RRF_WALLS != 0;` — given the offset the gate name sits at, return
// the DECLARED constant's name, or "" when this line is not a binding. Requirements, all cheap and all
// necessary: a real `=` left of the mention (not `==`/`!=`/`<=`/`>=`), a `constexpr` or `const` whole word
// left of it (only a compile-time constant can carry the gate into an `if constexpr`), and a declarator
// identifier immediately before the `=`.
inline std::string_view bindingNameOnLine( std::string_view line, std::size_t gateAt )
{
    const std::size_t eq = line.rfind( '=', gateAt );
    if( eq == std::string_view::npos || eq == 0 )
    {
        return {};
    }
    if( eq + 1 < line.size() && line[eq + 1] == '=' )
    {
        return {};
    }
    const char prev = line[ eq - 1 ];
    if( prev == '=' || prev == '!' || prev == '<' || prev == '>' )
    {
        return {};
    }

    const std::string_view head = line.substr( 0, eq );
    if( !containsWord( head, "constexpr" ) && !containsWord( head, "const" ) )
    {
        return {};
    }

    std::size_t e = head.size();
    while( e > 0 && std::isspace( (unsigned char)head[e - 1] ) )
    {
        --e;
    }
    std::size_t s = e;
    while( s > 0 && darkflags::identByte( (unsigned char)head[s - 1] ) )
    {
        --s;
    }
    if( s == e || std::isdigit( (unsigned char)head[s] ) )
    {
        return {};
    }
    return head.substr( s, e - s );
}

// Does this line DECLARE a `const`/`constexpr` named `name` (`constexpr int kTurns = 2;`)? Pass B uses this
// as a SHADOW test: a file that declares its own constant of that name is talking about ITS constant, not
// the gate's — plain C++ scoping. Without it the lane cross-wires on short house-style names: measured on
// the motivating repo, a `constexpr int kTurns = 2` and a `constexpr float kSpeed = 1.5f` in an unrelated
// weapons header contributed six phantom branch sites (and four phantom hosts) to a canyon-generator gate.
inline bool declaresConstant( std::string_view line, std::string_view name )
{
    for( std::size_t at = line.find( name ); at != std::string_view::npos; at = line.find( name, at + 1 ) )
    {
        if( !wholeWordAt( line, at, name.size() ) )
        {
            continue;
        }
        std::size_t j = at + name.size();
        while( j < line.size() && std::isspace( (unsigned char)line[j] ) )
        {
            ++j;
        }
        if( j >= line.size() || line[j] != '=' )
        {
            continue;
        }
        if( j + 1 < line.size() && line[j + 1] == '=' )
        {
            continue;
        }
        const std::string_view head = line.substr( 0, at );
        if( containsWord( head, "constexpr" ) || containsWord( head, "const" ) )
        {
            return true;
        }
    }
    return false;
}

// ── line-space symbol lookup ─────────────────────────────────────────────────────────────────────────────
// `--grep` finds a hit's enclosing symbol in BYTE space (sigStartByte..endByte). A `#if` region is delimited
// by LINES, so the same containment question is answered here in line space from the fields the model
// already carries: a def occupies [line, line + max(loc,1) - 1]. Built once per flip, not per lookup.
struct SymbolLineIndex
{
    std::vector<std::vector<NodeId>> byFile;        // fileId → def ids, ascending start line
};

inline SymbolLineIndex buildSymbolLineIndex( const IngestResult& ing )
{
    // model.h::symbolsByFile is the shared bucket-and-sort (see its note); this index keeps EVERY symbol and
    // orders by source line, tie-broken on the id, exactly as it always did.
    SymbolLineIndex ix;
    ix.byFile = symbolsByFile( ing,
                               []( const Symbol& ) { return true; },
                               [ & ]( NodeId a, NodeId b )
                               { return ing.symbols[a].line != ing.symbols[b].line ? ing.symbols[a].line < ing.symbols[b].line : a < b; } );
    return ix;
}

inline std::uint32_t symbolEndLine( const Symbol& s ) noexcept
{
    return s.line + ( s.loc > 0 ? s.loc - 1 : 0 );
}

// The defs a `#if` region [lo, hi] makes live, in the two shapes a region actually takes:
//   CONTAINED — a def wholly inside the region: a whole function the flip adds.
//   CONTAINING — the INNERMOST def the region's opening line sits in: the function holding the `#if`.
// Deliberately NOT "every def that intersects". A tree-sitter def extent can over-reach in a
// preprocessor-heavy ObjC++/C++ file (a parse recovering past a directive), and plain intersection then
// credits an unrelated earlier function as a host — measured on the motivating repo, where a `#if` inside
// a 3-line function also named the 40-line function above it. Innermost-wins is exactly the rule --grep's
// `in=` breadcrumb uses, so a flip host and a grep hit never disagree about which function code is in.
inline std::vector<NodeId> hostsForSpan( const IngestResult& ing, const SymbolLineIndex& ix,
                                         std::uint32_t fileId, std::uint32_t lo, std::uint32_t hi )
{
    std::vector<NodeId> hosts;
    if( fileId >= ix.byFile.size() )
    {
        return hosts;
    }
    NodeId innermost = kNoNode;
    for( NodeId id : ix.byFile[ fileId ] )
    {
        const Symbol& s = ing.symbols[ id ];
        if( s.line > hi )
        {
            break; // sorted by start line ⇒ nothing later can begin inside
        }
        const std::uint32_t end = symbolEndLine( s );
        if( s.line >= lo && end <= hi )
        {
            hosts.push_back( id );
            continue;
        }
        if( s.line <= lo && end >= lo && ( innermost == kNoNode || s.line >= ing.symbols[innermost].line ) )
        {
            innermost = id;
        }
    }
    if( innermost != kNoNode )
    {
        hosts.push_back( innermost );
    }
    return hosts;
}

// the INNERMOST def covering one line (greatest start line among the covers) — a branch site sits in exactly
// one function, and reporting its whole enclosing-class chain instead would blur the radius.
inline NodeId innermostAtLine( const IngestResult& ing, const SymbolLineIndex& ix, std::uint32_t fileId, std::uint32_t line )
{
    if( fileId >= ix.byFile.size() )
    {
        return kNoNode;
    }
    NodeId best = kNoNode;
    for( NodeId id : ix.byFile[ fileId ] )
    {
        const Symbol& s = ing.symbols[ id ];
        if( s.line > line )
        {
            break;
        }
        if( symbolEndLine( s ) >= line && ( best == kNoNode || s.line >= ing.symbols[best].line ) )
        {
            best = id;
        }
    }
    return best;
}

// ── the family a single flip lights ──────────────────────────────────────────────────────────────────────
// Descendants of `root` over the IMMEDIATE alias link, breadth-first and bounded: flipping a master lights
// every gate that aliases (transitively) to it. Flipping a leaf lights only the leaf — which falls out of
// the same walk returning a single-element family.
inline std::vector<std::string> aliasDescendants( const gtl::btree_map<std::string, darkflags::Gate>& byName,
                                                  const std::string& root, bool& capped )
{
    std::vector<std::string> family{ root };
    capped = false;
    for( std::uint32_t depth = 0; depth < kMaxChainDepth; ++depth )
    {
        std::vector<std::string> next;
        for( const auto& [ name, g ] : byName )                       // name order ⇒ deterministic family order
        {
            if( g.aliasParent.empty() )
            {
                continue;
            }
            if( std::find( family.begin(), family.end(), name ) != family.end() )
            {
                continue;
            }
            if( std::find( family.begin(), family.end(), g.aliasParent ) == family.end() )
            {
                continue;
            }
            next.push_back( name );
        }
        if( next.empty() )
        {
            break;
        }
        for( std::string& n : next )
        {
            if( family.size() >= kMaxFamily )
            {
                capped = true;
                break;
            }
            family.push_back( std::move( n ) );
        }
        if( capped )
        {
            break;
        }
    }
    if( capped )
    {
        DEGRADED_PATH_ALERT( "flip: alias family hit the fan-out cap — the radius below is a lower bound" );
    }
    return family;
}

// ── the value lane (the one piece of new analysis in this file) ──────────────────────────────────────────

struct ValueScanResult
{
    std::vector<LitBranch>    branches;
    std::vector<ValueBinding> bindings;
};

// darkflags' line splitter with the value lane's filter on top: ORDINARY-CODE lines only. Both passes go
// through here so "what counts as a scannable line" is decided in exactly one place.
template<class Visit>
inline void forEachCodeLine( std::string_view bytes, Visit&& visit )
{
    forEachLine( bytes, [ & ]( std::string_view line, std::uint32_t lineNo ) { if( isCodeLine( darkflags::trimView( line ) ) ) { visit( line, lineNo ); } } );
}

// The C-family files worth opening for `needles`, as (fileId, display path) — the needles-first screen that
// keeps both passes off the ~97% of a tree that never mentions the gate family.
inline bool fileMayHold( const IngestResult& ing, std::uint32_t fileId, std::string& bytesOut )
{
    if( !isCFamilyPath( ing.files[fileId] ) )
    {
        return false;
    }
    return darkflags::readWhole( diskPath( ing, fileId ), bytesOut );
}

// PASS A — every ordinary-code mention of a family gate, split into value BINDINGS (`constexpr bool kWalls =
// GATE != 0`) and direct value READS (`GATE ? a : b`). The bindings are the bridge pass B walks across.
inline void scanGateMentions( const IngestResult& ing, const std::string& root,
                              const std::vector<std::string>& family, ValueScanResult& out )
{
    std::string bytes;
    for( std::uint32_t f = 0; f < ing.files.size(); ++f )
    {
        if( !fileMayHold( ing, f, bytes ) )
        {
            continue;
        }
        std::vector<std::string_view> needles;                     // the family names this file actually contains
        for( const std::string& gname : family )
        {
            if( bytes.find( gname ) != std::string::npos )
            {
                needles.push_back( gname );
            }
        }
        if( needles.empty() )
        {
            continue;
        }

        const std::string rel( relForHash( ing.files[f], root ) );
        forEachCodeLine( bytes, [ & ]( std::string_view line, std::uint32_t lineNo )
        {
            for( std::string_view gname : needles )
            {
                const std::size_t at = firstWordAt( line, gname );
                if( at == std::string_view::npos )
                {
                    continue; // one row per (line, gate) — a repeat is the same site
                }
                const std::string_view bound = bindingNameOnLine( line, at );
                if( !bound.empty() )
                {
                    out.bindings.push_back( ValueBinding { std::string( bound ), std::string( gname ), rel, lineNo, 0 } );
                }
                else
                {
                    out.branches.push_back( LitBranch { std::string( gname ), {}, rel, lineNo, kNoNode } );
                }
            }
        } );
    }

    // one row per bound constant (a header re-included is still one binding), bounded for pass B's needle set
    std::sort( out.bindings.begin(), out.bindings.end(), []( const ValueBinding& a, const ValueBinding& b )
               { return a.name != b.name ? a.name < b.name : ( a.path != b.path ? a.path < b.path : a.line < b.line ); } );
    out.bindings.erase( std::unique( out.bindings.begin(), out.bindings.end(),
                                     []( const ValueBinding& a, const ValueBinding& b ) { return a.name == b.name; } ), out.bindings.end() );
    if( out.bindings.size() > kMaxBindings )
    {
        DEGRADED_PATH_ALERT( "flip: more value bindings than the scan cap — branch sites below are a lower bound" );
        out.bindings.resize( kMaxBindings );
    }
}

// PASS B — every whole-identifier use of a bound constant: the `if constexpr` sites, i.e. the gate's real
// and otherwise invisible surface. One walk per file does two jobs, because the SHADOW test has to see the
// whole file: a hit is only kept if the file did not also declare its own constant of that name, and that
// declaration can sit BELOW the use (a class member, a later block), so hits are held and filtered at the end.
inline void scanBindingUses( const IngestResult& ing, const std::string& root, ValueScanResult& out )
{
    std::string bytes;
    for( std::uint32_t f = 0; f < ing.files.size(); ++f )
    {
        if( !fileMayHold( ing, f, bytes ) )
        {
            continue;
        }
        std::vector<std::size_t> needles;                          // indices into out.bindings
        for( std::size_t b = 0; b < out.bindings.size(); ++b )
        {
            if( bytes.find( out.bindings[b].name ) != std::string::npos )
            {
                needles.push_back( b );
            }
        }
        if( needles.empty() )
        {
            continue;
        }

        const std::string        rel( relForHash( ing.files[f], root ) );
        std::vector<char>        shadowed( needles.size(), 0 );
        std::vector<LitBranch>   pending;
        std::vector<std::size_t> pendingNeedle;
        forEachCodeLine( bytes, [ & ]( std::string_view line, std::uint32_t lineNo )
        {
            for( std::size_t k = 0; k < needles.size(); ++k )
            {
                const ValueBinding& bind      = out.bindings[ needles[k] ];
                const bool          isOwnDecl = rel == bind.path && lineNo == bind.line;
                if( isOwnDecl )
                {
                    continue; // a declaration is not a use of itself
                }
                if( declaresConstant( line, bind.name ) )      { shadowed[k] = 1; continue; }
                if( firstWordAt( line, bind.name ) == std::string_view::npos )
                {
                    continue;
                }
                pending.push_back( LitBranch{ bind.gate, bind.name, rel, lineNo, kNoNode } );
                pendingNeedle.push_back( k );
            }
        } );
        for( std::size_t i = 0; i < pending.size(); ++i )
        {
            if( shadowed[pendingNeedle[i]] )
            {
                continue;
            }
            ++out.bindings[ needles[ pendingNeedle[i] ] ].uses;
            out.branches.push_back( std::move( pending[i] ) );
        }
    }
}

// The value lane in full: two needles-first passes over the corpus. `--flip` is a diagnostic verb, not the
// warm default path, and the second read hits the page cache the first one warmed.
inline ValueScanResult scanValueLane( const IngestResult& ing, const std::string& root,
                                      const std::vector<std::string>& family )
{
    ValueScanResult out;
    if( family.empty() )
    {
        return out;
    }
    scanGateMentions( ing, root, family, out );
    if( !out.bindings.empty() )
    {
        scanBindingUses( ing, root, out ); // a pure `#if` gate has nothing to cross to
    }
    return out;
}

// ── near-miss suggestions for an unknown gate name ───────────────────────────────────────────────────────
// Gate names are SCREAMING_SNAKE and usually family-prefixed, so the useful hint is containment
// (`RRF_ALL` → `CANYON_RRF_ALL`), with a shared-prefix score as the fallback. (main.cpp's didYouMean scores
// the SYMBOL pool for typo'd function names — a different pool answering a different question.)
inline std::vector<std::string> nearestGateNames( const std::vector<darkflags::Gate>& gates, std::string_view want )
{
    const auto lower = []( std::string_view v ) { std::string o; o.reserve( v.size() ); for( char c : v ) { o.push_back( char( std::tolower( (unsigned char)c ) ) ); } return o; };
    const std::string wantLow = lower( want );

    constexpr int     kContainsBonus = 1000;   // a literal containment beats any prefix score, by construction
    struct Cand { int score; std::string name; };
    std::vector<Cand> cands;
    for( const darkflags::Gate& g : gates )
    {
        const std::string low = lower( g.name );
        int score = 0;
        if( !wantLow.empty() && low.find( wantLow ) != std::string::npos )
        {
            score += kContainsBonus;
        }
        std::size_t pfx = 0;
        const std::size_t lim = std::min( low.size(), wantLow.size() );
        while( pfx < lim && low[pfx] == wantLow[pfx] )
        {
            ++pfx;
        }
        score += int( pfx ) * 4 - std::abs( int( low.size() ) - int( wantLow.size() ) );
        if( score > 8 )
        {
            cands.push_back( Cand { score, g.name } );
        }
    }
    std::sort( cands.begin(), cands.end(), []( const Cand& a, const Cand& b )
               { return a.score != b.score ? a.score > b.score : a.name < b.name; } );
    // When ANY gate literally contains what was typed, that is the answer — offering four family siblings
    // beside it just because they share the `FIXTURE_` prefix makes the hint noise instead of a fix.
    if( !cands.empty() && cands.front().score >= kContainsBonus )
    {
        cands.erase( std::find_if( cands.begin(), cands.end(), []( const Cand& c ) { return c.score < kContainsBonus; } ), cands.end() );
    }
    if( cands.size() > kMaxNearMisses )
    {
        cands.resize( kMaxNearMisses );
    }

    std::vector<std::string> out;
    out.reserve( cands.size() );
    for( Cand& c : cands )
    {
        out.push_back( std::move( c.name ) );
    }
    return out;
}

// ── the computation ──────────────────────────────────────────────────────────────────────────────────────

// The two lookups every lit site needs, built once: line → innermost def, and the HARVEST's spelling of a
// path (root-relative, exactly what darkflags::Region/Site carry) → fileId.
struct SiteLocator
{
    SymbolLineIndex                     lines;
    HashMap<std::string, std::uint32_t> fileIdOf;
};

inline SiteLocator buildSiteLocator( const IngestResult& ing, const std::string& root )
{
    SiteLocator loc;
    loc.lines = buildSymbolLineIndex( ing );
    loc.fileIdOf.reserve( ing.files.size() );
    for( std::uint32_t f = 0; f < ing.files.size(); ++f )
    {
        loc.fileIdOf[ std::string( relForHash( ing.files[f], root ) ) ] = f;
    }
    return loc;
}

inline std::uint32_t fileIdFor( const SiteLocator& loc, const std::string& rel ) noexcept
{
    const auto it = loc.fileIdOf.find( rel );
    return it == loc.fileIdOf.end() ? UINT32_MAX : it->second;
}

// Join ONE branch site to the def it sits inside. A site with no host is still real code becoming live (a
// file-scope constexpr, a doctest macro body tree-sitter does not index) — counted, never silently dropped.
inline void attachHost( const IngestResult& ing, const SiteLocator& loc, LitBranch& b, FlipResult& res )
{
    const std::uint32_t f = fileIdFor( loc, b.path );
    if( f != UINT32_MAX )
    {
        b.host = innermostAtLine( ing, loc.lines, f, b.line );
    }
    if( b.host != kNoNode )
    {
        res.hosts.push_back( b.host ); // deduped once, in computeFlip
    }
    else
    {
        ++res.fileScopeLights;
    }
}

// The `#if` lane: every family member's region spans, joined to the defs they hold. Also picks off each
// member's CMake read sites, which are build-graph reach this verb reports but deliberately does not follow.
inline void collectRegions( const IngestResult& ing, const SiteLocator& loc,
                            const gtl::btree_map<std::string, darkflags::Gate>& byName,
                            const std::vector<std::string>& family, FlipResult& res )
{
    for( const std::string& member : family )
    {
        const auto m = byName.find( member );
        if( m == byName.end() )
        {
            continue;
        }
        for( const darkflags::Region& r : m->second.regionSpans )
        {
            LitRegion           lit{ member, r.site.path, r.site.line, r.lines, 0 };
            const std::uint32_t f = fileIdFor( loc, r.site.path );
            if( f != UINT32_MAX )
            {
                const std::vector<NodeId> hosts = hostsForSpan( ing, loc.lines, f, r.site.line, darkflags::regionEndLine( r ) );
                lit.hostCount = std::uint32_t( hosts.size() );
                res.hosts.insert( res.hosts.end(), hosts.begin(), hosts.end() );
            }
            if( lit.hostCount == 0 )
            {
                ++res.fileScopeLights;
            }
            res.totalRegions += 1;
            res.totalLines   += r.lines;
            res.regions.push_back( std::move( lit ) );
        }
        for( const darkflags::Site& s : m->second.reads )
        {
            if( isCMakePath( s.path ) )
            {
                res.buildSites.push_back( s );
            }
        }
    }
}

// The ENV lane: no delimited region exists, so the branch points are the getenv read sites the harvest
// already found, and the hosts are the symbols that consult the variable. Language-agnostic on purpose —
// the harvest recognises Python's os.environ too, so the C-family allowlist must NOT apply here.
inline void collectEnvBranches( const IngestResult& ing, const SiteLocator& loc,
                                const gtl::btree_map<std::string, darkflags::Gate>& byName,
                                const std::vector<std::string>& family, FlipResult& res )
{
    for( const std::string& member : family )
    {
        const auto m = byName.find( member );
        if( m == byName.end() )
        {
            continue;
        }
        for( const darkflags::Site& s : m->second.reads )
        {
            if( isCMakePath( s.path ) || isProsePath( s.path ) )
            {
                continue; // a build row / a doc mention, not a read
            }
            LitBranch b{ member, "getenv", s.path, s.line, kNoNode };
            attachHost( ing, loc, b, res );
            res.branches.push_back( std::move( b ) );
        }
    }
}

// The VALUE lane's sites, hosted. (The scan itself is scanValueLane above; this only joins it to the index.)
inline void collectValueBranches( const IngestResult& ing, const SiteLocator& loc, const std::string& root,
                                  const std::vector<std::string>& family, FlipResult& res )
{
    ValueScanResult vs = scanValueLane( ing, root, family );
    res.bindings = std::move( vs.bindings );
    for( LitBranch& b : vs.branches )
    {
        attachHost( ing, loc, b, res );
        res.branches.push_back( std::move( b ) );
    }
}

// The radius, from the hosts: who depends on them (in-edges), which of those are tests, what the tests
// cover, and what the hosts themselves call. Two graph primitives — transitiveCallers and forwardReach —
// exactly as --impact and --test-gate use them; no third traversal is invented here.
inline void computeRadius( const IngestResult& ing, const Graph& g, FlipResult& res )
{
    if( res.hosts.empty() )
    {
        return;
    }
    const std::uint32_t F = std::uint32_t( ing.files.size() );
    const std::uint32_t N = std::uint32_t( ing.symbols.size() );

    const std::vector<NodeId> up = transitiveCallers( g, res.hosts );
    res.dependents = up.size();
    std::vector<char> testFileSeen( F, 0 );
    const auto        noteTestFile = [ & ]( NodeId n )
    {
        const std::uint32_t f = ing.symbols[n].fileId;
        if( isTestPath( ing.files[f] ) && !testFileSeen[f] ) { testFileSeen[f] = 1; res.tests.push_back( f ); }
    };
    for( NodeId n : up )
    {
        noteTestFile( n );
    }
    for( NodeId h : res.hosts )
    {
        noteTestFile( h ); // a host that IS test code is its own test
    }
    std::sort( res.tests.begin(), res.tests.end(), [ & ]( std::uint32_t a, std::uint32_t b ) { return ing.files[a] < ing.files[b]; } );

    // coverage — the forward dual from every test symbol (situ.h's convention, same primitive)
    std::vector<NodeId> testSeeds;
    for( NodeId i = 0; i < N; ++i )
    {
        if( isTestPath( ing.files[ing.symbols[i].fileId] ) )
        {
            testSeeds.push_back( i );
        }
    }
    res.testReach = forwardReach( g, testSeeds );
    for( NodeId h : res.hosts )
    {
        if( h < res.testReach.size() && !res.testReach[h] )
        {
            res.untested.push_back( h );
        }
    }

    // what the newly-live code will now CALL — the forward reach, minus the hosts themselves
    const std::vector<char> down = forwardReach( g, res.hosts );
    std::vector<char>       isHost( N, 0 );
    for( NodeId h : res.hosts )
    {
        if( h < N )
        {
            isHost[h] = 1;
        }
    }
    for( NodeId i = 0; i < N; ++i )
    {
        if( down[i] && !isHost[i] )
        {
            res.downstream.push_back( i );
        }
    }
}

// Every emitted list gets a total order here — determinism is a property of this one function, not of a
// dozen scattered sorts. Symbol lists lead with the riskiest (situ.h's untested ordering).
inline void orderFlipResult( const IngestResult& ing, FlipResult& res )
{
    std::sort( res.regions.begin(), res.regions.end(), []( const LitRegion& a, const LitRegion& b )
               { return a.path != b.path ? a.path < b.path : ( a.line != b.line ? a.line < b.line : a.gate < b.gate ); } );
    std::sort( res.branches.begin(), res.branches.end(), []( const LitBranch& a, const LitBranch& b )
               { return a.path != b.path ? a.path < b.path : ( a.line != b.line ? a.line < b.line : a.gate < b.gate ); } );
    std::sort( res.buildSites.begin(), res.buildSites.end(), darkflags::siteLess );
    res.buildSites.erase( std::unique( res.buildSites.begin(), res.buildSites.end(),
                                       []( const darkflags::Site& a, const darkflags::Site& b )
                                       { return a.path == b.path && a.line == b.line; } ), res.buildSites.end() );

    const auto bySymbolRisk = [ & ]( NodeId a, NodeId b )
    {
        if( ing.symbols[a].ccx != ing.symbols[b].ccx )
        {
            return ing.symbols[a].ccx > ing.symbols[b].ccx;
        }
        const std::string& fa = ing.files[ ing.symbols[a].fileId ];
        const std::string& fb = ing.files[ ing.symbols[b].fileId ];
        if( fa != fb )
        {
            return fa < fb;
        }
        if( ing.symbols[a].name != ing.symbols[b].name )
        {
            return ing.symbols[a].name < ing.symbols[b].name;
        }
        return a < b;
    };
    std::sort( res.hosts.begin(),      res.hosts.end(),      bySymbolRisk );
    std::sort( res.untested.begin(),   res.untested.end(),   bySymbolRisk );
    std::sort( res.downstream.begin(), res.downstream.end(), bySymbolRisk );
}

// Copy the flipped gate's identity off the harvest (never recomputed) and count the siblings a parent's
// flip would add beyond this one.
inline void adoptGateIdentity( const gtl::btree_map<std::string, darkflags::Gate>& byName,
                               const darkflags::Gate& gate, FlipResult& res )
{
    res.name      = gate.name;
    res.kind      = gate.kind;
    res.def       = gate.def;
    res.isDark    = darkflags::isDarkDefault( gate.def );
    res.isRuntime = gate.kind == darkflags::GateKind::Env;
    res.defSite   = gate.defSite;
    res.hasAlso   = gate.hasAlso;
    res.alsoKind  = gate.alsoKind;
    res.alsoDef   = gate.alsoDef;
    res.alsoSite  = gate.alsoSite;
    res.parent    = gate.aliasParent;
    if( res.parent.empty() )
    {
        return;
    }
    for( const auto& [ name, other ] : byName )
    {
        if( name != gate.name && other.aliasParent == res.parent )
        {
            ++res.siblingCount;
        }
    }
}

inline FlipResult computeFlip( const IngestResult& ing, const Graph& g, const std::string& root,
                               const std::vector<std::string>& excludes, std::string_view gateName )
{
    FlipResult res;

    // (0) the harvest — reused whole. keepUnreadGates: an alias CHILD consumed only as a value has no
    //     preprocessor reader, and the dead-name filter would delete exactly the gates a master's flip lights.
    const darkflags::FlagsResult harvest = darkflags::computeFlags( ing, root, excludes, {}, /*keepUnreadGates=*/true );
    res.filesScanned = harvest.filesScanned;

    gtl::btree_map<std::string, darkflags::Gate> byName;
    for( const darkflags::Gate& gate : harvest.gates )
    {
        byName[gate.name] = gate;
    }

    const auto self = byName.find( std::string( gateName ) );
    if( self == byName.end() )
    {
        res.unknownGate = true;
        res.nearMisses  = nearestGateNames( harvest.gates, gateName );
        return res;                                                 // ok stays false — the caller refuses loudly
    }
    const darkflags::Gate& gate = self->second;
    adoptGateIdentity( byName, gate, res );

    // (1) the family this ONE flip lights — the gate plus every gate that aliases (transitively) to it
    const std::vector<std::string> family = aliasDescendants( byName, gate.name, res.familyCapped );

    // (2) the lit sites, by lane, each joined to the def that holds it
    const SiteLocator loc = buildSiteLocator( ing, root );
    collectRegions( ing, loc, byName, family, res );
    if( res.isRuntime )
    {
        collectEnvBranches( ing, loc, byName, family, res );
    }
    else
    {
        collectValueBranches( ing, loc, root, family, res );
    }

    // (3) the per-member roll-up the report leads with (a master's weight IS its children's)
    for( const std::string& member : family )
    {
        FamilyMember fm{ member, member == gate.name, 0, 0, 0 };
        const auto   m = byName.find( member );
        if( m != byName.end() ) { fm.regions = m->second.regions; fm.lines = m->second.guardedLines; }
        for( const LitBranch& b : res.branches )
        {
            if( b.gate == member )
            {
                ++fm.branches;
            }
        }
        res.family.push_back( std::move( fm ) );
    }

    // (4) the radius — one dedupe of the hosts the three collectors accumulated, then the two traversals
    std::sort( res.hosts.begin(), res.hosts.end() );
    res.hosts.erase( std::unique( res.hosts.begin(), res.hosts.end() ), res.hosts.end() );
    computeRadius( ing, g, res );

    // (5) one total order over every emitted list, once, after every list exists
    orderFlipResult( ing, res );

    res.ok = true;
    return res;
}

// ── XML emission (G4: minified, xmllint-clean; no `--` inside a comment, no `\n` outside CDATA) ──────────

using XmlEscaper = std::function<std::string( std::string_view )>;

// the qualified display name a symbol row shows (`ns::Class::method`) — the same scope+"::"+name join
// --grep's breadcrumb uses, so a flip row and a grep hit name the same thing the same way.
inline std::string qualifiedName( const Symbol& s )
{
    return s.scope.empty() ? s.name : ( s.scope + "::" + s.name );
}

// Rows + the honest `<more …>` remainder, WITHOUT a wrapper element (the lights block holds two of these).
// Returns how many it printed. Every capped list in the report goes through here, so "cap then admit what
// was elided" is written once instead of six times.
template<class Seq, class Row>
inline std::size_t writeCappedRows( std::FILE* out, const char* moreAttr, const Seq& seq, std::size_t maxRows, Row&& row )
{
    std::size_t shown = 0;
    for( const auto& item : seq )
    {
        if( shown >= maxRows )
        {
            break;
        }
        ++shown;
        row( item );
    }
    if( seq.size() > shown )
    {
        std::fprintf( out, "<more %s=\"%zu\"/>", moreAttr, seq.size() - shown );
    }
    return shown;
}

// The same, wrapped in `<TAG n="N"> … </TAG>`.
template<class Seq, class Row>
inline void writeCappedList( std::FILE* out, const char* tag, const Seq& seq, std::size_t maxRows, Row&& row )
{
    std::fprintf( out, "<%s n=\"%zu\">", tag, seq.size() );
    writeCappedRows( out, tag, seq, maxRows, row );
    std::fprintf( out, "</%s>", tag );
}

// The doc comment, the `<flip …>` header attributes, and the four situational rows that qualify them
// (already-lit / also / parent / capped) plus the family roll-up.
inline void writeFlipHeader( std::FILE* out, const FlipResult& res, const XmlEscaper& ex )
{
    std::fprintf( out, "<!-- ripwire flip: the blast radius of turning ONE gate ON. lights = the code that becomes live: r rows "
                       "are #if regions, b rows are C++ branch sites (a gate read as a VALUE through a constexpr bool, via= names "
                       "the binding). hosts = the indexed defs that code sits inside; downstream = what those defs transitively "
                       "CALL (what starts executing); dependents = what transitively calls THEM. tests = test files reaching the "
                       "hosts; untested = hosts no test reaches (the honest is it safe answer). An alias MASTER rolls its children "
                       "in (member rows); flipping a CHILD lights only that child and names its parent. kind=cmake also steers the "
                       "BUILD graph, which no C++ side analysis follows: those sites are c rows. kind=env is RUNTIME (runtime=1) so "
                       "every row is conditional at its read. Lexical and single line, never preprocessed: the value lane reads "
                       "C family source only and treats a file declaring its OWN constant of that name as shadowing the gate's, "
                       "but a third header's same named constant (included, not redeclared) would still count. A lit site inside "
                       "no indexed def counts into filescope instead of a host. "
                       // §B12.5 — the cross-verb UNIT collision, in the same words on each verb that spells it.
                       "UNIT: untested= here counts HOSTS (indexed defs this gate lights that no test reaches). The test gate "
                       "verb spells untested= over impacted SYMBOLS and the seams verb over cross-directory call EDGES, so the "
                       "three numbers count three different things and must never be compared or summed across verbs. -->" );

    std::fprintf( out, "<flip gate=\"%s\" kind=\"%s\" default=\"%s\" dark=\"%d\" runtime=\"%d\" p=\"%s\" l=\"%u\""
                       " family=\"%zu\" regions=\"%u\" loc=\"%u\" branches=\"%zu\" bindings=\"%zu\""
                       " hosts=\"%zu\" filescope=\"%u\" downstream=\"%zu\" dependents=\"%zu\" tests=\"%zu\" untested=\"%zu\" files=\"%zu\">",
                  ex( res.name ).c_str(), darkflags::gateKindTag( res.kind ), ex( res.def ).c_str(),
                  res.isDark ? 1 : 0, res.isRuntime ? 1 : 0, ex( res.defSite.path ).c_str(), res.defSite.line,
                  res.family.size(), res.totalRegions, res.totalLines, res.branches.size(), res.bindings.size(),
                  res.hosts.size(), res.fileScopeLights, res.downstream.size(), res.dependents,
                  res.tests.size(), res.untested.size(), res.filesScanned );

    // the contradiction row: this gate is ALREADY lit by the winning declaration, and dark only in the other
    if( !res.isDark )
    {
        std::fprintf( out, "<already-lit note=\"the winning default already builds this code; the radius below is what the other declaration keeps dark\"/>" );
    }
    if( res.hasAlso )
    {
        std::fprintf( out, "<also kind=\"%s\" default=\"%s\" p=\"%s\" l=\"%u\"/>",
                      darkflags::gateKindTag( res.alsoKind ), ex( res.alsoDef ).c_str(),
                      ex( res.alsoSite.path ).c_str(), res.alsoSite.line );
    }
    if( !res.parent.empty() )
    {
        std::fprintf( out, "<parent name=\"%s\" siblings=\"%u\"/>", ex( res.parent ).c_str(), res.siblingCount );
    }
    if( res.familyCapped )
    {
        std::fprintf( out, "<capped what=\"family\" at=\"%zu\"/>", kMaxFamily );
    }

    for( const FamilyMember& m : res.family )
    {
        std::fprintf( out, "<member name=\"%s\" via=\"%s\" regions=\"%u\" loc=\"%u\" branches=\"%u\"/>",
                      ex( m.name ).c_str(), m.isSelf ? "self" : "alias", m.regions, m.lines, m.branches );
    }
}

// The two lit-site row kinds, in one element: `#if` regions and C++ branch sites.
inline void writeFlipLights( std::FILE* out, const FlipResult& res, const IngestResult& ing,
                             const XmlEscaper& ex, std::size_t maxRows )
{
    std::fprintf( out, "<lights r=\"%zu\" b=\"%zu\">", res.regions.size(), res.branches.size() );
    writeCappedRows( out, "r", res.regions, maxRows, [ & ]( const LitRegion& r )
    {
        std::fprintf( out, "<r p=\"%s\" l=\"%u\" lines=\"%u\" gate=\"%s\" syms=\"%u\"/>",
                      ex( r.path ).c_str(), r.line, r.lines, ex( r.gate ).c_str(), r.hostCount );
    } );
    writeCappedRows( out, "b", res.branches, maxRows, [ & ]( const LitBranch& b )
    {
        std::fprintf( out, "<b p=\"%s\" l=\"%u\" gate=\"%s\" via=\"%s\" sym=\"%s\"/>",
                      ex( b.path ).c_str(), b.line, ex( b.gate ).c_str(), ex( b.via ).c_str(),
                      b.host == kNoNode ? "" : ex( ing.symbols[ b.host ].name ).c_str() );
    } );
    std::fprintf( out, "</lights>" );
}

inline void writeFlip( std::FILE* out, const FlipResult& res, const IngestResult& ing,
                       const std::string& root, std::size_t maxRows )
{
    std::vector<char> esc;
    const XmlEscaper  ex  = [ & ]( std::string_view s ) { return std::string( escapeXml( s, esc ) ); };
    const auto        rel = [ & ]( std::uint32_t fileId ) { return std::string( relForHash( ing.files[ fileId ], root ) ); };
    const auto        isTested = [ & ]( NodeId n ) { return n < res.testReach.size() && res.testReach[n]; };

    writeFlipHeader( out, res, ex );
    writeFlipLights( out, res, ing, ex, maxRows );

    for( const ValueBinding& b : res.bindings )
    {
        std::fprintf( out, "<bind name=\"%s\" gate=\"%s\" p=\"%s\" l=\"%u\" uses=\"%u\"/>",
                      ex( b.name ).c_str(), ex( b.gate ).c_str(), ex( b.path ).c_str(), b.line, b.uses );
    }

    writeCappedList( out, "hosts", res.hosts, maxRows, [ & ]( NodeId h )
    {
        const Symbol& s = ing.symbols[h];
        std::fprintf( out, "<h sym=\"%s\" p=\"%s\" l=\"%u\" ccx=\"%u\" tested=\"%d\"/>",
                      ex( qualifiedName( s ) ).c_str(), ex( rel( s.fileId ) ).c_str(), s.line, s.ccx, isTested( h ) ? 1 : 0 );
    } );
    writeCappedList( out, "downstream", res.downstream, maxRows, [ & ]( NodeId d )
    {
        const Symbol& s = ing.symbols[d];
        std::fprintf( out, "<d sym=\"%s\" p=\"%s\" ccx=\"%u\"/>",
                      ex( qualifiedName( s ) ).c_str(), ex( rel( s.fileId ) ).c_str(), s.ccx );
    } );
    writeCappedList( out, "tests", res.tests, maxRows, [ & ]( std::uint32_t f )
    {
        std::fprintf( out, "<t p=\"%s\"/>", ex( rel( f ) ).c_str() );
    } );
    writeCappedList( out, "untested", res.untested, maxRows, [ & ]( NodeId u )
    {
        const Symbol& s = ing.symbols[u];
        std::fprintf( out, "<u sym=\"%s\" p=\"%s\" l=\"%u\" ccx=\"%u\"/>",
                      ex( qualifiedName( s ) ).c_str(), ex( rel( s.fileId ) ).c_str(), s.line, s.ccx );
    } );

    if( !res.buildSites.empty() )
    {
        std::fprintf( out, "<build n=\"%zu\" note=\"CMake read sites: a switch here can add whole translation units or link targets, which this verb does NOT follow\">",
                      res.buildSites.size() );
        writeCappedRows( out, "build", res.buildSites, maxRows, [ & ]( const darkflags::Site& s )
        {
            std::fprintf( out, "<c p=\"%s\" l=\"%u\"/>", ex( s.path ).c_str(), s.line );
        } );
        std::fprintf( out, "</build>" );
    }

    std::fprintf( out, "</flip>" );
}

}}   // namespace rw::flipimpact
