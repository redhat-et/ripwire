#pragma once
// verbtable.h -- V6: a small, deterministic, dictionary-based "is this token a known action verb" check.
//
// Transfer source: grepai's rpg/extractor_local.go (LocalExtractor) splits a symbol name into words and
// checks the first word against a fixed ~140-entry verb dictionary to build a zero-LLM, zero-embedding
// "verb-object" feature label. ripwire's community/zoom labels (src/main.cpp, communityPresentation)
// anchor on a single lead symbol only, so two clusters that happen to share an anchor name are visually
// indistinguishable; this table is the substrate for a verb-histogram SUFFIX on that label (still
// anchored -- this table never replaces the anchor, only adds a frequency-ranked summary of what the
// community's members, in aggregate, DO).
//
// G2: a sorted POD array + std::binary_search, not a std::map/std::unordered_map (CONTRIBUTING.md §3's
// container rule) and not a hash table at all -- the table is small and read-only, so a sorted array scan
// is both the simplest and the cache-friendliest shape.
//
// The list is curated for source-code identifiers (English imperative verb stems as they appear at the
// START of a camelCase/snake_case name -- "get", "compute", "resolve", ...), not a general English verb
// dictionary. MUST stay sorted (ascending, `operator<` on std::string_view, i.e. byte order) -- a
// static_assert below enforces it at compile time, and test/communitylabelcheck.sh's determinism arm
// depends on binary_search finding every entry it exercises. All entries lowercase (matched against the
// lowercased first split-token of a symbol name).

#include <algorithm>
#include <array>
#include <string_view>

namespace rw
{
namespace verbtable
{

inline constexpr std::array<std::string_view, 124> kKnownVerbs = {
    "accept",   "acquire",  "add",       "allocate", "allow",    "append",
    "apply",    "assert",   "attach",    "bind",     "cache",    "calculate",
    "call",     "cancel",   "check",     "clear",    "clone",    "close",
    "collect",  "compress", "compute",   "connect",  "convert",  "copy",
    "count",    "create",   "declare",   "decode",   "dedup",    "dedupe",
    "define",   "delete",   "deny",      "detect",   "disable",  "dispatch",
    "drill",    "drop",     "emit",      "enable",   "encode",   "ensure",
    "erase",    "evaluate", "expand",    "fetch",    "fill",     "filter",
    "find",     "fix",      "format",    "free",     "gather",   "generate",
    "get",      "grow",     "handle",    "init",     "insert",   "invoke",
    "join",     "kill",     "load",      "lock",     "log",      "make",
    "map",      "mark",     "match",     "measure",  "merge",    "move",
    "normalize","notify",   "open",      "pack",     "parse",    "pop",
    "print",    "process",  "publish",   "push",     "query",    "rank",
    "read",     "reduce",   "refuse",    "register", "reject",   "release",
    "remove",   "render",   "replace",   "report",   "require",  "reset",
    "resolve",  "route",    "run",       "save",     "scan",     "score",
    "search",   "serialize","set",       "skip",     "sort",     "split",
    "start",    "stop",     "store",     "tag",      "unlock",   "unpack",
    "unwrap",   "update",   "validate",  "verify",   "visit",    "walk",
    "want",     "wrap",     "write",     "zoom",
};

// std::string_view has a constexpr operator<, so this check runs at compile time -- a future edit that
// breaks the ascending-sort contract std::binary_search (below, at the one call site) depends on fails
// the build, not just the gate. There is deliberately no isKnownVerb() wrapper here: a bare one-line
// `return std::algorithm(...)` forwarder over a small fixed container is exactly the shape
// naminglens::ncAnyOf and notes::sortNotes already are, and adding a third structurally-identical
// wrapper is a clone, not a new primitive — src/main.cpp's communityVerbSuffix (the table's one caller)
// calls std::binary_search directly against kKnownVerbs instead.
static_assert( []() constexpr {
    for( std::size_t i = 1; i < kKnownVerbs.size(); ++i )
    {
        if( !( kKnownVerbs[i - 1] < kKnownVerbs[i] ) ) { return false; }
    }
    return true;
}(), "verbtable.h: kKnownVerbs must stay sorted ascending for binary_search" );

} // namespace verbtable
} // namespace rw
